// The floating pane, a shape of the window's own glass standing over the chooser, anchored above one of
// the bar's groups. It holds an optional header and one column of lines, each a label on the left
// and its chord on the right as a KeyCap, see Bar.swift, and scrolls when the lines are taller
// than the room it is given. The info pane is its first user and the actions pane its second, so it knows neither, only the
// lines it is handed. A line may carry a picture, drawn on its left, and a floating pane may highlight
// one line, which the pointer moves and a press chooses, reported by its index from one. Its
// corner is the groups' corner, and it follows the chooser's padding rules. Its lines stand the
// outer padding from all four edges, the way the list's highlighted rows stand from the window's,
// a line's picture and words stand the inner padding in from the line's edge, and the highlight's
// corner is the floating pane's less the outer padding. The info pane, whose lines are only read, is
// laid out the same, so both panels and the bar items share one size, Milos's choice of
// 2026-11-02. A header is the row title's size and colour, laid out as one more line, its text
// the inner padding in from a line's edge and centred in a line's height, with the rule on the
// line's bottom edge and the first line right below it, so the header keeps the room every line
// keeps.

import Cocoa

final class FloatingPaneView: FlippedView {
  struct Line {
    var label: String
    var chord: [[KeyMark]]
    // Keys drawn bare before the label, the legend's leader symbol, floatingpane.lua's lead. The lines
    // are two columns, a line's lead and label left aligned and its chord right aligned.
    var lead: [[KeyMark]] = []
    var image: NSImage? = nil
    // The image is one colour, see Row's tint, redrawn in the lit ink on the highlighted line.
    var tint = false
    // The heading the line is listed under. A heading is drawn above the first line of each run
    // of lines naming the same one, docs/PLAN-ACTION-PANEL.md.
    var section: String? = nil
    // A line that chooses nothing, drawn in the dimmed colours a disabled list row takes.
    var enabled = true
  }

  // The lines' own view, drawing the highlight under them and reporting the pointer by line.
  final class Document: FlippedView {
    var lineH: CGFloat = 1
    // Where each line starts, from the top of the document, since a heading takes room between
    // two lines and a line is no longer its index times the line height.
    var tops: [CGFloat] = []
    var count: Int { tops.count }
    var highlight = 0 { didSet { needsDisplay = true } }
    var color = NSColor.clear
    var inset: CGFloat = 0
    var radius: CGFloat = 0
    var onHover: ((Int) -> Void)?
    var onChoose: ((Int) -> Void)?

    func lineAt(_ event: NSEvent) -> Int? {
      let p = convert(event.locationInWindow, from: nil)
      guard let i = tops.firstIndex(where: { p.y >= $0 && p.y < $0 + lineH }) else { return nil }
      return i + 1
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
      if let i = lineAt(event) { onChoose?(i) }
    }
    override func mouseMoved(with event: NSEvent) {
      if let i = lineAt(event), i != highlight { onHover?(i) }
    }

    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      for area in trackingAreas { removeTrackingArea(area) }
      addTrackingArea(NSTrackingArea(rect: .zero,
        options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func draw(_ dirtyRect: NSRect) {
      guard highlight > 0, highlight <= count else { return }
      color.setFill()
      let rect = NSRect(x: inset, y: tops[highlight - 1], width: bounds.width - 2 * inset, height: lineH)
      NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
  }

  private let glass = Surface(holding: FlippedView())
  private let header = NSTextField(labelWithString: "")
  private let rule = NSBox()
  private let scroll = NSScrollView()
  let document = Document()
  private var rows: [(label: NSTextField, chord: KeyCap, image: NSImageView?, lead: KeyCap?)] = []
  private var iconSide: CGFloat = 0
  private var headings: [(field: NSTextField, top: CGFloat)] = []
  // The height of every line and heading together.
  private var contentH: CGFloat = 0
  private var outer: CGFloat = 0
  private var inner: CGFloat = 0
  private var lineH: CGFloat = 0
  private var gap: CGFloat = 0
  // Between a line's lead and its label, the bar's small step, floatingpane.lua's leadGap.
  private var leadGap: CGFloat = 0

  override init(frame: NSRect) {
    super.init(frame: frame)
    addSubview(glass.view)
    rule.boxType = .separator
    header.lineBreakMode = .byTruncatingTail
    scroll.drawsBackground = false
    scroll.contentView.drawsBackground = false
    scroll.automaticallyAdjustsContentInsets = false
    scroll.borderType = .noBorder
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .overlay
    scroll.horizontalScrollElasticity = .none
    scroll.documentView = document
    for view in [header, rule, scroll] as [NSView] { addSubview(view) }
  }

  required init?(coder: NSCoder) { nil }

  // Claims the pointer, so a press on the floating pane lands on no row under it, and keeps the scroll
  // for its own lines.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {}
  override func rightMouseDown(with event: NSEvent) {}

  // MARK: Opening and closing, through Motion.swift like every surface

  // Whether the floating pane is open. One closing is no longer open while it fades, so it takes
  // no pointer and lays nothing out, and it is hidden once the fade ends.
  private(set) var isOpen = false
  private var opening = false

  // Shown at once and faded in by play, once the floating pane has been laid out at its size.
  func setOpen(_ open: Bool) {
    guard open != isOpen else { return }
    isOpen = open
    opening = open
    if open {
      isHidden = false
      return
    }
    Motion.disappear(self) { [weak self] in
      guard let self, !self.isOpen else { return }
      self.isHidden = true
    }
  }

  func play() {
    guard opening else { return }
    opening = false
    Motion.appear(self)
  }

  // Closed with no fade, for a chooser that has gone down with the floating pane still open.
  func closeNow() {
    isOpen = false
    opening = false
    Motion.rest(self)
    isHidden = true
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    isOpen ? super.hitTest(point) : nil
  }

  // title is the header, nil for none. outer and inner are the two paddings, lineH the height of one line,
  // gap the room between a label and its chord and between a picture and its label, iconSide a
  // picture's side, radius the corner and highlight the line lit, from one, or zero for none.
  func show(title: String?, lines: [Line], style: Style, placement: Placement, outer: CGFloat, inner: CGFloat, lineH: CGFloat, gap: CGFloat,
    radius: CGFloat, iconSide: CGFloat = 0, highlight: Int = 0) {
    self.outer = outer
    self.inner = inner
    self.lineH = lineH
    self.gap = gap
    self.leadGap = placement.barGap
    self.iconSide = iconSide
    document.lineH = max(1, lineH)
    document.color = style.highlight
    document.inset = outer
    document.radius = max(0, radius - outer)
    document.highlight = highlight
    glass.setCornerRadius(radius)
    header.stringValue = title ?? ""
    header.font = style.titleFont
    header.textColor = style.text
    header.isHidden = title == nil
    rule.isHidden = title == nil
    for row in rows {
      row.label.removeFromSuperview()
      row.chord.removeFromSuperview()
      row.image?.removeFromSuperview()
      row.lead?.removeFromSuperview()
    }
    for heading in headings { heading.field.removeFromSuperview() }
    // Each line's top and each heading's, a heading as tall as a line, taken above the first line
    // of a run naming a section different from the line before it.
    var tops: [CGFloat] = []
    headings = []
    var y: CGFloat = 0
    var previous: String? = nil
    for line in lines {
      if let section = line.section, section != previous {
        let field = NSTextField(labelWithString: section)
        field.font = style.captionFont
        field.textColor = style.caption
        headings.append((field, y))
        document.addSubview(field)
        y += lineH
      }
      previous = line.section
      tops.append(y)
      y += lineH
    }
    document.tops = tops
    contentH = y
    // The highlighted line stands on the highlight and draws in its ink, see Ink, every other on
    // the glass.
    rows = lines.enumerated().map { index, line in
      let ink = style.ink(lit: index + 1 == highlight)
      let label = NSTextField(labelWithString: line.label)
      label.font = style.titleFont
      label.textColor = line.enabled ? ink.text : ink.textDim
      label.lineBreakMode = .byTruncatingTail
      let chord = KeyCap(line.chord, ink: ink, style: style, placement: placement, holderH: lineH,
        holderRadius: document.radius, enabled: line.enabled)
      let image = line.image.map { source -> NSImageView in
        let picture = line.tint ? (ink.icon.map { Crisp.tinted(source, $0) } ?? source) : source
        let view = NSImageView(image: picture)
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
      }
      let lead = line.lead.isEmpty ? nil : KeyCap(line.lead, ink: ink, style: style, placement: placement,
        holderH: lineH, holderRadius: 0, enabled: line.enabled, bare: true, strong: true, keyFont: style.rowKeyFont)
      return (label, chord, image, lead)
    }
    for row in rows {
      document.addSubview(row.label)
      document.addSubview(row.chord)
      if let image = row.image { document.addSubview(image) }
      if let lead = row.lead { document.addSubview(lead) }
    }
    needsLayout = true
    layoutSubtreeIfNeeded()
    revealHighlight()
  }

  // Scrolls just enough to show the highlighted line, as the list keeps its own highlight shown.
  private func revealHighlight() {
    guard document.highlight > 0, document.highlight <= document.count else { return }
    let rect = NSRect(x: 0, y: document.tops[document.highlight - 1], width: 1, height: lineH)
    document.scrollToVisible(rect)
  }

  // The room a line's picture takes, nothing for lines without one.
  private var lead: CGFloat {
    rows.contains { $0.image != nil } ? iconSide + gap : 0
  }

  // The room a line's leading keys take, the widest lead and the gap, only on a line that has one.
  private var leadCol: CGFloat {
    rows.compactMap { $0.lead?.fittingSize.width }.max() ?? 0
  }

  private func leadW(_ row: (label: NSTextField, chord: KeyCap, image: NSImageView?, lead: KeyCap?)) -> CGFloat {
    row.lead == nil ? 0 : leadCol + leadGap
  }

  private var headerH: CGFloat {
    header.isHidden ? 0 : lineH + 1 + outer
  }

  // How far a line's text stands in from its edges, the inner padding inside a line the outer
  // padding from the edge.
  private var side: CGFloat { outer + inner }

  // The size it would take with every line showing, its width the widest label and chord.
  var preferredSize: NSSize {
    // A table, the widest first column, the gap and the widest last column, so every label keeps the
    // gap from every chord rather than only from its own, floatingpane.lua's layout.
    let firstCol = rows.map { lead + leadW($0) + $0.label.fittingSize.width }.max() ?? 0
    let lastCol = rows.map { $0.chord.fittingSize.width }.max() ?? 0
    let widest = rows.isEmpty ? 0 : firstCol + gap + lastCol
    let width = max(widest + 2 * side, header.isHidden ? 0 : header.fittingSize.width + 2 * side)
    return NSSize(width: ceil(width),
      height: ceil(headerH + contentH + 2 * outer))
  }



  override func layout() {
    super.layout()
    glass.view.frame = bounds
    var top = outer
    if !header.isHidden {
      let h = header.fittingSize.height
      header.frame = NSRect(x: side, y: top + (lineH - h) / 2, width: bounds.width - 2 * side, height: h)
      // The rule on the header line's bottom edge, and the outer padding under it before the first
      // line, so a lit first line stands off the rule as the last one stands off the bottom edge.
      top += lineH
      rule.frame = NSRect(x: 0, y: top, width: bounds.width, height: 1)
      top += 1 + outer
    }
    let start = top
    scroll.frame = NSRect(x: 0, y: start, width: bounds.width, height: max(0, bounds.height - start))
    scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: outer, right: 0)
    document.frame = NSRect(x: 0, y: 0, width: bounds.width, height: contentH)
    for heading in headings {
      let h = heading.field.fittingSize.height
      heading.field.frame = NSRect(x: side, y: heading.top + (lineH - h) / 2, width: bounds.width - 2 * side, height: h)
    }
    for (i, row) in rows.enumerated() {
      let y = document.tops[i]
      let chordW = row.chord.fittingSize.width
      let labelH = row.label.fittingSize.height
      let chordH = row.chord.fittingSize.height
      row.chord.frame = NSRect(x: bounds.width - side - chordW, y: y + (lineH - chordH) / 2,
        width: chordW, height: chordH)
      let lw = leadW(row)
      row.label.frame = NSRect(x: side + lead + lw, y: y + (lineH - labelH) / 2,
        width: max(0, bounds.width - 2 * side - lead - lw - chordW - gap), height: labelH)
      if let cap = row.lead {
        let size = cap.fittingSize
        cap.frame = NSRect(x: side + lead, y: y + (lineH - size.height) / 2, width: size.width, height: size.height)
      }
      if let image = row.image {
        image.frame = Crisp.align(NSRect(x: side, y: y + (lineH - iconSide) / 2, width: iconSide, height: iconSide),
          in: document)
      }
    }
  }
}
