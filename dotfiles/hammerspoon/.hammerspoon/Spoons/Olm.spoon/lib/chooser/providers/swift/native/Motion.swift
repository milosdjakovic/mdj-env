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
// A FLOATING PANE grows out of its bar group and shrinks back onto it, always above the bar, its
// glass at its own size throughout, see ShapeMotion.
//
// REDUCED MOTION. With Reduce Motion on in System Settings a surface stays still and only fades,
// and a floating pane opens and closes at once.

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
  // How long a floating pane takes to grow out of its bar group and to fold back onto it.
  static var paneOpenDuration: CFTimeInterval = 0
  static var paneCloseDuration: CFTimeInterval = 0
  // How long a floating pane takes to fade in over its group before it grows, and to fade out off
  // it once it has shrunk back onto it.
  static var paneFadeDuration: CFTimeInterval = 0
  // The floating pane's own curves. It grows easing in and out, and shrinks easing out alone, so a
  // close moves the moment it is asked for, where the grow played backwards began on the grow's
  // long settle and read as a delay, and it still settles onto its group rather than snapping.
  static var paneCurve = CAMediaTimingFunction(name: .linear)
  static var paneCloseCurve = CAMediaTimingFunction(name: .linear)

  // Where a curve has got at t from 0 to 1, its two control points solved for x by Newton's method
  // and bisection, as Core Animation does, for a motion stepped by hand.
  static func progress(_ curve: CAMediaTimingFunction, _ t: CGFloat) -> CGFloat {
    var p1: [Float] = [0, 0], p2: [Float] = [0, 0]
    curve.getControlPoint(at: 1, values: &p1)
    curve.getControlPoint(at: 2, values: &p2)
    let (x1, y1, x2, y2) = (CGFloat(p1[0]), CGFloat(p1[1]), CGFloat(p2[0]), CGFloat(p2[1]))
    func bez(_ s: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
      3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s
    }
    let t = min(1, max(0, t))
    var s = t
    for _ in 0..<8 {
      let x = bez(s, x1, x2) - t
      let d = 3 * (1 - s) * (1 - s) * x1 + 6 * (1 - s) * s * (x2 - x1) + 3 * s * s * (1 - x2)
      if abs(x) < 1e-5 { return bez(s, y1, y2) }
      guard abs(d) > 1e-6 else { break }
      s = min(1, max(0, s - x / d))
    }
    var lo: CGFloat = 0, hi: CGFloat = 1
    s = t
    for _ in 0..<30 {
      let x = bez(s, x1, x2)
      if abs(x - t) < 1e-5 { break }
      if x < t { lo = s } else { hi = s }
      s = (lo + hi) / 2
    }
    return bez(s, y1, y2)
  }

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

// A floating pane growing out of its bar group and shrinking back onto it, always above the bar.
// The pane's glass stays at its full size the whole time and a mask at its corner shows as much of
// it as the motion has reached, since macOS draws glass by its size, frosted when large and clear
// when small, so a glass resized through the motion changed its look on the way. The mask starts on
// the group's rect and ends past the pane's edges by its shadow, so the rim and the shadow arrive
// with the shape rather than at the end. Everything is a function of one number, how open the pane
// is, so a motion cut short turns around from where it stands. Opening, the pane fades in over the
// group as it starts to grow and the group fades out under it, and closing does the same at the end
// of its shrink, the group fading back in under the pane. The pane's contents fade in as it grows.
// A mask and opacities on layers, stepped once a display frame so the group under it fades with it.
final class ShapeMotion: NSObject {
  private weak var view: NSView?
  private let content: NSView
  // The group the pane grows out of, faded against the pane, and its rect in the pane's coordinates.
  weak var group: NSView?
  var groupRect = NSRect.zero
  var radius: CGFloat = 0
  // How far past the pane's edges the mask ends, the room its glass's shadow takes.
  private let shadowRoom: CGFloat = 24

  private var link: CADisplayLink?
  // A window on no screen has no display to step by, so a timer steps it instead.
  private var timer: Timer?
  private var began: CFTimeInterval = 0
  private var duration: CFTimeInterval = 0
  private var curve = CAMediaTimingFunction(name: .linear)
  private var fromOpen: CGFloat = 0
  private var toOpen: CGFloat = 0
  private var fromClock: CGFloat = 0
  // The whole motion's length the way it is playing, open or close, which the fades are a share of.
  private var full: CFTimeInterval = 0
  private var ended: (() -> Void)?

  // How open the pane is, 0 on its group and 1 whole, along the curve, which the shape follows, and
  // the same along the clock, which the fades follow so each takes its own time in seconds.
  private(set) var openness: CGFloat = 0
  private var clock: CGFloat = 0
  var moving: Bool { link != nil || timer != nil }

  init(_ view: NSView, content: NSView) {
    self.view = view
    self.content = content
  }

  // Opens from wherever it stands and calls done once whole, at once with nothing to play.
  func open(done: @escaping () -> Void) {
    move(to: 1, duration: Motion.paneOpenDuration, curve: Motion.paneCurve, done: done)
  }

  // Closes from wherever it stands and calls done once it has faded off its group.
  func close(done: @escaping () -> Void) {
    move(to: 0, duration: Motion.paneCloseDuration, curve: Motion.paneCloseCurve, done: done)
  }

  // Down at once, with no callback, for a pane closed with its chooser.
  func stop() {
    stopClock()
    ended = nil
    openness = 0
    clock = 0
    rest()
  }

  private func move(to target: CGFloat, duration full: CFTimeInterval, curve: CAMediaTimingFunction,
    done: @escaping () -> Void) {
    guard let view else { return done() }
    stopClock()
    ended = nil
    if !moving, openness == target { return finish(done) }
    guard full > 0, !Motion.still, !groupRect.isEmpty else {
      openness = target
      clock = target
      return finish(done)
    }
    self.full = full
    fromOpen = openness
    fromClock = clock
    toOpen = target
    duration = full * Double(abs(target - clock))
    self.curve = curve
    began = CACurrentMediaTime()
    ended = done
    content.wantsLayer = true
    view.wantsLayer = true
    group?.wantsLayer = true
    if view.layer?.mask == nil {
      let mask = CALayer()
      mask.backgroundColor = NSColor.black.cgColor
      view.layer?.mask = mask
    }
    apply()
    if view.window?.screen != nil {
      let link = view.displayLink(target: self, selector: #selector(tick))
      link.add(to: .main, forMode: .common)
      self.link = link
    } else {
      let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.step() }
      RunLoop.main.add(timer, forMode: .common)
      self.timer = timer
    }
  }

  @objc private func tick(_ link: CADisplayLink) { step() }

  private func step() {
    let t = duration > 0 ? min(1, CGFloat((CACurrentMediaTime() - began) / duration)) : 1
    openness = fromOpen + (toOpen - fromOpen) * Motion.progress(curve, t)
    clock = fromClock + (toOpen - fromClock) * t
    apply()
    guard t >= 1 else { return }
    openness = toOpen
    clock = toOpen
    stopClock()
    let done = ended
    ended = nil
    finish(done ?? {})
  }

  private func finish(_ done: () -> Void) {
    rest()
    done()
  }

  // The share of the motion the pane takes to fade over its group, from the fade duration and the
  // length of the motion playing, so the fade is as long in seconds whichever way it plays.
  private var fadeShare: CGFloat {
    let total = max(full, 0.001)
    return max(0.001, min(1, CGFloat(Motion.paneFadeDuration / total)))
  }

  private func apply() {
    guard let view else { return }
    let whole = view.bounds.insetBy(dx: -shadowRoom, dy: -shadowRoom)
    let u = openness
    func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * u }
    let rect = NSRect(x: mix(groupRect.minX, whole.minX), y: mix(groupRect.minY, whole.minY),
      width: mix(groupRect.width, whole.width), height: mix(groupRect.height, whole.height))
    // The pane fades in over its group in the first fade's worth of the clock, and its contents in
    // the fade after that, so they are whole for all the time the pane is large and leave only as
    // it nears the group's size.
    let f = fadeShare
    let paneAlpha = min(1, clock / f)
    let contentAlpha = max(0, min(1, (clock - f / 2) / f))
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if let mask = view.layer?.mask {
      mask.cornerRadius = mix(radius, radius + shadowRoom)
      mask.frame = rect
    }
    view.layer?.opacity = Float(paneAlpha)
    content.layer?.opacity = Float(contentAlpha)
    group?.layer?.opacity = Float(1 - paneAlpha)
    CATransaction.commit()
  }

  private func stopClock() {
    link?.invalidate()
    link = nil
    timer?.invalidate()
    timer = nil
  }

  // At rest, whole or down. Unmasked and opaque, and the group opaque, since whether either shows
  // is then its own isHidden.
  private func rest() {
    view?.layer?.mask = nil
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    view?.layer?.opacity = 1
    content.layer?.opacity = 1
    group?.layer?.opacity = 1
    CATransaction.commit()
  }
}
