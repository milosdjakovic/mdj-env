// The docked pane's native view. lib/dockedpane.lua reduces every pane, described through the UI
// kit or painted directly, to a list of hs.canvas element tables, and this file draws that list
// the way hs.canvas documents it, on glass. It holds no pane rule. The lazy build, the inner
// rect, the scroll and its clamp, the thumb and the empty state all stay in Lua, and this file
// only places, draws, shows and hides.
//
// WHERE IT IS DRAWN. The pane is made by a plugin, which knows no chooser panel, so it never
// names one. Each time it is placed or shown it asks the seam in Entry.swift for the visible
// chooser panel whose reported companion rect is its own rect, and when there is one its view
// goes into that panel's pane region, in the chooser's own window, on the same one shape of glass
// as the list, so the two are one surface and appear and vanish together. When no visible
// swift chooser owns the rect it falls back to a window of its own, a nonactivating panel that
// is never key and never main, at the level the canvas pane floats at, with no animation. A
// click on that window still reaches the chooser panel's local monitor as a press on another
// Hammerspoon window, which the Lua view finds inside the companion rect and answers by keeping
// the list up, and a scroll over either is claimed by the Lua view's own tap first.
//
// THE SURFACE IS GLASS. The surface elements the canvas backend paints first are a filled and a
// stroked rounded rectangle, and the fill drawn over glass would hide the glass, so the Lua half
// hands only the content here, with the surface's corner radius, which the pane's own window takes.
// In a chooser's window the pane is part of that window's one shape and its radius.
//
// WHAT IS DRAWN. rectangle and segments, filled, stroked, both, or added to the clip, with
// fillColor, strokeColor, strokeWidth, strokeCapStyle, strokeJoinStyle, roundedRectRadii,
// coordinates with optional control points, and closed. image, with imageAlpha, imageAlignment
// and imageScaling as scaleProportionally or none. text, a string with textFont, textSize,
// textColor, textAlignment and textLineBreak, or an hs.styledtext drawn as it is. resetClip.
// A clip adds to the clip region until a resetClip clears all of it, the canvas rule the kit's
// layout is written against. An element of another type, with another action or scaling, or
// with any attribute not named here is not drawn at all, and is reported back so Lua can say so
// once, rather than drawn half right. The mouse tracking attributes are the one exception, since
// no pane listens for a click and the canvas ignores them in the same case.

import Cocoa

// Never key and never main, so the keyboard stays with the chooser panel.
final class PaneWindow: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

// One element, already read off its Lua table and resolved to points.
enum PaneElement {
  case shape(path: NSBezierPath, fill: NSColor?, stroke: NSColor?, clip: Bool)
  case image(NSImage, NSRect, CGFloat)
  case text(NSAttributedString, NSRect)
  case resetClip
}

// The canvas view, flipped so the elements' own coordinates, origin top left, are its own.
final class PaneCanvas: NSView {
  var elements: [PaneElement] = []

  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current else { return }
    context.saveGraphicsState()
    for element in elements {
      switch element {
      case .shape(let path, let fill, let stroke, let clip):
        if clip {
          path.addClip()
          continue
        }
        if let fill {
          fill.setFill()
          path.fill()
        }
        if let stroke {
          stroke.setStroke()
          path.stroke()
        }
      case .image(let image, let rect, let alpha):
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha,
          respectFlipped: true, hints: nil)
      case .text(let text, let rect):
        text.draw(in: rect)
      case .resetClip:
        context.restoreGraphicsState()
        context.saveGraphicsState()
      }
    }
    context.restoreGraphicsState()
  }
}

final class PanePanel {
  // The seam's question, the visible chooser panel whose companion is this rect, if any.
  typealias FindHost = (NSRect) -> ChooserPanel?

  private let window: PaneWindow
  private let canvas = PaneCanvas()
  private let surface: Surface
  private let findHost: FindHost
  private weak var host: ChooserPanel?
  private var rect = NSRect.zero
  private var radius: CGFloat = 0
  private var shown = false

  init(findHost: @escaping FindHost) {
    self.findHost = findHost
    window = PaneWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
      styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered, defer: true)
    surface = Surface(holding: canvas)
    window.isFloatingPanel = true
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.hidesOnDeactivate = false
    window.isReleasedWhenClosed = false
    window.becomesKeyOnlyIfNeeded = true
    window.animationBehavior = .none
    window.contentView = surface.view
  }

  // The size percentages in a frame are taken of, the pane's own.
  var size: NSSize { rect.size }

  func place(_ next: NSRect) {
    rect = next
    window.setFrame(ScreenSpace.cocoaRect(next), display: window.isVisible && host == nil)
    canvas.frame = NSRect(origin: .zero, size: next.size)
    rehome()
    canvas.needsDisplay = true
  }

  func draw(_ elements: [PaneElement], radius next: CGFloat) {
    radius = next
    applyRadius()
    canvas.elements = elements
    canvas.needsDisplay = true
  }

  func show() {
    shown = true
    rehome()
    present()
  }

  func hide() {
    shown = false
    host?.hidePane(canvas)
    window.orderOut(nil)
  }

  // Out of whichever window holds it, for good, on destroy and at a reload.
  func close() {
    hide()
    host?.releasePane(canvas)
    host = nil
  }

  // Moves the view to the chooser panel that owns this rect now, or to the own window when none
  // does, and leaves it where it is when that has not changed.
  private func rehome() {
    let next = findHost(rect)
    if next !== host {
      host?.releasePane(canvas)
      host = next
      if let next {
        window.orderOut(nil)
        next.adoptPane(canvas)
      } else {
        surface.hold(canvas)
      }
      applyRadius()
      if shown { present() }
    }
  }

  private func applyRadius() {
    // In a chooser's window the pane is part of that window's one shape and takes its radius.
    if host == nil { surface.setCornerRadius(radius) }
  }

  // In the chooser's window the pane's region is shown. In its own window the window is ordered
  // front without being made key, and only when it is not already up, since the pane asks for a
  // show on every paint and a window ordered front on every scroll would climb over anything
  // shown above it since.
  private func present() {
    if let host {
      host.showPane(canvas)
    } else if !window.isVisible {
      window.orderFrontRegardless()
    }
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

  // The elements in the array at index, and what could not be drawn, each named once.
  func elements(at index: Int32) -> ([PaneElement], [String]) {
    var out: [PaneElement] = []
    var unsupported: [String] = []
    guard r.isTable(index) else { return (out, unsupported) }
    let count = lua_rawlen(r.L, index)
    guard count > 0 else { return (out, unsupported) }
    for i in 1...count {
      _ = lua_rawgeti(r.L, index, lua_Integer(i))
      let t = r.absolute(-1)
      if r.isTable(t) {
        switch element(t) {
        case .success(let element): if let element { out.append(element) }
        case .failure(let why): if !unsupported.contains(why.name) { unsupported.append(why.name) }
        }
      }
      olm_pop(r.L, 1)
    }
    return (out, unsupported)
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
