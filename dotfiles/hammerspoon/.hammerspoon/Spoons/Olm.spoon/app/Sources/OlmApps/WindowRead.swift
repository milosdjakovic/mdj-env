// The focused window and the screens as Olm.app reads them, step 6.3b of docs/PLAN-STANDALONE.md,
// docs/DESIGN-APP-WINDOWS.md. Each is read the way Hammerspoon reads it, so the window manager's plan
// is handed the same input from either side.
//
// - The focused window is the frontmost application's AXFocusedWindow, hs.window.focusedWindow()'s
//   own route through hs.application.frontmostApplication().
// - Its id is the window number, _AXUIElementGetWindow, which hs.window:id() stands on.
// - Its screen is the one its frame overlaps most, by full frame, as hs.window:screen() picks it.
// - The screens are NSScreen.screens in order, hs.screen.allScreens()'s order, each by the uuid
//   hs.screen:getUUID() answers and its visible frame turned to the top left origin Accessibility uses.
//
// Accessibility calls wait on the app they ask, so they run off the main thread, each bounded to a
// second. What only AppKit answers, the frontmost app and the screens, is read on the main thread in
// one short hop.

import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func axWindowID(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// What a window action reads of the machine, plan.lua's window, id, screen and screens.
public struct WindowSnapshot: Sendable {
  public var window: WindowRect?
  public var id: UInt32?
  public var screen: String?
  public var screens: [WindowScreen] = []
  /// The pointer, in the same top left space, for a named size shown under it.
  public var pointer: (x: Double, y: Double)?
  /// The frontmost application's bundle id, and the regular apps showing besides it, the ones Hide
  /// Others would hide.
  public var bundle: String?
  public var others: [String] = []
  /// How long the read took, in milliseconds, since it runs before the press is handed on.
  public var took: Double = 0
  public init() {}
}

public enum WindowRead {
  private static let queue = DispatchQueue(label: "local.olm.windows.read")

  /// Reads the machine off the main thread and answers once done.
  public static func snapshot() async -> WindowSnapshot {
    await withCheckedContinuation { done in
      queue.async { done.resume(returning: read()) }
    }
  }

  private struct Shown {
    var pid: pid_t?
    var bundle: String?
    var others: [String] = []
    var screens: [WindowScreen] = []
    var full: [WindowRect] = []
    var pointer: (x: Double, y: Double)?
  }

  /// The whole read, on the caller's thread, which must not be the main one.
  static func read() -> WindowSnapshot { focused().snapshot }

  /// The read and the focused window's element, which the runner writes the frame to.
  static func focused() -> (snapshot: WindowSnapshot, window: AXUIElement?) {
    let start = DispatchTime.now()
    var element: AXUIElement?
    let shown = DispatchQueue.main.sync { appKit() }
    var s = WindowSnapshot()
    s.screens = shown.screens
    s.pointer = shown.pointer
    s.bundle = shown.bundle
    s.others = shown.others
    if let pid = shown.pid {
      let app = AXUIElementCreateApplication(pid)
      AXUIElementSetMessagingTimeout(app, 1.0)
      var value: CFTypeRef?
      if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
        let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
        let window = value as! AXUIElement
        element = window
        s.window = frame(window)
        var id: CGWindowID = 0
        if axWindowID(window, &id) == .success { s.id = id }
        if let f = s.window { s.screen = screen(of: f, shown) }
      }
    }
    s.took = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    return (s, element)
  }

  @MainActor private static func appKit() -> Shown {
    var out = Shown()
    let front = NSWorkspace.shared.frontmostApplication
    out.pid = front?.processIdentifier
    out.bundle = front?.bundleIdentifier
    out.others = NSWorkspace.shared.runningApplications
      .filter { $0.activationPolicy == .regular && !$0.isHidden && $0.processIdentifier != front?.processIdentifier }
      .compactMap(\.bundleIdentifier).sorted()
    let screens = NSScreen.screens
    guard let primary = screens.first?.frame else { return out }
    func flip(_ r: NSRect) -> WindowRect {
      WindowRect(x: r.origin.x, y: primary.maxY - r.origin.y - r.height, w: r.width, h: r.height)
    }
    for screen in screens {
      let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
      out.screens.append(WindowScreen(uuid: uuid(screen), frame: flip(screen.visibleFrame),
        builtin: CGDisplayIsBuiltin(CGDirectDisplayID(number?.uint32Value ?? 0)) != 0))
      out.full.append(flip(screen.frame))
    }
    let p = NSEvent.mouseLocation
    out.pointer = (p.x, primary.maxY - p.y)
    return out
  }

  /// hs.screen:getUUID(), the display's uuid string.
  @MainActor static func uuid(_ screen: NSScreen) -> String {
    let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    let display = CGDirectDisplayID(number?.uint32Value ?? 0)
    guard let id = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue(),
      let text = CFUUIDCreateString(nil, id) as String? else { return String(display) }
    return text
  }

  /// The screen a frame overlaps most, by full frame, the first one on a tie or none.
  private static func screen(of f: WindowRect, _ shown: Shown) -> String? {
    var best: (area: Double, index: Int)?
    for (i, s) in shown.full.enumerated() {
      let w = min(f.x + f.w, s.x + s.w) - max(f.x, s.x)
      let h = min(f.y + f.h, s.y + s.h) - max(f.y, s.y)
      let area = w > 0 && h > 0 ? w * h : 0
      if area > (best?.area ?? 0) { best = (area, i) }
    }
    return best.map { shown.screens[$0.index].uuid }
  }

  static func frame(_ window: AXUIElement) -> WindowRect? {
    var p: CFTypeRef?, z: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &p) == .success,
      AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &z) == .success, let p, let z else { return nil }
    var point = CGPoint.zero, size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(z as! AXValue, .cgSize, &size) else { return nil }
    return WindowRect(x: point.x, y: point.y, w: size.width, h: size.height)
  }
}
