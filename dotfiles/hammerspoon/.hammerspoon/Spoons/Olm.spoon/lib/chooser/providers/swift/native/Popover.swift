// The popover, a shape of the window's own glass standing over the chooser, anchored above one of
// the bar's groups. It holds an optional header and one column of lines, each a label on the left
// and its chord on the right, and scrolls when the lines are taller than the room it is given. The
// key panel is its first user and the action panel its second, so it knows neither, only the
// lines it is handed. A line may carry a picture, drawn on its left, and a popover may highlight
// one line, which the pointer moves and a press chooses, reported by its index from one. Its
// corner is the groups' corner, and it follows the chooser's padding rules, one of two ways. A
// popover whose lines are chosen, the action panel, stands its lines the outer padding from all
// four edges, the way the list's highlighted rows stand from the window's, a line's picture and
// words stand the inner padding in from the line's edge, and the highlight's corner is the
// popover's less the outer padding. A popover whose lines are only read, the key panel, has no
// line edge to see, so its text itself stands the outer padding from all four edges, the header
// and the labels on one left edge and the chords on one right edge, the top and bottom measured
// to the text rather than to a line's height. A header is the row title's size and colour, with a
// rule the outer padding below it and the first line the outer padding below the rule.

import Cocoa

final class PopoverView: FlippedView {
  struct Line {
    var label: String
    var chord: String
    var image: NSImage? = nil
    // The heading the line is listed under. A heading is drawn above the first line of each run
    // of lines naming the same one, docs/PLAN-ACTION-PANEL.md.
    var section: String? = nil
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
  private var cells: [(label: NSTextField, chord: NSTextField, image: NSImageView?)] = []
  private var iconSide: CGFloat = 0
  private var headings: [(field: NSTextField, top: CGFloat)] = []
  // The height of every line and heading together.
  private var contentH: CGFloat = 0
  private var outer: CGFloat = 0
  private var inner: CGFloat = 0
  private var selectable = false
  private var lineH: CGFloat = 0
  private var gap: CGFloat = 0

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

  // Claims the pointer, so a press on the popover lands on no row under it, and keeps the scroll
  // for its own lines.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {}
  override func rightMouseDown(with event: NSEvent) {}

  // title is the header, nil for none. outer and inner are the two paddings, lineH the height of one line,
  // gap the room between a label and its chord and between a picture and its label, iconSide a
  // picture's side, radius the corner and highlight the line lit, from one, or zero for none.
  // selectable says the lines are chosen rather than only read, see the paddings above.
  func show(title: String?, lines: [Line], style: Style, outer: CGFloat, inner: CGFloat, lineH: CGFloat, gap: CGFloat,
    radius: CGFloat, iconSide: CGFloat = 0, highlight: Int = 0, selectable: Bool = false) {
    self.outer = outer
    self.inner = inner
    self.selectable = selectable
    self.lineH = lineH
    self.gap = gap
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
    for cell in cells {
      cell.label.removeFromSuperview()
      cell.chord.removeFromSuperview()
      cell.image?.removeFromSuperview()
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
    cells = lines.map { line in
      let label = NSTextField(labelWithString: line.label)
      label.font = style.titleFont
      label.textColor = style.text
      label.lineBreakMode = .byTruncatingTail
      let chord = NSTextField(labelWithString: line.chord)
      chord.font = style.titleFont
      chord.textColor = style.sub
      chord.alignment = .right
      let image = line.image.map { picture -> NSImageView in
        let view = NSImageView(image: picture)
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
      }
      return (label, chord, image)
    }
    for cell in cells {
      document.addSubview(cell.label)
      document.addSubview(cell.chord)
      if let image = cell.image { document.addSubview(image) }
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
    cells.contains { $0.image != nil } ? iconSide + gap : 0
  }

  private var headerH: CGFloat {
    header.isHidden ? 0 : header.fittingSize.height + 2 * outer + 1
  }

  // How far a line's text stands in from its edges. A chosen line's text sits the inner padding
  // inside a line the outer padding from the edge, a read line's text the outer padding alone.
  private var side: CGFloat { selectable ? outer + inner : outer }

  // The room above and below a read line's text inside its height, taken off the popover's top
  // and bottom so the text itself stands the outer padding from them. None for chosen lines.
  private var slack: CGFloat {
    guard !selectable else { return 0 }
    let textH = cells.map { max($0.label.fittingSize.height, $0.chord.fittingSize.height) }.max() ?? lineH
    return max(0, (lineH - textH) / 2)
  }

  // The size it would take with every line showing, its width the widest label and chord.
  var preferredSize: NSSize {
    let widest = cells.map { lead + $0.label.fittingSize.width + gap + $0.chord.fittingSize.width }.max() ?? 0
    let width = max(widest + 2 * side, header.isHidden ? 0 : header.fittingSize.width + 2 * side)
    return NSSize(width: ceil(width),
      height: ceil(headerH + contentH - 2 * slack + 2 * outer))
  }

  override func layout() {
    super.layout()
    glass.view.frame = bounds
    var top = outer
    if !header.isHidden {
      let h = header.fittingSize.height
      header.frame = NSRect(x: side, y: top, width: bounds.width - 2 * side, height: h)
      // The rule stands the outer padding below the header and the first line's text the outer
      // padding below the rule, the same room every edge of the popover keeps.
      top += h + outer
      rule.frame = NSRect(x: 0, y: top, width: bounds.width, height: 1)
      top += 1 + outer
    }
    let start = top - slack
    scroll.frame = NSRect(x: 0, y: start, width: bounds.width, height: max(0, bounds.height - start))
    scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: outer - slack, right: 0)
    document.frame = NSRect(x: 0, y: 0, width: bounds.width, height: contentH)
    for heading in headings {
      let h = heading.field.fittingSize.height
      heading.field.frame = NSRect(x: side, y: heading.top + (lineH - h) / 2, width: bounds.width - 2 * side, height: h)
    }
    for (i, cell) in cells.enumerated() {
      let y = document.tops[i]
      let chordW = cell.chord.fittingSize.width
      let labelH = cell.label.fittingSize.height
      let chordH = cell.chord.fittingSize.height
      cell.chord.frame = NSRect(x: bounds.width - side - chordW, y: y + (lineH - chordH) / 2,
        width: chordW, height: chordH)
      cell.label.frame = NSRect(x: side + lead, y: y + (lineH - labelH) / 2,
        width: max(0, bounds.width - 2 * side - lead - chordW - gap), height: labelH)
      if let image = cell.image {
        image.frame = Crisp.align(NSRect(x: side, y: y + (lineH - iconSide) / 2, width: iconSide, height: iconSide),
          in: document)
      }
    }
  }
}
