// The action bar and the key panel above it, a plain faithful rendering of the footer model the
// engine hands over, the look being a later step. The bar shows the key button on the left, the
// keyboard icon or a question mark with the showKeys chord beside it, and the model's right side
// flush right, each entry its label beside its chord. The key panel lists every key the list
// answers, two to a line, over the bottom of the list. A press on the key button reports
// toggleKeys and nothing else here reports anything, so a press on the bar or the panel lands on
// no row and never hides the list.

import Cocoa

private func label(_ text: String, _ font: NSFont, _ color: NSColor) -> NSTextField {
  let field = NSTextField(labelWithString: text)
  field.font = font
  field.textColor = color
  field.lineBreakMode = .byTruncatingTail
  return field
}

// A thin rule along the top edge of the bar and of the key panel, the system separator.
private func divider() -> NSBox {
  let box = NSBox()
  box.boxType = .separator
  return box
}

// The key button, lit with the highlight colour while its panel is open.
final class KeyButton: FlippedView {
  var onPress: () -> Void = {}
  var lit = false { didSet { needsDisplay = true } }
  var color = NSColor.clear
  var radius: CGFloat = 0

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {}
  override func mouseUp(with event: NSEvent) {
    if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress() }
  }

  override func draw(_ dirtyRect: NSRect) {
    guard lit else { return }
    color.setFill()
    NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
  }
}

final class BarView: FlippedView {
  let button = KeyButton()
  private let rule = divider()
  private var parts: [NSView] = []
  private var rightParts: [NSView] = []
  private var placement = Placement()

  override init(frame: NSRect) {
    super.init(frame: frame)
    addSubview(rule)
    addSubview(button)
  }

  required init?(coder: NSCoder) { nil }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {}

  func show(_ footer: Footer, style: Style, placement: Placement, lit: Bool) {
    self.placement = placement
    for view in parts + rightParts { view.removeFromSuperview() }
    parts = []
    rightParts = []
    if let image = footer.keysImage {
      let view = NSImageView(image: image)
      view.imageScaling = .scaleProportionallyUpOrDown
      parts.append(view)
    } else {
      parts.append(label("?", style.badgeFont, style.badge))
    }
    if let chord = footer.keysChord { parts.append(label(chord, style.badgeFont, style.badge)) }
    for view in parts { button.addSubview(view) }
    for entry in footer.right {
      rightParts.append(label(entry.label, style.captionFont, style.caption))
      rightParts.append(label(entry.chord, style.badgeFont, style.badge))
    }
    for view in rightParts { addSubview(view) }
    button.color = style.highlight
    button.radius = style.highlightRadius
    button.lit = lit
    needsLayout = true
  }

  override func layout() {
    super.layout()
    rule.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
    let inset = placement.barInset
    let gap = placement.barGap
    let side = placement.keysIcon
    // The key button, its parts side by side and centred in the bar's height.
    var x: CGFloat = 0
    for view in parts {
      let size = view is NSImageView ? NSSize(width: side, height: side) : view.fittingSize
      view.frame = NSRect(x: x + gap / 2, y: 0, width: size.width, height: size.height)
      x += size.width + gap
    }
    let buttonH = parts.map { $0.frame.height }.max() ?? 0
    button.frame = NSRect(x: inset - gap / 2, y: (bounds.height - buttonH) / 2, width: x, height: buttonH)
    for view in parts { view.frame.origin.y = (buttonH - view.frame.height) / 2 }
    // The right side, laid from the right edge leftward, a wider gap between entries than
    // between a label and its chord.
    var right = bounds.width - inset
    for (i, view) in rightParts.enumerated().reversed() {
      let size = view.fittingSize
      right -= size.width
      view.frame = NSRect(x: right, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
      right -= i % 2 == 1 ? gap : placement.barGapWide
    }
  }
}

// The key panel, every key the list answers in two columns on the background colour.
final class KeysPanelView: FlippedView {
  private let rule = divider()
  private var cells: [NSTextField] = []
  private var pad: CGFloat = 0
  private var background = NSColor.clear

  override init(frame: NSRect) {
    super.init(frame: frame)
    addSubview(rule)
  }

  required init?(coder: NSCoder) { nil }

  // Claims the pointer so a press or a scroll over the panel reaches no row under it.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {}
  override func rightMouseDown(with event: NSEvent) {}
  override func scrollWheel(with event: NSEvent) {}

  func show(_ footer: Footer, style: Style, pad: CGFloat) {
    self.pad = pad
    background = style.background
    for cell in cells { cell.removeFromSuperview() }
    cells = footer.keys.map { entry in
      let line = NSMutableAttributedString(string: entry.chord,
        attributes: [.font: style.badgeFont, .foregroundColor: style.badge])
      line.append(NSAttributedString(string: "  " + entry.label,
        attributes: [.font: style.captionFont, .foregroundColor: style.caption]))
      let cell = NSTextField(labelWithAttributedString: line)
      cell.lineBreakMode = .byTruncatingTail
      return cell
    }
    for cell in cells { addSubview(cell) }
    needsLayout = true
    needsDisplay = true
  }

  // How tall the panel stands at width, two keys to a line and the padding around them.
  func height(for width: CGFloat) -> CGFloat {
    let lineH = cells.map { $0.fittingSize.height }.max() ?? 0
    let lines = CGFloat((cells.count + 1) / 2)
    return lines * lineH + max(0, lines - 1) * pad / 2 + 2 * pad
  }

  override func draw(_ dirtyRect: NSRect) {
    background.setFill()
    bounds.fill()
  }

  override func layout() {
    super.layout()
    rule.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
    let lineH = cells.map { $0.fittingSize.height }.max() ?? 0
    let columnW = max(0, (bounds.width - 3 * pad) / 2)
    for (i, cell) in cells.enumerated() {
      let x = pad + CGFloat(i % 2) * (columnW + pad)
      let y = pad + CGFloat(i / 2) * (lineH + pad / 2)
      cell.frame = NSRect(x: x, y: y, width: columnW, height: lineH)
    }
  }
}
