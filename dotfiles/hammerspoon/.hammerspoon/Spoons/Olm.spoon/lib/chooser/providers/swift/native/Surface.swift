// The surfaces this library draws on, built in one place. Surface is one shape of glass, the
// docked pane's own when it stands alone. SharedSurface is the chooser panel's window content, a
// glass container holding the list's shape and the docked pane's shape side by side, so macOS
// samples and renders the two as one material and they read as one surface. ScreenSpace is the
// one conversion between Hammerspoon's screen space and AppKit's.

import Cocoa

struct Surface {
  let view: NSView
  // Which surface was built, for a probe to say what it is looking at.
  let name: String

  // Glass where the running macOS ships it, and the visual effect view where it does not, so the
  // same build still draws a surface on an older system. content is what the surface holds.
  init(holding content: NSView) {
    if #available(macOS 26.0, *) {
      view = NSGlassEffectView()
      name = "glass"
    } else {
      let effect = NSVisualEffectView()
      effect.material = .hudWindow
      effect.state = .active
      effect.blendingMode = .behindWindow
      effect.wantsLayer = true
      effect.layer?.masksToBounds = true
      view = effect
      name = "visualEffect"
    }
    hold(content)
  }

  // Puts content in the surface in place of whatever it held, taking it from wherever it was,
  // which is how the docked pane's view moves between its own window and the chooser panel's.
  func hold(_ content: NSView) {
    content.removeFromSuperview()
    if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
      glass.contentView = content
      return
    }
    for old in view.subviews { old.removeFromSuperview() }
    content.frame = view.bounds
    content.autoresizingMask = [.width, .height]
    view.addSubview(content)
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

  // Whether two rects in Hammerspoon's space are the same one, to within half a point, since
  // both sides of the comparison went through Lua numbers.
  static func same(_ a: NSRect, _ b: NSRect) -> Bool {
    abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5
      && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
  }
}

// The chooser panel's window content. The window spans the list's rect and, when there is one,
// the companion's, and holds two shapes, the list's and the pane's, with the engine's gap between
// them clear. They sit in one NSGlassEffectContainerView, which renders its descendant glass as
// one batch and merges shapes only within its spacing. The spacing is zero, the header's own
// default, which batches them without merging, so the two stay two shapes with the gap between
// them. The rects come from the Lua view already in the window's own space, y measured down.
final class SharedSurface {
  let view: NSView
  let list: Surface
  let pane: Surface
  private let stage = FlippedView()
  // What the pane's shape holds while no docked pane is in it.
  private let vacant = NSView()

  var name: String { list.name }

  init(list content: NSView) {
    list = Surface(holding: content)
    pane = Surface(holding: vacant)
    stage.addSubview(list.view)
    stage.addSubview(pane.view)
    pane.view.isHidden = true
    if #available(macOS 26.0, *) {
      let container = NSGlassEffectContainerView()
      container.spacing = 0
      container.contentView = stage
      view = container
    } else {
      view = stage
    }
  }

  // Lays the two shapes out in a window of size, the pane's shown only when there is a rect for
  // it and a docked pane in it.
  func layout(size: NSSize, list listRect: NSRect, pane paneRect: NSRect?, paneShown: Bool) {
    stage.frame = NSRect(origin: .zero, size: size)
    list.view.frame = listRect
    pane.view.frame = paneRect ?? .zero
    pane.view.isHidden = paneRect == nil || !paneShown
  }

  // Whether a point in the window's own space lands on a shape rather than in the clear gap.
  func covers(_ point: NSPoint) -> Bool {
    let local = stage.convert(point, from: nil)
    if list.view.frame.contains(local) { return true }
    return !pane.view.isHidden && pane.view.frame.contains(local)
  }

  func holdPane(_ content: NSView) { pane.hold(content) }

  func vacatePane() { pane.hold(vacant) }
}
