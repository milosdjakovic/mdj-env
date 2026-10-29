// The popover, a shape of the window's own glass standing over the chooser, anchored above one of
// the bar's groups. It holds an optional header and one column of lines, each a label on the left
// and its chord on the right, and scrolls when the lines are taller than the room it is given. The
// key panel is its first user and the action panel its second, so it knows neither, only the
// lines it is handed. Every padding inside it is the inner padding and its corner is the groups'
// corner, so it changes with them.

import Cocoa

final class PopoverView: FlippedView {
  struct Line {
    var label: String
    var chord: String
  }

  private let glass = Surface(holding: FlippedView())
  private let header = NSTextField(labelWithString: "")
  private let rule = NSBox()
  private let scroll = NSScrollView()
  private let document = FlippedView()
  private var cells: [(label: NSTextField, chord: NSTextField)] = []
  private var pad: CGFloat = 0
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

  // title is the header, nil for none. pad is the inner padding, lineH the height of one line,
  // gap the room between a label and its chord, and radius the corner.
  func show(title: String?, lines: [Line], style: Style, pad: CGFloat, lineH: CGFloat, gap: CGFloat,
    radius: CGFloat) {
    self.pad = pad
    self.lineH = lineH
    self.gap = gap
    glass.setCornerRadius(radius)
    header.stringValue = title ?? ""
    header.font = style.captionFont
    header.textColor = style.caption
    header.isHidden = title == nil
    rule.isHidden = title == nil
    for cell in cells {
      cell.label.removeFromSuperview()
      cell.chord.removeFromSuperview()
    }
    cells = lines.map { line in
      let label = NSTextField(labelWithString: line.label)
      label.font = style.titleFont
      label.textColor = style.text
      label.lineBreakMode = .byTruncatingTail
      let chord = NSTextField(labelWithString: line.chord)
      chord.font = style.titleFont
      chord.textColor = style.sub
      chord.alignment = .right
      return (label, chord)
    }
    for cell in cells {
      document.addSubview(cell.label)
      document.addSubview(cell.chord)
    }
    needsLayout = true
  }

  private var headerH: CGFloat {
    header.isHidden ? 0 : header.fittingSize.height + pad
  }

  // The size it would take with every line showing, its width the widest label and chord.
  var preferredSize: NSSize {
    let widest = cells.map { $0.label.fittingSize.width + gap + $0.chord.fittingSize.width }.max() ?? 0
    let width = max(widest, header.isHidden ? 0 : header.fittingSize.width) + 2 * pad
    return NSSize(width: ceil(width), height: ceil(headerH + CGFloat(cells.count) * lineH + 2 * pad))
  }

  override func layout() {
    super.layout()
    glass.view.frame = bounds
    var top = pad
    if !header.isHidden {
      let h = header.fittingSize.height
      header.frame = NSRect(x: pad, y: top, width: bounds.width - 2 * pad, height: h)
      top += h + pad / 2
      rule.frame = NSRect(x: 0, y: top, width: bounds.width, height: 1)
      top += pad / 2
    }
    scroll.frame = NSRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
    scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: pad, right: 0)
    document.frame = NSRect(x: 0, y: 0, width: bounds.width, height: CGFloat(cells.count) * lineH)
    for (i, cell) in cells.enumerated() {
      let y = CGFloat(i) * lineH
      let chordW = cell.chord.fittingSize.width
      let labelH = cell.label.fittingSize.height
      let chordH = cell.chord.fittingSize.height
      cell.chord.frame = NSRect(x: bounds.width - pad - chordW, y: y + (lineH - chordH) / 2,
        width: chordW, height: chordH)
      cell.label.frame = NSRect(x: pad, y: y + (lineH - labelH) / 2,
        width: max(0, bounds.width - 2 * pad - chordW - gap), height: labelH)
    }
  }
}
