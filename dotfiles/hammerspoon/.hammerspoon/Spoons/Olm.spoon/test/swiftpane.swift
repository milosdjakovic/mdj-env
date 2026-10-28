// The swift chooser's native pane, in its real classes, with no window ever shown.
//
// Compiled by swiftpane.sh with the library's own sources and run as a program. It pins what the
// Lua cases cannot see, the AppKit view tree a docked pane lives in. A pane docked in a chooser
// panel's region keeps the region's size through a redock at a new size and the layout after it,
// which is the blank pane of 2026-10-28, where the scroll view left the pane's own glass placed
// by constraints with none left and the next layout sized it to nothing. A pane handed back to its
// own window is in that window again, and docked again it fills the region. The scroll view
// shows the top of new content, moves by scrollBy, keeps its place across a redraw and is clamped
// to shorter content, and what is drawn is drawn at the top of the document. An icon drawn by
// Crisp has exactly the pixels its box covers at the scale asked for, and a template stays one.
//
// A CanvasPanel's window, the same class made with a panel config, is never drawn into a chooser's
// window even on the companion rect, stands at the level asked for, is click through with no click
// handler and takes the mouse with one, hit tests the topmost element built with an id and
// trackMouseUp and reports _canvas_ off every one, hands a mouse up to its handler, and draws a full
// bleed surface over every pixel at backing scale 2 as at 1.
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

let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
let elements: [PaneElement] = [.shape(path: NSBezierPath(rect: NSRect(x: 10, y: 10, width: 50, height: 50)),
  fill: red, stroke: nil, clip: false)]

// A chooser panel placed with its companion at rect, its window spanning the list and the pane.
let panel = ChooserPanel(ask: { _, _ in false })
func placePanel(companion rect: NSRect) {
  var p = Placement()
  p.canvas = NSRect(x: 0, y: rect.minY, width: 480, height: rect.height)
  p.window = NSRect(x: 0, y: rect.minY, width: rect.maxX, height: rect.height)
  p.listFrame = NSRect(x: 0, y: 0, width: 480, height: rect.height)
  p.paneFrame = NSRect(x: rect.minX, y: 0, width: rect.width, height: rect.height)
  p.companion = rect
  panel.place(p)
}

// The seam's own comparison, without asking whether the panel is on screen, since none is here.
var owned = true
let pane = PanePanel(findHost: { rect in
  owned && panel.companion.map { ScreenSpace.same($0, rect) } == true ? panel : nil
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
let seed = NSRect(x: 500, y: 200, width: 290, height: 380)
let first = NSRect(x: 500, y: 200, width: 300, height: 400)
let wider = NSRect(x: 500, y: 200, width: 340, height: 420)

dock(seed, height: 1000, reset: true)
check("a pane starts in its own window", pane.debug.hosting == "own")

placePanel(companion: first)
dock(first, height: 1000, reset: false)
check("docked, it is in the chooser's region", pane.debug.hosting == "chooser")
check("and fills it after layout, though it was sized for the seed", view.frame.size == first.size,
  "\(view.frame)")

placePanel(companion: wider)
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
check("a panel is never drawn into a chooser, even on its companion rect", sheet.debug.hosting == "own",
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
check("a docked pane is never click through", !pane.debug.clickThrough && pane.debug.level ==
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

if failed {
  print("swiftpane, FAILED")
  exit(1)
}
print("swiftpane, every case passed")
