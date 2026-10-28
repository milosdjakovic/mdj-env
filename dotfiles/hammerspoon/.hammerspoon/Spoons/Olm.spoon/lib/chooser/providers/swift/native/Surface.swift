// The surface both windows of this library stand on, the chooser panel and the docked pane, built
// in one place so the two read as one surface beside each other, and the one conversion between
// Hammerspoon's screen space and AppKit's, which both windows are placed through.

import Cocoa

struct Surface {
  let view: NSView
  // Which surface was built, for a probe to say what it is looking at.
  let name: String

  // Glass where the running macOS ships it, and the visual effect view where it does not, so the
  // same build still draws a surface on an older system. content is what the surface holds.
  init(holding content: NSView) {
    if #available(macOS 26.0, *) {
      let glass = NSGlassEffectView()
      glass.contentView = content
      view = glass
      name = "glass"
      return
    }
    let effect = NSVisualEffectView()
    effect.material = .hudWindow
    effect.state = .active
    effect.blendingMode = .behindWindow
    effect.wantsLayer = true
    effect.layer?.masksToBounds = true
    content.autoresizingMask = [.width, .height]
    effect.addSubview(content)
    view = effect
    name = "visualEffect"
  }

  func setCornerRadius(_ radius: CGFloat) {
    if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
      glass.cornerRadius = radius
    } else {
      view.layer?.cornerRadius = radius
    }
  }
}

// Hammerspoon's screen space has its origin at the primary display's top left and y growing
// down, AppKit's at its bottom left and y growing up, so both conversions flip about its height.
enum ScreenSpace {
  static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

  static func cocoaRect(_ rect: NSRect) -> NSRect {
    NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
  }

  static func hsPoint(_ point: NSPoint) -> NSPoint {
    NSPoint(x: point.x, y: primaryHeight - point.y)
  }
}
