// A preview's picture read from its file, step 1.4b of docs/PLAN-STANDALONE.md. A plugin hands a
// path, OlmKit's Preview.Picture, and this reads it the way hs.image.imageFromPath does, through
// NSImage, so its size in points is the one the Lua layout's imageFit is handed. It then draws the
// picture once into a bitmap of the pixels it will be shown at, which is what decodes it, so the
// main thread only ever draws pixels already decoded and scaled, rule 8 of the plan. A picture the
// system cannot read answers nil and the pane draws its heading alone.
//
// Called on the task the stage lays a pane out on, never on the main thread.

import AppKit
import OlmKit

public enum PanePicture {
  /// The picture at its file, decoded at the size a slot width points wide draws it, at scale pixels
  /// to the point, nil when it cannot be read.
  public static func load(_ picture: OlmKit.Preview.Picture, width: Double, scale: Double) -> PaneImage? {
    guard let source = NSImage(contentsOfFile: picture.path) else { return nil }
    let natural = source.size
    guard natural.width > 0, natural.height > 0 else { return nil }
    let drawnW = picture.upscale ? width : min(width, Double(natural.width))
    let drawnH = drawnW * Double(natural.height) / Double(natural.width)
    // Asked at the pixels it is shown at, so a picture whose points are fewer than its pixels is
    // not handed over at one pixel to the point.
    var proposed = NSRect(x: 0, y: 0, width: drawnW * scale, height: drawnH * scale)
    guard drawnW > 0, let cg = source.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
    // No more pixels than the file holds, and no more than the screen shows.
    let pw = max(1, min(cg.width, Int((drawnW * scale).rounded(.up))))
    let ph = max(1, min(cg.height, Int((drawnH * scale).rounded(.up))))
    let space = cg.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.interpolationQuality = .high
    context.draw(cg, in: CGRect(x: 0, y: 0, width: pw, height: ph))
    guard let decoded = context.makeImage() else { return nil }
    let image = NSImage(cgImage: decoded, size: natural)
    return PaneImage(path: picture.path, w: Double(natural.width), h: Double(natural.height), image: image)
  }
}
