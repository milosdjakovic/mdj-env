// The native view's window, a field over the list over the bottom bar on a glass surface. It
// holds no picker rule. It draws what the Lua view hands it and tells Lua, through the one ask
// function it was built with, every thing a person does, so the engine behind the Lua view
// decides what each of them means.
//
// It is a nonactivating panel that can become key, the shape Spotlight uses, so it takes the
// keyboard without making Hammerspoon the active application and without pulling the app below
// it out of the foreground. The spike measured that over Ghostty and over Safari.
//
// THE KEY ORDER. lib/chooser/view.lua states it and this file runs it, in claim below. Every key
// down reaches the panel's sendEvent, or its performKeyEquivalent first when it carries Command,
// and both ask claim before AppKit does anything with it. Escape is asked as dismiss and always
// claimed. Then yields, then listKey, each claimed when Lua answers true. Then the field's own
// part. Backspace on an empty field is emptyBackspace. The standard edit commands on Command are
// sent to the field editor. Up, Down, Return, keypad Enter, Tab, a function key, and every
// Command chord that is neither an edit command nor a caret move are keys the field never edits,
// so they go to Lua as leftover and are claimed, Command and a digit among them. Everything else
// goes to the field, which edits natively, and its text is reported once afterwards. While an
// input method holds marked text every key belongs to it and none is asked about.
//
// CONTROL CHORDS. Cocoa's text bindings answer far more Control chords than the canvas field
// reads, Control and O inserting a line break and Control and T transposing among them. So only
// the Control keys the Lua view names through setFieldKeys reach the field, the ones its field
// keymap reads, and every other Control chord is a leftover. The field's command filter below is
// a second fence, letting through only the editing commands those keys produce.
//
// ONE WINDOW, ONE SHAPE. With a preview pane the window spans the canvas rect, the engine's gap and
// the preview pane rect, and stands on one shape of glass, a SharedSurface, with the list's content
// at the canvas rect and the preview pane's region at the preview pane rect, nothing drawn between
// them, and the bottom bar spanning the whole window. With none it is
// the canvas rect alone. The preview pane's native backend
// puts its view in the pane's region through the seam in Entry.swift, shown only while a pane is
// in it and shown. AppKit's own window animation is off. The window fades in rising and growing a
// hair and fades out in place, see THE MOTION below, so the list and the preview pane come and go
// together as the one surface they are.
//
// THE OUTLINE. The window is titled, with its title bar see through, hidden and empty, rather
// than borderless. A key window gets an edge drawn along its outline, and a borderless window's
// outline is its square frame, so while the panel was key a faint square edge stood outside the
// glass's rounded corners, measured on 2026-10-29 at an alpha of 7 to 15 in the corner pixels
// and gone the moment the window lost key. A titled window's outline is rounded by the window
// server at the system window corner, which is the corner surface.cornerRadius is set to.
//
// THE CLICK OUTSIDE. A press outside the panel is heard by two event monitors, a global one for
// presses delivered to other applications and a local one for presses on Hammerspoon's own other
// windows, a preview pane in a window of its own among them, and reported with the point. A press
// anywhere in this window, the gap and the pane included, lands on glass and is inside, so it is
// never reported. The Lua view decides the rest, so a press inside the span from the canvas to
// the preview pane keeps the list and asks refocus, and any other hides it.
//
// THE FOCUS. The field holds focus for as long as the panel is up. Nothing in the window takes first
// responder from it, a click on a row, the bar, a floating pane or a preview pane's view included, and the
// panel losing key hides the list, the way a press outside does, since a list in front that no
// longer hears the keyboard reads as broken. That is what another application's own shortcut does,
// Antinote's taking key while the list stood over it, seen on 2026-10-31. A pane in a window of its
// own never becomes key, so a press on it cannot take key from the panel.
//
// THE MOTION. The window comes and goes through a WindowMotion in Motion.swift, the one way every
// surface here does. It fades out in place and stays key while it does, since its glass drew in the
// look of a window that is not key for the whole fade when it gave key up at once, through a stand
// in, seen on 2026-11-02. A key it hears in that time is passed on to the application in front.

import Cocoa

// The keys the field never edits and the two the router reads by code, named as the canvas
// field names them.
private enum KeyCode {
  static let escape: UInt16 = 53
  static let returnKey: UInt16 = 36
  static let keypadEnter: UInt16 = 76
  static let up: UInt16 = 126
  static let down: UInt16 = 125
  static let tab: UInt16 = 48
  static let backspace: UInt16 = 51

  // Keys the field never edits, whatever the modifiers.
  static let leftover: Set<UInt16> = [up, down, returnKey, keypadEnter, tab]

  // The caret and deletion keys the field editor answers itself, with Command too, Command and
  // Left going to the start of the line and Command and Backspace deleting to it.
  static let caret: Set<UInt16> = [123, 124, 115, 119, 116, 121, 117, backspace]
}

final class InfoPane: NSPanel {
  weak var owner: ChooserPanel?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }


  // A titled window is kept below the menu bar and on screen by AppKit, and the Lua view already
  // places this one exactly on the canvas rect, so the frame it is handed is the frame it takes.
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

  override func sendEvent(_ event: NSEvent) {
    // A key heard while the list fades out belongs to the application below, see THE MOTION.
    if owner?.isClosing == true, Motion.passOn(event) { return }
    guard event.type == .keyDown, let owner else { super.sendEvent(event); return }
    if owner.claim(event) { return }
    owner.throughField { super.sendEvent(event) }
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.type == .keyDown, let owner, owner.claim(event) { return true }
    return super.performKeyEquivalent(with: event)
  }

  // The field keeps first responder while the panel is up, see THE FOCUS above.
  override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
    if let owner, !owner.lets(responder) { return false }
    return super.makeFirstResponder(responder)
  }
}

final class ChooserPanel: NSObject, NSTextFieldDelegate {
  private let window: InfoPane
  private let root: FlippedView
  private let field = NSTextField()
  // The field's clip, the highlighted row's width, so text scrolled past either end is cut where a
  // highlighted row's edge is rather than at the field editor's own bounds.
  private let fieldClip = NSView()
  private let list = ListView()
  private let bar = BarView()
  private let keys = FloatingPaneView()
  private let actionsPop = FloatingPaneView()
  // The side that drives this panel, Source.swift, Lua's adapter in Entry.swift inside Hammerspoon.
  private let source: ChooserSource
  private let surfaces: SharedSurface
  private var style = Style()
  private var placement = Placement()
  private var state = ViewState()
  private var started = false
  private var inField = false
  private var lastRouted: NSEvent?
  private var lastClaimed = false
  private var monitors: [Any] = []
  private var controlKeys: Set<UInt16> = []
  private var controlBackspace: Set<UInt16> = []
  var surfaceName: String { surfaces.name }
  // The preview pane rect the engine last reported, in Hammerspoon's space, nil when there is none.
  private(set) var previewPane: NSRect?
  // The preview pane's view while one is in the pane's region, and whether it is shown.
  private weak var paneContent: NSView?
  private var paneShown = false
  // A pane hidden while the list stays up is still drawn until the window has narrowed over it, so
  // it is covered by the moving edge the way it is uncovered when the window widens, rather than
  // leaving the glass empty before the motion starts, Milos's ask on 2026-11-06. Which of the hide
  // and the narrowing Lua asks for first is not known, so the hide waits one turn of the run loop
  // for a narrowing to start and goes then if none did.
  private var paneLingers = false
  // A pane's view released while the list stays up, kept in the pane's region for the same turn or
  // narrowing, see paneLingers, and let go after unless something else has taken it since.
  private var lingeringView: NSView?
  // How the window comes and goes, see THE MOTION above.
  private lazy var motion: WindowMotion = {
    let motion = WindowMotion(window)
    motion.onDown = { [weak self] in self?.settleDown() }
    return motion
  }()
  private var windowSize = NSSize.zero

  init(source: ChooserSource) {
    self.source = source
    window = InfoPane(
      contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
      styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered, defer: true)
    let content = FlippedView()
    root = content
    surfaces = SharedSurface(list: content)
    super.init()

    window.owner = self
    NotificationCenter.default.addObserver(self, selector: #selector(resignedKey),
      name: NSWindow.didResignKeyNotification, object: window)
    window.isFloatingPanel = true
    window.level = .popUpMenu
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.hidesOnDeactivate = false
    window.isReleasedWhenClosed = false
    window.becomesKeyOnlyIfNeeded = false
    window.animationBehavior = .none
    // Titled for its outline alone, see THE OUTLINE above. The title bar is see through and empty,
    // the content runs under it, and nothing in it moves, zooms or closes the window.
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isMovable = false
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      window.standardWindowButton(button)?.isHidden = true
    }

    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.delegate = self
    field.cell?.isScrollable = true
    field.cell?.wraps = false
    field.cell?.usesSingleLineMode = true
    field.allowsEditingTextAttributes = false
    fieldClip.wantsLayer = true
    fieldClip.layer?.masksToBounds = true
    fieldClip.addSubview(field)

    root.addSubview(list)
    // The field stands on the window's stage over the list, which runs on up behind it, and out of
    // the content the fades mask, which faded the field with the rows behind it.
    surfaces.addOverlay(fieldClip)
    // The bar and its info pane stand on the window's stage rather than in the list's content,
    // since with a preview pane they run under the gap and the pane too.
    // The bar first, so a floating pane wider than the room beside the other group stands above it.
    surfaces.addOverlay(bar)
    surfaces.addOverlay(keys)
    surfaces.addOverlay(actionsPop)
    keys.isHidden = true
    actionsPop.isHidden = true
    // A group is hidden exactly while its pane stands over it.
    keys.onCover = { [weak self] covers in self?.bar.setGroup(left: true, hidden: covers) }
    actionsPop.onCover = { [weak self] covers in self?.bar.setGroup(left: false, hidden: covers) }
    keys.groupView = bar.button
    actionsPop.groupView = bar.actions
    bar.isHidden = true

    // While the actions pane is open the engine's rows are the panel's, so the list behind it,
    // still showing the rows it was opened over, answers no pointer of its own.
    list.table.onHover = { [weak self] index in
      guard let self, self.state.actions == nil else { return }
      self.list.hover(index)
    }
    list.table.onChoose = { [weak self] index in
      guard let self, self.state.actions == nil else { return }
      self.list.flushReports()
      _ = self.ask("choose", [.int(index + 1)])
    }
    list.table.onRight = { [weak self] index in
      guard let self, self.state.actions == nil else { return }
      self.list.flushReports()
      _ = self.ask("rightClick", [index.map { .int($0 + 1) } ?? .none])
    }
    list.onLive = { [weak self] on in _ = self?.ask("liveScroll", [.bool(on)]) }
    list.onWantIcons = { [weak self] indices in
      guard let self, self.state.actions == nil else { return }
      _ = self.ask("wantIcons", [.string(indices.map { String($0 + 1) }.joined(separator: ","))])
    }
    list.onHighlight = { [weak self] index, byPointer in
      guard let self, self.state.actions == nil else { return }
      _ = self.ask("highlighted", [.int(index), .bool(byPointer)])
    }
    list.onScroll = { [weak self] y in
      guard let self, self.state.actions == nil else { return }
      _ = self.ask("scroll", [.number(Double(y))])
    }
    bar.button.onPress = { [weak self] in _ = self?.ask("toggleInfo", []) }
    bar.onItem = { [weak self] action in _ = self?.ask("bottomBarAction", [.string(action)]) }
    actionsPop.document.onHover = { [weak self] index in _ = self?.ask("hover", [.int(index)]) }
    actionsPop.document.onChoose = { [weak self] index in _ = self?.ask("choose", [.int(index)]) }

    window.contentView = surfaces.view
  }

  // MARK: What the Lua view asks for

  // Up and not on its way down, so a list fading out is already closed to Lua and to a pane.
  var isVisible: Bool { motion.isUp }
  var isClosing: Bool { motion.closing }

  func applyStyle(_ next: Style) {
    style = next
    surfaces.setCornerRadius(style.radius)
    field.font = style.fieldFont
    field.textColor = style.text
    applyPlaceholder()
    list.apply(style: style, placement: placement)
  }

  // A preview pane arriving or leaving while the list is up widens or narrows the window over a
  // ReshapeMotion rather than in one jump, the window's real frame stepping from what is on screen to
  // what Lua placed. Everything is laid out once, at the wider of the two shapes, so the list stays
  // where it stands against the window's left edge, which moves with it, and the pane's region is
  // uncovered or covered by the right edge. Only the window's frame and the bar's width, which spans
  // the window, follow each step, and the new shape is laid out alone when it ends. A place that asks
  // for another shape mid motion, a list's key pressed while it plays, turns it from where the window
  // stands rather than jumping to where it was going first. The preview pane rect is the new one at
  // once, since a pane is matched to this panel on it.
  func place(_ next: Placement) {
    Perf.note("place pane \(next.paneFrame != nil) was \(placement.paneFrame != nil) moving \(reshape.moving)")
    settleReshape()
    previewPane = next.previewPane
    var from = placement
    var old = Self.frame(of: from)
    var turned = false
    if reshape.moving {
      if ScreenSpace.same(Self.frame(of: next), Self.frame(of: reshapeTarget)) {
        reshapeTarget = next
        return
      }
      // Turned mid way, from the shape Lua last placed and the frame the window stands at now.
      from = reshapeTarget
      from.window = placement.window
      from.paneFrame = placement.paneFrame ?? reshapeTarget.paneFrame
      from.bottomBar = placement.bottomBar
      old = reshape.at
      reshape.stop()
      turned = true
    }
    let target = Self.frame(of: next)
    let changes = (turned || (from.paneFrame == nil) != (next.paneFrame == nil)) && !ScreenSpace.same(old, target)
    guard isVisible, window.isVisible, changes, Motion.reshapeDuration > 0, !Motion.still else {
      endLinger()
      lay(next)
      return
    }
    // Narrowing keeps the pane's region and the bar's width it had until the right edge has passed.
    var wide = next
    if target.width < old.width {
      wide.window = from.window
      wide.paneFrame = from.paneFrame
      wide.bottomBar = from.bottomBar
    }
    reshapeTarget = next
    lay(wide, at: old)
    reshape.play(on: root, from: old, to: target,
      step: { [weak self] frame, u in self?.stepShape(frame, u) },
      done: { [weak self] in self?.finishReshape() })
  }

  private lazy var reshape = ReshapeMotion()
  private var reshapeTarget = Placement()
  // A reshape stopped by a close, whose shape is still to be laid out.
  private var reshapeOwed = false

  private func settleReshape() {
    guard reshapeOwed else { return }
    reshapeOwed = false
    finishReshape()
  }

  // The window at one frame of a reshape, everything in it where the wide layout put it but the
  // surfaces' size and the bar's width, which follow the window's.
  private func stepShape(_ frame: NSRect, _ u: CGFloat) {
    windowSize = frame.size
    window.setFrame(ScreenSpace.cocoaRect(frame), display: true)
    layoutSurfaces()
    layoutBar(at: frame)
    bar.followMorph(u)
    window.invalidateShadow()
  }

  // The bar spans the window, so a window narrower than its placement's takes as much off the bar.
  private func layoutBar(at frame: NSRect? = nil) {
    var rect = toWindow(placement.bottomBar) ?? .zero
    if let frame { rect.size.width = max(0, rect.width - (Self.frame(of: placement).width - frame.width)) }
    bar.frame = rect
  }

  // The window on its new shape alone.
  private func finishReshape() {
    reshape.stop()
    bar.finishMorph()
    endLinger()
    lay(reshapeTarget)
  }

  private static func frame(of p: Placement) -> NSRect { p.window ?? p.canvas }

  // Lays the window and everything in it out on next, the window standing at shown when one is
  // given rather than at next's own frame, which is where a reshape starts.
  private func lay(_ next: Placement, at shown: NSRect? = nil) {
    placement = next
    let frame = shown ?? Self.frame(of: next)
    windowSize = frame.size
    window.setFrame(ScreenSpace.cocoaRect(frame), display: window.isVisible)
    layoutSurfaces()
    if let rect = next.field {
      let h = ceil(style.fieldFont.ascender - style.fieldFont.descender + style.fieldFont.leading) + 2
      // The field editor keeps one line fragment padding inside each end, so the field stands
      // that far past its rect on both sides and the caret lands on the rect's edge, the
      // highlighted row's edge. Its clip is the rect itself, so text scrolled past either end is
      // cut on the row's edges too.
      let lead = (window.fieldEditor(true, for: field) as? NSTextView)?.textContainer?.lineFragmentPadding ?? 0
      let inWindow = toWindow(rect) ?? rect
      fieldClip.frame = NSRect(x: inWindow.minX, y: inWindow.midY - h / 2, width: inWindow.width, height: h)
      field.frame = NSRect(x: -lead, y: 0, width: inWindow.width + 2 * lead, height: h)
    }
    // The bar floats. The list runs on down behind it to the window's bottom edge, its viewport
    // reaching that far and its content inset by the same height, so the furthest scroll and every
    // row the engine numbers sit where they did, and only the rows past them show behind the bar.
    // It runs on up behind the field in the same way, inset at the top by as much, so a row the
    // engine places at the band's top still sits there and only rows scrolled above it show behind
    // the field. It stops at the title bar's bottom edge, since a scroll view under the title bar
    // gets AppKit's own scroll edge effect, a blur with a hard edge over the field and the first
    // row, seen on 2026-10-31, which no setting turned off. The fade is clear by that edge.
    // It reaches the canvas's bottom edge, below the bar's own padding, so the faded rows touch the
    // window's edge rather than stopping a padding short of it.
    let under = next.bottomBar.map { _ in next.canvas.height - (next.list?.maxY ?? next.canvas.height) } ?? 0
    let over = max(0, (next.list?.minY ?? 0) - titlebarHeight)
    list.frame = next.list ?? .zero
    list.frame.origin.y -= over
    list.frame.size.height += max(0, under) + over
    list.underBar = max(0, under)
    list.overField = over
    layoutBar(at: shown)
    list.apply(style: style, placement: placement)
    layoutKeys()
    layoutActions()
  }

  func setRows(_ rows: [Row]) {
    list.setRows(rows)
    Timings.rowsSent()
  }

  func setImages(_ images: [(Int, NSImage, Bool)]) { list.setImages(images) }

  // Moves the highlight one row the way an arrow does, wrapping and scrolling only to show it, for
  // a list key heard outside the panel, Olm.app's verbs from Hammerspoon's leaders.
  func move(_ delta: Int) {
    list.flushReports()
    list.move(delta)
  }

  func update(_ next: ViewState) {
    state = next
    fieldClip.isHidden = next.bare
    applyPlaceholder()
    list.update(next)
    if let bottomBar = next.bottomBar, placement.bottomBar != nil {
      bar.isHidden = false
      // Neither group is lit for the pane it opens, which grows out of it and hides it, so a group
      // fading under its pane keeps the look it had at rest.
      bar.show(bottomBar, style: style, placement: placement, lit: false,
        leftHidden: keys.coversGroup, actionsHidden: actionsPop.coversGroup,
        keepRight: next.actions != nil)
      keys.setOpen(next.infoOpen)
      if next.infoOpen {
        keys.show(title: bottomBar.title, lines: bottomBar.keys.map { .init(label: $0.label, chord: $0.chord, lead: $0.lead, section: $0.section) },
          style: style, placement: placement, outer: placement.barPillPad, inner: placement.barPillPad, lineH: placement.barPillH,
          gap: placement.barGapWide, radius: style.highlightRadius)
      }
    } else {
      bar.isHidden = true
      keys.setOpen(false)
    }
    if let actions = next.actions, !bar.isHidden {
      actionsPop.setOpen(true)
      actionsPop.show(title: next.bottomBar?.panelTitle,
        lines: actions.map { .init(label: $0.title, chord: $0.chord, image: $0.image, tint: $0.tint, section: $0.section,
          enabled: $0.enabled) },
        style: style, placement: placement, outer: placement.barPillPad, inner: placement.barPillPad, lineH: placement.barPillH,
        gap: placement.barGapWide, radius: style.highlightRadius, iconSide: placement.infoIcon,
        highlight: next.actionsHighlight)
    } else {
      actionsPop.setOpen(false)
    }
    layoutKeys()
    layoutActions()
    keys.play()
    actionsPop.play()
  }

  var text: String { field.stringValue }

  // Replaces the text with the caret after it and nothing selected, through the field editor
  // while it is editing, since setting the value under an active editor would be overwritten.
  func setText(_ text: String) {
    if let editor = field.currentEditor() {
      editor.string = text
      editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
    } else {
      field.stringValue = text
    }
  }

  func show() {
    settleReshape()
    motion.show { window.makeKeyAndOrderFront(nil) }
    if !state.bare {
      window.makeFirstResponder(field)
      if let editor = field.currentEditor() as? NSTextView {
        editor.insertionPointColor = style.text
        editor.selectedTextAttributes = [.backgroundColor: style.highlight, .foregroundColor: style.text]
      }
    }
  }

  // animated false goes down at once, which a reload's cleanup asks for.
  func hide(animated: Bool = true) {
    list.table.forgetPress()
    // A reshape cut short by a close stops where the window stands and fades out from there, and
    // the shape it was going to is laid out once the window is down, so the next open starts on it.
    if reshape.moving {
      reshape.stop()
      reshapeOwed = true
    }
    motion.hide(animated: animated)
    if !animated { settleReshape() }
  }

  // What a list down forgets, once its fade has ended, the preview pane's region and any floating
  // pane left open, so a reopened list never shows the last pane's content before its pane repaints.
  private func settleDown() {
    keys.closeNow()
    actionsPop.closeNow()
    paneShown = false
    endLinger()
    settleReshape()
    layoutSurfaces()
  }


  func start() {
    started = true
    startMonitors()
    Timings.begin()
  }

  func stop() {
    if started { Timings.finish(list: state.placeholder) }
    started = false
    for monitor in monitors { NSEvent.removeMonitor(monitor) }
    monitors = []
  }

  // Whether responder may take first responder, anything while the panel is down or has no field,
  // and otherwise the field and the editor it edits through alone.
  func lets(_ responder: NSResponder?) -> Bool {
    guard window.isVisible, !state.bare else { return true }
    if responder === field { return true }
    if let editor = responder as? NSTextView, editor.isFieldEditor,
      editor === field.currentEditor() || editor.delegate === field || field.currentEditor() == nil {
      return true
    }
    return false
  }

  // The panel lost key while up, so the list goes down, decided once AppKit has settled, since an
  // orderOut resigns key on the way down and a refocus may already have taken it back.
  @objc private func resignedKey() {
    guard started else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.started, self.window.isVisible, !self.window.isKeyWindow else { return }
      _ = self.ask("resignedKey", [])
    }
  }

  // Gives the panel key again after a press the Lua view kept the list up for, once AppKit has
  // finished delivering that press, since the press may have handed key to the window it hit.
  func refocus() {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.isVisible, !self.window.isKeyWindow else { return }
      self.window.makeKey()
    }
  }

  // A key heard by another route, the focus hold's relay, taking the path a typed one takes.
  func feed(_ event: NSEvent) {
    if claim(event) { return }
    throughField { field.currentEditor()?.keyDown(with: event) }
  }

  // How far the title bar reaches down from the window's top, which the list stays below.
  private var titlebarHeight: CGFloat {
    max(0, window.frame.height - window.contentLayoutRect.maxY)
  }

  // MARK: The preview pane's region

  private func layoutSurfaces() {
    let listFrame = placement.listFrame ?? NSRect(origin: .zero, size: placement.canvas.size)
    // The fade begins where the last row stands at the furthest scroll, the list's bottom padding
    // above the bar, so only what has scrolled under the bar softens.
    // The top fade is clear down to the title bar's bottom edge, where the list stops, and rises
    // along one smooth curve to full where the first row rests. The pane's column rises along the
    // same curve from its own top edge to where its content rests, the outer padding below it.
    let barTop = toWindow(placement.bottomBar)?.minY ?? windowSize.height
    let listTop = toWindow(placement.list)?.minY ?? 0
    surfaces.layout(size: windowSize, list: listFrame, pane: placement.paneFrame,
      paneShown: (paneShown && paneContent != nil) || (paneLingers && (paneContent != nil || lingeringView != nil)),
      fadeTop: max(0, barTop - placement.padBottom), fadeListTop: listTop,
      fadeClearTo: min(titlebarHeight, listTop),
      listColumn: listFrame.maxX, paneTop: placement.paneFrame?.minY ?? 0,
      paneRest: (placement.paneFrame?.minY ?? 0) + placement.pad)
  }

  // Whether this panel is up with a preview pane at rect, the question the seam in Entry.swift asks.
  func hostsPane(at rect: NSRect) -> Bool {
    guard isVisible, let previewPane else { return false }
    return ScreenSpace.same(previewPane, rect)
  }

  // Whether this window is up with a preview pane shown in its region, so a scroll over the
  // preview pane lands on the pane's own scroll view. The Lua view's scroll tap asks, through
  // hostsPane in Entry.swift, before it claims one.
  var hostsShownPane: Bool { isVisible && paneShown && paneContent != nil }

  // A preview pane's view moves into the pane's region, hidden until it is shown.
  func adoptPane(_ view: NSView) {
    if paneContent !== view {
      paneContent = view
      paneShown = false
      surfaces.holdPane(view)
    }
    layoutSurfaces()
  }

  func showPane(_ view: NSView) {
    guard paneContent === view else { return }
    paneShown = true
    endLinger()
    layoutSurfaces()
  }

  // While the list fades out the pane's region fades with it, and goes when the fade ends.
  func hidePane(_ view: NSView) {
    Perf.note("pane hide shown \(paneShown) moving \(reshape.moving)")
    guard paneContent === view else { return }
    if paneShown { linger() }
    paneShown = false
    if !motion.closing { layoutSurfaces() }
  }

  // Keeps the pane drawn while the list stays up, see paneLingers.
  private func linger() {
    guard isVisible, !motion.closing, Motion.reshapeDuration > 0, !Motion.still, !paneLingers else { return }
    paneLingers = true
    DispatchQueue.main.async { [weak self] in
      guard let self, self.paneLingers, !self.reshape.moving else { return }
      self.endLinger()
      self.layoutSurfaces()
    }
  }

  private func endLinger() {
    paneLingers = false
    if let view = lingeringView {
      lingeringView = nil
      if paneContent == nil, view.superview != nil, surfaces.holdsPane(view) { surfaces.vacatePane() }
    }
  }

  // The pane's view leaves, for its own window or for good.
  func releasePane(_ view: NSView) {
    Perf.note("pane release shown \(paneShown) lingers \(paneLingers) moving \(reshape.moving)")
    guard paneContent === view else { return }
    let keep = paneShown || paneLingers
    paneContent = nil
    paneShown = false
    if keep, isVisible, !motion.closing, Motion.reshapeDuration > 0, !Motion.still {
      lingeringView = view
      linger()
    } else {
      endLinger()
      surfaces.vacatePane()
    }
    layoutSurfaces()
  }

  // MARK: Keys

  private var editor: NSTextView? { field.currentEditor() as? NSTextView }

  // Asked by the window for every key down, sometimes twice for one event, once as a key
  // equivalent and once as a plain event, so the first answer is kept and repeated.
  func claim(_ event: NSEvent) -> Bool {
    if event === lastRouted { return lastClaimed }
    lastRouted = event
    lastClaimed = decide(event)
    return lastClaimed
  }

  private func decide(_ event: NSEvent) -> Bool {
    guard started else { return false }
    if editor?.hasMarkedText() == true { return false }
    // The arrows move the list's own highlight, with any modifiers held as before, unless a held
    // leader or a list key claims the press first.
    let arrow = event.keyCode == KeyCode.up || event.keyCode == KeyCode.down
    let native = arrow && state.actions == nil
    // Lua acts on the highlight and the viewport from here on, so it hears both as they are.
    list.flushReports()
    let data = Self.data(of: event)
    if event.keyCode == KeyCode.escape {
      _ = ask("dismiss", [data])
      return true
    }
    if ask("yields", [data]) { return true }
    if ask("listKey", [data]) { return true }

    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function])
    let backward = (event.keyCode == KeyCode.backspace && mods.isDisjoint(with: [.command, .option, .control]))
      || (mods == .control && controlBackspace.contains(event.keyCode))
    if backward, field.stringValue.isEmpty {
      _ = ask("emptyBackspace", [])
      return true
    }
    let caret = KeyCode.caret.contains(event.keyCode)
    if native {
      list.move(event.keyCode == KeyCode.down ? 1 : -1)
      return true
    }
    if state.bare {
      if KeyCode.leftover.contains(event.keyCode) { _ = ask("leftover", [data]) }
      return true
    }
    if mods.contains(.command), let action = Self.editAction(event, mods) {
      throughField { NSApp.sendAction(action, to: nil, from: field) }
      return true
    }
    let fieldControl = mods == .control && controlKeys.contains(event.keyCode)
    let leftover = KeyCode.leftover.contains(event.keyCode)
      || (mods.contains(.command) && !caret)
      || (mods.contains(.control) && !fieldControl)
      || (event.specialKey != nil && !caret)
    if leftover {
      _ = ask("leftover", [data])
      return true
    }
    return false
  }

  // The standard edits a single line field answers on Command, which the field editor only
  // receives through a menu that a panel over another application cannot rely on.
  private static func editAction(_ event: NSEvent, _ mods: NSEvent.ModifierFlags) -> Selector? {
    let shift = mods.contains(.shift)
    let others = mods.subtracting([.command, .shift, .capsLock, .numericPad, .function])
    guard others.isEmpty else { return nil }
    switch event.charactersIgnoringModifiers?.lowercased() {
    case "a" where !shift: return #selector(NSText.selectAll(_:))
    case "c" where !shift: return #selector(NSText.copy(_:))
    case "v" where !shift: return #selector(NSText.paste(_:))
    case "x" where !shift: return #selector(NSText.cut(_:))
    case "z": return shift ? Selector(("redo:")) : Selector(("undo:"))
    default: return nil
    }
  }

  // Tells the driver an event, see Source.swift.
  @discardableResult
  private func ask(_ event: String, _ args: [PanelValue]) -> Bool { source.ask(event, args) }

  // The key event as the bytes hs.eventtap.event.newEventFromData reads, so Lua hands the engine
  // an event with the key code, the flags and the autorepeat bit the event tap would have seen.
  private static func data(of event: NSEvent) -> PanelValue {
    guard let cg = event.cgEvent, let bytes = cg.data else { return .none }
    return .bytes(bytes as Data)
  }

  // Runs an edit through the field, then tells Lua the text once, however many change
  // notifications the edit raised. Text still being composed by an input method is not told.
  func throughField(_ body: () -> Void) {
    let before = field.stringValue
    let key = NSApp.currentEvent.flatMap { $0.type == .keyDown ? $0.timestamp : nil }
    inField = true
    body()
    inField = false
    if field.stringValue != before { Timings.typed(at: key) }
    reportText()
  }

  private func reportText() {
    guard started, editor?.hasMarkedText() != true else { return }
    _ = ask("text", [.string(field.stringValue)])
  }

  // A change that did not come through a key, a drop or an input method committing on a click.
  func controlTextDidChange(_ obj: Notification) {
    if !inField { reportText() }
  }

  // The Control keys the field may edit with, by key code, and the ones among them that delete
  // backward and so stand for Backspace on an empty field, as the Lua view's field keys say.
  func setFieldKeys(control: Set<UInt16>, backspace: Set<UInt16>) {
    controlKeys = control
    controlBackspace = backspace
  }

  // The editing commands the named Control keys produce through Cocoa's standard bindings.
  private static let controlCommands: Set<Selector> = [
    #selector(NSResponder.moveToBeginningOfParagraph(_:)), #selector(NSResponder.moveToEndOfParagraph(_:)),
    #selector(NSResponder.moveToBeginningOfLine(_:)), #selector(NSResponder.moveToEndOfLine(_:)),
    #selector(NSResponder.moveBackward(_:)), #selector(NSResponder.moveForward(_:)),
    #selector(NSResponder.deleteForward(_:)), #selector(NSResponder.deleteBackward(_:)),
    #selector(NSResponder.deleteBackwardByDecomposingPreviousCharacter(_:)),
    #selector(NSResponder.deleteToEndOfParagraph(_:)), #selector(NSResponder.deleteToEndOfLine(_:)),
  ]

  // Return, Escape and the arrows never reach here, the router claims them first, so any command
  // the field editor still asks about is one the field must not act on by moving focus. A command
  // a Control chord produced is let through only when it is one of the editing commands above.
  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    if NSApp.currentEvent?.modifierFlags.contains(.control) == true {
      return !Self.controlCommands.contains(selector)
    }
    switch selector {
    case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)),
      #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:)):
      return true
    default:
      return false
    }
  }

  // MARK: The pointer outside the panel

  private func startMonitors() {
    guard monitors.isEmpty else { return }
    let mask: NSEvent.EventTypeMask = [.leftMouseDown]
    if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
      self?.outside(event)
    }) {
      monitors.append(global)
    }
    if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
      guard let self else { return event }
      if event.window !== self.window {
        self.outside(event)
        return event
      }
      // With the info pane open a press anywhere else in this window only closes it, and a press
      // on the panel itself is the panel's, which does nothing with it.
      if self.keys.isOpen, let content = self.window.contentView {
        let hit = content.hitTest(content.convert(event.locationInWindow, from: nil))
        if let hit, hit.isDescendant(of: self.keys) { return event }
        _ = self.ask("closeInfo", [])
        return nil
      }
      return event
    }) {
      monitors.append(local)
    }
  }

  private func outside(_ event: NSEvent) {
    guard started else { return }
    guard event.type == .leftMouseDown else { return }
    let point = ScreenSpace.hsPoint(NSEvent.mouseLocation)
    _ = ask("pressOutside", [.number(point.x), .number(point.y)])
  }

  // MARK: Layout and coordinates

  private func applyPlaceholder() {
    field.placeholderAttributedString = NSAttributedString(string: state.placeholder,
      attributes: [.font: style.fieldFont, .foregroundColor: style.textDim])
  }

  // A rect in the canvas's own space moved into the window's, where the bar and its info pane
  // stand, since the canvas sits at the list's frame inside the window.
  private func toWindow(_ rect: NSRect?) -> NSRect? {
    guard let rect else { return nil }
    let origin = placement.listFrame?.origin ?? .zero
    return rect.offsetBy(dx: origin.x, dy: origin.y)
  }

  // Both floating panes follow one rule, floatingpane.lua's place, written once for a pane standing
  // on the left and mirrored for one on the right, so a change to it reaches both, Milos's call on
  // 2026-11-04. The info pane takes the left side's corner, its left and bottom edges on the
  // group's, and the actions pane the action group's, its right and bottom edges on it, the group
  // under it hidden and the other staying. A pane is as wide as its lines laid out as a table and
  // never narrower than its floor, the group it stands above, and stops only the bar pad clear of
  // the window's far edge, past which its labels truncate, so a pane wider than the room beside
  // the other group stands over it, the panes added above the bar. It is as tall as its lines and
  // never above the list's top, where it scrolls instead.
  static func floatingFrame(size: NSSize, anchor: NSRect, floor: CGFloat,
                            leading: Bool, width: CGFloat, top: CGFloat, pad: CGFloat) -> NSRect {
    func mirror(_ r: NSRect) -> NSRect {
      leading ? r : NSRect(x: width - r.maxX, y: r.minY, width: r.width, height: r.height)
    }
    let a = mirror(anchor)
    let w = min(max(size.width, floor), max(0, width - pad - a.minX))
    let h = min(size.height, max(0, a.maxY - top))
    return mirror(NSRect(x: a.minX, y: a.maxY - h, width: w, height: h))
  }

  private func layoutActions() {
    // While the actions pane is open the bar describes the panel and its right side is shorter, so
    // the width the right side had at rest, the group the person pressed from, is kept as the floor.
    if !actionsPop.isOpen {
      if !bar.isHidden {
        bar.layoutSubtreeIfNeeded()
        restActionsWidth = bar.actionsWidth
      }
      return
    }
    guard let stage = actionsPop.superview else { return }
    bar.layoutSubtreeIfNeeded()
    let anchor = bar.convert(bar.actions.frame, to: stage)
    // The group's width while open is not the floor, since its Return label follows the lit line
    // and would move the pane's width as the highlight moves.
    let rest = restActionsWidth > 0 ? restActionsWidth : anchor.width
    actionsPop.frame = ChooserPanel.floatingFrame(
      size: actionsPop.preferredSize, anchor: anchor, floor: rest,
      leading: false, width: windowSize.width,
      top: toWindow(placement.list)?.minY ?? 0, pad: placement.barPad)
    // The right side as it stood at rest, the group the pane grows out of and folds back onto, on
    // the pane's bottom right corner.
    let pane = actionsPop.frame.size
    actionsPop.group = NSRect(x: pane.width - min(rest, pane.width), y: pane.height - min(anchor.height, pane.height),
      width: min(rest, pane.width), height: min(anchor.height, pane.height))
  }

  private var restActionsWidth: CGFloat = 0

  private func layoutKeys() {
    guard keys.isOpen, let stage = keys.superview else { return }
    bar.layoutSubtreeIfNeeded()
    let anchor = bar.convert(bar.button.frame, to: stage)
    keys.frame = ChooserPanel.floatingFrame(
      size: keys.preferredSize, anchor: anchor, floor: anchor.width,
      leading: true, width: windowSize.width,
      top: toWindow(placement.list)?.minY ?? 0, pad: placement.barPad)
    // The left side, the group the pane grows out of and folds back onto, on its bottom left corner.
    let pane = keys.frame.size
    keys.group = NSRect(x: 0, y: pane.height - min(anchor.height, pane.height),
      width: min(anchor.width, pane.width), height: min(anchor.height, pane.height))
  }
}
