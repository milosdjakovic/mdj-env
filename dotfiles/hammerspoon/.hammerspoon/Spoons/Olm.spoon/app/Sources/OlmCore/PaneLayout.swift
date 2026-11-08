// The preview pane's layout, step 1.4a of docs/PLAN-STANDALONE.md, a port of the parts of the Lua UI
// kit a preview pane is drawn with, lib/ui/measure.lua, lib/ui/tabs.lua and lib/ui/layout.lua, so a
// pane in Olm.app is laid out exactly where the swift chooser's pane is. The tokens come from
// Hammerspoon, `~/.olm/run/chooser.json` under pane, which the bridge writes from the kit's own
// resolved tokens, lib/chooser/providers/swift/pane.lua's tokens, so no font, size, colour or space
// is written here. test/fixtures/chooser/pane.json pins the result, recorded from the Lua pane and
// run by olm-fixtures.
//
// What is ported is what a pane uses, text with its wrap, width, alignment and line break, a row
// with its filling child, a stack with its gaps, a code block with the visible slice rule, and since
// step 1.4b a picture, kit.image, with imageFit's size and its nested radius clip, plus the clip a
// layout opens and closes. The arithmetic is the Lua's in the same order, since the
// fixtures compare frames.
//
// MEASURING. A width is what hs.drawing.getTextDrawingSize answers, which is NSString's size with
// the font alone, checked against the live Hammerspoon on 2026-11-08 to the last bit for every
// role's font. A natural width is measured whole, measure.lua's exact, and a wrap sums one width per
// character, measure.lua's width, so the two sides break a line at the same character.
//
// Nothing here touches a window, so a layout runs off the main thread, rule 8 of the plan, and only
// the elements it answers are drawn on it, by PaneHost.

import AppKit
@preconcurrency @testable import OlmChooser

public struct PaneRect: Equatable, Sendable {
  public var x, y, w, h: Double
  public init(x: Double, y: Double, w: Double, h: Double) {
    self.x = x
    self.y = y
    self.w = w
    self.h = h
  }
}

/// A colour as the kit resolves one, red, green, blue and alpha between zero and one, sRGB.
public struct PaneColor: Equatable, Sendable {
  public var red, green, blue, alpha: Double
  public init(red: Double, green: Double, blue: Double, alpha: Double) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }
}

/// One text the layout placed, what lib/ui/layout.lua's textElement builds as hs.styledtext.
public struct PaneText: Equatable, Sendable {
  public var string: String
  public var frame: PaneRect
  public var font: String
  public var size: Double
  public var color: PaneColor
  /// left, right or center.
  public var align: String
  /// One of lib/ui/kit.lua's lineBreaks.
  public var lineBreak: String
  /// The line height pinned both ways.
  public var lineHeight: Double
  /// The mono font never tightens before it truncates, so a code column stays aligned.
  public var tight: Bool
}

/// A picture a pane draws, its own size in points as hs.image's size answers it, and the image
/// decoded off the main thread, PanePicture, or nil where only the size is known, as in a fixture.
public struct PaneImage: @unchecked Sendable, Equatable {
  public var path: String
  public var w, h: Double
  public let image: NSImage?

  public init(path: String, w: Double, h: Double, image: NSImage? = nil) {
    self.path = path
    self.w = w
    self.h = h
    self.image = image
  }

  public static func == (a: PaneImage, b: PaneImage) -> Bool { a.path == b.path && a.w == b.w && a.h == b.h }
}

/// One element of a laid out pane, the hs.canvas element the Lua layout answers.
public enum PaneItem: Equatable, Sendable {
  /// A rectangle added to the clip, rounded by radius when it is above zero.
  case clip(PaneRect, radius: Double)
  case resetClip
  case text(PaneText)
  /// A picture scaled proportionally into its frame at the top left, at alpha.
  case image(PaneImage, PaneRect, alpha: Double)
}

/// The tokens a pane is laid out with, one half's, as pane.lua's tokens hands them over.
public struct PaneTokens: @unchecked Sendable {
  public struct Role: @unchecked Sendable {
    public var font: String
    public var size: Double
    public var lineHeight: Double
    /// The colour role the text is drawn in unless a node names another.
    public var color: String
    let nsFont: NSFont
    // The font's cap height and descender, measure.lua's metrics, which centre a text in its band.
    let capHeight: Double
    let descender: Double

    init(font: String, size: Double, lineHeight: Double, color: String) {
      self.font = font
      self.size = size
      self.lineHeight = lineHeight
      self.color = color
      nsFont = fontOf(name: font, size: CGFloat(size))
      capHeight = Double(nsFont.capHeight)
      descender = Double(nsFont.descender)
    }
  }

  public var pad: Double
  public var space: [String: Double]
  public var nestedRadius: Double
  /// The box inside the surface's border, its inset from each edge and its corner.
  public var interiorInset: Double
  public var interiorRadius: Double
  public var mono: String?
  public var text: [String: Role]
  public var colors: [String: PaneColor]

  /// One half as JSON carries it, nil when it holds no type roles.
  public init?(_ value: Any?) {
    guard let object = value as? [String: Any] else { return nil }
    func number(_ v: Any?) -> Double? {
      guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
      return n.doubleValue
    }
    var roles: [String: Role] = [:]
    for (name, raw) in object["text"] as? [String: Any] ?? [:] {
      guard let r = raw as? [String: Any], let size = number(r["size"]), let lh = number(r["lineHeight"]) else { continue }
      roles[name] = Role(font: r["font"] as? String ?? "", size: size, lineHeight: lh,
        color: r["color"] as? String ?? "foreground")
    }
    guard !roles.isEmpty else { return nil }
    text = roles
    pad = number(object["pad"]) ?? 0
    space = (object["space"] as? [String: Any] ?? [:]).compactMapValues { number($0) }
    nestedRadius = number((object["radius"] as? [String: Any])?["nested"]) ?? 0
    let interior = object["interior"] as? [String: Any] ?? [:]
    interiorInset = number(interior["inset"]) ?? 0
    interiorRadius = number(interior["radius"]) ?? 0
    mono = (object["fonts"] as? [String: Any])?["mono"] as? String
    var colors: [String: PaneColor] = [:]
    for (name, raw) in object["colors"] as? [String: Any] ?? [:] {
      guard let c = raw as? [String: Any], let r = number(c["red"]), let g = number(c["green"]),
        let b = number(c["blue"]) else { continue }
      colors[name] = PaneColor(red: r, green: g, blue: b, alpha: number(c["alpha"]) ?? 1)
    }
    self.colors = colors
  }

  func role(_ name: String) -> Role {
    text[name] ?? text["body"] ?? text.values.first!
  }
}

/// lib/ui/measure.lua, the widths and the wrap, cached by font and size. Safe across threads.
public final class PaneMeasure: @unchecked Sendable {
  private let lock = NSLock()
  private var chars: [String: [String: Double]] = [:]
  private var whole: [String: Double] = [:]

  public init() {}

  private static func measured(_ s: String, _ font: NSFont) -> Double {
    Double((s as NSString).size(withAttributes: [.font: font]).width)
  }

  private static func key(_ role: PaneTokens.Role) -> String { role.font + "\u{0}" + String(role.size) }

  /// One string measured whole in a font, for a check against what Hammerspoon measured.
  public static func measure(_ s: String, font: String, size: Double) -> Double {
    measured(s, fontOf(name: font, size: CGFloat(size)))
  }

  /// One character's width, measured once per font and size.
  func charWidth(_ ch: String, _ role: PaneTokens.Role) -> Double {
    let k = Self.key(role)
    if let w = lock.withLock({ chars[k]?[ch] }) { return w }
    let w = Self.measured(ch, role.nsFont)
    lock.withLock { chars[k, default: [:]][ch] = w }
    return w
  }

  /// measure.lua's width, the sum of each character's own, stepped by code point.
  func width(_ scalars: ArraySlice<Unicode.Scalar>, _ role: PaneTokens.Role) -> Double {
    var total = 0.0
    for s in scalars { total = total + charWidth(String(Character(s)), role) }
    return total
  }

  func width(_ s: String, _ role: PaneTokens.Role) -> Double {
    width(ArraySlice(Array(s.unicodeScalars)), role)
  }

  /// measure.lua's exact, one string measured whole, emptied past 512 strings as the Lua is.
  func exact(_ s: String, _ role: PaneTokens.Role) -> Double {
    if s.isEmpty { return 0 }
    let k = Self.key(role) + "\u{0}" + s
    if let w = lock.withLock({ whole[k] }) { return w }
    let w = Self.measured(s, role.nsFont)
    lock.withLock {
      if whole.count >= 512 { whole = [:] }
      whole[k] = w
    }
    return w
  }

  /// lib/ui/tabs.lua, a tab to the next multiple of four columns, counted in code points.
  public static func expandTabs(_ line: String) -> String {
    guard line.unicodeScalars.contains("\t") else { return line }
    var out = String.UnicodeScalarView()
    var col = 0
    for s in line.unicodeScalars {
      if s == "\t" {
        let n = 4 - (col % 4)
        out.append(contentsOf: Array(repeating: " ", count: n))
        col += n
      } else {
        out.append(s)
        col += 1
      }
    }
    return String(out)
  }

  /// measure.lua's wrap, greedy by word with the whitespace kept, a word wider than the line
  /// broken by character, tabs expanded first, at least one line.
  func wrap(_ str: String, _ role: PaneTokens.Role, _ maxW: Double?) -> [String] {
    guard let maxW, maxW > 0 else { return [str] }
    let all = Array(Self.expandTabs(str).unicodeScalars)
    var lines: [String] = []
    func text(_ s: ArraySlice<Unicode.Scalar>) -> String {
      var v = String.UnicodeScalarView()
      v.append(contentsOf: s)
      return String(v)
    }
    for paragraph in all.split(separator: "\n", omittingEmptySubsequences: false) {
      if paragraph.isEmpty || width(paragraph, role) <= maxW {
        lines.append(text(paragraph))
        continue
      }
      var cur: [Unicode.Scalar] = []
      var curW = 0.0
      let before = lines.count
      var pos = paragraph.startIndex
      let n = paragraph.endIndex
      while pos < n {
        let isSpace = paragraph[pos] == " "
        var stop = pos
        while stop < n, (paragraph[stop] == " ") == isSpace { stop += 1 }
        let token = paragraph[pos..<stop]
        pos = stop
        let w = width(token, role)
        if curW + w <= maxW {
          cur.append(contentsOf: token)
          curW = curW + w
        } else if isSpace {
          if !cur.isEmpty { lines.append(text(cur[...])) }
          cur = []
          curW = 0
        } else {
          // The spaces trailing a line that breaks before a word are the break, not content.
          while cur.last == " " { cur.removeLast() }
          if !cur.isEmpty { lines.append(text(cur[...])) }
          if w <= maxW {
            cur = Array(token)
            curW = w
          } else {
            var piece: [Unicode.Scalar] = []
            var pieceW = 0.0
            for ch in token {
              let cw = charWidth(String(Character(ch)), role)
              if !piece.isEmpty, pieceW + cw > maxW {
                lines.append(text(piece[...]))
                piece = []
                pieceW = 0
              }
              piece.append(ch)
              pieceW = pieceW + cw
            }
            cur = piece
            curW = pieceW
          }
        }
      }
      if !cur.isEmpty || lines.count == before { lines.append(text(cur[...])) }
    }
    return lines
  }
}

/// A kit node, the part of lib/ui/kit.lua a pane is built from.
indirect enum PaneNode {
  struct Text {
    var str: String
    var variant: String
    var color: String?
    var align: String?
    var lineBreak: String?
    var wrap = false
    var width: Double?
  }

  case text(Text)
  case row([PaneNode], gap: String? = nil, align: String? = nil, fill: Bool = true, fillIndex: Int? = nil)
  case stack([PaneNode], gap: String? = nil)
  /// The lines with their tabs expanded, as kit.code holds them.
  case code([String])
  /// kit.image, drawn at the width of its slot, or its own where it may not be upscaled.
  case image(PaneImage, upscale: Bool)

  static func text(_ str: String, _ variant: String, color: String? = nil, align: String? = nil,
                   lineBreak: String? = nil, wrap: Bool = false) -> PaneNode {
    .text(Text(str: str, variant: variant, color: color, align: align, lineBreak: lineBreak, wrap: wrap))
  }

  static func codeBlock(_ lines: [String]) -> PaneNode { .code(lines.map(PaneMeasure.expandTabs)) }
}

/// lib/ui/layout.lua's engine over one token table and one measurer.
struct PaneLayoutEngine {
  let T: PaneTokens
  let measure: PaneMeasure

  private struct Slot {
    var node: PaneNode
    var w: Double
    var h: Double
  }

  private struct Context {
    var items: [PaneItem] = []
    var window: (top: Double, bottom: Double)?
    // The clip the layout opened, put back after a picture's own.
    var clip: PaneItem?
  }

  // layout.lua's imageFit, the slot's width or the picture's own where it may not be upscaled and
  // is narrower, the height following its aspect, and a square of the width for one with no size.
  private func imageFit(_ img: PaneImage, _ upscale: Bool, _ maxW: Double) -> (Double, Double) {
    guard img.w > 0, img.h > 0 else { return (maxW, maxW) }
    let w = upscale ? maxW : min(maxW, img.w)
    return (w, w * img.h / img.w)
  }

  private func spaceOf(_ name: String?) -> Double { name.flatMap { T.space[$0] } ?? 0 }

  private func rowSlots(_ kids: [PaneNode], gap gapName: String?, fill: Bool, fillIndex: Int?,
                        _ maxW: Double) -> ([Slot], Double, Double) {
    let gap = spaceOf(gapName)
    let fillAt: Int? = fill ? (fillIndex ?? kids.count) : nil
    var slots: [Slot?] = Array(repeating: nil, count: kids.count)
    var others = 0.0, gapsBefore = 0.0
    for (i, child) in kids.enumerated() {
      if i > 0 { gapsBefore = gapsBefore + gap }
      if i + 1 != fillAt {
        let (cw, ch) = sizeOf(child, max(0, maxW - gapsBefore - others))
        slots[i] = Slot(node: child, w: cw, h: ch)
        others = others + cw
      }
    }
    let room = max(0, maxW - gap * Double(max(0, kids.count - 1)) - others)
    if let fillAt, fillAt >= 1, fillAt <= kids.count {
      let (_, ch) = sizeOf(kids[fillAt - 1], room)
      slots[fillAt - 1] = Slot(node: kids[fillAt - 1], w: room, h: ch)
    }
    var used = 0.0, rowH = 0.0
    var out: [Slot] = []
    // ipairs stops at the first hole, as the Lua's does.
    for (i, slot) in slots.enumerated() {
      guard let slot else { break }
      if i > 0 { used = used + gap }
      used = used + slot.w
      if slot.h > rowH { rowH = slot.h }
      out.append(slot)
    }
    return (out, used, rowH)
  }

  private func stackSize(_ children: [PaneNode], _ gap: Double, _ maxW: Double) -> (Double, Double) {
    var w = 0.0, h = 0.0, n = 0
    for child in children {
      let (cw, ch) = sizeOf(child, maxW)
      if n > 0 { h = h + gap }
      h = h + ch
      n += 1
      if cw > w { w = cw }
    }
    return (w, h)
  }

  func sizeOf(_ node: PaneNode, _ maxW: Double) -> (Double, Double) {
    switch node {
    case .text(let t):
      let v = T.role(t.variant)
      if let width = t.width {
        let slot = min(width, maxW)
        if t.wrap { return (slot, Double(measure.wrap(t.str, v, slot).count) * v.lineHeight) }
        return (slot, v.lineHeight)
      }
      if t.wrap { return (maxW, Double(measure.wrap(t.str, v, maxW).count) * v.lineHeight) }
      return (min(measure.exact(t.str, v).rounded(.up), maxW), v.lineHeight)
    case .code(let lines):
      return (maxW, Double(lines.count) * T.role("code").lineHeight)
    case .row(let kids, let gap, _, let fill, let fillIndex):
      let (_, used, rowH) = rowSlots(kids, gap: gap, fill: fill, fillIndex: fillIndex, maxW)
      return (used, rowH)
    case .stack(let kids, let gap):
      return stackSize(kids, spaceOf(gap), maxW)
    case .image(let img, let upscale):
      return imageFit(img, upscale, maxW)
    }
  }

  // layout.lua's glyphShift, the frame moved up so the font's cap height sits centred in its band.
  private func glyphShift(_ v: PaneTokens.Role) -> Double {
    (v.capHeight + 2 * abs(v.descender) - v.lineHeight) / 2 + 0.25
  }

  private func textItem(_ str: String, _ v: PaneTokens.Role, _ colorRole: String, _ align: String,
                        _ lineBreak: String, _ frame: PaneRect) -> PaneItem {
    var frame = frame
    frame.y = frame.y + glyphShift(v)
    let color = T.colors[colorRole] ?? PaneColor(red: 0, green: 0, blue: 0, alpha: 1)
    return .text(PaneText(string: str, frame: frame, font: v.font, size: v.size, color: color, align: align,
      lineBreak: lineBreak, lineHeight: v.lineHeight, tight: v.font == T.mono))
  }

  private func emitStack(_ children: [PaneNode], _ gap: Double, _ x: Double, _ y: Double, _ w: Double,
                         _ ctx: inout Context) {
    var cy = y, n = 0
    for child in children {
      let (_, ch) = sizeOf(child, w)
      if n > 0 { cy = cy + gap }
      emit(child, x, cy, w, ch, &ctx)
      cy = cy + ch
      n += 1
    }
  }

  private func emit(_ node: PaneNode, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ ctx: inout Context) {
    switch node {
    case .text(let t):
      let v = T.role(t.variant)
      let lineBreak = t.lineBreak ?? (t.wrap ? "wordWrap" : "truncateTail")
      let tw = t.width.map { min($0, w) } ?? w
      ctx.items.append(textItem(t.str, v, t.color ?? v.color, t.align ?? "left", lineBreak,
        PaneRect(x: x, y: y, w: tw, h: h)))
    case .code(let lines):
      // The visible slice rule, every line one height, a line wholly outside the window skipped,
      // the rest drawn as one text joined by newlines.
      let code = T.role("code")
      let lh = code.lineHeight
      let shown = lines.count
      var first = 1, last = shown
      if let win = ctx.window, shown > 0 {
        first = max(1, Int(((win.top - y) / lh).rounded(.down)) + 1)
        last = min(shown, Int(((win.bottom - y) / lh).rounded(.up)))
      }
      if last >= first {
        let slice = lines[(first - 1)..<last].joined(separator: "\n")
        ctx.items.append(textItem(slice, code, code.color, "left", "truncateTail",
          PaneRect(x: x, y: y + Double(first - 1) * lh, w: w, h: Double(last - first + 1) * lh)))
      }
    case .row(let kids, let gap, let align, let fill, let fillIndex):
      let (slots, _, rowH) = rowSlots(kids, gap: gap, fill: fill, fillIndex: fillIndex, w)
      let g = spaceOf(gap)
      var cx = x
      for (i, slot) in slots.enumerated() {
        if i > 0 { cx = cx + g }
        var cy = y
        if align == "center" { cy = y + ((rowH - slot.h) / 2 + 0.5).rounded(.down) }
        else if align == "end" { cy = y + rowH - slot.h }
        emit(slot.node, cx, cy, slot.w, slot.h, &ctx)
        cx = cx + slot.w
      }
    case .stack(let kids, let gap):
      emitStack(kids, spaceOf(gap), x, y, w, &ctx)
    case .image(let img, let upscale):
      // A picture sits a pad inside its pane, so its corners take the nested radius, and the
      // canvas has one clip region, so the layout's own clip is put back after it.
      let (iw, ih) = imageFit(img, upscale, w)
      let frame = PaneRect(x: x, y: y, w: iw, h: ih)
      let r = T.nestedRadius
      if r > 0 { ctx.items.append(.clip(frame, radius: r)) }
      ctx.items.append(.image(img, frame, alpha: 1))
      if r > 0 {
        ctx.items.append(.resetClip)
        if let clip = ctx.clip { ctx.items.append(clip) }
      }
    }
  }

  /// engine.layout, the elements and the content height. scrollY set lays a code block out only
  /// inside the visible window, and any of scrollY, clip and viewport clips to the viewport, or to
  /// rect when there is none.
  func layout(_ node: PaneNode, _ rect: PaneRect, scrollY: Double? = nil, clip: Bool = false,
              viewport: PaneRect? = nil, viewportRadius: Double = 0) -> ([PaneItem], Double) {
    var ctx = Context()
    let clipped = scrollY != nil || clip || viewport != nil
    let box = viewport ?? rect
    if clipped {
      ctx.clip = .clip(box, radius: viewport != nil ? viewportRadius : 0)
      ctx.items.append(ctx.clip!)
    }
    let (_, contentH) = sizeOf(node, rect.w)
    if scrollY != nil { ctx.window = (top: box.y, bottom: box.y + box.h) }
    emit(node, rect.x, rect.y - (scrollY ?? 0), rect.w, contentH, &ctx)
    if clipped { ctx.items.append(.resetClip) }
    return (ctx.items, contentH)
  }
}
