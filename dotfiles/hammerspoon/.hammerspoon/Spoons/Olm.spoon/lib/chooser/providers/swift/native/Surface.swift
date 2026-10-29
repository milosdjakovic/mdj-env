// The surfaces this library draws on, built in one place. Surface is one shape of glass, the
// docked pane's own when it stands alone. SharedSurface is the chooser panel's window content,
// one shape of glass under the list and, when there is one, the docked pane beside it, so the two
// are one surface. ScreenSpace is the one conversion between Hammerspoon's screen space and
// AppKit's.

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
      // A glass that still names this view from before it left would take the assignment as no
      // change and leave it with no superview, so the old claim is dropped first.
      if glass.contentView === content { glass.contentView = nil }
      glass.contentView = content
      return
    }
    for old in view.subviews { old.removeFromSuperview() }
    content.frame = view.bounds
    content.autoresizingMask = [.width, .height]
    view.addSubview(content)
  }

  // Gives content up for another window to hold. A glass keeps naming its content view after
  // that view moved elsewhere, and goes on laying it out, so a view another window holds was
  // resized to nothing on that window's next layout. The claim is dropped here.
  func release(_ content: NSView) {
    if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView, glass.contentView === content {
      glass.contentView = nil
    }
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

// The chooser panel's window content, one shape of glass at the surface radius. With no
// companion it is the canvas rect, the list's shape alone. With one, the window and the glass
// span the canvas rect, the engine's gap and the companion rect, the list's content sits at the
// canvas rect inside it, the docked pane's view at the companion rect, and a hairline divider
// stands in the middle of the gap from the top down to the action bar, which runs under both. One shape rather than two because two
// shapes side by side each shade their edges and cast their shadow where they meet, which read
// as a dark band in the gap. The rects come from the Lua view already in the window's own space,
// y measured down.
final class SharedSurface {
  private let glass: Surface
  private let stage = FlippedView()
  private let list: NSView
  private let paneSlot = FlippedView()
  private let divider = DividerView()

  var view: NSView { glass.view }
  var name: String { glass.name }

  init(list content: NSView) {
    list = content
    stage.addSubview(content)
    stage.addSubview(paneSlot)
    stage.addSubview(divider)
    paneSlot.isHidden = true
    divider.isHidden = true
    glass = Surface(holding: stage)
  }

  func setCornerRadius(_ radius: CGFloat) { glass.setCornerRadius(radius) }

  func setDividerColor(_ color: NSColor) {
    divider.color = color
    divider.needsDisplay = true
  }

  // Lays the content out in a window of size. The pane's region shows only when there is a rect
  // for it and a docked pane in it, and the divider whenever there is a rect for it.
  func layout(size: NSSize, list listRect: NSRect, pane paneRect: NSRect?, divider dividerRect: NSRect?,
    paneShown: Bool) {
    stage.frame = NSRect(origin: .zero, size: size)
    list.frame = listRect
    paneSlot.frame = paneRect ?? .zero
    paneSlot.isHidden = paneRect == nil || !paneShown
    divider.frame = dividerRect ?? .zero
    divider.isHidden = dividerRect == nil
  }

  // A docked pane's view goes into the pane's region in place of whatever was there.
  func holdPane(_ content: NSView) {
    for old in paneSlot.subviews where old !== content { old.removeFromSuperview() }
    if content.superview !== paneSlot {
      content.removeFromSuperview()
      paneSlot.addSubview(content)
    }
    // Sized by its autoresizing mask here. A glass that held it before set it to be placed by
    // constraints and pinned it to itself, and those pins went with the glass, so without this
    // the view stood in the region with no constraint at all and the next layout after its frame
    // changed sized it to nothing, which left a pane in its own window and then docked here blank.
    content.translatesAutoresizingMaskIntoConstraints = true
    content.frame = paneSlot.bounds
    content.autoresizingMask = [.width, .height]
  }

  func vacatePane() {
    for old in paneSlot.subviews { old.removeFromSuperview() }
  }

  // A view that stands over the list's content and the pane's region alike, the action bar and
  // its key panel, placed by its owner in the window's own space and kept above both.
  func addOverlay(_ view: NSView) {
    stage.addSubview(view, positioned: .above, relativeTo: nil)
  }
}

// The hairline between the list and the pane, filled with the kit's border colour.
final class DividerView: NSView {
  var color = NSColor.separatorColor

  override func draw(_ dirtyRect: NSRect) {
    color.setFill()
    bounds.fill()
  }
}
