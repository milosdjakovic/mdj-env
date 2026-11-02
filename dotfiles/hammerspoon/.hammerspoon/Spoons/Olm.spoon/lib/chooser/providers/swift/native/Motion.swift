// How every surface this library draws comes and goes, the chooser's window, its two floating panes,
// a preview pane in a window of its own and every CanvasPanel, the cheat sheets and the toasts among
// them. Opening fades in while the shape rises a few points and grows from a hair smaller, closing
// fades out while it shrinks back by half as much, both quick enough to read as a response rather
// than as a wait.
//
// ONE PLACE. The look is the motion block of config/settings.lua, which reaches the kit's motion
// tokens through root/uispec.lua and this file through setMotion in Entry.swift, the way every size
// the library draws with arrives from Lua, so one edit and a reload moves every surface. Nothing else
// in the library animates a surface. A view comes and goes through appear and disappear, a window
// through a WindowMotion, which is the same two over its content. Until the tokens arrive, and with
// a duration of zero, a surface comes and goes at once.
//
// THE COST. Everything here is Core Animation on the render server, an opacity and a transform
// animation on a layer whose model values are already where it ends, so no layout runs, no view
// draws and no Lua is asked while it plays, and a busy main thread cannot skip it. Never fade
// through a window's alphaValue animator, which AppKit steps on the main thread, so menu search,
// reading the menu bar right after it showed, opened with no fade at all.
//
// A KEY WINDOW stays key while it fades out and passes on what it hears, see WindowMotion.
//
// TURNING AROUND. A surface shown while it fades out fades back in from where it had got to, and
// the close that was cut short does nothing when it would have ended.
//
// REDUCED MOTION. With Reduce Motion on in System Settings a surface stays still and only fades.

import Cocoa

enum Motion {
  // The kit's motion tokens, set by setMotion, none until they arrive. How far below its place a
  // shape starts and how much smaller, a closing shape travelling half.
  static var openDuration: CFTimeInterval = 0
  static var closeDuration: CFTimeInterval = 0
  static var rise: CGFloat = 0
  static var scale: CGFloat = 1
  static var openCurve = CAMediaTimingFunction(name: .linear)
  static var closeCurve = CAMediaTimingFunction(name: .linear)

  // MARK: Keys a closing window hears

  // Posts a key event to the application in front, for a window still key while it fades out, see
  // WindowMotion. False when there is no other application to post to, Hammerspoon itself in front,
  // or the event is not a key.
  static func passOn(_ event: NSEvent) -> Bool {
    guard [.keyDown, .keyUp, .flagsChanged].contains(event.type), let cg = event.cgEvent,
      let app = NSWorkspace.shared.frontmostApplication,
      app.processIdentifier != ProcessInfo.processInfo.processIdentifier
    else { return false }
    cg.postToPid(app.processIdentifier)
    return true
  }

  // MARK: Views

  private static let fadeKey = "olm.motion.fade"
  private static let moveKey = "olm.motion.move"
  private static let tokenKey = "olm.motion.token"
  private static var tokens = 0

  static var still: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

  // Fades view in where it stands, from however far a fade out had got.
  static func appear(_ view: NSView) {
    view.wantsLayer = true
    guard let layer = view.layer else { return }
    let from = layer.animation(forKey: fadeKey) != nil ? layer.presentation()?.opacity ?? 0 : 0
    settle(layer)
    view.alphaValue = 1
    guard openDuration > 0 else { return }
    play(view, layer, closing: false, from: from, token: nil)
  }

  // Fades view out, then leaves it see through and calls done, unless it was shown again first.
  static func disappear(_ view: NSView, done: (() -> Void)? = nil) {
    view.wantsLayer = true
    guard let layer = view.layer, closeDuration > 0 else {
      rest(view)
      done?()
      return
    }
    tokens += 1
    let token = tokens
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak view] in
      guard let view, let layer = view.layer,
        layer.animation(forKey: fadeKey)?.value(forKey: tokenKey) as? Int == token
      else { return }
      rest(view)
      done?()
    }
    play(view, layer, closing: true, from: 1, token: token)
    CATransaction.commit()
  }

  // See through at once with nothing playing, where a surface waits until it next appears.
  static func rest(_ view: NSView) {
    view.alphaValue = 0
    if let layer = view.layer { settle(layer) }
  }

  private static func settle(_ layer: CALayer) {
    layer.removeAnimation(forKey: fadeKey)
    layer.removeAnimation(forKey: moveKey)
  }

  private static func play(_ view: NSView, _ layer: CALayer, closing: Bool, from: Float, token: Int?) {
    let duration = closing ? closeDuration : openDuration
    let curve = closing ? closeCurve : openCurve
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = from
    fade.toValue = closing ? 0 : 1
    fade.duration = duration
    fade.timingFunction = curve
    fade.fillMode = .forwards
    fade.isRemovedOnCompletion = !closing
    if let token { fade.setValue(token, forKey: tokenKey) }
    layer.add(fade, forKey: fadeKey)
    guard !still else { return }
    let away = offset(view, layer, rise: closing ? rise / 2 : rise, scale: closing ? 1 - (1 - scale) / 2 : scale)
    let move = CABasicAnimation(keyPath: "transform")
    move.fromValue = NSValue(caTransform3D: closing ? CATransform3DIdentity : away)
    move.toValue = NSValue(caTransform3D: closing ? away : CATransform3DIdentity)
    move.duration = duration
    move.timingFunction = curve
    move.fillMode = .forwards
    move.isRemovedOnCompletion = !closing
    layer.add(move, forKey: moveKey)
  }

  // The transform that puts a view's content rise points down the screen and scaled by scale about
  // its centre. The translation is in the superview's space, which AppKit gives the superlayer, so
  // its sign follows whether the superview is flipped, and the centre is the centre either way.
  private static func offset(_ view: NSView, _ layer: CALayer, rise: CGFloat, scale: CGFloat) -> CATransform3D {
    let size = view.bounds.size
    let px = size.width * (0.5 - layer.anchorPoint.x)
    let py = size.height * (0.5 - layer.anchorPoint.y)
    var t = CATransform3DMakeTranslation(px, py, 0)
    t = CATransform3DScale(t, scale, scale, 1)
    t = CATransform3DTranslate(t, -px, -py, 0)
    let down = view.superview?.isFlipped == true ? rise : -rise
    return CATransform3DConcat(t, CATransform3DMakeTranslation(0, down, 0))
  }
}

// One window's coming and going, through its content view. The content rests see through while the
// window is down, so a window ordered front before its fade is committed shows nothing rather than
// what it showed last time. A closing window fades out in place, takes no pointer from the moment
// the fade starts, and answers that it is down from then too.
//
// A window that took key stays key while it fades, since glass follows its window's key state and
// has no setting to hold the active look, so a window that gave up key at the start of its close
// drew darker and more opaque for the whole fade, seen at a two second close. A key it hears then
// is not its own, so its sendEvent hands the key to Motion.passOn, which posts it to the
// application in front, where it would have gone had the window gone down at once.
final class WindowMotion {
  let window: NSWindow
  // Whether a close is fading now, and whether the window took the pointer before it began.
  private(set) var closing = false
  private var ignored = false
  // Called once the window is down and its fade has ended, or at once for a close with no fade.
  var onDown: (() -> Void)?

  init(_ window: NSWindow) {
    self.window = window
    if let content = window.contentView { Motion.rest(content) }
  }

  // Whether the window is up and not on its way down.
  var isUp: Bool { window.isVisible && !closing }

  // order brings the window up, and the content fades in when it was down or going down.
  func show(_ order: () -> Void) {
    let fresh = !isUp
    endClose()
    order()
    if fresh, let content = window.contentView { Motion.appear(content) }
  }

  // animated false goes down at once, which a reload's cleanup asks for, and so does a close
  // duration of zero.
  func hide(animated: Bool = true) {
    let animated = animated && Motion.closeDuration > 0
    if animated && closing { return }
    guard animated, isUp, let content = window.contentView else {
      endClose()
      window.orderOut(nil)
      if let content = window.contentView { Motion.rest(content) }
      onDown?()
      return
    }
    closing = true
    ignored = window.ignoresMouseEvents
    window.ignoresMouseEvents = true
    Motion.disappear(content) { [weak self] in
      guard let self, self.closing else { return }
      self.endClose()
      self.window.orderOut(nil)
      self.onDown?()
    }
  }

  private func endClose() {
    guard closing else { return }
    closing = false
    window.ignoresMouseEvents = ignored
  }
}
