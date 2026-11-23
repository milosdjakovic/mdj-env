// The window manager run by the app, step 6.3b of docs/PLAN-STANDALONE.md, docs/DESIGN-APP-WINDOWS.md.
// A META window key the app claims is run here once the windowsInApp switch is on and the app holds
// Accessibility: the focused window and the screens read as WindowRead reads them, the plan
// WindowPlan answers with Olm's own settings and named sizes, and the frame written. Hide Others
// hides every regular app showing but the one in front, as macOS's own does.
//
// The frame is written size, position and size again, hs.window's workaround, since a window
// growing as it crosses onto a larger screen is clamped to the screen it leaves by a single write,
// and read back. A window that refuses it, an app with a minimum size or one sizing in whole cells,
// is logged by the shadow, never retried. The memory of the frame a window had on each screen,
// which a display move goes back to, lives here for the app's life, as Lua's does for a load.
//
// Everything runs on a queue of its own, each Accessibility call bounded to a second, so a hung app
// costs its own press.

import AppKit
import ApplicationServices

public final class WindowRun: @unchecked Sendable {
  private let queue = DispatchQueue(label: "local.olm.windows.run")
  private let shadow: WindowShadow?
  // On the queue: the frame each window had on each screen, by window number and screen uuid.
  private var memory: [UInt32: [String: WindowRect]] = [:]

  public init(shadow: WindowShadow?) {
    self.shadow = shadow
  }

  /// The actions run here: every one plan.lua answers that a key reaches, the named sizes and Hide
  /// Others. exactSize is reached from the launcher with a size and stays in Hammerspoon.
  public static func runs(_ action: String, _ settings: WindowSettings) -> Bool {
    if action == "hideAllExceptFocused" || settings.sizes[action] != nil { return true }
    return ["maximize", "center", "fullHeight", "fullHeightReasonableWidth", "reasonableSize", "leftHalf",
      "rightHalf", "increaseSize", "decreaseSize", "moveLeft", "moveRight", "moveUp", "moveDown",
      "nextDisplay", "previousDisplay"].contains(action) || WindowPlan.layouts[action] != nil
  }

  /// Runs one action, answering once the frame is written.
  public func run(_ action: String, depth: Int, settings: WindowSettings) async {
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
      queue.async {
        self.act(action, depth: depth, settings: settings)
        done.resume()
      }
    }
  }

  private func act(_ action: String, depth: Int, settings: WindowSettings) {
    if action == "hideAllExceptFocused" {
      DispatchQueue.main.sync { Self.hideOthers() }
      return
    }
    let (snap, element) = WindowRead.focused()
    guard let element else { return }
    var s = WindowInput()
    s.window = snap.window
    s.id = snap.id
    s.screen = snap.screen
    s.screens = snap.screens
    s.pointer = snap.pointer
    s.margins = settings.margins
    s.gap = settings.gap
    s.sizing = settings.sizing
    s.depth = depth
    if let id = snap.id { s.memory = memory[id] ?? [:] }
    var planned = action
    if let named = settings.sizes[action] {
      s.named = named
      planned = "namedSize"
    }
    guard let result = WindowPlan.plan(planned, s) else { return }
    if let remember = result.remember, let id = snap.id {
      memory[id, default: [:]][remember.screen] = remember.frame
      if memory.count > 200 { memory.removeValue(forKey: memory.keys.first!) }
    }
    let f = result.frame
    setSize(element, f)
    setPosition(element, f)
    setSize(element, f)
    if let got = WindowRead.frame(element) { shadow?.placed(action: action, asked: f, got: got) }
  }

  @MainActor private static func hideOthers() {
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    for app in NSWorkspace.shared.runningApplications
    where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != front {
      app.hide()
    }
  }

  private func setSize(_ window: AXUIElement, _ f: WindowRect) {
    var size = CGSize(width: f.w, height: f.h)
    if let value = AXValueCreate(.cgSize, &size) {
      AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }
  }

  private func setPosition(_ window: AXUIElement, _ f: WindowRect) {
    var point = CGPoint(x: f.x, y: f.y)
    if let value = AXValueCreate(.cgPoint, &point) {
      AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }
  }
}
