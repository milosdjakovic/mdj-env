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

// The stand in a closing key window fades out in, see WindowMotion, outlined as the window is.
final class FadingPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// One window's coming and going, through its content view. The content rests see through while the
// window is down, so a window ordered front before its fade is committed shows nothing rather than
// what it showed last time.
//
// A window that takes key cannot fade out in place, since a window still up is still key, and a key
// typed or posted in that tenth of a second, an insert a list makes as it closes among them, would
// land in it rather than in the application below. So with standIn the window goes down at once and
// its content moves to a FadingPanel, which never becomes key and takes no pointer, fades out there
// and moves back. A window that never takes key, a CanvasPanel's, fades out in place and says it is
// down from the moment the fade starts.
final class WindowMotion {
  let window: NSWindow
  private let standIn: Bool
  private var fader: FadingPanel?
  // Whether the stand in holds the content now.
  private var lent = false
  // Whether a close is fading now.
  private(set) var closing = false
  // Called once the window is down and its fade has ended, or at once for a close with no fade.
  var onDown: (() -> Void)?

  init(_ window: NSWindow, standIn: Bool) {
    self.window = window
    self.standIn = standIn
    if let content = window.contentView { Motion.rest(content) }
  }

  // Whether the window is up and not on its way down.
  var isUp: Bool { window.isVisible && !closing }

  // order brings the window up, and the content fades in when it was down or going down.
  func show(_ order: () -> Void) {
    let fresh = !isUp
    closing = false
    reclaim()
    order()
    if fresh, let content = window.contentView { Motion.appear(content) }
  }

  // animated false goes down at once, which a reload's cleanup asks for.
  func hide(animated: Bool = true) {
    if animated && closing { return }
    guard animated, isUp, let content = window.contentView else {
      closing = false
      window.orderOut(nil)
      reclaim()
      if let content = window.contentView { Motion.rest(content) }
      onDown?()
      return
    }
    closing = true
    if standIn {
      let fader = self.fader ?? makeFader()
      fader.level = window.level
      fader.setFrame(window.frame, display: false)
      // Down first, so a view holding the focus leaves a window that no longer has it.
      window.orderOut(nil)
      window.contentView = NSView()
      fader.contentView = content
      lent = true
      fader.orderFrontRegardless()
    }
    Motion.disappear(content) { [weak self] in
      guard let self, self.closing else { return }
      self.closing = false
      if self.standIn { self.reclaim() } else { self.window.orderOut(nil) }
      self.onDown?()
    }
  }

  // The content back from the stand in, which goes down.
  private func reclaim() {
    guard lent, let fader, let content = fader.contentView else { return }
    lent = false
    fader.orderOut(nil)
    fader.contentView = NSView()
    window.contentView = content
  }

  private func makeFader() -> FadingPanel {
    let fader = FadingPanel(contentRect: window.frame, styleMask: window.styleMask, backing: .buffered, defer: true)
    fader.isFloatingPanel = true
    fader.collectionBehavior = window.collectionBehavior
    fader.isOpaque = false
    fader.backgroundColor = .clear
    fader.hasShadow = window.hasShadow
    fader.hidesOnDeactivate = false
    fader.isReleasedWhenClosed = false
    fader.animationBehavior = .none
    fader.ignoresMouseEvents = true
    fader.titlebarAppearsTransparent = window.titlebarAppearsTransparent
    fader.titleVisibility = window.titleVisibility
    fader.isMovable = false
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      fader.standardWindowButton(button)?.isHidden = true
    }
    self.fader = fader
    return fader
  }
}
