// How the tables that describe a chooser are read, whoever hands them over. Lua.swift reads them off
// the Lua stack for Hammerspoon. JSONFields reads the same fields out of the JSON Olm.app is handed,
// `~/.olm/run/chooser.json`, which the bridge writes from the very tables the Lua view sends the
// panel, docs/PLAN-STANDALONE.md. The field names below are the one list of them, so Hammerspoon's
// panel and the app cannot read a look two ways. Every answer is nil when the field is missing or of
// another type, so a caller writes one fallback rather than a type check.

import Cocoa

protocol Fields {
  func number(_ name: String) -> CGFloat?
  func bool(_ name: String) -> Bool?
  func string(_ name: String) -> String?
  // A colour as the UI kit writes one, red, green, blue and alpha between zero and one.
  func color(_ name: String) -> NSColor?
  // A font as a name and a size, the system font of that size when the name is not installed.
  func font(_ name: String) -> NSFont?
  func rect(_ name: String) -> NSRect?
  // A chord as lib/kbd.lua's wire hands it over, a list of alternatives each a list of keys.
  func chord(_ name: String) -> [[KeyMark]]
  // A list of plain numbers, a motion curve's four control points.
  func numbers(_ name: String) -> [Double]
  // A picture, an hs.image from Lua and a PNG data URL out of JSON, the bar's info icon.
  func image(_ name: String) -> NSImage?
  // Calls body once per table in the list at name, the bar's entries.
  func each(_ name: String, _ body: (Fields) -> Void)
}

func fontOf(name: String?, size: CGFloat) -> NSFont {
  if let name, let font = NSFont(name: name, size: size) { return font }
  return NSFont.systemFont(ofSize: size)
}

// A row of the list or of the actions pane, read the same for Hammerspoon's panel and Olm.app's
// actions pane, whose rows come from its share.
extension Row {
  init(_ f: Fields) {
    title = f.string("title") ?? ""
    subtitle = f.string("subtitle") ?? ""
    chord = f.chord("chord")
    enabled = f.bool("enabled") ?? true
    muted = f.bool("muted") ?? false
    image = f.image("image")
    tint = f.bool("tint") ?? false
    section = f.string("section")
  }
}

extension Style {
  init(_ f: Fields) {
    text = f.color("text") ?? text
    textDim = f.color("textDim") ?? textDim
    sub = f.color("sub") ?? sub
    subDim = f.color("subDim") ?? subDim
    highlight = f.color("highlight") ?? highlight
    number = f.color("number") ?? number
    background = f.color("background") ?? background
    caption = f.color("caption") ?? caption
    badge = f.color("badge") ?? badge
    keycap = f.color("keycap") ?? keycap
    fieldFont = f.font("fieldFont") ?? fieldFont
    titleFont = f.font("titleFont") ?? titleFont
    subFont = f.font("subFont") ?? subFont
    numberFont = f.font("numberFont") ?? numberFont
    captionFont = f.font("captionFont") ?? captionFont
    keycapFont = f.font("keycapFont") ?? keycapFont
    rowKeyFont = f.font("rowKeyFont") ?? rowKeyFont
    let numbers = f.chord("numberKeys")
    if !numbers.isEmpty { numberKeys = numbers }
    let ret = f.chord("returnKey")
    if !ret.isEmpty { returnKey = ret }
    radius = f.number("radius") ?? radius
    highlightRadius = f.number("highlightRadius") ?? highlightRadius
  }
}

extension Placement {
  init(_ f: Fields) {
    canvas = f.rect("canvas") ?? canvas
    window = f.rect("window")
    listFrame = f.rect("listFrame")
    paneFrame = f.rect("paneFrame")
    previewPane = f.rect("previewPane")
    field = f.rect("field")
    list = f.rect("list")
    bottomBar = f.rect("bottomBar")
    rowH = max(1, f.number("rowH") ?? rowH)
    iconSize = f.number("iconSize") ?? iconSize
    iconFrame = f.number("iconFrame") ?? iconSize
    iconPad = f.number("iconPad") ?? iconPad
    iconPadLeft = f.number("iconPadLeft") ?? iconPadLeft
    iconGap = f.number("iconGap") ?? iconGap
    padX = f.number("padX") ?? padX
    numW = f.number("numW") ?? numW
    padBottom = f.number("padBottom") ?? padBottom
    pad = f.number("pad") ?? pad
    showNumbers = f.bool("showNumbers") ?? showNumbers
    barInset = f.number("barInset") ?? barInset
    barGap = f.number("barGap") ?? barGap
    barGapWide = f.number("barGapWide") ?? barGapWide
    infoIcon = f.number("infoIcon") ?? infoIcon
    keysPad = f.number("keysPad") ?? keysPad
    barPad = f.number("barPad") ?? barPad
    barPillH = f.number("barPillH") ?? barPillH
    barPillPad = f.number("barPillPad") ?? barPillPad
    keycapH = f.number("keycapH") ?? keycapH
    keycapPadX = f.number("keycapPadX") ?? keycapPadX
    keycapGap = f.number("keycapGap") ?? keycapGap
    keycapOr = f.string("keycapOr") ?? keycapOr
  }
}

extension Motion {
  // The kit's motion tokens, { open, close, rise, scale, paneOpen, paneClose, paneFade, reshape,
  // openCurve, closeCurve, paneCurve, paneCloseCurve, reshapeCurve }, each curve four control point
  // numbers. A field left out keeps what Motion holds.
  static func apply(_ f: Fields) {
    func curve(_ name: String) -> CAMediaTimingFunction? {
      let p = f.numbers(name).map { Float($0) }
      return p.count == 4 ? CAMediaTimingFunction(controlPoints: p[0], p[1], p[2], p[3]) : nil
    }
    if let v = f.number("open") { openDuration = CFTimeInterval(v) }
    if let v = f.number("close") { closeDuration = CFTimeInterval(v) }
    if let v = f.number("rise") { rise = v }
    if let v = f.number("scale") { scale = v }
    if let v = f.number("paneOpen") { paneOpenDuration = CFTimeInterval(v) }
    if let v = f.number("paneClose") { paneCloseDuration = CFTimeInterval(v) }
    if let v = f.number("paneFade") { paneFadeDuration = CFTimeInterval(v) }
    if let v = f.number("reshape") { reshapeDuration = CFTimeInterval(v) }
    if let c = curve("openCurve") { openCurve = c }
    if let c = curve("closeCurve") { closeCurve = c }
    if let c = curve("paneCurve") { paneCurve = c }
    if let c = curve("paneCloseCurve") { paneCloseCurve = c }
    if let c = curve("reshapeCurve") { reshapeCurve = c }
  }
}

// The bottom bar's model, read here for Hammerspoon's panel and for Olm.app alike, so the bar the
// app draws from the share host/bridge writes, step 1.4f, reads the very fields the Lua view sends.
extension BottomBar {
  init(_ f: Fields) {
    f.each("right") { e in
      right.append(Entry(label: e.string("label") ?? "", chord: e.chord("chord"),
        action: e.string("action"), fit: e.bool("fit") ?? false))
    }
    f.each("keys") { e in
      keys.append(Entry(label: e.string("label") ?? "", chord: e.chord("chord"),
        section: e.string("section"), lead: e.chord("lead")))
    }
    keysChord = f.chord("keysChord")
    keysImage = f.image("keysImage")
    keysTint = f.bool("keysTint") ?? false
    title = f.string("title")
    panelOpen = f.bool("panelOpen") ?? false
    panelTitle = f.string("panelTitle")
  }
}

// The same fields out of a decoded JSON object. A boolean is told from a number by its Core
// Foundation type, since JSONSerialization hands both as NSNumber.
struct JSONFields: Fields {
  let object: [String: Any]

  init(_ object: [String: Any]) { self.object = object }
  init(_ value: Any?) { self.object = value as? [String: Any] ?? [:] }

  private static func isBool(_ n: NSNumber) -> Bool { CFGetTypeID(n) == CFBooleanGetTypeID() }

  private static func number(_ value: Any?) -> CGFloat? {
    guard let n = value as? NSNumber, !isBool(n) else { return nil }
    return CGFloat(n.doubleValue)
  }

  func number(_ name: String) -> CGFloat? { Self.number(object[name]) }

  func bool(_ name: String) -> Bool? {
    guard let n = object[name] as? NSNumber, Self.isBool(n) else { return nil }
    return n.boolValue
  }

  func string(_ name: String) -> String? { object[name] as? String }

  func color(_ name: String) -> NSColor? {
    let c = JSONFields(object[name])
    guard let r = c.number("red"), let g = c.number("green"), let b = c.number("blue") else { return nil }
    return NSColor(srgbRed: r, green: g, blue: b, alpha: c.number("alpha") ?? 1)
  }

  func font(_ name: String) -> NSFont? {
    let f = JSONFields(object[name])
    guard let size = f.number("size") else { return nil }
    return fontOf(name: f.string("name"), size: size)
  }

  func rect(_ name: String) -> NSRect? {
    let r = JSONFields(object[name])
    guard let x = r.number("x"), let y = r.number("y"), let w = r.number("w"), let h = r.number("h")
    else { return nil }
    return NSRect(x: x, y: y, width: w, height: h)
  }

  func chord(_ name: String) -> [[KeyMark]] {
    guard let alternatives = object[name] as? [Any] else { return [] }
    return alternatives.compactMap { alt -> [KeyMark]? in
      guard let keys = alt as? [Any] else { return nil }
      let marks = keys.compactMap { key -> KeyMark? in
        let k = JSONFields(key)
        guard let glyph = k.string("glyph") else { return nil }
        return KeyMark(glyph: glyph, symbol: k.string("symbol"))
      }
      return marks.isEmpty ? nil : marks
    }
  }

  func numbers(_ name: String) -> [Double] {
    (object[name] as? [Any] ?? []).compactMap { Self.number($0).map { Double($0) } }
  }

  func image(_ name: String) -> NSImage? {
    guard let url = object[name] as? String, let comma = url.firstIndex(of: ","),
      url.hasPrefix("data:"), let data = Data(base64Encoded: String(url[url.index(after: comma)...]))
    else { return nil }
    return NSImage(data: data)
  }

  func each(_ name: String, _ body: (Fields) -> Void) {
    for item in object[name] as? [Any] ?? [] where item is [String: Any] { body(JSONFields(item)) }
  }
}
