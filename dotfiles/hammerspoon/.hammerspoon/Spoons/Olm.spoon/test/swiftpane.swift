// The swift chooser's native pane, in its real classes, with nothing ever on screen.
//
// Compiled by swiftpane.sh with the library's own sources and run as a program. It pins what the
// Lua cases cannot see, the AppKit view tree a preview pane lives in. A pane docked in a chooser
// panel's region keeps the region's size through a redock at a new size and the layout after it,
// which is the blank pane of 2026-10-28, where the scroll view left the pane's own glass placed
// by constraints with none left and the next layout sized it to nothing. A pane handed back to its
// own window is in that window again, and docked again it fills the region. The scroll view
// shows the top of new content, moves by scrollBy, keeps its place across a redraw and is clamped
// to shorter content, and what is drawn is drawn at the top of the document. An icon drawn by
// Crisp has exactly the pixels its box covers at the scale asked for, and a template stays one.
//
// A CanvasPanel's window, the same class made with a panel config, is never drawn into a chooser's
// window even on the preview pane rect, stands at the level asked for, is click through with no click
// handler and takes the mouse with one, hit tests the topmost element built with an id and
// trackMouseUp and reports _canvas_ off every one, hands a mouse up to its handler, and draws a full
// bleed surface over every pixel at backing scale 2 as at 1.
//
// The list, its table in a window never shown. A query that shortens the list after the highlight
// scrolled it down shows the rows from the top, never under an empty band, the bug of 2026-10-30.
// The arrows move the highlight and the viewport only far enough to show the row above the bar,
// wrapping at both ends, and a burst of moves reaches Lua as one report. A state with no scrollTop
// or highlight leaves the list's own. A fast scroll asks for the icons of the rows on screen first,
// then of the rows its velocity carries it into, a dozen at most per ask and each row once. A cursor
// update ends at the list, so a scroll never sets the cursor again, a third of every frame once.
//
// The fades mask the list and the pane as one, from the list's bottom padding above the bar to the
// window's edge, the list's column from the title bar's bottom edge to where the first row rests,
// the list running on up behind the field and stopping at the title bar, and the pane's column on
// the same curve from its top edge to where its content rests.
//
// Motion's cases are at the end, see their own comment there.
//
// The pane and the panel window are really shown, since that is what moves a pane between windows,
// so every rect they are placed on sits far to the left of any display. On screen they flashed a red
// square over whatever the person was doing on every dry run.
//
// Run it through swiftpane.sh, which suite.sh dry does.

import Cocoa

var failed = false
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
  if ok { print("ok   " + name) } else {
    failed = true
    print("FAIL " + name + (detail.isEmpty ? "" : ", " + detail))
  }
}

_ = NSApplication.shared

// Left of every display, so a window this program shows is never seen.
let away: CGFloat = -20000

let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
let elements: [PaneElement] = [.shape(path: NSBezierPath(rect: NSRect(x: 10, y: 10, width: 50, height: 50)),
  fill: red, stroke: nil, clip: false)]

// A chooser panel placed with its preview pane at rect, its window spanning the list and the pane.
let panel = ChooserPanel(ask: { _, _ in false })
func placePanel(previewPane rect: NSRect) {
  var p = Placement()
  p.canvas = NSRect(x: away, y: rect.minY, width: 480, height: rect.height)
  p.window = NSRect(x: away, y: rect.minY, width: rect.maxX - away, height: rect.height)
  p.listFrame = NSRect(x: 0, y: 0, width: 480, height: rect.height)
  p.paneFrame = NSRect(x: rect.minX - away, y: 0, width: rect.width, height: rect.height)
  p.previewPane = rect
  panel.place(p)
}

// The seam's own comparison, without asking whether the panel is on screen, since none is here.
var owned = true
let pane = PanePanel(findHost: { rect in
  owned && panel.previewPane.map { ScreenSpace.same($0, rect) } == true ? panel : nil
})
let view = pane.hostedView

func settle() {
  for window in NSApp.windows { window.contentView?.layoutSubtreeIfNeeded() }
}
func dock(_ rect: NSRect, height: CGFloat, reset: Bool) {
  pane.place(rect)
  pane.draw(elements, radius: 12, scroll: PaneScroll(height: height, reset: reset, thumb: false))
  pane.show()
  settle()
}

// The seed rect a pane is first docked on before the chooser settles, the settled one, and a
// later one at a new size.
let seed = NSRect(x: away + 500, y: 200, width: 290, height: 380)
let first = NSRect(x: away + 500, y: 200, width: 300, height: 400)
let wider = NSRect(x: away + 500, y: 200, width: 340, height: 420)

dock(seed, height: 1000, reset: true)
check("a pane starts in its own window", pane.debug.hosting == "own")

placePanel(previewPane: first)
dock(first, height: 1000, reset: false)
check("docked, it is in the chooser's region", pane.debug.hosting == "chooser")
check("and fills it after layout, though it was sized for the seed", view.frame.size == first.size,
  "\(view.frame)")

placePanel(previewPane: wider)
dock(wider, height: 1000, reset: false)
check("redocked at a new size, it fills the region after layout", view.frame.size == wider.size,
  "\(view.frame)")
check("placed by its autoresizing mask", view.translatesAutoresizingMaskIntoConstraints)

owned = false
dock(wider, height: 1000, reset: false)
check("handed back, it is in its own window again", pane.debug.hosting == "own", pane.debug.hosting)
check("at the pane's size", view.frame.size == wider.size, "\(view.frame)")

owned = true
dock(wider, height: 1000, reset: true)
check("docked again, it fills the region", pane.debug.hosting == "chooser" && view.frame.size == wider.size,
  "\(view.frame)")

// The scroll.
let clip = view.contentView
check("new content shows its top", clip.bounds.origin.y == 0)
check("the document is the content's full height", pane.debug.document.height == 1000)
check("scrollBy moves it", pane.scrollBy(120) && clip.bounds.origin.y == 120, "\(clip.bounds)")
dock(wider, height: 1000, reset: false)
check("a redraw of the same content keeps its place", clip.bounds.origin.y == 120)
dock(wider, height: 500, reset: false)
check("shorter content clamps it", clip.bounds.origin.y == 500 - wider.height, "\(clip.bounds)")
check("and scrollBy stops at the end", !pane.scrollBy(10))
dock(wider, height: 1000, reset: true)
check("new content goes back to the top", clip.bounds.origin.y == 0)

// What is drawn, read back from the scroll view standing in a plain view, the only place an
// offscreen render reads a layer free tree.
func redPixels(_ target: NSView) -> Int {
  guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else { return -1 }
  target.cacheDisplay(in: target.bounds, to: rep)
  var n = 0
  for y in 0..<rep.pixelsHigh {
    for x in 0..<rep.pixelsWide {
      if let c = rep.colorAt(x: x, y: y), c.redComponent > 0.9, c.greenComponent < 0.1,
        c.alphaComponent > 0.9 { n += 1 }
    }
  }
  return n
}
let stand = FlippedView(frame: NSRect(origin: .zero, size: wider.size))
view.removeFromSuperview()
stand.addSubview(view)
view.frame = stand.bounds
check("the drawn content shows at the top", redPixels(stand) > 0)
_ = pane.scrollBy(200)
check("and scrolls out of view", redPixels(stand) == 0)

// Icons.
let symbol = NSImage(size: NSSize(width: 72, height: 72), flipped: false) { rect in
  red.setFill()
  rect.fill()
  return true
}
symbol.isTemplate = true
let crisp = Crisp.image(symbol, size: NSSize(width: 20, height: 20), scale: 2)
let rep = crisp.representations.first as? NSBitmapImageRep
check("an icon is drawn at the pixels its box covers", rep?.pixelsWide == 40 && rep?.pixelsHigh == 40)
check("and sized in points", crisp.size == NSSize(width: 20, height: 20))
check("a template stays a template", crisp.isTemplate)

// A lit row's one colour icon is redrawn whole in the lit text colour, its alpha and pixels kept,
// so a symbol under the macOS highlight turns white with its title.
// The symbol arrives in the translucent foreground role, so the white is as opaque as the title.
let half = NSImage(size: NSSize(width: 72, height: 72), flipped: false) { rect in
  NSColor.black.withAlphaComponent(0.85).setFill()
  NSRect(x: 0, y: 0, width: rect.width / 2, height: rect.height).fill()
  return true
}
let lit = Crisp.tinted(Crisp.image(half, size: NSSize(width: 20, height: 20), scale: 2), .white)
let litRep = lit.representations.first as? NSBitmapImageRep
let inked = litRep?.colorAt(x: 5, y: 20)?.usingColorSpace(.sRGB)
let bare = litRep?.colorAt(x: 35, y: 20)
check("a tinted icon keeps its pixels and size", litRep?.pixelsWide == 40 && lit.size == NSSize(width: 20, height: 20))
check("its inked pixels take the colour at full strength, as the title does", (inked?.redComponent ?? 0) > 0.99 && (inked?.alphaComponent ?? 0) > 0.99,
  "\(String(describing: inked))")
check("and its clear pixels stay clear", (bare?.alphaComponent ?? 1) < 0.01, "\(String(describing: bare))")

// What stands on a solid highlight draws in the selection's text colour, each role at the strength
// it has against the foreground on the glass, the key chip included. A translucent highlight, and
// anything not lit, keeps the palette's own.
func srgb(_ c: NSColor) -> NSColor { c.usingColorSpace(.sRGB) ?? c }
var solid = Style()
solid.text = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.8)
solid.sub = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.4)
solid.keycap = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.12)
solid.highlight = NSColor(srgbRed: 0, green: 0.4, blue: 1, alpha: 1)
let litInk = solid.ink(lit: true)
let on = srgb(NSColor.alternateSelectedControlTextColor)
check("lit by a solid highlight, the text is the selection's text colour", srgb(litInk.text) == on)
check("a subtitle keeps its strength against the text", abs(Ink.alpha(litInk.sub) - Ink.alpha(on) * 0.5) < 0.001,
  "\(Ink.alpha(litInk.sub))")
check("a key chip is the lit text at the keycap's strength", abs(Ink.alpha(litInk.keycap) - Ink.alpha(on) * 0.15) < 0.001
  && abs(srgb(litInk.keycap).redComponent - on.redComponent) < 0.001, "\(srgb(litInk.keycap))")
check("and a one colour icon takes the lit text", litInk.icon.map(srgb) == on)
let restInk = solid.ink(lit: false)
check("not lit, the palette's own", restInk.text == solid.text && restInk.keycap == solid.keycap && restInk.icon == nil)
var wash = solid
wash.highlight = NSColor(srgbRed: 0, green: 0.4, blue: 1, alpha: 0.2)
check("a translucent highlight keeps the palette's own", wash.ink(lit: true).text == wash.text
  && wash.ink(lit: true).icon == nil)

// A full bleed opaque square must cover the whole bitmap at either scale. Drawn through a context
// made before the rep had its size in points, it covered a quarter of it at scale 2.
func coverage(scale: CGFloat) -> (opaque: Int, total: Int) {
  let square = NSImage(size: NSSize(width: 72, height: 72), flipped: false) { rect in
    red.setFill()
    rect.fill()
    return true
  }
  let image = Crisp.image(square, size: NSSize(width: 20, height: 20), scale: scale)
  guard let bits = image.representations.first as? NSBitmapImageRep else { return (0, 0) }
  var opaque = 0
  for y in 0..<bits.pixelsHigh {
    for x in 0..<bits.pixelsWide where (bits.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.99 { opaque += 1 }
  }
  return (opaque, bits.pixelsWide * bits.pixelsHigh)
}
for scale in [CGFloat(2), CGFloat(1)] {
  let c = coverage(scale: scale)
  check("a full bleed square covers the whole bitmap at scale \(Int(scale))", c.total > 0 && c.opaque == c.total,
    "\(c.opaque) of \(c.total) pixels")
}

// A CanvasPanel's window.
var clicked: [String] = []
let sheet = PanePanel(findHost: { _ in panel }, config: PaneConfig(panel: true, level: .popUpMenu,
  onClick: { clicked.append($0) }))
let sheetRect = wider
let chip = NSBezierPath(roundedRect: NSRect(x: 200, y: 360, width: 80, height: 24), xRadius: 6, yRadius: 6)
let label = NSBezierPath(rect: NSRect(x: 210, y: 364, width: 60, height: 16))
sheet.place(sheetRect)
sheet.draw([.shape(path: NSBezierPath(rect: NSRect(origin: .zero, size: sheetRect.size)), fill: red, stroke: nil,
  clip: false)], targets: [PaneTarget(id: "dismiss", area: chip), PaneTarget(id: "label", area: label)],
  radius: 12, scroll: PaneScroll(height: sheetRect.height, reset: true, thumb: false))
sheet.show()
settle()
check("a panel is never drawn into a chooser, even on its preview pane rect", sheet.debug.hosting == "own",
  sheet.debug.hosting)
check("a panel stands at the level it asks for", sheet.debug.level == NSWindow.Level.popUpMenu.rawValue)
check("a panel with a click handler takes the mouse", !sheet.debug.clickThrough)
check("the topmost target under the pointer answers", sheet.hit(NSPoint(x: 215, y: 370)) == "label")
check("a target answers in its own shape", sheet.hit(NSPoint(x: 200.5, y: 360.5)) == "_canvas_")
check("and off every target the canvas answers", sheet.hit(NSPoint(x: 20, y: 20)) == "_canvas_")
let drawn = sheet.drawnView
let at = drawn.convert(NSPoint(x: 276, y: 372), to: nil)
if let up = NSEvent.mouseEvent(with: .leftMouseUp, location: at, modifierFlags: [], timestamp: 0,
  windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0) {
  drawn.mouseUp(with: up)
}
check("a mouse up reaches the handler with the id", clicked == ["dismiss"], "\(clicked)")
check("and takes the first press on a window that is not key", drawn.acceptsFirstMouse(for: nil))

let plain = PanePanel(findHost: { _ in nil }, config: PaneConfig(panel: true, level: .popUpMenu, onClick: nil))
plain.place(sheetRect)
check("a panel without a click handler is click through", plain.debug.clickThrough)
check("a preview pane is never click through", !pane.debug.clickThrough && pane.debug.level ==
  NSWindow.Level.floating.rawValue)

// The panel's drawn view rendered into a bitmap at a backing scale, a full bleed surface filling
// every pixel, so a panel on a Retina screen draws at its full size and not a corner of it.
func panelCoverage(scale: CGFloat) -> (opaque: Int, total: Int) {
  let size = drawn.bounds.size
  guard let bits = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
    pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return (0, 0) }
  bits.size = size
  drawn.cacheDisplay(in: drawn.bounds, to: bits)
  var opaque = 0
  for y in 0..<bits.pixelsHigh {
    for x in 0..<bits.pixelsWide where (bits.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.99 { opaque += 1 }
  }
  return (opaque, bits.pixelsWide * bits.pixelsHigh)
}
for scale in [CGFloat(2), CGFloat(1)] {
  let c = panelCoverage(scale: scale)
  check("a panel's surface covers every pixel at backing scale \(Int(scale))", c.total > 0 && c.opaque == c.total,
    "\(c.opaque) of \(c.total) pixels")
}

// MARK: The list

extension Row {
  init(title: String) { self.title = title }
}

let listWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520), styleMask: [.titled],
  backing: .buffered, defer: false)
let list = ListView(frame: NSRect(x: 0, y: 60, width: 460, height: 470))
listWindow.contentView?.addSubview(list)
list.underBar = 60
var listPlacement = Placement()
listPlacement.rowH = 47
listPlacement.padBottom = 8
list.apply(style: Style(), placement: listPlacement)
let listScroll = list.subviews.compactMap { $0 as? NSScrollView }.first!
func listTop() -> CGFloat {
  listWindow.contentView?.layoutSubtreeIfNeeded()
  return listScroll.contentView.bounds.origin.y
}
func rows(_ n: Int) -> [Row] { (1...n).map { Row(title: "row \($0)") } }
func state(highlight: Int?, top: CGFloat?) -> ViewState {
  var s = ViewState()
  s.highlight = highlight
  s.scrollTop = top
  return s
}
// The viewport above the bar, the window's list band less the bar and the margin under the rows.
let shown: CGFloat = 470 - 60 - 8

list.setRows(rows(50))
list.update(state(highlight: 1, top: 0))
list.update(state(highlight: 12, top: 200))
check("the engine's scrollTop moves the list", listTop() == 200, "\(listTop())")
list.setRows(rows(4))
list.update(state(highlight: 1, top: 0))
check("a shorter list after a scroll shows its rows from the top", listTop() == 0, "\(listTop())")

var heard: [Int] = []
var byPointer: [Bool] = []
list.onHighlight = { heard.append($0); byPointer.append($1) }
list.setRows(rows(50))
list.update(state(highlight: 1, top: 0))
heard = []
for _ in 0..<12 { list.move(1) }
check("twelve steps down highlight row thirteen", list.highlight == 13)
check("the viewport moved only far enough to show it above the bar",
  abs(listTop() - (13 * 47 - shown)) < 0.5, "\(listTop())")
list.flushReports()
check("a burst of moves reaches Lua as one report", heard == [13], "\(heard)")
check("and a key's move is not reported as the pointer's", byPointer == [false], "\(byPointer)")
list.update(state(highlight: nil, top: nil))
check("a state with no highlight and no scrollTop leaves the list's own",
  list.highlight == 13 && abs(listTop() - (13 * 47 - shown)) < 0.5)
for _ in 0..<13 { list.move(-1) }
check("up from the first row wraps to the last", list.highlight == 50)
check("and shows it at the bottom", abs(listTop() - (50 * 47 - shown)) < 0.5, "\(listTop())")
list.move(1)
check("down from the last row wraps to the first", list.highlight == 1 && listTop() == 0)
heard = []; byPointer = []
list.hover(2)
list.flushReports()
check("the pointer over a row reports its move as the pointer's", heard == [3] && byPointer == [true],
  "\(heard) \(byPointer)")
list.move(1)
list.flushReports()
heard = []; byPointer = []
list.move(1)
list.flushReports()
check("a key's move after it is a key's again", byPointer == [false], "\(byPointer)")

var asks: [[Int]] = []
list.onWantIcons = { asks.append($0) }
list.setRows(rows(300))
list.update(state(highlight: 1, top: 0))
RunLoop.main.run(until: Date().addingTimeInterval(0.1))
asks = []
for i in 1...10 {
  listScroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: CGFloat(i) * 60))
  RunLoop.main.run(until: Date().addingTimeInterval(0.01))
}
RunLoop.main.run(until: Date().addingTimeInterval(0.6))
let askedRows = asks.flatMap { $0 }
let onScreen = listScroll.contentView.bounds.origin.y / 47
check("a fast scroll asks first for the rows on screen",
  Double(asks.first?.first ?? -1) >= Double(onScreen) - 3 && Double(asks.first?.first ?? 999) <= Double(onScreen) + 1,
  "\(asks.first ?? [])")
check("then for rows ahead of the viewport, in the scroll's direction",
  (askedRows.max() ?? 0) > Int(onScreen) + 20, "max \(askedRows.max() ?? -1)")
check("a dozen rows at most per ask", asks.allSatisfy { $0.count <= 12 })
check("each row asked once", Set(askedRows).count == askedRows.count)

// The fades, the content masked as one, the list and the pane alike, opaque down to the list's
// bottom padding above the bar and clear at the window's edge.
do {
  let fadePanel = ChooserPanel(ask: { _, _ in false })
  var p = Placement()
  p.canvas = NSRect(x: 0, y: 100, width: 480, height: 400)
  p.window = NSRect(x: 0, y: 100, width: 800, height: 400)
  p.listFrame = NSRect(x: 0, y: 0, width: 480, height: 400)
  p.paneFrame = NSRect(x: 480, y: 0, width: 320, height: 352)
  p.previewPane = NSRect(x: 480, y: 100, width: 320, height: 352)
  p.list = NSRect(x: 0, y: 60, width: 480, height: 292)
  p.bottomBar = NSRect(x: 0, y: 352, width: 800, height: 48)
  p.padBottom = 8
  p.pad = 12
  fadePanel.place(p)
  func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
  let tree = NSApp.windows.compactMap { $0.contentView }.flatMap(all)
  let masked = tree.filter { $0.layer?.mask != nil && $0.frame.width == 800 && $0.frame.height == 400 }
  check("the list and the pane fade under one mask", masked.count == 1, "\(masked.map { $0.frame })")
  let columns = (masked.first?.layer?.mask?.sublayers ?? []).compactMap { $0 as? CAGradientLayer }
  func stops(_ c: CAGradientLayer?) -> [CGFloat] { (c?.locations ?? []).map { CGFloat(truncating: $0) } }
  func has(_ c: CAGradientLayer?, _ y: CGFloat) -> Bool {
    stops(c).contains { abs($0 - y / 400) < 0.001 || abs($0 - (400 - y) / 400) < 0.001 }
  }
  let listColumn = columns.first { $0.frame.minX == 0 }, paneColumn = columns.first { $0.frame.minX > 0 }
  check("one column over the list and one over the pane",
    listColumn?.frame.width == 480 && paneColumn?.frame.width == 320, "\(columns.map { $0.frame })")
  check("both fade out from the list's bottom padding above the bar", has(listColumn, 344) && has(paneColumn, 344),
    "\(stops(listColumn)) \(stops(paneColumn))")
  check("the list's column fades in from the window's top to where the first row rests",
    has(listColumn, 60) && stops(listColumn).count > 6, "\(stops(listColumn))")
  check("the pane's column fades in along the same curve from its top edge to where its content rests",
    has(paneColumn, 12) && stops(paneColumn).count == stops(listColumn).count, "\(stops(paneColumn))")
  let fields = tree.compactMap { $0 as? NSTextField }.filter { $0.isEditable }
  check("the field stands outside the content the fades mask",
    !fields.isEmpty && fields.allSatisfy { f in !masked.contains { f.isDescendant(of: $0) } })
  func lists(_ v: NSView) -> [ListView] { (v as? ListView).map { [$0] } ?? v.subviews.flatMap(lists) }
  let fadeList = NSApp.windows.compactMap { $0.contentView }.flatMap(lists).first { $0.frame.maxY == 400 && $0.overField > 0 }
  let titlebar = NSApp.windows.first { $0.contentView?.subviews.isEmpty == false && $0.frame.width == 800 }
    .map { $0.frame.height - $0.contentLayoutRect.maxY } ?? -1
  check("the list runs on up behind the field to the title bar's bottom edge, not under it",
    fadeList.map { abs($0.frame.minY - titlebar) < 0.5 && abs($0.overField - (60 - titlebar)) < 0.5 } == true,
    "titlebar \(titlebar) \(String(describing: fadeList?.frame)) over \(String(describing: fadeList?.overField))")
}

let ownCursor = class_getMethodImplementation(ListView.self, #selector(NSView.cursorUpdate(with:)))
let viewCursor = class_getMethodImplementation(NSView.self, #selector(NSView.cursorUpdate(with:)))
check("a cursor update ends at the list", ownCursor != viewCursor)

// Motion, how every surface comes and goes. A window's content rests see through and fades in when
// it shows. One that never takes key fades out in place and answers down at once, and a show during
// the fade brings it back from where the fade had got, taking no pointer until then, and a reload's
// close during the fade puts it down at once. A cut short close does nothing when it would have ended, and with
// no duration a surface comes and goes at once.
do {
  Motion.openDuration = 0.14
  Motion.closeDuration = 0.09
  Motion.rise = 4
  Motion.scale = 0.98
  func panelAway() -> (NSPanel, NSView) {
    let w = NSPanel(contentRect: NSRect(x: away, y: away, width: 200, height: 100),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    w.isReleasedWhenClosed = false
    let v = NSView()
    w.contentView = v
    return (w, v)
  }
  func fading(_ v: NSView) -> Bool { v.layer?.animation(forKey: "olm.motion.fade") != nil }
  func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
  // Runs the loop until done answers true or two seconds pass, since a fade's end arrives from the
  // render server and its time varies from run to run, which a fixed wait made a flaky case.
  func spin(until done: () -> Bool) {
    let limit = Date().addingTimeInterval(2)
    while !done() && Date() < limit { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
  }

  let (win, content) = panelAway()
  let inPlace = WindowMotion(win)
  var downs = 0
  inPlace.onDown = { downs += 1 }
  check("a window's content rests see through before it first shows", content.alphaValue == 0)
  inPlace.show { win.orderFrontRegardless() }
  check("a shown window is up and its content opaque, fading in", inPlace.isUp && content.alphaValue == 1 && fading(content))
  inPlace.hide()
  check("a window fading out in place answers down at once and stays on screen for its fade",
    !inPlace.isUp && win.isVisible)
  inPlace.show { win.orderFrontRegardless() }
  check("a show during the fade brings it back up, fading in", inPlace.isUp && content.alphaValue == 1 && fading(content))
  spin(0.3)
  check("and the close cut short does nothing when it would have ended", win.isVisible && inPlace.isUp && downs == 0)
  inPlace.hide()
  spin { !win.isVisible }
  check("a close that runs its course orders the window out and says so once",
    !win.isVisible && downs == 1 && content.alphaValue == 0)
  inPlace.show { win.orderFrontRegardless() }
  inPlace.hide(animated: false)
  check("a close with no fade orders it out at once, see through", !win.isVisible && downs == 2 && content.alphaValue == 0)

  let (keyWin, keyContent) = panelAway()
  let keyMotion = WindowMotion(keyWin)
  keyMotion.show { keyWin.orderFrontRegardless() }
  keyMotion.hide()
  check("a closing window takes no pointer while it fades",
    !keyMotion.isUp && keyMotion.closing && keyWin.isVisible && keyWin.ignoresMouseEvents)
  keyMotion.show { keyWin.orderFrontRegardless() }
  check("and takes it again when shown during the fade", keyMotion.isUp && !keyWin.ignoresMouseEvents)
  keyMotion.hide()
  keyMotion.hide(animated: false)
  check("a reload's close during the fade puts it down at once, see through, taking the pointer again",
    !keyWin.isVisible && !keyMotion.closing && keyContent.alphaValue == 0 && !keyWin.ignoresMouseEvents)
  check("a key is passed on only when it is a key", !Motion.passOn(NSEvent.otherEvent(with: .applicationDefined,
    location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!))

  let floating = FloatingPaneView(frame: NSRect(x: 0, y: 0, width: 100, height: 60))
  content.addSubview(floating)
  floating.setOpen(true)
  floating.play()
  floating.setOpen(false)
  check("a closing floating pane is no longer open and takes no pointer",
    !floating.isOpen && floating.hitTest(NSPoint(x: 50, y: 30)) == nil)
  floating.setOpen(true)
  floating.play()
  spin(0.3)
  check("a floating pane reopened during its close stays shown", floating.isOpen && !floating.isHidden && floating.alphaValue == 1)
  floating.closeNow()
  check("a floating pane closed with its chooser is hidden at once", !floating.isOpen && floating.isHidden)

  // A floating pane grows out of its bar group above it, its glass at full size and a mask showing
  // as much as the motion has reached, the group fading out under it, hidden once the pane is whole,
  // and closing shows the group again at once and fades it back in under the shrinking pane.
  Motion.paneOpenDuration = 0.2
  Motion.paneCloseDuration = 0.1
  Motion.paneFadeDuration = 0.05
  var covers: [Bool] = []
  let groupView = FlippedView(frame: NSRect(x: 0, y: 40, width: 30, height: 20))
  groupView.wantsLayer = true
  content.addSubview(groupView)
  floating.onCover = { covers.append($0) }
  floating.group = NSRect(x: 0, y: 40, width: 30, height: 20)
  floating.groupView = groupView
  floating.setOpen(true)
  floating.play()
  let glassOf = { floating.subviews.first?.frame ?? .zero }
  let maskOf = { floating.layer?.mask?.frame ?? .zero }
  if Motion.still {
    check("with Reduce Motion a floating pane opens at once over its group", covers == [true] && floating.layer?.mask == nil)
  } else {
    check("a floating pane starts on its group's rect, its glass whole and the group not yet hidden",
      maskOf() == floating.group && glassOf() == floating.bounds && covers.isEmpty)
    spin(0.1)
    check("midway the mask has grown and the group has faded under it",
      maskOf().height > floating.group.height && (groupView.layer?.opacity ?? 1) < 0.5 && covers.isEmpty)
    spin(0.25)
    check("once whole it is unmasked and covers its group", floating.layer?.mask == nil && covers == [true]
      && (groupView.layer?.opacity ?? 0) == 1)
    floating.setOpen(false)
    check("closing shows the group again at once, faded out under the pane", covers == [true, false]
      && (groupView.layer?.opacity ?? 1) < 0.01)
    spin(0.05)
    check("a closing floating pane shrinks toward its group", maskOf().width < floating.bounds.width && !floating.isHidden)
    spin(0.2)
    check("and hides once back on it", floating.isHidden && floating.layer?.mask == nil)
  }
  floating.closeNow()
  floating.onCover = nil
  floating.groupView = nil
  groupView.removeFromSuperview()
  Motion.paneOpenDuration = 0
  Motion.paneCloseDuration = 0
  Motion.paneFadeDuration = 0

  Motion.openDuration = 0
  Motion.closeDuration = 0
  keyMotion.show { keyWin.orderFrontRegardless() }
  check("with no open duration a window shows opaque at once", keyContent.alphaValue == 1 && !fading(keyContent))
  keyMotion.hide()
  check("with no close duration a window goes down at once", !keyWin.isVisible && !keyMotion.closing && keyContent.alphaValue == 0)
  let still = NSView()
  var done = false
  Motion.disappear(still) { done = true }
  check("with no close duration a view rests and is done at once", done && still.alphaValue == 0)
  Motion.appear(still)
  check("with no open duration a view appears at once", still.alphaValue == 1 && !fading(still))
}

// One placement rule for both floating panes, mirrored by side, floatingpane.lua's place. A pane
// takes the width its lines need and stops only the pad clear of the window's edge, standing over
// the other group rather than cutting its labels.
do {
  let W: CGFloat = 400, pad: CGFloat = 10
  let keysGroup = NSRect(x: 10, y: 300, width: 60, height: 30)
  let info = ChooserPanel.floatingFrame(size: NSSize(width: 250, height: 100), anchor: keysGroup,
    floor: 60, leading: true, width: W, top: 0, pad: pad)
  check("the info pane takes the width its lines need", info.width == 250)
  check("its left and bottom edges on its group's", info.minX == keysGroup.minX && info.maxY == keysGroup.maxY)
  func mirror(_ r: NSRect) -> NSRect { NSRect(x: W - r.maxX, y: r.minY, width: r.width, height: r.height) }
  let actions = ChooserPanel.floatingFrame(size: NSSize(width: 250, height: 100), anchor: mirror(keysGroup),
    floor: 60, leading: false, width: W, top: 0, pad: pad)
  check("the actions pane is the info pane mirrored", actions == mirror(info))
  let edge = ChooserPanel.floatingFrame(size: NSSize(width: 500, height: 100), anchor: keysGroup,
    floor: 60, leading: true, width: W, top: 0, pad: pad)
  check("only the window's edge less the pad stops it", edge.maxX == W - pad)
  let floored = ChooserPanel.floatingFrame(size: NSSize(width: 20, height: 100), anchor: keysGroup,
    floor: 60, leading: true, width: W, top: 0, pad: pad)
  check("and it is never narrower than its group", floored.width == 60)
}

// A floating pane is sized as a table, and a lead takes a column of its own room.
do {
  var p = Placement()
  p.keycapPadX = 4
  let style = Style()
  func pane(_ lines: [FloatingPaneView.Line]) -> FloatingPaneView {
    let v = FloatingPaneView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    v.show(title: nil, lines: lines, style: style, placement: p, outer: 6, inner: 6, lineH: 28, gap: 16, radius: 10)
    return v
  }
  let longLabel = FloatingPaneView.Line(label: "A long label for the first column", chord: [[KeyMark(glyph: "K", symbol: nil)]])
  let longChord = FloatingPaneView.Line(label: "X", chord: [[KeyMark(glyph: "WWWW", symbol: nil), KeyMark(glyph: "WWWW", symbol: nil)]])
  let both = pane([longLabel, longChord]).preferredSize.width
  check("the widest label and the widest chord on different lines both keep the gap",
    both > pane([longLabel]).preferredSize.width && both > pane([longChord]).preferredSize.width)
  var led = longLabel
  led.lead = [[KeyMark(glyph: "M", symbol: nil)]]
  check("a lead widens the first column", pane([led]).preferredSize.width > pane([longLabel]).preferredSize.width)
}

// A symbol in a key cap is drawn at its colour's alpha, as a glyph beside it is.
do {
  var style = Style()
  style.number = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5)
  let p = Placement()
  style.text = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.9)
  func peak(_ mark: KeyMark, strong: Bool = false) -> CGFloat {
    let cap = KeyCap([[mark]], ink: style.ink(lit: false), style: style, placement: p, holderH: 30, holderRadius: 0,
      bare: true, strong: strong, keyFont: NSFont.systemFont(ofSize: 24, weight: .bold))
    let stand = FlippedView(frame: NSRect(x: 0, y: 0, width: 60, height: 40))
    stand.addSubview(cap)
    cap.frame = NSRect(origin: .zero, size: cap.fittingSize)
    cap.layoutSubtreeIfNeeded()
    guard let rep = stand.bitmapImageRepForCachingDisplay(in: stand.bounds) else { return -1 }
    stand.cacheDisplay(in: stand.bounds, to: rep)
    var most: CGFloat = 0
    for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide { most = max(most, rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) } }
    return most
  }
  let glyph = peak(KeyMark(glyph: "M", symbol: nil))
  let symbol = peak(KeyMark(glyph: "M", symbol: "square.fill"))
  check("a symbol's ink is as strong as a glyph's in the same translucent colour", abs(glyph - symbol) < 0.08,
    "glyph \(glyph) symbol \(symbol)")
  let lead = peak(KeyMark(glyph: "M", symbol: "square.fill"), strong: true)
  check("a floating pane line's lead is drawn in the text colour, not a row shortcut's", abs(lead - 0.9) < 0.08,
    "lead \(lead)")
}

if failed {
  print("swiftpane, FAILED")
  exit(1)
}
print("swiftpane, every case passed")
