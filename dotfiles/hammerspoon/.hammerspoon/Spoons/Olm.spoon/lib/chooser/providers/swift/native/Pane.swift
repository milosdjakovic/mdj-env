// The docked pane's native view. lib/dockedpane.lua reduces every pane, described through the UI
// kit or painted directly, to a list of hs.canvas element tables, and this file draws that list
// the way hs.canvas documents it, on glass. It holds no pane rule. The lazy build, the inner
// rect, the layout and the empty state all stay in Lua, and this file only places, draws, scrolls,
// shows and hides.
//
// IT SCROLLS NATIVELY. The drawn elements live in a flipped document view inside an NSScrollView,
// and Lua hands them laid out at the content's full height, so a scroll over the pane is AppKit's
// own, with momentum and at display rate, and Lua repaints only when the content changes. A
// redraw keeps where the view is, clamped to the new height, unless Lua says the content changed,
// and then it goes back to the top. No scroller shows unless the pane asked for a thumb, and then
// it is the overlay style. scrollBy moves the view for a key that pages the pane. Only the
// elements that reach the area being drawn are drawn, the clips excepted, so a tall pane costs a
// scroll only what comes into view.
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
// the list up. A scroll over the pane in a chooser's window is left to the scroll view, the Lua
// view's tap passing it on, and one over the pane's own window is claimed by that tap and comes
// back as scrollBy, see View colon _onScroll in view.lua.
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
//
// IT DRAWS A CANVASPANEL TOO. lib/panel.lua hands the same element lists to the same backend, and
// a PaneConfig with panel set makes the window a CanvasPanel's. It is never drawn into a chooser
// panel's window, whatever its rect, it stands at the level the panel asks for, popUpMenu unless it
// says otherwise, and it is ordered front on every show, as hs.canvas orders a canvas front on
// every show, so a sheet shown over a list rises above it as before. It is click through unless the
// panel's content takes a click, and then a press on it is answered without the window becoming
// key or main and without activating Hammerspoon, since the panel is nonactivating. The click is
// hit tested here against the elements built with id and trackMouseUp, the topmost first, by the
// element's own shape or by its bounds when trackMouseByBounds says so, and the id of the one
// under the pointer, or _canvas_ when none is, goes to the panel's click handler on the mouse up.

import Cocoa

// What the window is for, a docked pane by default and a CanvasPanel when panel is set. onClick
// is told the id of a clicked element, and is only ever set for a panel.
struct PaneConfig {
  var panel = false
  var level: NSWindow.Level = .floating
  var onClick: ((String) -> Void)?
}

// One element a click can land on, its id and the area it answers in, in the canvas's own
// coordinates, origin top left.
struct PaneTarget {
  let id: String
  let area: NSBezierPath
}

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

// The diagnostic's answer, see PanePanel.debug.
struct PaneDebug {
  let hosting: String
  let windowVisible: Bool
  let hidden: Bool
  let scroll: NSRect?
  let superview: NSRect?
  let autoresizes: Bool
  let document: NSRect
  let documentFlipped: Bool
  let clipBounds: NSRect
  let elements: Int
  let panel: Bool
  let level: Int
  let clickThrough: Bool
  let targets: Int
}

// What a draw says about the scroll, the content's full height, whether the view goes back to
// the top and whether it shows an overlay scroller.
struct PaneScroll {
  let height: CGFloat
  let reset: Bool
  let thumb: Bool
}

// The canvas view, flipped so the elements' own coordinates, origin top left, are its own. It is
// the scroll view's document view, as tall as the content.
final class PaneCanvas: NSView {
  var elements: [PaneElement] = []
  var targets: [PaneTarget] = []
  var onClick: ((String) -> Void)?

  override var isFlipped: Bool { true }

  // A press on a window that is not key reaches the view at once, as a press on a canvas does.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { onClick != nil }

  // Taken here so the mouse up comes back to this view, and answered only on the mouse up, the
  // one event lib/panel.lua's content listens for.
  override func mouseDown(with event: NSEvent) {
    if onClick == nil { super.mouseDown(with: event) }
  }

  override func mouseUp(with event: NSEvent) {
    guard let onClick else {
      super.mouseUp(with: event)
      return
    }
    onClick(hit(convert(event.locationInWindow, from: nil)))
  }

  // The id of the topmost target under point, or _canvas_, the name hs.canvas reports a mouse up
  // on the canvas itself by.
  func hit(_ point: NSPoint) -> String {
    for target in targets.reversed() where target.area.contains(point) { return target.id }
    return "_canvas_"
  }

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
        let reach = path.bounds.insetBy(dx: -path.lineWidth, dy: -path.lineWidth)
        if !reach.intersects(dirtyRect) { continue }
        if let fill {
          fill.setFill()
          path.fill()
        }
        if let stroke {
          stroke.setStroke()
          path.stroke()
        }
      case .image(let image, let rect, let alpha):
        if !rect.intersects(dirtyRect) { continue }
        // On whole pixels and with Core Graphics' best interpolation, see Crisp in List.swift.
        context.imageInterpolation = .high
        image.draw(in: Crisp.align(rect, in: self), from: .zero, operation: .sourceOver, fraction: alpha,
          respectFlipped: true, hints: nil)
      case .text(let text, let rect):
        if !rect.intersects(dirtyRect) { continue }
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
  private let scroller = NSScrollView()
  // The content's full height, never less than the pane's own.
  private var contentHeight: CGFloat = 0
  private let surface: Surface
  private let findHost: FindHost
  private weak var host: ChooserPanel?
  private var rect = NSRect.zero
  private var radius: CGFloat = 0
  private var shown = false

  private let config: PaneConfig

  init(findHost: @escaping FindHost, config: PaneConfig = PaneConfig()) {
    self.findHost = findHost
    self.config = config
    window = PaneWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
      styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered, defer: true)
    scroller.drawsBackground = false
    scroller.contentView.drawsBackground = false
    // The chooser's window is titled, see THE OUTLINE in Panel.swift, and a scroll view under a
    // title bar insets its content by the bar's height on its own, which would push every row down.
    scroller.automaticallyAdjustsContentInsets = false
    scroller.borderType = .noBorder
    scroller.hasHorizontalScroller = false
    scroller.hasVerticalScroller = false
    scroller.scrollerStyle = .overlay
    scroller.autohidesScrollers = true
    scroller.horizontalScrollElasticity = .none
    scroller.verticalScrollElasticity = .none
    scroller.documentView = canvas
    surface = Surface(holding: scroller)
    window.isFloatingPanel = true
    window.level = config.level
    // Click through unless something here takes a click, the canvas rule for a canvas with no
    // mouse callback. A pane's window keeps taking the press, which the chooser's local monitor
    // reads as a press inside the companion.
    window.ignoresMouseEvents = config.panel && config.onClick == nil
    canvas.onClick = config.onClick
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

  // The scroll view that holds the drawn elements, the view that moves between hosts.
  var hostedView: NSScrollView { scroller }

  // The view the elements are drawn in, for the harness to render and to click.
  var drawnView: NSView { canvas }

  // Where the pane is and what it holds, for the read only diagnostic paneDebug in Entry.swift.
  // Every rect is in its window's coordinates, AppKit's, y measured up.
  var debug: PaneDebug {
    let hosting = host != nil ? "chooser" : (scroller.superview == nil ? "none" : "own")
    func inWindow(_ view: NSView?) -> NSRect? {
      guard let view, view.window != nil else { return nil }
      return view.convert(view.bounds, to: nil)
    }
    return PaneDebug(hosting: hosting, windowVisible: scroller.window?.isVisible ?? false,
      hidden: scroller.isHiddenOrHasHiddenAncestor, scroll: inWindow(scroller),
      superview: inWindow(scroller.superview), autoresizes: scroller.translatesAutoresizingMaskIntoConstraints,
      document: canvas.frame, documentFlipped: canvas.isFlipped, clipBounds: scroller.contentView.bounds,
      elements: canvas.elements.count, panel: config.panel, level: window.level.rawValue,
      clickThrough: window.ignoresMouseEvents, targets: canvas.targets.count)
  }

  func place(_ next: NSRect) {
    rect = next
    window.setFrame(ScreenSpace.cocoaRect(next), display: window.isVisible && host == nil)
    scroller.frame = NSRect(origin: .zero, size: next.size)
    layoutDocument()
    rehome()
    canvas.needsDisplay = true
  }

  func draw(_ elements: [PaneElement], targets: [PaneTarget] = [], radius next: CGFloat, scroll: PaneScroll) {
    radius = next
    applyRadius()
    contentHeight = scroll.height
    scroller.hasVerticalScroller = scroll.thumb
    canvas.elements = elements
    canvas.targets = targets
    layoutDocument()
    if scroll.reset { scrollTo(0) }
    canvas.needsDisplay = true
  }

  // Further down by points, clamped to the content, answering whether the view moved.
  func scrollBy(_ points: CGFloat) -> Bool {
    let next = min(max(0, offset + points), maxOffset)
    guard abs(next - offset) >= 0.5 else { return false }
    scrollTo(next)
    if scroller.hasVerticalScroller { scroller.flashScrollers() }
    return true
  }

  private var offset: CGFloat { scroller.contentView.bounds.origin.y }
  private var maxOffset: CGFloat { max(0, canvas.frame.height - rect.height) }

  private func scrollTo(_ y: CGFloat) {
    let clip = scroller.contentView
    clip.scroll(to: NSPoint(x: 0, y: y))
    scroller.reflectScrolledClipView(clip)
  }

  // The document as wide as the pane and as tall as the content, the view kept where it was
  // unless the content got shorter than that, and the bounce at the ends only when there is
  // something to scroll, so a pane that fits sits still under a scroll.
  private func layoutDocument() {
    let height = max(contentHeight, rect.height)
    canvas.frame = NSRect(x: 0, y: 0, width: rect.width, height: height)
    scroller.verticalScrollElasticity = height > rect.height + 0.5 ? .automatic : .none
    if offset > maxOffset { scrollTo(maxOffset) }
  }

  func show() {
    shown = true
    rehome()
    present()
  }

  // Whether it can be seen, in the chooser's window or in its own.
  var isVisible: Bool {
    guard shown else { return false }
    if let host { return host.isVisible }
    return window.isVisible
  }

  // The id a click at point in the canvas's coordinates reports, for the harness.
  func hit(_ point: NSPoint) -> String { canvas.hit(point) }

  func hide() {
    shown = false
    host?.hidePane(scroller)
    window.orderOut(nil)
  }

  // Out of whichever window holds it, for good, on destroy and at a reload.
  func close() {
    hide()
    host?.releasePane(scroller)
    host = nil
  }

  // Moves the view to the chooser panel that owns this rect now, or to the own window when none
  // does, and leaves it where it is when that has not changed.
  private func rehome() {
    // A panel is never drawn into a chooser's window, even on a rect that matches a companion.
    let next = config.panel ? nil : findHost(rect)
    if next !== host {
      host?.releasePane(scroller)
      host = next
      if let next {
        window.orderOut(nil)
        surface.release(scroller)
        next.adoptPane(scroller)
      } else {
        surface.hold(scroller)
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
  // show on every paint and a window ordered front on every paint would climb over anything
  // shown above it since. A panel's window is ordered front on every show, which is what
  // hs.canvas does on every show and what lib/panel.lua's overlays were always stacked by.
  private func present() {
    if let host {
      host.showPane(scroller)
    } else if config.panel || !window.isVisible {
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
