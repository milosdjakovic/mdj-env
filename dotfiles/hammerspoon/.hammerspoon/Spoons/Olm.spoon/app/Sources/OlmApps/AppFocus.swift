// Bringing an app forward from Olm.app, step 6.2, docs/DESIGN-APP-APPS.md. It reads an app the way
// Hammerspoon reads it, decides with AppPlan, acts, places the window when the press asked for it,
// and hands each press to the shadow beside what Lua would have done.
//
// Everything runs on a queue of its own, never the main thread, since an Accessibility call waits on
// the app it asks, and each is bounded to a second so a hung app costs its own press and no other.
// What only AppKit answers, which app runs and is active and where the screens stand, is read on the
// main thread in one short hop.

import AppKit
import ApplicationServices

// The window number behind an Accessibility window, the private call hs.window:id() stands on, so a
// cycle orders windows as Lua does.
@_silgen_name("_AXUIElementGetWindow")
private func axWindowNumber(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// One press the bridge's appRun carries.
public struct AppPress: Sendable {
  public let id: String
  public let bundle: String
  public let hides: Bool
  public let placement: Placement?
  public let lua: AppPlan?

  public init(id: String, bundle: String, hides: Bool, placement: Placement?, lua: AppPlan?) {
    self.id = id
    self.bundle = bundle
    self.hides = hides
    self.placement = placement
    self.lua = lua
  }

  /// Read from appRun's params as Foundation answers JSON, nil without a bundle id.
  public init?(_ params: Any) {
    guard let o = params as? [String: Any], let bundle = o["bundle"] as? String, !bundle.isEmpty else { return nil }
    let lua = (o["lua"] as? [String: Any]).flatMap { l -> AppPlan? in
      guard let word = l["outcome"] as? String, let outcome = AppOutcome(rawValue: word) else { return nil }
      return AppPlan(outcome, window: (l["window"] as? Double).map { UInt32($0) })
    }
    self.init(id: o["id"] as? String ?? "launcher", bundle: bundle, hides: o["hides"] as? Bool ?? false,
      placement: Placement(o["placement"]), lua: lua)
  }
}

public final class AppFocus: @unchecked Sendable {
  /// The placement wait's timing, the toggler's own: a beat, then polls until the app is ready.
  /// Lua's wait was meant to stop at twenty and never did, since hs.timer.waitUntil takes no count.
  public struct Timing: Sendable {
    public var first = 0.1, every = 0.25, attempts = 20
    public init() {}
  }

  private let queue = DispatchQueue(label: "local.olm.apps")
  private let shadow: AppShadow?
  private let timing: Timing
  private let log: @Sendable (String) -> Void
  // Each placing press's number, so an older press's wait stops once a newer one starts. On the queue.
  private var placing = 0

  public init(shadow: AppShadow?, timing: Timing = Timing(), log: @escaping @Sendable (String) -> Void) {
    self.shadow = shadow
    self.timing = timing
    self.log = log
  }

  /// Whether macOS lets the app act on other apps.
  public static var allowed: Bool { AXIsProcessTrusted() }

  /// Asks for Accessibility once, macOS's own prompt, which lists the app in System Settings.
  public static func ask() {
    let key = "AXTrustedCheckOptionPrompt" as CFString
    _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
  }

  /// Runs one press, on the queue, returning at once.
  public func run(_ press: AppPress) {
    queue.async { self.act(press) }
  }

  // MARK: Reading

  private struct Running {
    let pid: pid_t
    let active: Bool
  }

  private func running(_ bundle: String) -> Running? {
    DispatchQueue.main.sync {
      NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first.map {
        Running(pid: $0.processIdentifier, active: $0.isActive)
      }
    }
  }

  private func element(_ pid: pid_t) -> AXUIElement {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1.0)
    return app
  }

  private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
  }

  private func number(_ window: AXUIElement) -> UInt32? {
    var id: CGWindowID = 0
    return axWindowNumber(window, &id) == .success ? id : nil
  }

  private func windows(_ app: AXUIElement) -> [(AXUIElement, AppWindow)] {
    guard let list = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
    return list.compactMap { w in
      guard let id = number(w) else { return nil }
      let subrole = attribute(w, kAXSubroleAttribute) as? String
      let minimized = attribute(w, kAXMinimizedAttribute) as? Bool ?? false
      return (w, AppWindow(id: id, standard: subrole == (kAXStandardWindowSubrole as String), minimized: minimized))
    }
  }

  // The focused application's focused window, whichever app that is, and that application's pid.
  private func focused() -> (pid: pid_t?, window: AXUIElement?) {
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 1.0)
    guard let value = attribute(system, kAXFocusedApplicationAttribute) else { return (nil, nil) }
    let app = value as! AXUIElement
    AXUIElementSetMessagingTimeout(app, 1.0)
    var pid: pid_t = 0
    let hasPid = AXUIElementGetPid(app, &pid) == .success
    let window = attribute(app, kAXFocusedWindowAttribute).map { $0 as! AXUIElement }
    return (hasPid ? pid : nil, window)
  }

  // MARK: Acting

  private func read(_ bundle: String, hides: Bool) -> (AppPlan, AXUIElement?, [(AXUIElement, AppWindow)]) {
    let found = running(bundle)
    let app = found.map { element($0.pid) }
    let listed = app.map(windows) ?? []
    // The app's own focused and main windows, never the system wide focused application's, which
    // answered none of Chrome's at its presses, so every cycle restarted at the first, 2026-11-23.
    let own = { (name: String) in
      hides ? nil : app.flatMap { self.attribute($0, name) }.flatMap { self.number($0 as! AXUIElement) }
    }
    let state = AppState(running: found != nil, frontmost: found?.active ?? false, windows: listed.map(\.1),
      focused: own(kAXFocusedWindowAttribute), main: own(kAXMainWindowAttribute))
    return (AppPlan.decide(state, hides: hides), app, listed)
  }

  /// What a press on each app would do now, changing nothing, for the live check's olm://apps-plan.
  /// Waits on the queue, so never call it from the main thread.
  public func plans(_ bundles: [String], hides: Bool) -> [String: AppPlan] {
    queue.sync {
      var out: [String: AppPlan] = [:]
      for bundle in bundles { out[bundle] = read(bundle, hides: hides).0 }
      return out
    }
  }

  private func act(_ press: AppPress) {
    let (plan, app, listed) = read(press.bundle, hides: press.hides)
    shadow?.ran(press, plan: plan, trusted: Self.allowed)

    switch plan.outcome {
    case .launched, .focused:
      launchOrFocus(press.bundle)
    case .cycled:
      if let app, let target = listed.first(where: { $0.1.id == plan.window })?.0 {
        AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
      }
    case .hidden:
      let bundle = press.bundle
      DispatchQueue.main.async {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.hide()
      }
    }

    placing += 1
    if plan.places, let placement = press.placement {
      let mine = placing
      queue.asyncAfter(deadline: .now() + timing.first) { self.wait(press, placement, mine, left: self.timing.attempts) }
    }
  }

  // LaunchServices with activation, which reopens a window for a running app that has none, as
  // hs.application.launchOrFocusByBundleID does.
  private func launchOrFocus(_ bundle: String) {
    let log = self.log
    DispatchQueue.main.async {
      guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
        log("no application has the bundle id \(bundle)")
        return
      }
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
        if let error { log("\(bundle) did not open, \(error.localizedDescription)") }
      }
    }
  }

  // MARK: Placing

  // Ready is the toggler's _isAppReady: the app has a main window and holds focus.
  private func wait(_ press: AppPress, _ placement: Placement, _ mine: Int, left: Int) {
    guard mine == placing else { return }
    guard let found = running(press.bundle) else { return }
    let app = element(found.pid)
    let main = attribute(app, kAXMainWindowAttribute).map { $0 as! AXUIElement }
    let focus = focused()
    guard main != nil, focus.pid == found.pid else {
      if left > 1 {
        queue.asyncAfter(deadline: .now() + timing.every) { self.wait(press, placement, mine, left: left - 1) }
      } else {
        shadow?.unplaced(press)
      }
      return
    }
    AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    guard let window = main ?? focus.window, let current = frame(window) else { return }
    let screens = visibleScreens()
    guard let screen = screenOf(current, among: screens) else { return }
    let asked = placement.frame(in: placement.box(screen), current: current)
    // Size, position, then size again, as hs.window:setFrame does, since an app may refuse a size
    // that would cross the screen's edge from where the window stood.
    setSize(window, asked)
    setPosition(window, asked)
    setSize(window, asked)
    if let got = frame(window) { shadow?.placed(press, asked: asked, got: got) }
  }

  private func frame(_ window: AXUIElement) -> Box? {
    guard let p = attribute(window, kAXPositionAttribute), let s = attribute(window, kAXSizeAttribute) else { return nil }
    var point = CGPoint.zero, size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
    return Box(x: point.x, y: point.y, w: size.width, h: size.height)
  }

  private func setSize(_ window: AXUIElement, _ box: Box) {
    var size = CGSize(width: box.w, height: box.h)
    if let value = AXValueCreate(.cgSize, &size) {
      AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }
  }

  private func setPosition(_ window: AXUIElement, _ box: Box) {
    var point = CGPoint(x: box.x, y: box.y)
    if let value = AXValueCreate(.cgPoint, &point) {
      AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }
  }

  // Every screen's visible frame, the menu bar and the Dock left out, turned to the top left origin
  // Accessibility uses, as hs.screen:frame() answers it.
  private func visibleScreens() -> [Box] {
    DispatchQueue.main.sync {
      let screens = NSScreen.screens
      guard let primary = screens.first?.frame else { return [] }
      return screens.map {
        let v = $0.visibleFrame
        return Box(x: v.origin.x, y: primary.maxY - v.origin.y - v.height, w: v.width, h: v.height)
      }
    }
  }
}
