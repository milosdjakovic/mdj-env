// The native view's window, a field over the list over the action bar on a glass surface. It
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
// ONE WINDOW, ONE SHAPE. With a companion the window spans the canvas rect, the engine's gap and
// the companion rect, and stands on one shape of glass, a SharedSurface, with the list's content
// at the canvas rect, the docked pane's region at the companion rect and a hairline divider in
// the middle of the gap down to the action bar, which spans the whole window. With none it is
// the canvas rect alone. The docked pane's native backend
// puts its view in the pane's region through the seam in Entry.swift, shown only while a pane is
// in it and shown. The window never animates, so nothing fades in.
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
// windows, a docked pane in a window of its own among them, and reported with the point. A press
// anywhere in this window, the gap and the pane included, lands on glass and is inside, so it is
// never reported. The Lua view decides the rest, so a press inside the span from the canvas to
// the companion keeps the list and asks refocus, and any other hides it. Losing key is never
// treated as a dismissal, since a click on a pane in its own window may take key from the panel,
// which is why refocus exists.

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

final class KeyPanel: NSPanel {
  weak var owner: ChooserPanel?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  // A titled window is kept below the menu bar and on screen by AppKit, and the Lua view already
  // places this one exactly on the canvas rect, so the frame it is handed is the frame it takes.
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

  override func sendEvent(_ event: NSEvent) {
    guard event.type == .keyDown, let owner else { super.sendEvent(event); return }
    if owner.claim(event) { return }
    owner.throughField { super.sendEvent(event) }
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.type == .keyDown, let owner, owner.claim(event) { return true }
    return super.performKeyEquivalent(with: event)
  }
}

final class ChooserPanel: NSObject, NSTextFieldDelegate {
  typealias Ask = (String, [LuaValue]) -> Bool

  private let window: KeyPanel
  private let root: FlippedView
  private let field = NSTextField()
  private let list = ListView()
  private let bar = BarView()
  private let keys = PopoverView()
  private let actionsPop = PopoverView()
  private let ask: Ask
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
  // The companion rect the engine last reported, in Hammerspoon's space, nil when there is none.
  private(set) var companion: NSRect?
  // The docked pane's view while one is in the pane's region, and whether it is shown.
  private weak var paneContent: NSView?
  private var paneShown = false
  private var windowSize = NSSize.zero

  init(ask: @escaping Ask) {
    self.ask = ask
    window = KeyPanel(
      contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
      styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered, defer: true)
    let content = FlippedView()
    root = content
    surfaces = SharedSurface(list: content)
    super.init()

    window.owner = self
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

    for view in [field, list] as [NSView] { root.addSubview(view) }
    // The bar and its key panel stand on the window's stage rather than in the list's content,
    // since with a companion they run under the gap and the pane too.
    surfaces.addOverlay(keys)
    surfaces.addOverlay(actionsPop)
    surfaces.addOverlay(bar)
    keys.isHidden = true
    actionsPop.isHidden = true
    bar.isHidden = true

    // While the action panel is open the engine's rows are the panel's, so the list behind it,
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
    list.onHighlight = { [weak self] index in
      guard let self, self.state.actions == nil else { return }
      _ = self.ask("highlighted", [.int(index)])
    }
    list.onScroll = { [weak self] y in
      guard let self, self.state.actions == nil else { return }
      _ = self.ask("scroll", [.number(Double(y))])
    }
    bar.button.onPress = { [weak self] in _ = self?.ask("toggleKeys", []) }
    bar.onEntry = { [weak self] action in _ = self?.ask("footerAction", [.string(action)]) }
    actionsPop.document.onHover = { [weak self] index in _ = self?.ask("hover", [.int(index)]) }
    actionsPop.document.onChoose = { [weak self] index in _ = self?.ask("choose", [.int(index)]) }

    window.contentView = surfaces.view
  }

  // MARK: What the Lua view asks for

  var isVisible: Bool { window.isVisible }

  func applyStyle(_ next: Style) {
    style = next
    surfaces.setCornerRadius(style.radius)
    surfaces.setDividerColor(style.divider)
    field.font = style.fieldFont
    field.textColor = style.text
    applyPlaceholder()
    list.apply(style: style, placement: placement)
  }

  func place(_ next: Placement) {
    placement = next
    companion = next.companion
    let frame = next.window ?? next.canvas
    windowSize = frame.size
    window.setFrame(ScreenSpace.cocoaRect(frame), display: window.isVisible)
    layoutSurfaces()
    if let rect = next.field {
      let h = ceil(style.fieldFont.ascender - style.fieldFont.descender + style.fieldFont.leading) + 2
      // The field editor starts its text one line fragment padding in, so the field stands that
      // far left of its rect and the caret lands on the rect's edge, the inset every other
      // surface takes.
      let lead = (window.fieldEditor(true, for: field) as? NSTextView)?.textContainer?.lineFragmentPadding ?? 0
      field.frame = NSRect(x: rect.minX - lead, y: rect.midY - h / 2, width: rect.width + lead, height: h)
    }
    // The bar floats. The list runs on down behind it to the window's bottom edge, its viewport
    // reaching that far and its content inset by the same height, so the furthest scroll and every
    // row the engine numbers sit where they did, and only the rows past them show behind the bar.
    let under = next.footer.map { $0.maxY - (next.list?.maxY ?? $0.minY) } ?? 0
    list.frame = next.list ?? .zero
    list.frame.size.height += max(0, under)
    list.underBar = max(0, under)
    bar.frame = toWindow(next.footer) ?? .zero
    list.apply(style: style, placement: placement)
    layoutKeys()
    layoutActions()
  }

  func setRows(_ rows: [Row]) { list.setRows(rows) }

  func setImages(_ images: [(Int, NSImage)]) { list.setImages(images) }

  func update(_ next: ViewState) {
    state = next
    field.isHidden = next.bare
    applyPlaceholder()
    list.update(next)
    if let footer = next.footer, placement.footer != nil {
      bar.isHidden = false
      bar.show(footer, style: style, placement: placement, lit: next.keysOpen)
      keys.isHidden = !next.keysOpen
      if next.keysOpen {
        keys.show(title: footer.title, lines: footer.keys.map { .init(label: $0.label, chord: $0.chord) },
          style: style, outer: placement.barPad, inner: placement.barPillPad, lineH: placement.barPillH,
          gap: placement.barGapWide, radius: style.highlightRadius)
      }
    } else {
      bar.isHidden = true
      keys.isHidden = true
    }
    if let actions = next.actions, !bar.isHidden {
      actionsPop.isHidden = false
      actionsPop.show(title: next.footer?.panelTitle,
        lines: actions.map { .init(label: $0.title, chord: $0.subtitle, image: $0.image, section: $0.section, enabled: $0.enabled) },
        style: style, outer: placement.barPad, inner: placement.barPillPad, lineH: placement.barPillH,
        gap: placement.barGapWide, radius: style.highlightRadius, iconSide: placement.keysIcon,
        highlight: next.actionsHighlight, selectable: true)
    } else {
      actionsPop.isHidden = true
    }
    layoutKeys()
    layoutActions()
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
    window.makeKeyAndOrderFront(nil)
    if !state.bare {
      window.makeFirstResponder(field)
      if let editor = field.currentEditor() as? NSTextView {
        editor.insertionPointColor = style.text
        editor.selectedTextAttributes = [.backgroundColor: style.highlight, .foregroundColor: style.text]
      }
    }
  }

  // The pane's region goes down with the window and comes back only when a pane shows again, so a
  // reopened list never shows the last pane's content before its pane repaints.
  func hide() {
    list.table.forgetPress()
    window.orderOut(nil)
    paneShown = false
    layoutSurfaces()
  }

  func start() {
    started = true
    startMonitors()
  }

  func stop() {
    started = false
    for monitor in monitors { NSEvent.removeMonitor(monitor) }
    monitors = []
  }

  // Gives the panel key again after a press the Lua view kept the list up for, once AppKit has
  // finished delivering that press, since the press may have handed key to the window it hit.
  func refocus() {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.window.isVisible, !self.window.isKeyWindow else { return }
      self.window.makeKey()
    }
  }

  // A key heard by another route, the focus hold's relay, taking the path a typed one takes.
  func feed(_ event: NSEvent) {
    if claim(event) { return }
    throughField { field.currentEditor()?.keyDown(with: event) }
  }

  // MARK: The docked pane's region

  private func layoutSurfaces() {
    let listFrame = placement.listFrame ?? NSRect(origin: .zero, size: placement.canvas.size)
    // The fade begins where the last row stands at the furthest scroll, the list's bottom padding
    // above the bar, so only what has scrolled under the bar softens.
    let barTop = toWindow(placement.footer)?.minY ?? windowSize.height
    surfaces.layout(size: windowSize, list: listFrame, pane: placement.paneFrame,
      divider: placement.dividerFrame, paneShown: paneShown && paneContent != nil,
      fadeTop: max(0, barTop - placement.padBottom))
  }

  // Whether this panel is up with a companion at rect, the question the seam in Entry.swift asks.
  func hostsPane(at rect: NSRect) -> Bool {
    guard window.isVisible, let companion else { return false }
    return ScreenSpace.same(companion, rect)
  }

  // Whether this window is up with a docked pane shown in its region, so a scroll over the
  // companion lands on the pane's own scroll view. The Lua view's scroll tap asks, through
  // hostsPane in Entry.swift, before it claims one.
  var hostsShownPane: Bool { window.isVisible && paneShown && paneContent != nil }

  // A docked pane's view moves into the pane's region, hidden until it is shown.
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
    layoutSurfaces()
  }

  func hidePane(_ view: NSView) {
    guard paneContent === view else { return }
    paneShown = false
    layoutSurfaces()
  }

  // The pane's view leaves, for its own window or for good.
  func releasePane(_ view: NSView) {
    guard paneContent === view else { return }
    paneContent = nil
    paneShown = false
    surfaces.vacatePane()
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

  // The key event as the bytes hs.eventtap.event.newEventFromData reads, so Lua hands the engine
  // an event with the key code, the flags and the autorepeat bit the event tap would have seen.
  private static func data(of event: NSEvent) -> LuaValue {
    guard let cg = event.cgEvent, let bytes = cg.data else { return .none }
    return .bytes(bytes as Data)
  }

  // Runs an edit through the field, then tells Lua the text once, however many change
  // notifications the edit raised. Text still being composed by an input method is not told.
  func throughField(_ body: () -> Void) {
    inField = true
    body()
    inField = false
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
      if let self, event.window !== self.window { self.outside(event) }
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

  // A rect in the canvas's own space moved into the window's, where the bar and its key panel
  // stand, since the canvas sits at the list's frame inside the window.
  private func toWindow(_ rect: NSRect?) -> NSRect? {
    guard let rect else { return nil }
    let origin = placement.listFrame?.origin ?? .zero
    return rect.offsetBy(dx: origin.x, dy: origin.y)
  }

  // The key panel is a popover standing above the keys group, its left edge on the group's and
  // the outer padding between them, as wide as its widest line and never wider than the window
  // less the outer padding on both sides, as tall as its lines and never above the list's top,
  // where it scrolls instead.
  // The action panel is the same popover above the action group, its right edge on the group's,
  // never wider than the window less the outer padding and never above the list's top.
  private func layoutActions() {
    guard !actionsPop.isHidden, let stage = actionsPop.superview else { return }
    bar.layoutSubtreeIfNeeded()
    let anchor = bar.convert(bar.actions.frame, to: stage)
    let top = toWindow(placement.list)?.minY ?? 0
    let bottom = anchor.minY - placement.barPad
    let size = actionsPop.preferredSize
    let w = min(size.width, max(0, anchor.maxX - placement.barPad))
    let h = min(size.height, max(0, bottom - top))
    actionsPop.frame = NSRect(x: anchor.maxX - w, y: bottom - h, width: w, height: h)
  }

  private func layoutKeys() {
    guard !keys.isHidden, let stage = keys.superview else { return }
    bar.layoutSubtreeIfNeeded()
    let anchor = bar.convert(bar.button.frame, to: stage)
    let top = toWindow(placement.list)?.minY ?? 0
    let bottom = anchor.minY - placement.barPad
    let size = keys.preferredSize
    let w = min(size.width, max(0, windowSize.width - anchor.minX - placement.barPad))
    let h = min(size.height, max(0, bottom - top))
    keys.frame = NSRect(x: anchor.minX, y: bottom - h, width: w, height: h)
  }
}
