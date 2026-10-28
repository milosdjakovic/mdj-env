// The native panel, a field over a list on a glass surface. It knows nothing about Lua. Every
// thing a person does that Lua has to hear about leaves through onEvent, query when the text
// changes, choose with the row when Return is pressed, and dismiss when Escape is pressed or the
// panel loses key.
//
// It is a nonactivating panel that can become key, the shape Spotlight uses, so it takes the
// keyboard without making Hammerspoon the active application and without pulling the app below
// it out of the foreground. Whether that holds over Safari is the first thing the spike measures.

import Cocoa

final class KeyPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

final class ChooserPanel: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate,
  NSWindowDelegate
{
  private let window: KeyPanel
  private let field = NSTextField()
  private let table = NSTableView()
  private let scroll = NSScrollView()
  private let onEvent: (String, Any?) -> Void
  private var rows: [String] = []
  private(set) var surfaceName = ""

  private static let width: CGFloat = 640
  private static let height: CGFloat = 420
  private static let radius: CGFloat = 18
  private static let rowHeight: CGFloat = 34
  private static let cellID = NSUserInterfaceItemIdentifier("olm.row")

  init(onEvent: @escaping (String, Any?) -> Void) {
    self.onEvent = onEvent
    window = KeyPanel(
      contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
      styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered, defer: true)
    super.init()

    window.isFloatingPanel = true
    window.level = .modalPanel
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.hidesOnDeactivate = false
    window.isReleasedWhenClosed = false
    window.becomesKeyOnlyIfNeeded = false
    window.delegate = self

    let stack = buildStack()
    window.contentView = buildSurface(around: stack)
  }

  private func buildStack() -> NSView {
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = .systemFont(ofSize: 22, weight: .regular)
    field.placeholderString = "Search"
    field.delegate = self
    field.cell?.isScrollable = true
    field.cell?.wraps = false

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
    table.addTableColumn(column)
    table.headerView = nil
    table.backgroundColor = .clear
    table.style = .inset
    table.rowHeight = Self.rowHeight
    table.intercellSpacing = NSSize(width: 0, height: 2)
    table.dataSource = self
    table.delegate = self
    table.target = self
    table.doubleAction = #selector(chooseClicked)
    table.refusesFirstResponder = true

    scroll.documentView = table
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true

    let divider = NSBox()
    divider.boxType = .separator

    let stack = NSView()
    for view in [field, divider, scroll] as [NSView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      stack.addSubview(view)
    }
    NSLayoutConstraint.activate([
      field.topAnchor.constraint(equalTo: stack.topAnchor, constant: 18),
      field.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 20),
      field.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -20),
      divider.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 14),
      divider.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
      divider.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 6),
      scroll.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 6),
      scroll.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -6),
      scroll.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: -8),
    ])
    return stack
  }

  // Glass where the running macOS ships it, and the visual effect view where it does not, so the
  // same build still draws a surface on an older system.
  private func buildSurface(around stack: NSView) -> NSView {
    if #available(macOS 26.0, *) {
      let glass = NSGlassEffectView()
      glass.cornerRadius = Self.radius
      glass.contentView = stack
      surfaceName = "glass"
      return glass
    }
    let effect = NSVisualEffectView()
    effect.material = .hudWindow
    effect.state = .active
    effect.blendingMode = .behindWindow
    effect.wantsLayer = true
    effect.layer?.cornerRadius = Self.radius
    effect.layer?.masksToBounds = true
    stack.translatesAutoresizingMaskIntoConstraints = false
    effect.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: effect.topAnchor),
      stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
    ])
    surfaceName = "visualEffect"
    return effect
  }

  // MARK: What the Lua side asks for

  var isShowing: Bool { window.isVisible }
  var isKey: Bool { window.isKeyWindow }

  var query: String {
    get { field.stringValue }
    set { field.stringValue = newValue }
  }

  var placeholder: String {
    get { field.placeholderString ?? "" }
    set { field.placeholderString = newValue }
  }

  // One based like every row number Lua sees, and zero when nothing is selected.
  var selectedRow: Int { table.selectedRow < 0 ? 0 : table.selectedRow + 1 }

  func setRows(_ next: [String]) {
    rows = next
    table.reloadData()
    if !rows.isEmpty { select(0) }
  }

  // Lands on the screen under the pointer, a third of the way down, which is where a person is
  // already looking when they press the key.
  func present(activate: Bool) {
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    if let frame = screen?.visibleFrame {
      let x = frame.midX - Self.width / 2
      let y = frame.maxY - frame.height / 3 - Self.height / 2
      window.setFrame(NSRect(x: x, y: y, width: Self.width, height: Self.height), display: false)
    }
    if activate { NSApp.activate() }
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(field)
  }

  func dismiss(notify: Bool) {
    guard window.isVisible else { return }
    window.orderOut(nil)
    if notify { onEvent("dismiss", nil) }
  }

  // MARK: Keys and text

  func controlTextDidChange(_ obj: Notification) {
    onEvent("query", field.stringValue)
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    switch selector {
    case #selector(NSResponder.moveDown(_:)): step(1)
    case #selector(NSResponder.moveUp(_:)): step(-1)
    case #selector(NSResponder.insertNewline(_:)): choose()
    case #selector(NSResponder.cancelOperation(_:)): dismiss(notify: true)
    default: return false
    }
    return true
  }

  func windowDidResignKey(_ notification: Notification) {
    dismiss(notify: true)
  }

  private func step(_ delta: Int) {
    guard !rows.isEmpty else { return }
    let from = max(table.selectedRow, 0)
    select(min(max(from + delta, 0), rows.count - 1))
  }

  private func select(_ row: Int) {
    table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    table.scrollRowToVisible(row)
  }

  private func choose() {
    guard table.selectedRow >= 0 else { return }
    onEvent("choose", table.selectedRow + 1)
  }

  @objc private func chooseClicked() {
    guard table.clickedRow >= 0 else { return }
    select(table.clickedRow)
    choose()
  }

  // MARK: The list

  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell: NSTableCellView
    if let reused = tableView.makeView(withIdentifier: Self.cellID, owner: self) as? NSTableCellView {
      cell = reused
    } else {
      cell = NSTableCellView()
      cell.identifier = Self.cellID
      let label = NSTextField(labelWithString: "")
      label.font = .systemFont(ofSize: 15)
      label.lineBreakMode = .byTruncatingTail
      label.translatesAutoresizingMaskIntoConstraints = false
      cell.addSubview(label)
      cell.textField = label
      NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
        label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
        label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      ])
    }
    cell.textField?.stringValue = rows[row]
    return cell
  }
}
