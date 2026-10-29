// The action bar and the key panel above it, a plain faithful rendering of the footer model the
// engine hands over. The bar is two rounded groups standing on the glass, the key group in the
// bottom left corner and the action group in the bottom right, each the bar pad in from the
// bottom edge and from its side, the same inset the list and the pane take, so one token moves
// every gap. Each group is the window's own glass and its words and chords are the row title's
// font and colour. The key group holds the keyboard icon, or a question mark, with the showKeys chord
// beside it, and the action group holds the model's right side, each entry its label beside its
// chord. A group's corner is the highlighted row's, the surface radius less the bar pad. The key
// panel lists every key the list answers, two to a line, over the bottom of the list. A press on
// the key group reports toggleKeys and nothing else here reports anything, so a press on the bar
// or the panel lands on no row and never hides the list.

import Cocoa

private func label(_ text: String, _ font: NSFont, _ color: NSColor) -> NSTextField {
  let field = NSTextField(labelWithString: text)
  field.font = font
  field.textColor = color
  field.lineBreakMode = .byTruncatingTail
  return field
}

// A thin rule along the top edge of the key panel, the system separator.
private func divider() -> NSBox {
  let box = NSBox()
  box.boxType = .separator
  return box
}

// One group of the bar, a shape of exactly the glass the window stands on, untinted, and tinted
// with the highlight colour only while lit. A press anywhere on it reports through onPress when
// one is set, whatever part of the group is under the pointer.
final class BarGroup: FlippedView {
  var onPress: (() -> Void)?
  var lit = false { didSet { tint() } }
  var color = NSColor.clear { didSet { tint() } }
  var radius: CGFloat = 0 { didSet { glass.setCornerRadius(radius) } }
  private let glass = Surface(holding: FlippedView())

  override init(frame: NSRect) {
    super.init(frame: frame)
    addSubview(glass.view)
  }

  required init?(coder: NSCoder) { nil }

  override func hitTest(_ point: NSPoint) -> NSView? {
    frame.contains(point) ? self : nil
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {}
  override func mouseUp(with event: NSEvent) {
    if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
  }

  override func layout() {
    super.layout()
    glass.view.frame = bounds
  }

  // The glass takes the tint where the system has glass, and the visual effect view below macOS
  // 26 is left as it is.
  private func tint() {
    if #available(macOS 26.0, *), let view = glass.view as? NSGlassEffectView {
      view.tintColor = lit ? color : nil
    }
  }
}

final class BarView: FlippedView {
  let button = BarGroup()
  let actions = BarGroup()
  private var parts: [NSView] = []
  private var rightParts: [NSView] = []
  private var placement = Placement()
  // The key button's picture as it came, drawn again on the pixel grid at every layout.
  private var keysSource: NSImage?

  override init(frame: NSRect) {
    super.init(frame: frame)
    addSubview(button)
    addSubview(actions)
  }

  required init?(coder: NSCoder) { nil }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  // Only the groups take the pointer, so a press or a scroll between them reaches the rows the
  // list shows behind the bar.
  override func hitTest(_ point: NSPoint) -> NSView? {
    let hit = super.hitTest(point)
    return hit === self ? nil : hit
  }

  func show(_ footer: Footer, style: Style, placement: Placement, lit: Bool) {
    self.placement = placement
    for view in parts + rightParts { view.removeFromSuperview() }
    parts = []
    rightParts = []
    keysSource = footer.keysImage
    if let image = footer.keysImage {
      let view = NSImageView(image: image)
      view.imageScaling = .scaleProportionallyUpOrDown
      parts.append(view)
    } else {
      parts.append(label("?", style.titleFont, style.text))
    }
    if let chord = footer.keysChord { parts.append(label(chord, style.titleFont, style.text)) }
    for view in parts { button.addSubview(view) }
    for entry in footer.right {
      rightParts.append(label(entry.label, style.titleFont, style.text))
      rightParts.append(label(entry.chord, style.titleFont, style.text))
    }
    for view in rightParts { actions.addSubview(view) }
    for group in [button, actions] {
      group.color = style.highlight
      group.radius = style.highlightRadius
    }
    button.lit = lit
    actions.isHidden = rightParts.isEmpty
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let pad = placement.barPad
    let inner = placement.barPillPad
    let gap = placement.barGap
    let side = placement.keysIcon
    let h = placement.barPillH
    // The key group, its parts side by side and centred in the group's height.
    var x = inner
    for view in parts {
      let size = view is NSImageView ? NSSize(width: side, height: side) : view.fittingSize
      view.frame = NSRect(x: x, y: (h - size.height) / 2, width: size.width, height: size.height)
      x += size.width + gap
    }
    let buttonW = x - gap + inner
    button.frame = Crisp.align(NSRect(x: pad, y: 0, width: buttonW, height: h), in: self)
    // The picture on whole pixels and drawn for exactly the pixels it covers, see Crisp.
    for case let view as NSImageView in parts {
      view.frame = Crisp.align(view.frame, in: button)
      if let keysSource {
        view.image = Crisp.image(keysSource, size: view.frame.size, scale: Crisp.scale(of: self))
      }
    }
    // The action group, laid from its right edge leftward, a wider gap between entries than
    // between a label and its chord, then placed flush with the bar pad from the right edge.
    var right: CGFloat = 0
    var frames: [NSRect] = []
    for (i, view) in rightParts.enumerated().reversed() {
      let size = view.fittingSize
      right -= size.width
      frames.append(NSRect(x: right, y: (h - size.height) / 2, width: size.width, height: size.height))
      if i > 0 { right -= i % 2 == 1 ? gap : placement.barGapWide }
    }
    let actionsW = -right + 2 * inner
    for (view, frame) in zip(rightParts.reversed(), frames) {
      view.frame = frame.offsetBy(dx: actionsW - inner, dy: 0)
    }
    actions.frame = Crisp.align(NSRect(x: bounds.width - pad - actionsW, y: 0, width: actionsW, height: h), in: self)
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
