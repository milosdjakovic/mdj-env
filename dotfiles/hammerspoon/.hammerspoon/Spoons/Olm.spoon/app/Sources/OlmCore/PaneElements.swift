// What a hosted list's pane drew in Lua, read into what the pane view draws, step 3.3d of
// docs/PLAN-STANDALONE.md, docs/PROTOCOL-BRIDGE.md The preview pane. The elements are hs.canvas's,
// as lib/previewpane.lua hands any backend, crossed as JSON by host/bridge/pane.lua, and this is
// PaneReader in lib/chooser/providers/swift/native/Lua.swift reading the same attributes off JSON in
// place of the Lua stack: a text is a Text, a picture a Picture, a colour its red, green, blue and
// alpha. An element it cannot draw is left out and named in the second answer.
//
// Main thread only, since it builds AppKit paths, strings and images.

import AppKit
@preconcurrency @testable import OlmChooser

@MainActor
public enum PaneElements {
  /// What a drawing reads as, each element's kind in order and the kinds left out, for
  /// olm-bridge-check, which cannot see the pane view's own types.
  public static func kinds(_ data: Data, w: Double, h: Double) -> (kinds: [String], unsupported: [String]) {
    let (elements, unsupported) = read(data, size: NSSize(width: w, height: h))
    let kinds = elements.map { e -> String in
      switch e {
      case .shape(let path, let fill, let stroke, let clip):
        if clip { return "clip" }
        return (fill != nil ? "fill" : "") + (stroke != nil ? "stroke" : "") + ":\(path.elementCount)"
      case .image(_, let rect, _): return "image:\(Int(rect.width))x\(Int(rect.height))"
      case .text(let s, _): return "text:" + s.string
      case .resetClip: return "resetClip"
      }
    }
    return (kinds, unsupported)
  }

  // A picture by its path, read once, since the Lua side names the same file for the same picture.
  private static var pictures: [String: NSImage] = [:]

  /// The elements of a drawing, in a pane of size, and the kinds it could not draw.
  static func read(_ data: Data, size: NSSize) -> ([PaneElement], [String]) {
    guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return ([], ["elements"]) }
    var out: [PaneElement] = []
    var unsupported: [String] = []
    for case let t as [String: Any] in list {
      switch element(t, size: size) {
      case .success(let e): if let e { out.append(e) }
      case .failure(let why): if !unsupported.contains(why.name) { unsupported.append(why.name) }
      }
    }
    return (out, unsupported)
  }

  struct Unsupported: Error { let name: String }

  private static func element(_ t: [String: Any], size: NSSize) -> Result<PaneElement?, Unsupported> {
    let type = t["type"] as? String ?? "nil"
    if t["action"] as? String == "skip" { return .success(nil) }
    switch type {
    case "rectangle", "segments": return shape(t, type, size: size)
    case "image": return image(t, size: size)
    case "text": return text(t, size: size)
    case "resetClip": return .success(.resetClip)
    default: return .failure(Unsupported(name: type))
    }
  }

  // MARK: Values

  private static func number(_ v: Any?) -> CGFloat? {
    if let n = v as? NSNumber { return CGFloat(truncating: n) }
    return nil
  }

  // A length in points, or a percent string of the pane's own size along that axis, as hs.canvas
  // reads one.
  private static func length(_ v: Any?, of whole: CGFloat) -> CGFloat? {
    if let n = number(v) { return n }
    if let s = v as? String, s.hasSuffix("%"), let p = Double(s.dropLast()) { return CGFloat(p) / 100 * whole }
    return nil
  }

  private static func frame(_ t: [String: Any], size: NSSize) -> NSRect {
    let f = t["frame"] as? [String: Any] ?? [:]
    return NSRect(x: length(f["x"], of: size.width) ?? 0, y: length(f["y"], of: size.height) ?? 0,
      width: length(f["w"], of: size.width) ?? size.width, height: length(f["h"], of: size.height) ?? size.height)
  }

  private static func color(_ v: Any?) -> NSColor? {
    guard let c = v as? [String: Any] else { return nil }
    return NSColor(srgbRed: number(c["red"]) ?? 0, green: number(c["green"]) ?? 0, blue: number(c["blue"]) ?? 0,
      alpha: number(c["alpha"]) ?? 1)
  }

  // MARK: Shapes

  private static func shape(_ t: [String: Any], _ type: String, size: NSSize) -> Result<PaneElement?, Unsupported> {
    let action = t["action"] as? String ?? "strokeAndFill"
    let fills = action == "fill" || action == "strokeAndFill"
    let strokes = action == "stroke" || action == "strokeAndFill"
    let clips = action == "clip"
    guard fills || strokes || clips else { return .failure(Unsupported(name: type + ":" + action)) }
    let path: NSBezierPath
    if type == "rectangle" {
      let radii = t["roundedRectRadii"] as? [String: Any]
      path = NSBezierPath(roundedRect: frame(t, size: size), xRadius: number(radii?["xRadius"]) ?? 0,
        yRadius: number(radii?["yRadius"]) ?? 0)
    } else {
      guard let segments = segmentsPath(t, size: size) else { return .success(nil) }
      path = segments
    }
    path.lineWidth = number(t["strokeWidth"]) ?? 1
    switch t["strokeCapStyle"] as? String {
    case "round": path.lineCapStyle = .round
    case "square": path.lineCapStyle = .square
    default: path.lineCapStyle = .butt
    }
    switch t["strokeJoinStyle"] as? String {
    case "round": path.lineJoinStyle = .round
    case "bevel": path.lineJoinStyle = .bevel
    default: path.lineJoinStyle = .miter
    }
    // hs.canvas's own defaults, red to fill and black to stroke.
    let fill = fills ? (color(t["fillColor"]) ?? NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)) : nil
    let stroke = strokes ? (color(t["strokeColor"]) ?? NSColor(white: 0, alpha: 1)) : nil
    return .success(.shape(path: path, fill: fill, stroke: stroke, clip: clips))
  }

  private static func segmentsPath(_ t: [String: Any], size: NSSize) -> NSBezierPath? {
    let path = NSBezierPath()
    var first = true
    for case let p as [String: Any] in t["coordinates"] as? [Any] ?? [] {
      let point = NSPoint(x: length(p["x"], of: size.width) ?? 0, y: length(p["y"], of: size.height) ?? 0)
      if first {
        path.move(to: point)
        first = false
      } else if let c1x = length(p["c1x"], of: size.width), let c1y = length(p["c1y"], of: size.height),
        let c2x = length(p["c2x"], of: size.width), let c2y = length(p["c2y"], of: size.height) {
        path.curve(to: point, controlPoint1: NSPoint(x: c1x, y: c1y), controlPoint2: NSPoint(x: c2x, y: c2y))
      } else {
        path.line(to: point)
      }
    }
    if first { return nil }
    if t["closed"] as? Bool == true { path.close() }
    return path
  }

  // MARK: Images

  private static func image(_ t: [String: Any], size: NSSize) -> Result<PaneElement?, Unsupported> {
    guard let path = (t["image"] as? [String: Any])?["path"] as? String else { return .success(nil) }
    let picture: NSImage
    if let held = pictures[path] {
      picture = held
    } else {
      guard let read = NSImage(contentsOfFile: path) else { return .failure(Unsupported(name: "image.path")) }
      pictures[path] = read
      picture = read
    }
    let scaling = t["imageScaling"] as? String ?? "scaleProportionally"
    let box = frame(t, size: size)
    let natural = picture.size
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
    let along: (CGFloat, CGFloat)
    switch t["imageAlignment"] as? String ?? "center" {
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
    return .success(.image(picture, rect, number(t["imageAlpha"]) ?? 1))
  }

  // MARK: Text

  private static func paragraph(alignment: String?, lineBreak: String?) -> NSMutableParagraphStyle {
    let p = NSMutableParagraphStyle()
    switch alignment {
    case "left": p.alignment = .left
    case "right": p.alignment = .right
    case "center": p.alignment = .center
    case "justified": p.alignment = .justified
    default: p.alignment = .natural
    }
    switch lineBreak {
    case "charWrap": p.lineBreakMode = .byCharWrapping
    case "clip": p.lineBreakMode = .byClipping
    case "truncateHead": p.lineBreakMode = .byTruncatingHead
    case "truncateTail": p.lineBreakMode = .byTruncatingTail
    case "truncateMiddle": p.lineBreakMode = .byTruncatingMiddle
    default: p.lineBreakMode = .byWordWrapping
    }
    return p
  }

  private static func font(_ name: String?, _ size: CGFloat) -> NSFont {
    name.flatMap { NSFont(name: $0, size: size) } ?? NSFont.systemFont(ofSize: size)
  }

  private static func text(_ t: [String: Any], size: NSSize) -> Result<PaneElement?, Unsupported> {
    if let string = t["text"] as? String {
      // A plain string with the text attributes hs.canvas reads for one, and its defaults.
      let s = number(t["textSize"]) ?? 27
      let value = NSAttributedString(string: string, attributes: [
        .font: font(t["textFont"] as? String, s),
        .foregroundColor: color(t["textColor"]) ?? NSColor(white: 1, alpha: 1),
        .paragraphStyle: paragraph(alignment: t["textAlignment"] as? String, lineBreak: t["textLineBreak"] as? String),
      ])
      return .success(.text(value, frame(t, size: size)))
    }
    guard let styled = t["text"] as? [String: Any], let string = styled["string"] as? String else {
      return .failure(Unsupported(name: "text.text"))
    }
    // A Text, the one run of the kit's styled text, layout.lua's textElement.
    let p = paragraph(alignment: styled["alignment"] as? String, lineBreak: styled["lineBreak"] as? String)
    if let h = number(styled["lineHeight"]) {
      p.minimumLineHeight = h
      p.maximumLineHeight = h
    }
    if styled["tight"] as? Bool == true { p.tighteningFactorForTruncation = 0 }
    let value = NSAttributedString(string: string, attributes: [
      .font: font(styled["font"] as? String, number(styled["size"]) ?? 14),
      .foregroundColor: color(styled["color"]) ?? NSColor(white: 1, alpha: 1),
      .paragraphStyle: p,
    ])
    return .success(.text(value, frame(t, size: size)))
  }
}
