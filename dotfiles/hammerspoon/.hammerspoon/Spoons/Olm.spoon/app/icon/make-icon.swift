// Draws Olm.app's icon, app/Olm.icns, which build.sh copies into the bundle. Run it by hand when the
// icon changes and commit the result, since the build has no Xcode to compile an asset catalogue:
//
//   app/icon/make-icon.sh
//
// The body follows macOS's icon grid, an 824 point rounded square in a 1024 canvas with its shadow,
// so the system shows it as it shows its own and does not put it on a plate. A deep blue to violet
// face with a glass sheen over its top half, and the Command symbol in white, the mark the Olm row
// of the settings window shows beside the name.
//
// look-exempt, the whole file: an icon is a picture drawn once, not a surface of Olm's look.

import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "Olm.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func draw(_ pixels: Int) -> Data {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  rep.size = NSSize(width: 1024, height: 1024)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let body = NSRect(x: 100, y: 100, width: 824, height: 824)
  let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

  // The shadow the system's own icons stand on.
  NSGraphicsContext.saveGraphicsState()
  let shadow = NSShadow()
  shadow.shadowColor = NSColor(white: 0, alpha: 0.32)
  shadow.shadowOffset = NSSize(width: 0, height: -14)
  shadow.shadowBlurRadius = 28
  shadow.set()
  NSColor.black.setFill()
  shape.fill()
  NSGraphicsContext.restoreGraphicsState()

  // The face.
  NSGradient(colors: [NSColor(srgbRed: 0.18, green: 0.47, blue: 1.0, alpha: 1),
                      NSColor(srgbRed: 0.36, green: 0.25, blue: 0.93, alpha: 1),
                      NSColor(srgbRed: 0.55, green: 0.22, blue: 0.85, alpha: 1)])!
    .draw(in: shape, angle: -55)

  // The glass sheen over the top half, and a light rim.
  NSGraphicsContext.saveGraphicsState()
  shape.addClip()
  NSGradient(colors: [NSColor(white: 1, alpha: 0.38), NSColor(white: 1, alpha: 0.0)])!
    .draw(in: NSRect(x: 100, y: 470, width: 824, height: 454), angle: -90)
  NSGraphicsContext.restoreGraphicsState()
  NSColor(white: 1, alpha: 0.30).setStroke()
  let rim = NSBezierPath(roundedRect: body.insetBy(dx: 3, dy: 3), xRadius: 182, yRadius: 182)
  rim.lineWidth = 6
  rim.stroke()

  // The mark.
  let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
  if let symbol = NSImage(systemSymbolName: "command", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let size = symbol.size
    let at = NSRect(x: 512 - size.width / 2, y: 512 - size.height / 2, width: size.width, height: size.height)
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = NSColor(white: 0, alpha: 0.22)
    glow.shadowOffset = NSSize(width: 0, height: -8)
    glow.shadowBlurRadius = 18
    glow.set()
    symbol.draw(in: at)
    NSGraphicsContext.restoreGraphicsState()
  }
  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
  for scale in scales {
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try! draw(points * scale).write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
  }
}
