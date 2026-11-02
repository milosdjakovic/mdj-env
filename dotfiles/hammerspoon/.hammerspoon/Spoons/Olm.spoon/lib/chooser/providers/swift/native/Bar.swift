// The action bar and the key panel above it, a plain faithful rendering of the footer model the
// engine hands over. The bar is two rounded groups standing on the glass, the key group in the
// bottom left corner and the action group in the bottom right, each the bar pad in from the
// bottom edge and from its side, the same inset the list and the pane take, so one token moves
// every gap. Inside a group its entries are cells as tall as an action panel line, edge to edge,
// standing the panel's outer padding from the group's four edges, so the pointer over one lights
// it exactly as the panel lights its highlighted line. Each group is the window's own glass and its words and chords are the row title's
// font and colour. The key group holds the keyboard icon, or a question mark, with the showKeys chord
// beside it, and the action group holds the model's right side, each entry its label beside its
// chord. Every chord, here and in the popovers, is a KeyCap, so a key reads as a key and never as
// a word or an icon. A group's corner is the highlighted row's, the surface radius less the bar pad,
// and a cell's is the group's less the padding around it, a panel line's. The key
// panel the keys group opens is a popover, see Popover.swift. A press on
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

// A chord drawn as key caps, the glyphs in the badge font on a chip of the keycap fill, the kit's
// hint badge. A chord naming alternatives, keys joined by the unit separator, is one chip per key
// with the alternative word between them in the caption colour, so it reads as press one or the
// other. A chip is the hint badge's height and its glyphs stand padX in from either side. Its
// corner nests in whatever line or group holds it, radius less the room above the chip. An empty
// chord draws nothing and takes no room.
final class KeyCap: FlippedView {
  static let separator: Character = "\u{1F}"
  private var keys: [NSTextField] = []
  private var words: [NSTextField] = []
  private var padX: CGFloat = 0
  private var gap: CGFloat = 0
  private var height: CGFloat = 0
  private var fill = NSColor.clear
  private var radius: CGFloat = 0
  private var chips: [NSRect] = []

  init(_ text: String, style: Style, placement: Placement, holderH: CGFloat, holderRadius: CGFloat,
    enabled: Bool = true) {
    super.init(frame: .zero)
    padX = placement.keycapPadX
    gap = placement.barGap
    height = placement.keycapH
    fill = enabled ? style.keycap : style.keycap.withAlphaComponent(style.keycap.alphaComponent * 0.5)
    radius = max(0, holderRadius - max(0, holderH - height) / 2)
    let parts = text.split(separator: KeyCap.separator).map(String.init).filter { !$0.isEmpty }
    for (i, part) in parts.enumerated() {
      if i > 0 {
        let word = NSTextField(labelWithString: placement.keycapOr)
        word.font = style.captionFont
        word.textColor = enabled ? style.caption : style.subDim
        words.append(word)
        addSubview(word)
      }
      let field = NSTextField(labelWithString: part)
      field.font = style.badgeFont
      field.textColor = enabled ? style.text : style.textDim
      field.alignment = .center
      field.lineBreakMode = .byClipping
      keys.append(field)
      addSubview(field)
    }
  }

  required init?(coder: NSCoder) { nil }

  override var fittingSize: NSSize {
    guard !keys.isEmpty else { return .zero }
    let capsW = keys.reduce(0) { $0 + ceil($1.fittingSize.width + 2 * padX) }
    let wordsW = words.reduce(0) { $0 + ceil($1.fittingSize.width) + 2 * gap }
    return NSSize(width: capsW + wordsW, height: height)
  }

  override func layout() {
    super.layout()
    chips = []
    var x: CGFloat = 0
    for (i, field) in keys.enumerated() {
      if i > 0 {
        let word = words[i - 1]
        let size = word.fittingSize
        x += gap
        word.frame = NSRect(x: x, y: (bounds.height - size.height) / 2, width: ceil(size.width), height: size.height)
        x += ceil(size.width) + gap
      }
      let w = ceil(field.fittingSize.width + 2 * padX)
      let h = field.fittingSize.height
      chips.append(NSRect(x: x, y: 0, width: w, height: bounds.height))
      field.frame = NSRect(x: x, y: (bounds.height - h) / 2, width: w, height: h)
      x += w
    }
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    fill.setFill()
    for chip in chips { NSBezierPath(roundedRect: chip, xRadius: radius, yRadius: radius).fill() }
  }
}

// One group of the bar, a shape of exactly the glass the window stands on, untinted, and tinted
// with the highlight colour only while lit. Its entries are cells, standing the outer padding in
// from all four edges and touching one another, each a line of the action panel, so the pointer
// over one lights it in the highlight colour with the corner a panel line takes. A press anywhere
// on it reports through onPress when one is set, whatever part of the group is under the pointer.
final class BarGroup: FlippedView {
  var onPress: (() -> Void)?
  // A press reported with where it landed, in the group's own space, for a group whose parts
  // each do something of their own.
  var onPressAt: ((NSPoint) -> Void)?
  var lit = false { didSet { tint() } }
  var color = NSColor.clear { didSet { tint(); shade.color = color } }
  var radius: CGFloat = 0 { didSet { glass.setCornerRadius(radius) } }
  // The cells, in the group's own space, and the corner of a lit one.
  var cells: [NSRect] = [] { didSet { shade.cells = cells } }
  var cellRadius: CGFloat = 0 { didSet { shade.radius = cellRadius } }
  private let glass = Surface(holding: FlippedView())
  private let shade = Shade()

  // The lit cell, drawn over the glass and under the words and chords.
  final class Shade: FlippedView {
    var cells: [NSRect] = [] { didSet { needsDisplay = true } }
    var hover: Int? { didSet { if hover != oldValue { needsDisplay = true } } }
    var color = NSColor.clear { didSet { needsDisplay = true } }
    var radius: CGFloat = 0 { didSet { needsDisplay = true } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
      guard let hover, hover < cells.count else { return }
      color.setFill()
      NSBezierPath(roundedRect: cells[hover], xRadius: radius, yRadius: radius).fill()
    }
  }

  override init(frame: NSRect) {
    super.init(frame: frame)
    addSubview(glass.view)
    addSubview(shade)
  }

  required init?(coder: NSCoder) { nil }

  override func hitTest(_ point: NSPoint) -> NSView? {
    !isHidden && frame.contains(point) ? self : nil
  }

  // The cell under point, nil between cells and in the padding around them.
  func cell(at point: NSPoint) -> Int? {
    cells.firstIndex { $0.contains(point) }
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {}
  override func mouseUp(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard bounds.contains(point) else { return }
    onPress?()
    onPressAt?(point)
  }

  override func mouseMoved(with event: NSEvent) { hover(event) }
  override func mouseEntered(with event: NSEvent) { hover(event) }
  override func mouseExited(with event: NSEvent) { shade.hover = nil }

  private func hover(_ event: NSEvent) {
    shade.hover = cell(at: convert(event.locationInWindow, from: nil))
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas { removeTrackingArea(area) }
    addTrackingArea(NSTrackingArea(rect: .zero,
      options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
  }

  override var isHidden: Bool { didSet { if isHidden { shade.hover = nil } } }

  override func layout() {
    super.layout()
    glass.view.frame = bounds
    shade.frame = bounds
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
  private var rightActions: [String?] = []
  private var placement = Placement()
  // A press on an entry of the action group, with the action that entry names.
  var onEntry: (String) -> Void = { _ in }
  // The key button's picture as it came, drawn again on the pixel grid at every layout.
  private var keysSource: NSImage?

  override init(frame: NSRect) {
    super.init(frame: frame)
    addSubview(button)
    addSubview(actions)
    actions.onPressAt = { [weak self] point in self?.pressEntry(at: point) }
  }

  // The entry whose cell is under point runs the action it names.
  private func pressEntry(at point: NSPoint) {
    guard let i = actions.cell(at: point), i < rightActions.count, let action = rightActions[i] else { return }
    onEntry(action)
  }

  required init?(coder: NSCoder) { nil }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  // Only the groups take the pointer, so a press or a scroll between them reaches the rows the
  // list shows behind the bar.
  override func hitTest(_ point: NSPoint) -> NSView? {
    let hit = super.hitTest(point)
    return hit === self ? nil : hit
  }

  // keysHidden and actionsHidden each hide one group whole, while the panel that group opens
  // stands in its corner. The other group stays as it is.
  func show(_ footer: Footer, style: Style, placement: Placement, lit: Bool, keysHidden: Bool = false,
    actionsHidden: Bool = false) {
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
    // A cell's corner, the panel line's, the group's corner less the padding around the cells.
    let capRadius = max(0, style.highlightRadius - placement.barPillPad)
    if let chord = footer.keysChord {
      parts.append(KeyCap(chord, style: style, placement: placement, holderH: placement.barPillH, holderRadius: capRadius))
    }
    for view in parts { button.addSubview(view) }
    rightActions = footer.right.map { $0.action }
    for entry in footer.right {
      rightParts.append(label(entry.label, style.titleFont, style.text))
      rightParts.append(KeyCap(entry.chord, style: style, placement: placement, holderH: placement.barPillH,
        holderRadius: capRadius))
    }
    for view in rightParts { actions.addSubview(view) }
    for group in [button, actions] {
      group.color = style.highlight
      group.radius = style.highlightRadius
      group.cellRadius = capRadius
    }
    button.lit = lit
    actions.lit = footer.panelOpen
    button.isHidden = keysHidden
    actions.isHidden = actionsHidden || rightParts.isEmpty
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let pad = placement.barPad
    let inner = placement.barPillPad
    let gap = placement.barGap
    let side = placement.keysIcon
    let cellH = placement.barPillH
    let h = cellH + 2 * inner
    // The key group, one cell holding its parts side by side, centred in the cell's height.
    var x = 2 * inner
    for view in parts {
      let size = view is NSImageView ? NSSize(width: side, height: side) : view.fittingSize
      view.frame = NSRect(x: x, y: inner + (cellH - size.height) / 2, width: size.width, height: size.height)
      x += size.width + gap
    }
    let buttonW = x - gap + 2 * inner
    button.frame = Crisp.align(NSRect(x: pad, y: 0, width: buttonW, height: h), in: self)
    button.cells = [NSRect(x: inner, y: inner, width: buttonW - 2 * inner, height: cellH)]
    // The picture on whole pixels and drawn for exactly the pixels it covers, see Crisp.
    for case let view as NSImageView in parts {
      view.frame = Crisp.align(view.frame, in: button)
      if let keysSource {
        view.image = Crisp.image(keysSource, size: view.frame.size, scale: Crisp.scale(of: self))
      }
    }
    // The action group, one cell per entry, edge to edge, its label and chord the inner padding
    // in from the cell's sides, then placed flush with the bar pad from the right edge.
    var cells: [NSRect] = []
    x = inner
    for i in stride(from: 0, to: rightParts.count - 1, by: 2) {
      let label = rightParts[i].fittingSize
      let chord = rightParts[i + 1].fittingSize
      let w = inner + label.width + (chord.width > 0 ? gap : 0) + chord.width + inner
      rightParts[i].frame = NSRect(x: x + inner, y: inner + (cellH - label.height) / 2,
        width: label.width, height: label.height)
      rightParts[i + 1].frame = NSRect(x: x + w - inner - chord.width, y: inner + (cellH - chord.height) / 2,
        width: chord.width, height: chord.height)
      cells.append(NSRect(x: x, y: inner, width: w, height: cellH))
      x += w
    }
    let actionsW = x + inner
    actions.frame = Crisp.align(NSRect(x: bounds.width - pad - actionsW, y: 0, width: actionsW, height: h), in: self)
    actions.cells = cells
  }
}
