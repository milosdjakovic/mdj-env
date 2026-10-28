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
// THE CLICK OUTSIDE. A press outside the panel is heard by two event monitors, a global one for
// presses delivered to other applications and a local one for presses on Hammerspoon's own other
// windows, the docked pane among them, and reported with the point. The Lua view decides, so a
// press inside the companion rect keeps the list and asks refocus, and any other hides it. Losing
// key is never treated as a dismissal, since a click on the companion may take key from the
// panel, which is why refocus exists.

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
  private let root = FlippedView()
  private let field = NSTextField()
  private let list = ListView()
  private let bar = BarView()
  private let keys = KeysPanelView()
  private let ask: Ask
  private var surface: NSView
  private var style = Style()
  private var placement = Placement()
  private var state = ViewState()
  private var started = false
  private var inField = false
  private var lastRouted: NSEvent?
  private var lastClaimed = false
  private var monitors: [Any] = []
  private(set) var surfaceName = ""

  init(ask: @escaping Ask) {
    self.ask = ask
    window = KeyPanel(
      contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
      styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered, defer: true)
    surface = NSView()
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

    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.delegate = self
    field.cell?.isScrollable = true
    field.cell?.wraps = false
    field.cell?.usesSingleLineMode = true
    field.allowsEditingTextAttributes = false

    for view in [field, list, keys, bar] as [NSView] { root.addSubview(view) }
    keys.isHidden = true
    bar.isHidden = true

    list.table.onHover = { [weak self] index in _ = self?.ask("hover", [.int(index + 1)]) }
    list.table.onChoose = { [weak self] index in _ = self?.ask("choose", [.int(index + 1)]) }
    list.table.onRight = { [weak self] index in
      _ = self?.ask("rightClick", [index.map { .int($0 + 1) } ?? .none])
    }
    list.onScroll = { [weak self] y in _ = self?.ask("scroll", [.number(Double(y))]) }
    bar.button.onPress = { [weak self] in _ = self?.ask("toggleKeys", []) }

    surface = buildSurface()
    window.contentView = surface
  }

  // Glass where the running macOS ships it, and the visual effect view where it does not, so the
  // same build still draws a surface on an older system.
  private func buildSurface() -> NSView {
    if #available(macOS 26.0, *) {
      let glass = NSGlassEffectView()
      glass.contentView = root
      surfaceName = "glass"
      return glass
    }
    let effect = NSVisualEffectView()
    effect.material = .hudWindow
    effect.state = .active
    effect.blendingMode = .behindWindow
    effect.wantsLayer = true
    effect.layer?.masksToBounds = true
    root.autoresizingMask = [.width, .height]
    effect.addSubview(root)
    surfaceName = "visualEffect"
    return effect
  }

  // MARK: What the Lua view asks for

  var isVisible: Bool { window.isVisible }

  func applyStyle(_ next: Style) {
    style = next
    if #available(macOS 26.0, *), let glass = surface as? NSGlassEffectView {
      glass.cornerRadius = style.radius
    } else {
      surface.layer?.cornerRadius = style.radius
    }
    field.font = style.fieldFont
    field.textColor = style.text
    applyPlaceholder()
    list.apply(style: style, placement: placement)
  }

  func place(_ next: Placement) {
    placement = next
    window.setFrame(cocoaRect(next.canvas), display: window.isVisible)
    root.frame = NSRect(origin: .zero, size: next.canvas.size)
    if let rect = next.field {
      let h = ceil(style.fieldFont.ascender - style.fieldFont.descender + style.fieldFont.leading) + 2
      field.frame = NSRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h)
    }
    list.frame = next.list ?? .zero
    bar.frame = next.footer ?? .zero
    list.apply(style: style, placement: placement)
    layoutKeys()
  }

  func setRows(_ rows: [Row]) { list.setRows(rows) }

  func update(_ next: ViewState) {
    state = next
    field.isHidden = next.bare
    applyPlaceholder()
    list.update(next)
    if let footer = next.footer, placement.footer != nil {
      bar.isHidden = false
      bar.show(footer, style: style, placement: placement, lit: next.keysOpen)
      keys.isHidden = !next.keysOpen
      if next.keysOpen { keys.show(footer, style: style, pad: placement.keysPad) }
    } else {
      bar.isHidden = true
      keys.isHidden = true
    }
    layoutKeys()
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

  func hide() {
    list.table.forgetPress()
    window.orderOut(nil)
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
    let data = Self.data(of: event)
    if event.keyCode == KeyCode.escape {
      _ = ask("dismiss", [data])
      return true
    }
    if ask("yields", [data]) { return true }
    if ask("listKey", [data]) { return true }

    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if event.keyCode == KeyCode.backspace, mods.isDisjoint(with: [.command, .option, .control]),
      field.stringValue.isEmpty
    {
      _ = ask("emptyBackspace", [])
      return true
    }
    let caret = KeyCode.caret.contains(event.keyCode)
    if state.bare {
      if KeyCode.leftover.contains(event.keyCode) { _ = ask("leftover", [data]) }
      return true
    }
    if mods.contains(.command), let action = Self.editAction(event, mods) {
      throughField { NSApp.sendAction(action, to: nil, from: field) }
      return true
    }
    let leftover = KeyCode.leftover.contains(event.keyCode)
      || (mods.contains(.command) && !caret)
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

  // Return, Escape and the arrows never reach here, the router claims them first, so any command
  // the field editor still asks about is one the field must not act on by moving focus.
  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
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
    let mask: NSEvent.EventTypeMask = [.leftMouseDown, .scrollWheel]
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
    let point = Self.hsPoint(NSEvent.mouseLocation)
    switch event.type {
    case .leftMouseDown:
      _ = ask("pressOutside", [.number(point.x), .number(point.y)])
    case .scrollWheel:
      // The same two deltas lib/chooser/providers/default/mouse.lua reads, the point delta for a
      // trackpad and the line delta for a wheel.
      guard let cg = event.cgEvent else { return }
      let continuous = cg.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
      let dy = cg.getIntegerValueField(continuous ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventDeltaAxis1)
      if dy != 0 {
        _ = ask("scrollOutside", [.number(point.x), .number(point.y), .number(Double(dy)), .bool(continuous)])
      }
    default:
      break
    }
  }

  // MARK: Layout and coordinates

  private func applyPlaceholder() {
    field.placeholderAttributedString = NSAttributedString(string: state.placeholder,
      attributes: [.font: style.fieldFont, .foregroundColor: style.textDim])
  }

  // The key panel rises from the action bar's top edge over the rows, as tall as its keys and
  // never taller than the list.
  private func layoutKeys() {
    guard !keys.isHidden, let footer = placement.footer else { return }
    let top = placement.list?.minY ?? 0
    let h = min(keys.height(for: footer.width), max(0, footer.minY - top))
    keys.frame = NSRect(x: footer.minX, y: footer.minY - h, width: footer.width, height: h)
  }

  // Hammerspoon's screen space has its origin at the primary display's top left and y growing
  // down, AppKit's at its bottom left and y growing up, so both conversions flip about its height.
  private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

  private func cocoaRect(_ rect: NSRect) -> NSRect {
    NSRect(x: rect.minX, y: Self.primaryHeight - rect.maxY, width: rect.width, height: rect.height)
  }

  private static func hsPoint(_ point: NSPoint) -> NSPoint {
    NSPoint(x: point.x, y: primaryHeight - point.y)
  }
}
