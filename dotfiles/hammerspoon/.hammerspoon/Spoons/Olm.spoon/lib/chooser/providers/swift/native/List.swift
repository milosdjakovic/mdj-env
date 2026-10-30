// The list, an NSTableView in a native scroll view, with the empty state over it. It draws the
// rows Lua sent and owns the scroll and the highlight, as a native list does. The arrows and the
// pointer move the highlight here, the viewport follows only far enough to show it, and Lua hears
// the scroll and the highlight afterwards, coalesced, so neither ever waits on Lua. Lua moves
// either only when the engine did, a new list or a list key. It never chooses on its own, and
// every press Lua acts on first flushes what Lua has not heard.
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

  // Each picture drawn once per size and scale, kept while its source lives, so a row scrolling
  // back into view reuses its bitmap rather than drawing it again in the middle of a scroll.
  private static let drawn = NSMapTable<NSImage, NSImage>.weakToStrongObjects()
  private static let drawnScale = NSMapTable<NSImage, NSNumber>.weakToStrongObjects()

  static func cached(_ source: NSImage, size: NSSize, scale: CGFloat) -> NSImage {
    if let hit = drawn.object(forKey: source), hit.size == size,
      drawnScale.object(forKey: source)?.doubleValue == Double(scale) {
      return hit
    }
    let out = image(source, size: size, scale: scale)
    drawn.setObject(out, forKey: source)
    drawnScale.setObject(NSNumber(value: Double(scale)), forKey: source)
    return out
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
  static let identifier = NSUserInterfaceItemIdentifier("olm.swiftchooser.rowview")
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
        icon.image = Crisp.cached(source, size: size, scale: scale)
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
  // The highlighted row, one based, 0 for none. The list owns it. The arrows and the pointer move
  // it here and Lua is told afterwards, and Lua sets it only when the engine moved it, a new list
  // or a list key.
  private(set) var highlight = 0
  // What the person did that Lua has not heard yet, the scroll and the highlight. Reports are
  // coalesced and sent after the frame that drew the change, so a trackpad or a held arrow never
  // waits on Lua, and flushReports sends them at once before anything Lua acts on.
  private var scrollPending = false
  private var highlightPending = false
  private var flushScheduled = false
  private static let scrollInterval = 0.05
  private static let highlightInterval = 0.016
  var onScroll: (CGFloat) -> Void = { _ in }
  var onHighlight: (Int) -> Void = { _ in }
  var onLive: (Bool) -> Void = { _ in }
  // Asks Lua for the icons of these rows, zero based, nearest first.
  var onWantIcons: ([Int]) -> Void = { _ in }
  // Rows whose icon was asked for since the rows were last sent, so none is asked twice, a row
  // with no icon at all included, and the rows waiting to be asked.
  private var asked = Set<Int>()
  private var wanted: [Int] = []
  private var iconFlushScheduled = false
  // The scroll's velocity in points a second, smoothed, from the bounds changes a scroll makes.
  private var lastY: CGFloat = 0
  private var lastT: CFTimeInterval = 0
  private var velocity: CGFloat = 0
  // How far ahead of the viewport icons are asked for, in seconds of the current velocity, about
  // the distance a trackpad's momentum still has to run, and the most rows one ask may carry,
  // since an icon costs Lua about 0.66 ms, measured on 2026-10-30, so twelve stay under a frame.
  private static let lookahead: CGFloat = 0.4
  private static let iconsPerAsk = 12
  private static let iconInterval = 0.03
  // True from the moment a trackpad gesture begins until its momentum ends. Nothing calls into
  // Lua in between, since a flick reversed mid momentum must be answered in the very next frame,
  // and Lua work queued among those frames made the reversal land late and all at once.
  private var live = false
  // How far the viewport reaches past the engine's own band, behind the floating bar.
  var underBar: CGFloat = 0

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
    // The chooser's window is titled, see THE OUTLINE in Panel.swift, and a scroll view under a
    // title bar insets its content by the bar's height on its own, which would push every row down.
    scroll.automaticallyAdjustsContentInsets = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .overlay
    scroll.verticalScrollElasticity = .allowed
    scroll.horizontalScrollElasticity = .none
    scroll.automaticallyAdjustsContentInsets = false
    scroll.contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
      name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    NotificationCenter.default.addObserver(self, selector: #selector(liveStarted),
      name: NSScrollView.willStartLiveScrollNotification, object: scroll)
    NotificationCenter.default.addObserver(self, selector: #selector(liveEnded),
      name: NSScrollView.didEndLiveScrollNotification, object: scroll)

    empty.alignment = .center
    empty.isHidden = true
    addSubview(scroll)
    addSubview(empty)
  }

  required init?(coder: NSCoder) { nil }

  // The list shows only the arrow, so a cursor update stops here rather than climbing every
  // superview to the window, which sets the arrow again. Measured on 2026-10-30, AppKit asks on
  // every frame of a scroll as rows pass under a still pointer, and setting the cursor went through
  // the accessibility cursor generator, which draws the cursor image anew each time, a third of
  // the main thread during a trackpad scroll and the stutter it had.
  override func cursorUpdate(with event: NSEvent) {}

  func apply(style: Style, placement: Placement) {
    self.style = style
    self.placement = placement
    empty.font = style.captionFont
    empty.textColor = style.caption
    needsLayout = true
    quietly {
      table.rowHeight = placement.rowH
      scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: placement.padBottom + underBar, right: 0)
      table.reloadData()
    }
  }

  // The same number of rows, a new query's or the same rows gaining their icons as a scroll
  // brings them near, reloads only the rows the table holds a view for, on screen and the few it
  // prepared past either edge, since it asks for any other row as it scrolls in. A full reload on
  // every icon batch was a stall in the middle of a scroll.
  func setRows(_ next: [Row]) {
    let sameCount = next.count == rows.count
    rows = next
    asked.removeAll()
    wanted.removeAll()
    quietly {
      if sameCount {
        var held = IndexSet()
        table.enumerateAvailableRowViews { _, index in held.insert(index) }
        if !held.isEmpty { table.reloadData(forRowIndexes: held, columnIndexes: IndexSet(integer: 0)) }
      } else {
        table.reloadData()
      }
    }
  }

  // Rows that gained their icon after they were sent. Only a row the table holds a view for is
  // filled again, in place, so a scroll that brings icons near reloads nothing.
  func setImages(_ images: [(Int, NSImage)]) {
    for (index, image) in images where index >= 0 && index < rows.count {
      rows[index].image = image
      if let cell = table.view(atColumn: 0, row: index, makeIfNecessary: false) as? RowCell {
        fill(cell, row: index)
      }
    }
  }

  private func fill(_ cell: RowCell, row: Int) {
    cell.placement = placement
    let slot = state.slots.firstIndex(of: row + 1).map { $0 + 1 }
    cell.fill(rows[row], slot: placement.showNumbers ? slot : nil, style: style, lineBreak: state.lineBreak)
  }

  func update(_ next: ViewState) {
    let before = state
    state = next
    quietly {
      if next.slots != before.slots || next.lineBreak != before.lineBreak {
        table.reloadData()
      }
      if let h = next.highlight, h != highlight {
        highlight = h
        highlightPending = false
        relight()
      }
      empty.stringValue = next.emptyText
      empty.isHidden = !next.empty
      if let top = next.scrollTop { setScrollTop(top) }
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
  // this view reported does not come back as a jump. The origin is set outright rather than
  // through scroll(to:). A reload that shortened the table, a query typed after the highlight
  // moved down, left the clip past the new end, and scroll(to:) from there landed at a negative
  // origin once the table was laid out, the rows drawn a few rows down under an empty band.
  // The engine already bounds scrollTop to what the list can show.
  private func setScrollTop(_ y: CGFloat) {
    let clip = scroll.contentView
    guard abs(clip.bounds.origin.y - y) > 0.5 else { return }
    clip.setBoundsOrigin(NSPoint(x: 0, y: max(0, y)))
    scroll.reflectScrolledClipView(clip)
  }

  @objc private func scrolled() {
    trackVelocity()
    wantAhead()
    guard !applyingScroll else { return }
    scrollPending = true
    if !live { scheduleFlush(after: Self.scrollInterval) }
  }

  private func trackVelocity() {
    let y = scroll.contentView.bounds.origin.y
    let t = CACurrentMediaTime()
    let dt = t - lastT
    if dt > 0, dt < 0.1 {
      let instant = (y - lastY) / CGFloat(dt)
      velocity = velocity * 0.5 + instant * 0.5
    } else {
      velocity = 0
    }
    lastY = y
    lastT = t
  }

  // The rows on screen, then the rows the scroll is heading into, as far as its velocity carries
  // it in lookahead seconds, nearest first, each asked once.
  private func wantAhead() {
    guard !rows.isEmpty else { return }
    let visible = table.rows(in: table.visibleRect)
    guard visible.length > 0 else { return }
    let first = visible.location, last = NSMaxRange(visible) - 1
    let reach = Int((abs(velocity) * Self.lookahead / max(1, placement.rowH)).rounded(.up))
    var order = Array(first...last)
    if velocity > 0 {
      order += Array(stride(from: last + 1, through: min(rows.count - 1, last + reach), by: 1))
    } else if velocity < 0 {
      order += Array(stride(from: first - 1, through: max(0, first - reach), by: -1))
    }
    want(order)
  }

  private func want(_ indices: [Int]) {
    var added = false
    for i in indices where i >= 0 && i < rows.count && rows[i].image == nil && !asked.contains(i) {
      asked.insert(i)
      wanted.append(i)
      added = true
    }
    guard added, !iconFlushScheduled else { return }
    iconFlushScheduled = true
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.iconInterval) { [weak self] in
      self?.flushIcons()
    }
  }

  // Sends one ask of at most iconsPerAsk rows, during a scroll too, and schedules the next while
  // more wait. The wait is dropped when the rows change, since setRows empties it.
  private func flushIcons() {
    iconFlushScheduled = false
    guard !wanted.isEmpty else { return }
    let batch = Array(wanted.prefix(Self.iconsPerAsk))
    wanted.removeFirst(batch.count)
    onWantIcons(batch)
    if !wanted.isEmpty {
      iconFlushScheduled = true
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.iconInterval) { [weak self] in
        self?.flushIcons()
      }
    }
  }

  @objc private func liveStarted() {
    Perf.note("live scroll begins")
    live = true
    onLive(true)
  }

  @objc private func liveEnded() {
    Perf.note("live scroll ends")
    live = false
    onLive(false)
    flushReports()
  }

  private func scheduleFlush(after delay: Double) {
    guard !flushScheduled, !live else { return }
    flushScheduled = true
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      self?.flushScheduled = false
      self?.flushReports()
    }
  }

  // Sends what Lua has not heard yet, the scroll first so the engine's viewport is current when
  // it hears the highlight.
  func flushReports() {
    if scrollPending {
      scrollPending = false
      onScroll(scroll.contentView.bounds.origin.y)
    }
    if highlightPending {
      highlightPending = false
      onHighlight(highlight)
    }
  }

  // Moves the highlight one row, wrapping at either end as the engine's list model does, and
  // scrolls only far enough to show it.
  func move(_ delta: Int) {
    guard !rows.isEmpty else { return }
    var next = highlight + delta
    if next < 1 { next = rows.count }
    if next > rows.count { next = 1 }
    setHighlight(next)
    reveal(next)
  }

  // The pointer over a row highlights it and leaves the viewport where it is.
  func hover(_ index: Int) {
    guard index >= 0, index < rows.count, index + 1 != highlight else { return }
    setHighlight(index + 1)
  }

  private func setHighlight(_ h: Int) {
    highlight = h
    relight()
    highlightPending = true
    scheduleFlush(after: Self.highlightInterval)
  }

  // The viewport moved only far enough to show row h whole above the bar, the engine's rule.
  private func reveal(_ h: Int) {
    let clip = scroll.contentView
    let rect = table.rect(ofRow: h - 1)
    let top = clip.bounds.origin.y
    let visible = clip.bounds.height - scroll.contentInsets.bottom
    var y = top
    if rect.minY < top { y = rect.minY } else if rect.maxY > top + visible { y = rect.maxY - visible }
    guard abs(y - top) > 0.5 else { return }
    clip.setBoundsOrigin(NSPoint(x: 0, y: max(0, y)))
    scroll.reflectScrolledClipView(clip)
  }

  private func relight() {
    table.enumerateAvailableRowViews { view, index in
      (view as? LitRowView)?.lit = index == self.highlight - 1
    }
  }

  override func layout() {
    super.layout()
    scroll.frame = bounds
    column.width = bounds.width
    let h = ceil(style.captionFont.ascender - style.captionFont.descender + style.captionFont.leading)
    empty.frame = NSRect(x: 0, y: max(0, (bounds.height - underBar - h) / 2), width: bounds.width, height: h)
  }

  // MARK: Table

  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let view = (tableView.makeView(withIdentifier: LitRowView.identifier, owner: self) as? LitRowView)
      ?? LitRowView()
    view.identifier = LitRowView.identifier
    view.color = style.highlight
    view.radius = style.highlightRadius
    view.lit = row == highlight - 1
    return view
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = (tableView.makeView(withIdentifier: RowCell.identifier, owner: self) as? RowCell) ?? RowCell(frame: .zero)
    fill(cell, row: row)
    if rows[row].image == nil { want([row]) }
    return cell
  }

  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
}
