// Reading Lua values into Swift and pushing Swift values back. This file and Entry.swift are the
// seam, the only Swift here that touches LuaSkin or the Lua C API, Entry.swift for the functions Lua
// calls and this file for the values they carry. The first half is plumbing that knows the Lua
// stack and nothing about a chooser, so everything else reads a table field by name and never
// touches an index by hand. The second half builds the model from what the Lua view hands over, and
// reads a pane's element list, so Model.swift, Pane.swift and everything that draws know no Lua.

import Cocoa

// Lua's state arrives as a typed pointer here, since LuaSkin's headers make its struct complete.
public typealias LuaState = UnsafeMutablePointer<lua_State>

// One argument of an event the panel sends, Source.swift, pushed onto the Lua stack.
func pushValue(_ L: LuaState?, _ value: PanelValue) {
  switch value {
  case .string(let text): _ = lua_pushstring(L, text)
  case .bytes(let data): data.withUnsafeBytes { raw in olm_pushBytes(L, raw.baseAddress, raw.count) }
  case .int(let number): lua_pushinteger(L, lua_Integer(number))
  case .number(let number): lua_pushnumber(L, number)
  case .bool(let flag): lua_pushboolean(L, flag ? 1 : 0)
  case .none: lua_pushnil(L)
  }
}

// Reads values off the stack and fields off tables, every answer nil when the value is missing
// or of another type, so a caller writes one fallback rather than a type check.
struct LuaReader {
  let L: LuaState?

  init(_ L: LuaState?) { self.L = L }

  func absolute(_ index: Int32) -> Int32 { lua_absindex(L, index) }

  func isTable(_ index: Int32) -> Bool { lua_type(L, index) == LUA_TTABLE }

  func string(at index: Int32) -> String? {
    guard lua_type(L, index) == LUA_TSTRING else { return nil }
    var length = 0
    guard let raw = lua_tolstring(L, index, &length) else { return nil }
    return String(decoding: UnsafeRawBufferPointer(start: raw, count: length), as: UTF8.self)
  }

  func bytes(at index: Int32) -> Data? {
    guard lua_type(L, index) == LUA_TSTRING else { return nil }
    var length = 0
    guard let raw = lua_tolstring(L, index, &length) else { return nil }
    return Data(bytes: raw, count: length)
  }

  func number(at index: Int32) -> Double? {
    lua_type(L, index) == LUA_TNUMBER ? olm_toNumber(L, index) : nil
  }

  func integer(at index: Int32) -> Int? {
    lua_type(L, index) == LUA_TNUMBER ? Int(olm_toInteger(L, index)) : nil
  }

  // Pushes table[name], runs read on it, and pops it again whatever read answered.
  func field<T>(_ table: Int32, _ name: String, _ read: (Int32) -> T?) -> T? {
    guard isTable(table) else { return nil }
    _ = lua_getfield(L, table, name)
    defer { olm_pop(L, 1) }
    return read(lua_gettop(L))
  }

  func string(_ table: Int32, _ name: String) -> String? { field(table, name) { string(at: $0) } }

  func number(_ table: Int32, _ name: String) -> CGFloat? {
    field(table, name) { number(at: $0).map { CGFloat($0) } }
  }

  func integer(_ table: Int32, _ name: String) -> Int? { field(table, name) { integer(at: $0) } }

  func bool(_ table: Int32, _ name: String) -> Bool? {
    field(table, name) { lua_type(L, $0) == LUA_TBOOLEAN ? lua_toboolean(L, $0) != 0 : nil }
  }

  // A colour table as the UI kit writes one, red, green, blue and alpha between zero and one.
  func color(_ table: Int32, _ name: String) -> NSColor? {
    field(table, name) { index in
      guard isTable(index), let r = number(index, "red"), let g = number(index, "green"),
        let b = number(index, "blue")
      else { return nil }
      return NSColor(srgbRed: r, green: g, blue: b, alpha: number(index, "alpha") ?? 1)
    }
  }

  // A font as a name and a size, the system font of that size when the name is not installed.
  func font(_ table: Int32, _ name: String) -> NSFont? {
    field(table, name) { index in
      guard isTable(index), let size = number(index, "size") else { return nil }
      if let face = string(index, "name"), let font = NSFont(name: face, size: size) { return font }
      return NSFont.systemFont(ofSize: size)
    }
  }

  func rect(_ table: Int32, _ name: String) -> NSRect? {
    field(table, name) { index in
      guard isTable(index), let x = number(index, "x"), let y = number(index, "y"),
        let w = number(index, "w"), let h = number(index, "h")
      else { return nil }
      return NSRect(x: x, y: y, width: w, height: h)
    }
  }

  // An hs.image, converted through the helper Hammerspoon's image module registers with LuaSkin.
  func image(_ table: Int32, _ name: String) -> NSImage? {
    field(table, name) { index in
      guard lua_type(L, index) == LUA_TUSERDATA, let L else { return nil }
      let skin = LuaSkin.shared(with: L) as! LuaSkin
      return skin.luaObject(at: index, toClass: "NSImage") as? NSImage
    }
  }

  // A chord as lib/kbd.lua's wire hands it over, a list of alternatives each a list of keys, one
  // entry per key, each its glyph and the SF Symbol drawn in its place where it names one, so a
  // chord never crosses the bridge as one joined string.
  func chord(_ table: Int32, _ name: String) -> [[KeyMark]] {
    var out: [[KeyMark]] = []
    each(table, name) { alt in
      guard isTable(alt) else { return }
      var keys: [KeyMark] = []
      let count = lua_rawlen(L, alt)
      if count > 0 {
        for i in 1...count {
          _ = lua_rawgeti(L, alt, lua_Integer(i))
          let entry = lua_gettop(L)
          if isTable(entry), let glyph = string(entry, "glyph") {
            keys.append(KeyMark(glyph: glyph, symbol: string(entry, "symbol")))
          }
          olm_pop(L, 1)
        }
      }
      if !keys.isEmpty { out.append(keys) }
    }
    return out
  }

  // Calls body once per element of the array at table[name], each pushed while body runs.
  func each(_ table: Int32, _ name: String, _ body: (Int32) -> Void) {
    _ = field(table, name) { index -> Bool? in
      guard isTable(index) else { return nil }
      let count = lua_rawlen(L, index)
      guard count > 0 else { return nil }
      for i in 1...count {
        _ = lua_rawgeti(L, index, lua_Integer(i))
        body(lua_gettop(L))
        olm_pop(L, 1)
      }
      return nil
    }
  }
}

// MARK: The model, built from the tables the Lua view hands over

extension Style {
  init(_ r: LuaReader, _ t: Int32) {
    text = r.color(t, "text") ?? text
    textDim = r.color(t, "textDim") ?? textDim
    sub = r.color(t, "sub") ?? sub
    subDim = r.color(t, "subDim") ?? subDim
    highlight = r.color(t, "highlight") ?? highlight
    number = r.color(t, "number") ?? number
    background = r.color(t, "background") ?? background
    caption = r.color(t, "caption") ?? caption
    badge = r.color(t, "badge") ?? badge
    keycap = r.color(t, "keycap") ?? keycap
    fieldFont = r.font(t, "fieldFont") ?? fieldFont
    titleFont = r.font(t, "titleFont") ?? titleFont
    subFont = r.font(t, "subFont") ?? subFont
    numberFont = r.font(t, "numberFont") ?? numberFont
    captionFont = r.font(t, "captionFont") ?? captionFont
    keycapFont = r.font(t, "keycapFont") ?? keycapFont
    rowKeyFont = r.font(t, "rowKeyFont") ?? rowKeyFont
    let numbers = r.chord(t, "numberKeys")
    if !numbers.isEmpty { numberKeys = numbers }
    let ret = r.chord(t, "returnKey")
    if !ret.isEmpty { returnKey = ret }
    radius = r.number(t, "radius") ?? radius
    highlightRadius = r.number(t, "highlightRadius") ?? highlightRadius
  }
}

extension Placement {
  init(_ r: LuaReader, _ t: Int32) {
    canvas = r.rect(t, "canvas") ?? canvas
    window = r.rect(t, "window")
    listFrame = r.rect(t, "listFrame")
    paneFrame = r.rect(t, "paneFrame")
    previewPane = r.rect(t, "previewPane")
    field = r.rect(t, "field")
    list = r.rect(t, "list")
    bottomBar = r.rect(t, "bottomBar")
    rowH = max(1, r.number(t, "rowH") ?? rowH)
    iconSize = r.number(t, "iconSize") ?? iconSize
    iconFrame = r.number(t, "iconFrame") ?? iconSize
    iconPad = r.number(t, "iconPad") ?? iconPad
    iconPadLeft = r.number(t, "iconPadLeft") ?? iconPadLeft
    iconGap = r.number(t, "iconGap") ?? iconGap
    padX = r.number(t, "padX") ?? padX
    numW = r.number(t, "numW") ?? numW
    padBottom = r.number(t, "padBottom") ?? padBottom
    pad = r.number(t, "pad") ?? pad
    showNumbers = r.bool(t, "showNumbers") ?? showNumbers
    barInset = r.number(t, "barInset") ?? barInset
    barGap = r.number(t, "barGap") ?? barGap
    barGapWide = r.number(t, "barGapWide") ?? barGapWide
    infoIcon = r.number(t, "infoIcon") ?? infoIcon
    keysPad = r.number(t, "keysPad") ?? keysPad
    barPad = r.number(t, "barPad") ?? barPad
    barPillH = r.number(t, "barPillH") ?? barPillH
    barPillPad = r.number(t, "barPillPad") ?? barPillPad
    keycapH = r.number(t, "keycapH") ?? keycapH
    keycapPadX = r.number(t, "keycapPadX") ?? keycapPadX
    keycapGap = r.number(t, "keycapGap") ?? keycapGap
    keycapOr = r.string(t, "keycapOr") ?? keycapOr
  }
}

extension Row {
  init(_ r: LuaReader, _ t: Int32) {
    title = r.string(t, "title") ?? ""
    subtitle = r.string(t, "subtitle") ?? ""
    chord = r.chord(t, "chord")
    enabled = r.bool(t, "enabled") ?? true
    muted = r.bool(t, "muted") ?? false
    image = r.image(t, "image")
    tint = r.bool(t, "tint") ?? false
    section = r.string(t, "section")
  }
}

extension BottomBar {
  init(_ r: LuaReader, _ t: Int32) {
    r.each(t, "right") { e in
      right.append(Entry(label: r.string(e, "label") ?? "", chord: r.chord(e, "chord"),
        action: r.string(e, "action"), fit: r.bool(e, "fit") ?? false))
    }
    r.each(t, "keys") { e in
      keys.append(Entry(label: r.string(e, "label") ?? "", chord: r.chord(e, "chord"),
        section: r.string(e, "section"), lead: r.chord(e, "lead")))
    }
    keysChord = r.chord(t, "keysChord")
    keysImage = r.image(t, "keysImage")
    keysTint = r.bool(t, "keysTint") ?? false
    title = r.string(t, "title")
    panelOpen = r.bool(t, "panelOpen") ?? false
    panelTitle = r.string(t, "panelTitle")
  }
}

extension ViewState {
  init(_ r: LuaReader, _ t: Int32) {
    highlight = r.integer(t, "highlight")
    scrollTop = r.number(t, "scrollTop").map { CGFloat($0) }
    placeholder = r.string(t, "placeholder") ?? ""
    bare = r.bool(t, "bare") ?? false
    r.each(t, "slots") { e in slots.append(r.integer(at: e) ?? 0) }
    empty = r.bool(t, "empty") ?? false
    emptyText = r.string(t, "emptyText") ?? ""
    lineBreak = ViewState.lineBreak(r.string(t, "lineBreak"))
    bottomBar = r.field(t, "bottomBar") { r.isTable($0) ? BottomBar(r, $0) : nil }
    infoOpen = r.bool(t, "infoOpen") ?? false
    if r.field(t, "actions", { r.isTable($0) }) == true {
      var rows: [Row] = []
      r.each(t, "actions") { e in rows.append(Row(r, e)) }
      actions = rows
    }
    actionsHighlight = r.integer(t, "actionsHighlight") ?? 0
  }
}

// Reads one pane's element list off the Lua stack. Colours, pictures and styled text go through
// the helpers Hammerspoon's own modules register with LuaSkin, the ones hs.canvas converts with,
// so a colour written any way hs.drawing.color reads draws the same here.
struct PaneReader {
  let r: LuaReader
  let skin: LuaSkin
  let size: NSSize

  // Every attribute this file draws, and the mouse tracking ones it may ignore.
  private static let known: Set<String> = [
    "type", "action", "frame", "fillColor", "strokeColor", "strokeWidth", "strokeCapStyle",
    "strokeJoinStyle", "roundedRectRadii", "coordinates", "closed", "image", "imageAlpha",
    "imageAlignment", "imageScaling", "text", "textFont", "textSize", "textColor",
    "textAlignment", "textLineBreak",
    "id", "trackMouseUp", "trackMouseDown", "trackMouseEnterExit", "trackMouseMove",
    "trackMouseByBounds",
  ]

  // The elements in the array at index, the ones a click can land on, and what could not be
  // drawn, each named once.
  func elements(at index: Int32) -> ([PaneElement], [PaneTarget], [String]) {
    var out: [PaneElement] = []
    var targets: [PaneTarget] = []
    var unsupported: [String] = []
    guard r.isTable(index) else { return (out, targets, unsupported) }
    let count = lua_rawlen(r.L, index)
    guard count > 0 else { return (out, targets, unsupported) }
    for i in 1...count {
      _ = lua_rawgeti(r.L, index, lua_Integer(i))
      let t = r.absolute(-1)
      if r.isTable(t) {
        switch element(t) {
        case .success(let element):
          if let element {
            out.append(element)
            if let target = target(t, element) { targets.append(target) }
          }
        case .failure(let why): if !unsupported.contains(why.name) { unsupported.append(why.name) }
        }
      }
      olm_pop(r.L, 1)
    }
    return (out, targets, unsupported)
  }

  // The element's click target, when it carries an id and asks for the mouse up. A shape answers
  // in its own path, text and an image in their frame, and any of them in its bounds when
  // trackMouseByBounds says so, as hs.canvas hit tests.
  private func target(_ t: Int32, _ element: PaneElement) -> PaneTarget? {
    guard r.bool(t, "trackMouseUp") == true, let id = r.string(t, "id") else { return nil }
    let byBounds = r.bool(t, "trackMouseByBounds") == true
    switch element {
    case .shape(let path, _, _, let clip):
      if clip { return nil }
      return PaneTarget(id: id, area: byBounds ? NSBezierPath(rect: path.bounds) : path)
    case .image, .text:
      return PaneTarget(id: id, area: NSBezierPath(rect: frame(t)))
    case .resetClip:
      return nil
    }
  }

  struct Unsupported: Error { let name: String }

  // One element, nil for one that draws nothing by design, a skip or an empty path, and a
  // failure naming what is not supported.
  private func element(_ t: Int32) -> Result<PaneElement?, Unsupported> {
    let type = r.string(t, "type") ?? "nil"
    if let key = unknownKey(t) { return .failure(Unsupported(name: type + "." + key)) }
    // A skipped element draws nothing whatever its type, the canvas rule.
    if r.string(t, "action") == "skip" { return .success(nil) }
    switch type {
    case "rectangle", "segments": return shape(t, type)
    case "image": return image(t)
    case "text": return text(t)
    case "resetClip": return .success(.resetClip)
    default: return .failure(Unsupported(name: type))
    }
  }

  // The first attribute of the element this file does not draw, if any.
  private func unknownKey(_ t: Int32) -> String? {
    var found: String?
    lua_pushnil(r.L)
    while lua_next(r.L, t) != 0 {
      if found == nil {
        if let key = r.string(at: -2) {
          if !Self.known.contains(key) { found = key }
        } else {
          found = "?"
        }
      }
      olm_pop(r.L, 1)
    }
    return found
  }

  // MARK: Shapes

  private func shape(_ t: Int32, _ type: String) -> Result<PaneElement?, Unsupported> {
    let action = r.string(t, "action") ?? "strokeAndFill"
    let fills = action == "fill" || action == "strokeAndFill"
    let strokes = action == "stroke" || action == "strokeAndFill"
    let clips = action == "clip"
    guard fills || strokes || clips else { return .failure(Unsupported(name: type + ":" + action)) }
    let path: NSBezierPath
    if type == "rectangle" {
      let radii = r.field(t, "roundedRectRadii") { i -> NSSize? in
        guard r.isTable(i) else { return nil }
        return NSSize(width: r.number(i, "xRadius") ?? 0, height: r.number(i, "yRadius") ?? 0)
      } ?? .zero
      path = NSBezierPath(roundedRect: frame(t), xRadius: radii.width, yRadius: radii.height)
    } else {
      guard let segments = segmentsPath(t) else { return .success(nil) }
      path = segments
    }
    path.lineWidth = r.number(t, "strokeWidth") ?? 1
    switch r.string(t, "strokeCapStyle") {
    case "round": path.lineCapStyle = .round
    case "square": path.lineCapStyle = .square
    default: path.lineCapStyle = .butt
    }
    switch r.string(t, "strokeJoinStyle") {
    case "round": path.lineJoinStyle = .round
    case "bevel": path.lineJoinStyle = .bevel
    default: path.lineJoinStyle = .miter
    }
    // hs.canvas's own defaults, red to fill and black to stroke.
    let fill = fills ? (color(t, "fillColor") ?? NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)) : nil
    let stroke = strokes ? (color(t, "strokeColor") ?? NSColor(white: 0, alpha: 1)) : nil
    return .success(.shape(path: path, fill: fill, stroke: stroke, clip: clips))
  }

  // A line through every coordinate, a curve where a point carries both control points, closed
  // back to the start when closed is true. Nil for no points.
  private func segmentsPath(_ t: Int32) -> NSBezierPath? {
    let path = NSBezierPath()
    var first = true
    r.each(t, "coordinates") { p in
      guard r.isTable(p) else { return }
      let point = NSPoint(x: length(p, "x", of: size.width) ?? 0, y: length(p, "y", of: size.height) ?? 0)
      if first {
        path.move(to: point)
        first = false
      } else if let c1x = length(p, "c1x", of: size.width), let c1y = length(p, "c1y", of: size.height),
        let c2x = length(p, "c2x", of: size.width), let c2y = length(p, "c2y", of: size.height) {
        path.curve(to: point, controlPoint1: NSPoint(x: c1x, y: c1y), controlPoint2: NSPoint(x: c2x, y: c2y))
      } else {
        path.line(to: point)
      }
    }
    if first { return nil }
    if r.bool(t, "closed") == true { path.close() }
    return path
  }

  // MARK: Images

  private func image(_ t: Int32) -> Result<PaneElement?, Unsupported> {
    guard let image = r.image(t, "image") else { return .success(nil) }
    let scaling = r.string(t, "imageScaling") ?? "scaleProportionally"
    let box = frame(t)
    let natural = image.size
    var drawn = natural
    switch scaling {
    case "scaleProportionally":
      if natural.width > 0, natural.height > 0 {
        let scale = min(box.width / natural.width, box.height / natural.height)
        drawn = NSSize(width: natural.width * scale, height: natural.height * scale)
      }
    case "none":
      break
    default:
      return .failure(Unsupported(name: "image:" + scaling))
    }
    // How far along each axis the spare room goes before the picture, y measured down.
    let along: (CGFloat, CGFloat)
    switch r.string(t, "imageAlignment") ?? "center" {
    case "topLeft": along = (0, 0)
    case "top": along = (0.5, 0)
    case "topRight": along = (1, 0)
    case "left": along = (0, 0.5)
    case "right": along = (1, 0.5)
    case "bottomLeft": along = (0, 1)
    case "bottom": along = (0.5, 1)
    case "bottomRight": along = (1, 1)
    default: along = (0.5, 0.5)
    }
    let rect = NSRect(x: box.minX + (box.width - drawn.width) * along.0,
      y: box.minY + (box.height - drawn.height) * along.1, width: drawn.width, height: drawn.height)
    // hs.canvas draws a template image at half alpha unless the element says otherwise.
    let alpha = r.number(t, "imageAlpha") ?? (image.isTemplate ? 0.5 : 1)
    return .success(.image(image, rect, alpha))
  }

  // MARK: Text

  private func text(_ t: Int32) -> Result<PaneElement?, Unsupported> {
    let L = r.L
    let value: NSAttributedString? = r.field(t, "text") { i -> NSAttributedString? in
      if lua_type(L, i) == LUA_TUSERDATA {
        return skin.luaObject(at: i, toClass: "NSAttributedString") as? NSAttributedString
      }
      guard let string = r.string(at: i) else { return nil }
      return plainText(t, string)
    }
    guard let value else { return .failure(Unsupported(name: "text.text")) }
    return .success(.text(value, frame(t)))
  }

  // A plain string with the text attributes hs.canvas reads for one, and its defaults.
  private func plainText(_ t: Int32, _ string: String) -> NSAttributedString {
    let size = r.number(t, "textSize") ?? 27
    let font = r.string(t, "textFont").flatMap { NSFont(name: $0, size: size) } ?? NSFont.systemFont(ofSize: size)
    let paragraph = NSMutableParagraphStyle()
    switch r.string(t, "textAlignment") {
    case "left": paragraph.alignment = .left
    case "right": paragraph.alignment = .right
    case "center": paragraph.alignment = .center
    case "justified": paragraph.alignment = .justified
    default: paragraph.alignment = .natural
    }
    switch r.string(t, "textLineBreak") {
    case "charWrap": paragraph.lineBreakMode = .byCharWrapping
    case "clip": paragraph.lineBreakMode = .byClipping
    case "truncateHead": paragraph.lineBreakMode = .byTruncatingHead
    case "truncateTail": paragraph.lineBreakMode = .byTruncatingTail
    case "truncateMiddle": paragraph.lineBreakMode = .byTruncatingMiddle
    default: paragraph.lineBreakMode = .byWordWrapping
    }
    return NSAttributedString(string: string, attributes: [
      .font: font,
      .foregroundColor: color(t, "textColor") ?? NSColor(white: 1, alpha: 1),
      .paragraphStyle: paragraph,
    ])
  }

  // MARK: Values

  // A colour through the helper hs.drawing.color registers, and the plain red, green and blue
  // table when that helper answers nothing.
  private func color(_ t: Int32, _ name: String) -> NSColor? {
    let converted = r.field(t, name) { i -> NSColor? in
      guard r.isTable(i) else { return nil }
      return skin.luaObject(at: i, toClass: "NSColor") as? NSColor
    }
    return converted ?? r.color(t, name)
  }

  // A length as a number of points, or as a percentage string of the pane's size, as hs.canvas
  // reads one.
  private func length(_ t: Int32, _ name: String, of total: CGFloat) -> CGFloat? {
    r.field(t, name) { i -> CGFloat? in
      if let number = r.number(at: i) { return CGFloat(number) }
      if let text = r.string(at: i), text.hasSuffix("%"), let percent = Double(text.dropLast()) {
        return CGFloat(percent) / 100 * total
      }
      return nil
    }
  }

  // The element's frame, every missing part the whole pane, hs.canvas's default.
  private func frame(_ t: Int32) -> NSRect {
    r.field(t, "frame") { i -> NSRect? in
      guard r.isTable(i) else { return nil }
      return NSRect(x: length(i, "x", of: size.width) ?? 0, y: length(i, "y", of: size.height) ?? 0,
        width: length(i, "w", of: size.width) ?? size.width, height: length(i, "h", of: size.height) ?? size.height)
    } ?? NSRect(origin: .zero, size: size)
  }
}
