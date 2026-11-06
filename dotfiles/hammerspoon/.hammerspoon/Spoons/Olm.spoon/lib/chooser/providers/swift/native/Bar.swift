// The bottom bar and the info pane above it, a plain faithful rendering of the bottom bar model the
// engine hands over. The bar is two rounded groups standing on the glass, the key group in the
// bottom left corner and the action group in the bottom right, each the bar pad in from the
// bottom edge and from its side, the same inset the list and the pane take, so one token moves
// every gap. Inside a group its items are items as tall as an actions pane line, edge to edge,
// standing the panel's outer padding from the group's four edges, so the pointer over one lights
// it exactly as the panel lights its highlighted line. Each group is the window's own glass and its words and chords are the row title's
// font and colour. The key group holds the keyboard icon, or a question mark, with the showInfo chord
// beside it, and the action group holds the model's right side, each item its label beside its
// chord. Every chord, here and in the floating panes, is a KeyCap, so a key reads as a key and never as
// a word or an icon. A group's corner is the highlighted row's, the surface radius less the bar pad,
// and a item's is the group's less the padding around it, a panel line's. The key
// panel the left side opens is a floating pane, see FloatingPane.swift. A press on
// the key group reports toggleInfo and nothing else here reports anything, so a press on the bar
// or the panel lands on no row and never hides the list.

import Cocoa

private func label(_ text: String, _ font: NSFont, _ color: NSColor) -> NSTextField {
  let field = NSTextField(labelWithString: text)
  field.font = font
  field.textColor = color
  field.lineBreakMode = .byTruncatingTail
  return field
}

// A chord drawn as key caps, lib/kbd.lua's wire, a list of alternatives each a list of keys. Each
// alternative is one chip of the keycap fill, the kit's hint badge, its keys drawn here one at a
// time. A key is its glyph in the keycap font, or the SF Symbol kbd names for it, which a key whose
// glyph the font lacks takes, since the fallback font drew it at another size than its neighbours.
// A symbol is tinted the text colour and scaled so its ink is the font's cap height, and centred on
// the capitals' middle, so it stands in a row of glyphs as one of them. Every key is placed by its
// ink, the bounds of what it actually draws, and not by its advance, since a monospaced advance
// leaves room either side of a narrow symbol, which Milos found on 2026-11-02. So two keys stand
// exactly the badge's gap apart, ink to ink, never a character, and padX is measured from the ink
// too. Alternatives stand apart with the alternative word between them in the caption colour, so
// it reads as press one or the other. A chip is the hint badge's height. Its corner nests in
// whatever line or group holds it, radius less the room above the chip. No chord draws nothing.
// A bare cap, lib/ui/keycap.lua's opts.bare, draws the same keys with no chip and no padding, in
// the number ink, the row number shortcut on a list row.
final class KeyCap: FlippedView {
  // One key, what it draws and its ink. A glyph's ink is measured from its pen position, a
  // symbol's from the left and top of the box it is drawn in, both already at drawn size.
  private enum Mark {
    case text(NSAttributedString)
    // A symbol is rendered opaque and drawn at its colour's alpha, as a glyph's colour composites,
    // since a translucent palette colour does not, and the sparkle read another shade than the diamond beside it.
    case image(NSImage, NSSize, CGFloat)
  }
  private struct Key {
    let mark: Mark
    let ink: NSRect
  }
  private var caps: [[Key]] = []
  private var words: [NSTextField] = []
  private var padX: CGFloat = 0
  private var keyGap: CGFloat = 0
  private var gap: CGFloat = 0
  private var height: CGFloat = 0
  private var fill = NSColor.clear
  private var radius: CGFloat = 0
  private var chips: [NSRect] = []
  // The font's line height and the distance from a line's top to the capitals' middle.
  private var lineH: CGFloat = 0
  private var capMiddle: CGFloat = 0
  // Where each key is drawn, parallel to caps, set by layout, a pen for a glyph, a box for a symbol.
  private var places: [[NSRect]] = []
  private let chord: [[KeyMark]]
  private let font: NSFont
  private let enabled: Bool
  private let bare: Bool
  // A bare cap drawn in the text colour rather than a row shortcut's, a floating pane line's lead.
  private let strong: Bool
  // The colours the chip, its keys and the alternative word are drawn in, the ink of whatever the
  // cap stands on, so a cap on a lit line or a lit bar item is drawn in the lit ink, see Ink. A
  // change keeps every key's place, since a colour moves no ink.
  var ink: Ink { didSet { paint() } }

  init(_ chord: [[KeyMark]], ink: Ink, style: Style, placement: Placement, holderH: CGFloat,
    holderRadius: CGFloat, enabled: Bool = true, bare: Bool = false, strong: Bool = false, keyFont: NSFont? = nil) {
    self.chord = chord
    self.ink = ink
    self.font = keyFont ?? style.keycapFont
    self.enabled = enabled
    self.bare = bare
    self.strong = strong
    super.init(frame: .zero)
    padX = bare ? 0 : placement.keycapPadX
    keyGap = placement.keycapGap
    gap = placement.barGap
    height = placement.keycapH
    radius = max(0, holderRadius - max(0, holderH - height) / 2)
    lineH = NSAttributedString(string: "X", attributes: [.font: font]).size().height
    capMiddle = font.ascender - font.capHeight / 2
    // A larger font than the badge's, a row's shortcut, stands in a box its own line tall.
    height = max(height, ceil(lineH))
    for (i, keys) in chord.enumerated() where !keys.isEmpty && i > 0 {
      let word = NSTextField(labelWithString: placement.keycapOr)
      word.font = style.captionFont
      words.append(word)
      addSubview(word)
    }
    paint()
  }

  // The chip's fill, the keys and the alternative word in the current ink.
  private func paint() {
    fill = bare ? .clear : (enabled ? ink.keycap : ink.keycap.withAlphaComponent(Ink.alpha(ink.keycap) * 0.5))
    let color = bare && !strong ? ink.number : (enabled ? ink.text : ink.textDim)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    for word in words { word.textColor = enabled ? ink.caption : ink.subDim }
    caps = chord.filter { !$0.isEmpty }.map { keys in
      keys.map { mark in
        if let name = mark.symbol, let key = KeyCap.symbol(name, font: font, color: color) { return key }
        return KeyCap.glyph(mark.glyph, attributes)
      }
    }
    needsDisplay = true
  }

  required init?(coder: NSCoder) { nil }

  // A small context Core Text measures a glyph's ink against, made once.
  private static let measureContext: CGContext? = CGContext(data: nil, width: 8, height: 8,
    bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)

  // A glyph's ink, what Core Text's line actually draws, measured from the pen position. A line is
  // measured rather than the attributed string's bounding rect, because a glyph the keycap font
  // lacks is drawn from a fallback font, and the string's own rect answered that font's box rather
  // than its ink. A glyph that draws nothing keeps its advance, so a blank never has no width.
  private static func glyph(_ text: String, _ attributes: [NSAttributedString.Key: Any]) -> Key {
    let string = NSAttributedString(string: text, attributes: attributes)
    let line = CTLineCreateWithAttributedString(string)
    var ink = CTLineGetImageBounds(line, measureContext)
    if ink.isNull || ink.width <= 0 { ink = NSRect(origin: .zero, size: string.size()) }
    return Key(mark: .text(string), ink: ink)
  }

  // A symbol's ink at the size it is drawn, measured once per symbol and font size by drawing it
  // and reading where its pixels are, since a symbol's box carries room the ink does not fill.
  private static var symbolInks: [String: NSRect] = [:]

  private static func inkOf(_ image: NSImage, key: String) -> NSRect? {
    if let known = symbolInks[key] { return known }
    let scale: CGFloat = 4
    let w = Int(ceil(image.size.width * scale)), h = Int(ceil(image.size.height * scale))
    guard w > 0, h > 0, let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = image.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: image.size))
    NSGraphicsContext.restoreGraphicsState()
    var minX = w, maxX = -1, minY = h, maxY = -1
    for y in 0..<h {
      for x in 0..<w where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
      }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    // Rows count from the top in a bitmap, which is the flipped space the cap draws in.
    let ink = NSRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    symbolInks[key] = ink
    return ink
  }

  // A symbol as a key, tinted the text colour and scaled so its ink is as tall as the font's
  // capitals. nil when the system has no symbol of that name, and the key falls back to its glyph.
  private static func symbol(_ name: String, font: NSFont, color: NSColor) -> Key? {
    let config = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular, scale: .small)
      .applying(NSImage.SymbolConfiguration(paletteColors: [color.withAlphaComponent(1)]))
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(config),
      let ink = inkOf(image, key: name + "@" + String(describing: font.pointSize)), ink.height > 0
    else { return nil }
    let k = font.capHeight / ink.height
    let size = NSSize(width: image.size.width * k, height: image.size.height * k)
    let scaled = NSRect(x: ink.minX * k, y: ink.minY * k, width: ink.width * k, height: ink.height * k)
    return Key(mark: .image(image, size, Ink.alpha(color)), ink: scaled)
  }

  // A chip's width, its keys' ink side by side with the key gap between them and padX either side.
  private func capWidth(_ keys: [Key]) -> CGFloat {
    let inks = keys.reduce(0) { $0 + $1.ink.width }
    return ceil(inks + CGFloat(max(0, keys.count - 1)) * keyGap + 2 * padX)
  }

  override var fittingSize: NSSize {
    guard !caps.isEmpty else { return .zero }
    let capsW = caps.reduce(0) { $0 + capWidth($1) }
    let wordsW = words.reduce(0) { $0 + ceil($1.fittingSize.width) + 2 * gap }
    return NSSize(width: capsW + wordsW, height: height)
  }

  override func layout() {
    super.layout()
    chips = []
    places = []
    let lineTop = (bounds.height - lineH) / 2
    var x: CGFloat = 0
    for (i, keys) in caps.enumerated() {
      if i > 0 {
        let word = words[i - 1]
        let size = word.fittingSize
        x += gap
        word.frame = NSRect(x: x, y: (bounds.height - size.height) / 2, width: ceil(size.width), height: size.height)
        x += ceil(size.width) + gap
      }
      let w = capWidth(keys)
      chips.append(NSRect(x: x, y: 0, width: w, height: bounds.height))
      // The keys' ink centred in the chip, so the rounding of the chip's width splits evenly.
      let inks = keys.reduce(0) { $0 + $1.ink.width } + CGFloat(max(0, keys.count - 1)) * keyGap
      var ix = x + (w - inks) / 2
      var row: [NSRect] = []
      for (j, key) in keys.enumerated() {
        if j > 0 { ix += keyGap }
        switch key.mark {
        case .text:
          row.append(NSRect(x: ix - key.ink.minX, y: lineTop, width: 0, height: 0))
        case .image(_, let size, _):
          // The ink's middle on the capitals' middle.
          let top = lineTop + capMiddle - (key.ink.minY + key.ink.height / 2)
          row.append(NSRect(x: ix - key.ink.minX, y: top, width: size.width, height: size.height))
        }
        ix += key.ink.width
      }
      places.append(row)
      x += w
    }
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    fill.setFill()
    for chip in chips { NSBezierPath(roundedRect: chip, xRadius: radius, yRadius: radius).fill() }
    for (keys, row) in zip(caps, places) {
      for (key, place) in zip(keys, row) {
        switch key.mark {
        case .text(let string): string.draw(at: place.origin)
        case .image(let image, _, let alpha):
          image.draw(in: place, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
        }
      }
    }
  }
}

// One group of the bar, a shape of exactly the glass the window stands on, untinted, and tinted
// with the highlight colour only while lit. Its items are items, standing the outer padding in
// from all four edges and touching one another, each a line of the actions pane, so the pointer
// over one lights it in the highlight colour with the corner a panel line takes. A press anywhere
// on it reports through onPress when one is set, whatever part of the group is under the pointer.
final class BarSide: FlippedView {
  var onPress: (() -> Void)?
  // A press reported with where it landed, in the group's own space, for a group whose parts
  // each do something of their own.
  var onPressAt: ((NSPoint) -> Void)?
  var lit = false { didSet { tint() } }
  var color = NSColor.clear { didSet { tint(); shade.color = color } }
  var radius: CGFloat = 0 { didSet { glass.setCornerRadius(radius) } }
  // The items, in the group's own space, and the corner of a lit one.
  var items: [NSRect] = [] { didSet { shade.items = items } }
  var cellRadius: CGFloat = 0 { didSet { shade.radius = cellRadius } }
  // Told the item under the pointer whenever it changes, nil for none, so the bar draws that
  // item's words and chord in the ink of the highlight it stands on.
  var onHover: ((Int?) -> Void)?
  var hovered: Int? { shade.hover }
  private let glass = Surface(holding: FlippedView())
  private let shade = Shade()

  // The lit item, drawn over the glass and under the words and chords.
  final class Shade: FlippedView {
    var items: [NSRect] = [] { didSet { needsDisplay = true } }
    var hover: Int? { didSet { if hover != oldValue { needsDisplay = true } } }
    var color = NSColor.clear { didSet { needsDisplay = true } }
    var radius: CGFloat = 0 { didSet { needsDisplay = true } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
      guard let hover, hover < items.count else { return }
      color.setFill()
      NSBezierPath(roundedRect: items[hover], xRadius: radius, yRadius: radius).fill()
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

  // The item under point, nil between items and in the padding around them.
  func item(at point: NSPoint) -> Int? {
    items.firstIndex { $0.contains(point) }
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
  override func mouseExited(with event: NSEvent) { setHover(nil) }

  // A tracking area reports the pointer whatever stands above it, so a group a floating pane stands
  // over would light under the pane. Only a point the window would hand this group lights it.
  private func hover(_ event: NSEvent) {
    let hit = window?.contentView?.hitTest(event.locationInWindow)
    guard let hit, hit === self || hit.isDescendant(of: self) else { return setHover(nil) }
    setHover(item(at: convert(event.locationInWindow, from: nil)))
  }

  private func setHover(_ index: Int?) {
    guard index != shade.hover else { return }
    shade.hover = index
    onHover?(index)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas { removeTrackingArea(area) }
    addTrackingArea(NSTrackingArea(rect: .zero,
      options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
  }

  override var isHidden: Bool { didSet { if isHidden { setHover(nil) } } }

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
  let button = BarSide()
  private var rightFit: [Bool] = []
  let actions = BarSide()
  private var parts: [NSView] = []
  private var rightParts: [NSView] = []
  private var rightActions: [String?] = []
  private var placement = Placement()
  // A press on an item of the action group, with the action that item names.
  var onItem: (String) -> Void = { _ in }
  // The key button's picture as it came, drawn again on the pixel grid at every layout, and
  // whether it is one colour, redrawn in the lit ink while its group is.
  private var keysSource: NSImage?
  private var keysTint = false
  private var style = Style()
  // The right side morphing from the actions it held to new ones, see BarMorph. While it plays the
  // group stands at the wider of the two widths, morphWidth, its items on its right edge.
  private let morph = BarMorph()
  private var morphWidth: CGFloat = 0
  // The right side's own width, whatever a morph stands it at, which the actions pane is floored on.
  private(set) var actionsWidth: CGFloat = 0

  override init(frame: NSRect) {
    super.init(frame: frame)
    addSubview(button)
    addSubview(actions)
    actions.onPressAt = { [weak self] point in self?.pressItem(at: point) }
    button.onHover = { [weak self] _ in self?.relight() }
    actions.onHover = { [weak self] _ in self?.relight() }
  }

  // Each item's words, chord and picture in the ink of what it stands on, the lit ink while its
  // group is lit whole or the pointer lights it, the glass's otherwise. The key group is one item.
  private func relight() {
    let keysInk = style.ink(lit: button.lit || button.hovered == 0)
    for view in parts {
      if let cap = view as? KeyCap { cap.ink = keysInk }
      if let field = view as? NSTextField { field.textColor = keysInk.text }
    }
    needsLayout = true
    for i in stride(from: 0, to: rightParts.count - 1, by: 2) {
      let ink = style.ink(lit: actions.lit || actions.hovered == i / 2)
      (rightParts[i] as? NSTextField)?.textColor = ink.text
      (rightParts[i + 1] as? KeyCap)?.ink = ink
    }
  }

  // The item whose item is under point runs the action it names.
  private func pressItem(at point: NSPoint) {
    guard let i = actions.item(at: point), i < rightActions.count, let action = rightActions[i] else { return }
    onItem(action)
  }

  required init?(coder: NSCoder) { nil }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  // Only the groups take the pointer, so a press or a scroll between them reaches the rows the
  // list shows behind the bar.
  override func hitTest(_ point: NSPoint) -> NSView? {
    let hit = super.hitTest(point)
    return hit === self ? nil : hit
  }

  // Hides a group while its floating pane stands over it and shows it once the pane leaves it.
  func setGroup(left: Bool, hidden: Bool) {
    if left { button.isHidden = hidden } else { actions.isHidden = hidden || rightParts.isEmpty }
    relight()
  }

  // leftHidden and actionsHidden each hide one group whole, while the panel that group opens
  // stands in its corner. The other group stays as it is.
  // keepRight leaves the right side as it stands, which it does while the actions pane is open, so
  // the group the pane grows out of and shrinks back onto is the one the person pressed rather than
  // one describing the pane, whose width and words changed under the pane as it moved.
  func show(_ bottomBar: BottomBar, style: Style, placement: Placement, lit: Bool, leftHidden: Bool = false,
    actionsHidden: Bool = false, keepRight: Bool = false) {
    self.placement = placement
    self.style = style
    let keepRight = keepRight && !rightParts.isEmpty
    for view in parts { view.removeFromSuperview() }
    parts = []
    // The right side morphs only when its actions changed while it stood on screen, a list switched
    // in place, and never for a label alone, which follows the selected row, nor under its pane.
    let nextActions = bottomBar.right.map { $0.action }
    let morphs = !keepRight && !actionsHidden && !actions.isHidden && window?.isVisible == true
      && !rightParts.isEmpty && !bottomBar.right.isEmpty && nextActions != rightActions
    if morph.moving && (keepRight || actionsHidden || morphs) { endMorph() }
    var leaving: NSView?
    var oldWidth: CGFloat = 0
    if morphs {
      // The old items carry on in a view of their own on the group's right edge, fading out.
      oldWidth = actions.bounds.width
      let hold = FlippedView(frame: actions.bounds)
      for view in rightParts { hold.addSubview(view) }
      leaving = hold
      rightParts = []
    } else if !keepRight {
      for view in rightParts { view.removeFromSuperview() }
      rightParts = []
    }
    keysSource = bottomBar.keysImage
    keysTint = bottomBar.keysTint
    if let image = bottomBar.keysImage {
      let view = NSImageView(image: image)
      view.imageScaling = .scaleProportionallyUpOrDown
      parts.append(view)
    } else {
      parts.append(label("?", style.titleFont, style.text))
    }
    // A item's corner, the panel line's, the group's corner less the padding around the items.
    let capRadius = max(0, style.highlightRadius - placement.barPillPad)
    if !bottomBar.keysChord.isEmpty {
      parts.append(KeyCap(bottomBar.keysChord, ink: style.ink(lit: false), style: style, placement: placement,
        holderH: placement.barPillH, holderRadius: capRadius))
    }
    for view in parts { button.addSubview(view) }
    if !keepRight {
      rightActions = bottomBar.right.map { $0.action }
      rightFit = bottomBar.right.map { $0.fit }
      for item in bottomBar.right {
        rightParts.append(label(item.label, style.titleFont, style.text))
        rightParts.append(KeyCap(item.chord, ink: style.ink(lit: false), style: style, placement: placement,
          holderH: placement.barPillH, holderRadius: capRadius))
      }
      for view in rightParts { actions.addSubview(view) }
      if leaving == nil { morph.adopt(rightParts) }
    }
    for group in [button, actions] {
      group.color = style.highlight
      group.radius = style.highlightRadius
      group.cellRadius = capRadius
    }
    button.lit = lit
    actions.lit = false
    button.isHidden = leftHidden
    actions.isHidden = actionsHidden || rightParts.isEmpty
    relight()
    if let leaving {
      layoutSubtreeIfNeeded()
      let newWidth = actionsWidth
      let h = actions.bounds.height
      morphWidth = max(oldWidth, newWidth)
      needsLayout = true
      layoutSubtreeIfNeeded()
      leaving.frame = NSRect(x: morphWidth - oldWidth, y: 0, width: oldWidth, height: h)
      actions.addSubview(leaving)
      morph.play(group: actions,
        from: NSRect(x: morphWidth - oldWidth, y: 0, width: oldWidth, height: h),
        to: NSRect(x: morphWidth - newWidth, y: 0, width: newWidth, height: h),
        radius: style.highlightRadius, leaving: leaving, arriving: rightParts,
        done: { [weak self] in self?.settleMorph() })
    }
  }

  // The group back on its own width once a morph ends.
  private func settleMorph() {
    morphWidth = 0
    needsLayout = true
  }

  // A morph cut short, by a new one or by the actions pane, ends where it was going.
  private func endMorph() {
    morph.stop()
    settleMorph()
    layoutSubtreeIfNeeded()
  }

  override func layout() {
    super.layout()
    let pad = placement.barPad
    let inner = placement.barPillPad
    let gap = placement.barGap
    let side = placement.infoIcon
    let itemH = placement.barPillH
    let h = itemH + 2 * inner
    // The key group, one item holding its parts side by side, centred in the item's height.
    var x = 2 * inner
    for view in parts {
      let size = view is NSImageView ? NSSize(width: side, height: side) : view.fittingSize
      view.frame = NSRect(x: x, y: inner + (itemH - size.height) / 2, width: size.width, height: size.height)
      x += size.width + gap
    }
    let buttonW = x - gap + 2 * inner
    button.frame = Crisp.align(NSRect(x: pad, y: 0, width: buttonW, height: h), in: self)
    button.items = [NSRect(x: inner, y: inner, width: buttonW - 2 * inner, height: itemH)]
    // The picture on whole pixels and drawn for exactly the pixels it covers, see Crisp.
    for case let view as NSImageView in parts {
      view.frame = Crisp.align(view.frame, in: button)
      if let keysSource {
        let crisp = Crisp.image(keysSource, size: view.frame.size, scale: Crisp.scale(of: self))
        let tint = keysTint ? style.ink(lit: button.lit || button.hovered == 0).icon : nil
        view.image = tint.map { Crisp.tinted(crisp, $0) } ?? crisp
      }
    }
    // The action group, one item per item, edge to edge, its label and chord the inner padding
    // in from the item's sides, then placed flush with the bar pad from the right edge.
    // The right side never reaches past the left side, its widest the bar less the left side and
    // the bar pad three times, between the edges and the groups. Past it the labels marked fit,
    // the primary's and the secondary's, give up width, the longest first, and end in an ellipsis,
    // bar.lua's fitLabels.
    var natural: [CGFloat] = []
    var fixed = 2 * inner
    for i in stride(from: 0, to: rightParts.count - 1, by: 2) {
      let label = rightParts[i].fittingSize.width
      let chord = rightParts[i + 1].fittingSize.width
      natural.append(label)
      fixed += 2 * inner + (chord > 0 ? gap + chord : 0)
    }
    let room = max(0, bounds.width - 3 * pad - buttonW)
    let widths = Self.fitLabels(natural, fit: rightFit, budget: room - fixed)
    var items: [NSRect] = []
    x = inner
    for i in stride(from: 0, to: rightParts.count - 1, by: 2) {
      var label = rightParts[i].fittingSize
      label.width = widths[i / 2]
      let chord = rightParts[i + 1].fittingSize
      let w = inner + label.width + (chord.width > 0 ? gap : 0) + chord.width + inner
      rightParts[i].frame = NSRect(x: x + inner, y: inner + (itemH - label.height) / 2,
        width: label.width, height: label.height)
      rightParts[i + 1].frame = NSRect(x: x + w - inner - chord.width, y: inner + (itemH - chord.height) / 2,
        width: chord.width, height: chord.height)
      items.append(NSRect(x: x, y: inner, width: w, height: itemH))
      x += w
    }
    let actionsW = x + inner
    actionsWidth = actionsW
    // While a morph plays the group stands at the wider of its two widths, its items on its right
    // edge, and the morph's mask shows the width it has reached.
    let standW = max(actionsW, morphWidth)
    let shift = standW - actionsW
    if shift > 0 {
      for view in rightParts { view.frame.origin.x += shift }
      items = items.map { $0.offsetBy(dx: shift, dy: 0) }
    }
    actions.frame = Crisp.align(NSRect(x: bounds.width - pad - standW, y: 0, width: standW, height: h), in: self)
    actions.items = items
  }

  // The widths the labels take so they fit the budget, every label not marked fit kept whole and
  // the fit ones cut, the longest first, until they share what is left equally at most.
  static func fitLabels(_ widths: [CGFloat], fit: [Bool], budget: CGFloat) -> [CGFloat] {
    var out = widths
    var left = budget
    var open: [Int] = []
    for (i, w) in widths.enumerated() {
      if i < fit.count && fit[i] { open.append(i) } else { left -= w }
    }
    guard !open.isEmpty else { return out }
    let total = open.reduce(CGFloat(0)) { $0 + widths[$1] }
    if total <= left { return out }
    open.sort { widths[$0] < widths[$1] }
    var n = CGFloat(open.count)
    for i in open {
      let share = max(0, left) / n
      if widths[i] <= share {
        left -= widths[i]
      } else {
        out[i] = floor(share)
        left -= out[i]
      }
      n -= 1
    }
    return out
  }
}
