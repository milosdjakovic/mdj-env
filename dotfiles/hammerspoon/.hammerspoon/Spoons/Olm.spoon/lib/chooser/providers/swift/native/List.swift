// The list, an NSTableView in a native scroll view, with the empty state over it. It draws the
// rows Lua sent and the highlight Lua says, and reports what the pointer does, a hover, a press
// and release on one row, a right press and a scroll, each as a one based row number the way Lua
// counts. It never moves the highlight itself and never chooses on its own, the engine decides
// both and answers with a fresh state.
//
// Row geometry follows the engine's own list model exactly, every row rowH tall with no spacing
// and the band's bottom margin as a content inset, so a scroll position here is the model's
// scrollTop in the same points and Command with a digit means the same row in both.

import Cocoa

class FlippedView: NSView {
  override var isFlipped: Bool { true }
}

// Pictures on the pixel grid at the screen's backing scale. An icon arrives as an hs.image whose
// bitmap is larger than the box it is shown in, and an NSImageView hands that bitmap to Core
// Animation, which shrinks it with a plain linear filter and puts it wherever the frame lands, a
// half point included, so a symbol came out softer than the canvas list, which draws the same
// picture with Core Graphics' own interpolation. So the frame is moved to whole pixels and the
// picture is drawn once, at high quality, into a bitmap of exactly the pixels it covers, which
// the view then shows unscaled. Nothing here knows which source made the picture.
enum Crisp {
  // The rect moved and sized to whole pixels of view's backing store.
  static func align(_ rect: NSRect, in view: NSView) -> NSRect {
    view.backingAlignedRect(rect, options: .alignAllEdgesNearest)
  }

  // The backing scale view draws at, the main screen's while it is in no window.
  static func scale(of view: NSView) -> CGFloat {
    view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
  }

  // source fitted whole into size, centred and kept to its aspect as scaleProportionallyUpOrDown
  // fits it, drawn into a bitmap of size times scale pixels on whole pixels. A template stays a
  // template, so a tinted view still tints it.
  static func image(_ source: NSImage, size: NSSize, scale: CGFloat) -> NSImage {
    let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
    guard w > 0, h > 0, source.size.width > 0, source.size.height > 0,
      let blank = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let rep = blank.retagging(with: .sRGB)
    else { return source }
    // The size in points goes on before the context is made, since a context reads its user space
    // from the rep's size then, and a rep still sized in pixels draws a point rect at half size
    // towards the bottom left at scale 2.
    rep.size = size
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return source }
    let fit = min(size.width / source.size.width, size.height / source.size.height)
    func pixel(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
    let dw = pixel(source.size.width * fit), dh = pixel(source.size.height * fit)
    let rect = NSRect(x: pixel((size.width - dw) / 2), y: pixel((size.height - dh) / 2), width: dw, height: dh)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let out = NSImage(size: size)
    out.addRepresentation(rep)
    out.isTemplate = source.isTemplate
    return out
  }
}

// A row's background, filled with the highlight colour while the row is the highlighted one.
final class LitRowView: NSTableRowView {
  var lit = false { didSet { if lit != oldValue { needsDisplay = true } } }
  var color = NSColor.clear
  var radius: CGFloat = 0

  override func drawBackground(in dirtyRect: NSRect) {
    guard lit else { return }
    color.setFill()
    NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
  }

  override func drawSelection(in dirtyRect: NSRect) {}
}

// One row's content, laid out by hand from the engine's row metrics, the same columns the canvas
// list draws, the icon, the title over the subtitle, and the shortcut on the trailing edge.
final class RowCell: NSView {
  static let identifier = NSUserInterfaceItemIdentifier("olm.swiftchooser.row")
  let icon = NSImageView()
  let title = NSTextField(labelWithString: "")
  let subtitle = NSTextField(labelWithString: "")
  let number = NSTextField(labelWithString: "")
  var placement = Placement()
  // The row's picture as it came, and what it was last drawn for, so a layout redraws the icon
  // only when the picture, its box or the backing scale changed.
  private var source: NSImage?
  private var drawnFor: (NSImage, NSSize, CGFloat)?

  override var isFlipped: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    identifier = Self.identifier
    icon.imageScaling = .scaleProportionallyUpOrDown
    number.alignment = .right
    for view in [icon, title, subtitle, number] as [NSView] { addSubview(view) }
  }

  required init?(coder: NSCoder) { nil }

  // A move to a screen of another scale draws the icon again for it.
  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    needsLayout = true
  }

  func fill(_ row: Row, slot: Int?, style: Style, lineBreak: NSLineBreakMode) {
    if row.image !== source {
      source = row.image
      drawnFor = nil
      icon.image = nil
    }
    title.stringValue = row.title
    title.font = style.titleFont
    title.textColor = row.enabled ? style.text : style.textDim
    title.lineBreakMode = lineBreak
    subtitle.stringValue = row.subtitle
    subtitle.font = style.subFont
    subtitle.textColor = row.enabled ? style.sub : style.subDim
    subtitle.lineBreakMode = .byTruncatingTail
    subtitle.isHidden = row.subtitle.isEmpty
    number.font = style.numberFont
    number.textColor = style.number
    number.stringValue = slot.map { "\u{2318}\($0)" } ?? ""
    number.isHidden = slot == nil
    needsLayout = true
  }

  private static func lineHeight(_ font: NSFont?) -> CGFloat {
    guard let font else { return 0 }
    return ceil(font.ascender - font.descender + font.leading)
  }

  override func layout() {
    super.layout()
    let p = placement
    let side = p.iconFrame
    icon.frame = Crisp.align(NSRect(x: p.iconPadLeft - (side - p.iconSize) / 2,
      y: p.iconPad - (side - p.iconSize) / 2, width: side, height: side), in: self)
    if let source {
      let scale = Crisp.scale(of: self)
      let size = icon.frame.size
      if !(drawnFor.map { $0.0 === source && $0.1 == size && $0.2 == scale } ?? false) {
        icon.image = Crisp.image(source, size: size, scale: scale)
        drawnFor = (source, size, scale)
      }
    }
    let textX = p.iconPadLeft + p.iconSize + p.iconGap
    let reserved = number.isHidden ? 0 : p.numW
    let textW = max(0, bounds.width - textX - p.padX - reserved)
    let titleH = Self.lineHeight(title.font)
    if subtitle.isHidden {
      title.frame = NSRect(x: textX, y: (bounds.height - titleH) / 2, width: textW, height: titleH)
    } else {
      let subH = Self.lineHeight(subtitle.font)
      let top = (bounds.height - titleH - subH) / 2
      title.frame = NSRect(x: textX, y: top, width: textW, height: titleH)
      subtitle.frame = NSRect(x: textX, y: top + titleH, width: textW, height: subH)
    }
    let numH = Self.lineHeight(number.font)
    number.frame = NSRect(x: bounds.width - p.padX - p.numW, y: (bounds.height - numH) / 2,
      width: p.numW, height: numH)
  }
}

// The table, which keeps the pointer for itself rather than selecting natively, so a press and
// release on one row is the only click that chooses, as on the canvas.
final class RowTable: NSTableView {
  var onHover: (Int) -> Void = { _ in }
  var onChoose: (Int) -> Void = { _ in }
  var onRight: (Int?) -> Void = { _ in }
  private var pressed: Int?
  private var tracking: NSTrackingArea?

  private func rowAt(_ event: NSEvent) -> Int? {
    let index = row(at: convert(event.locationInWindow, from: nil))
    return index >= 0 ? index : nil
  }

  func forgetPress() { pressed = nil }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) { pressed = rowAt(event) }

  override func mouseDragged(with event: NSEvent) {}

  override func mouseUp(with event: NSEvent) {
    let index = rowAt(event)
    defer { pressed = nil }
    if let index, index == pressed { onChoose(index) }
  }

  override func rightMouseDown(with event: NSEvent) { onRight(rowAt(event)) }

  override func mouseMoved(with event: NSEvent) {
    if let index = rowAt(event) { onHover(index) }
  }

  // Always active, since the panel never activates Hammerspoon and an area that waits for an
  // active application would never report a move.
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
      owner: self, userInfo: nil)
    addTrackingArea(area)
    tracking = area
  }
}

final class ListView: FlippedView, NSTableViewDataSource, NSTableViewDelegate {
  let table = RowTable()
  private let scroll = NSScrollView()
  private let empty = NSTextField(labelWithString: "")
  private let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("olm.swiftchooser.column"))
  private var rows: [Row] = []
  private var style = Style()
  private var placement = Placement()
  private var state = ViewState()
  private var applyingScroll = false
  var onScroll: (CGFloat) -> Void = { _ in }

  override init(frame: NSRect) {
    super.init(frame: frame)
    table.addTableColumn(column)
    table.headerView = nil
    table.style = .plain
    table.backgroundColor = .clear
    table.intercellSpacing = .zero
    table.selectionHighlightStyle = .none
    table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    table.refusesFirstResponder = true
    table.usesAutomaticRowHeights = false
    table.dataSource = self
    table.delegate = self

    scroll.documentView = table
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .overlay
    scroll.verticalScrollElasticity = .none
    scroll.horizontalScrollElasticity = .none
    scroll.automaticallyAdjustsContentInsets = false
    scroll.contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
      name: NSView.boundsDidChangeNotification, object: scroll.contentView)

    empty.alignment = .center
    empty.isHidden = true
    addSubview(scroll)
    addSubview(empty)
  }

  required init?(coder: NSCoder) { nil }

  func apply(style: Style, placement: Placement) {
    self.style = style
    self.placement = placement
    empty.font = style.captionFont
    empty.textColor = style.caption
    needsLayout = true
    quietly {
      table.rowHeight = placement.rowH
      scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: placement.padBottom, right: 0)
      table.reloadData()
    }
  }

  func setRows(_ next: [Row]) {
    rows = next
    quietly { table.reloadData() }
  }

  func update(_ next: ViewState) {
    let before = state
    state = next
    quietly {
      if next.slots != before.slots || next.lineBreak != before.lineBreak {
        table.reloadData()
      }
      if next.highlight != before.highlight { relight() }
      empty.stringValue = next.emptyText
      empty.isHidden = !next.empty
      setScrollTop(next.scrollTop)
    }
  }

  // Runs a change Lua asked for without reporting the scroll it may cause, a reload clamping the
  // viewport to a shorter list among them, so only a scroll the person made is ever reported and
  // a draw can never call back into the Lua that is drawing.
  private func quietly(_ body: () -> Void) {
    let outer = applyingScroll
    applyingScroll = true
    body()
    applyingScroll = outer
  }

  // Moves the viewport to the engine's scrollTop, skipped when it already sits there so a scroll
  // this view reported does not come back as a jump.
  private func setScrollTop(_ y: CGFloat) {
    let clip = scroll.contentView
    guard abs(clip.bounds.origin.y - y) > 0.5 else { return }
    clip.scroll(to: NSPoint(x: 0, y: y))
    scroll.reflectScrolledClipView(clip)
  }

  @objc private func scrolled() {
    guard !applyingScroll else { return }
    onScroll(scroll.contentView.bounds.origin.y)
  }

  private func relight() {
    table.enumerateAvailableRowViews { view, index in
      (view as? LitRowView)?.lit = index == self.state.highlight - 1
    }
  }

  override func layout() {
    super.layout()
    scroll.frame = bounds
    column.width = bounds.width
    let h = ceil(style.captionFont.ascender - style.captionFont.descender + style.captionFont.leading)
    empty.frame = NSRect(x: 0, y: max(0, (bounds.height - h) / 2), width: bounds.width, height: h)
  }

  // MARK: Table

  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let view = LitRowView()
    view.color = style.highlight
    view.radius = style.highlightRadius
    view.lit = row == state.highlight - 1
    return view
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = (tableView.makeView(withIdentifier: RowCell.identifier, owner: self) as? RowCell) ?? RowCell(frame: .zero)
    cell.placement = placement
    let slot = state.slots.firstIndex(of: row + 1).map { $0 + 1 }
    cell.fill(rows[row], slot: placement.showNumbers ? slot : nil, style: style, lineBreak: state.lineBreak)
    return cell
  }

  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
}
