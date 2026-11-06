// The surfaces this library draws on, built in one place. Surface is one shape of glass, the
// preview pane's own when it stands alone. SharedSurface is the chooser panel's window content,
// one shape of glass under the list and, when there is one, the preview pane beside it, so the two
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
  // which is how the preview pane's view moves between its own window and the chooser panel's.
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
// preview pane it is the canvas rect, the list's shape alone. With one, the window and the glass
// span the canvas rect, the engine's gap and the preview pane rect, the list's content sits at the
// canvas rect inside it and the preview pane's view at the preview pane rect, nothing drawn
// between them, with the bottom bar running under both. One shape rather than two because two
// shapes side by side each shade their edges and cast their shadow where they meet, which read
// as a dark band in the gap. The rects come from the Lua view already in the window's own space,
// y measured down.
final class SharedSurface {
  private let glass: Surface
  private let stage = FlippedView()
  // The list's content and the pane's region, masked together, each column fading on its own.
  private let content = FlippedView()
  private let fade = BottomFade()
  private let list: NSView
  private let paneSlot = FlippedView()

  var view: NSView { glass.view }
  var name: String { glass.name }
  // The list's content, the pane's region and the divider together, which a reshape slides.
  var sliding: NSView { content }

  init(list content: NSView) {
    list = content
    self.content.addSubview(content)
    self.content.addSubview(paneSlot)
    stage.addSubview(self.content)
    // Both backed by layers of their own from the start, since the content's mask is a layer mask
    // and drew nothing, seen live on 2026-10-31, until a sibling happened to make the stage a layer.
    stage.wantsLayer = true
    self.content.wantsLayer = true
    paneSlot.isHidden = true
    glass = Surface(holding: stage)
  }

  func setCornerRadius(_ radius: CGFloat) { glass.setCornerRadius(radius) }

  // Lays the content out in a window of size. The pane's region shows only when there is a rect
  // for it and a preview pane in it. fadeTop is
  // where the bottom fade begins and fadeListTop where the top fade ends, both measured down from
  // the window's top, the second over the list's column, which ends at listColumn. The pane's
  // column fades in from paneTop to paneRest, where its content rests.
  func layout(size: NSSize, list listRect: NSRect, pane paneRect: NSRect?,
    paneShown: Bool, fadeTop: CGFloat, fadeListTop: CGFloat = 0, fadeClearTo: CGFloat = 0,
    listColumn: CGFloat? = nil, paneTop: CGFloat = 0, paneRest: CGFloat = 0) {
    stage.frame = NSRect(origin: .zero, size: size)
    content.frame = stage.bounds
    fade.layout(content: content, size: size, top: fadeTop, listTop: fadeListTop, clearTo: fadeClearTo, column: min(size.width, listColumn ?? size.width), paneTop: paneTop, paneRest: paneRest)
    list.frame = listRect
    paneSlot.frame = paneRect ?? .zero
    paneSlot.isHidden = paneRect == nil || !paneShown
  }

  // A preview pane's view goes into the pane's region in place of whatever was there.
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

  // A view that stands over the list's content and the pane's region alike, the bottom bar and
  // its info pane, placed by its owner in the window's own space and kept above both.
  func addOverlay(_ view: NSView) {
    stage.addSubview(view, positioned: .above, relativeTo: nil)
  }
}

// The top and the bottom of the chooser, where the list runs on behind the field and the list and
// the pane behind the floating bar. Over the bottom band, from bottom to the window's bottom edge,
// the content's alpha falls to nothing across the window's whole width, so the list and the pane
// fade alike. Over the top band it is nothing down to clearTo, the title bar's bottom edge where the
// list stops, and rises along one smooth curve to full where the first row rests, low behind the
// field's text so the field reads over a row there and with no kink anywhere, since a kink at the
// field's bottom drew a line through a row scrolled half into the band, seen on 2026-10-31. The
// pane's column rises along the same curve over its own band, from its top edge to where its
// content rests, since its header rests inside the list's band and would fade there. The mask is
// one layer holding a gradient per column. Nothing blurs, see decisions/olm-swift-chooser.md for every blur tried.
final class BottomFade {
  private let mask = CALayer()
  private let listColumn = CAGradientLayer()
  private let paneColumn = CAGradientLayer()
  // The top curve, the alpha at t from 0 at the clear edge to 1 where the first row rests, a
  // smoothstep squared, flat at both ends and about a tenth a third of the way down.
  private static func rise(_ t: CGFloat) -> CGFloat {
    let s = t * t * (3 - 2 * t)
    return s * s
  }
  private static let riseStops = 12

  init() {
    for column in [listColumn, paneColumn] {
      column.startPoint = CGPoint(x: 0.5, y: 0)
      column.endPoint = CGPoint(x: 0.5, y: 1)
      mask.addSublayer(column)
    }
  }

  func layout(content: NSView, size: NSSize, top bottom: CGFloat, listTop: CGFloat, clearTo: CGFloat,
    column: CGFloat, paneTop: CGFloat, paneRest: CGFloat) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if content.layer?.mask !== mask { content.layer?.mask = mask }
    mask.frame = content.bounds
    let h = max(1, size.height)
    let end = max(0, min(1, bottom / h))
    listColumn.frame = CGRect(x: 0, y: 0, width: column, height: size.height)
    Self.fill(listColumn, in: content.layer, clear: clearTo / h, rest: listTop / h, end: end)
    paneColumn.frame = CGRect(x: column, y: 0, width: max(0, size.width - column), height: size.height)
    Self.fill(paneColumn, in: content.layer, clear: paneTop / h, rest: paneRest / h, end: end)
    CATransaction.commit()
  }

  // One column's gradient, nothing down to clear, the rise to full at rest, full down to end and
  // nothing at the bottom edge, every stop a fraction of the height measured down.
  private static func fill(_ column: CAGradientLayer, in host: CALayer?, clear clearAt: CGFloat,
    rest: CGFloat, end: CGFloat) {
    let start = max(0, min(end, rest))
    let clearEnd = max(0, min(start, clearAt))
    let black = NSColor.black.cgColor, clear = NSColor.clear.cgColor
    var colors: [CGColor] = [], stops: [CGFloat] = []
    if start > clearEnd {
      colors.append(clear); stops.append(0)
      for i in 0...riseStops {
        let t = CGFloat(i) / CGFloat(riseStops)
        colors.append(NSColor.black.withAlphaComponent(rise(t)).cgColor)
        stops.append(clearEnd + (start - clearEnd) * t)
      }
    } else {
      colors.append(black); stops.append(0)
    }
    colors += [black, clear]; stops += [end, 1]
    column.colors = colors
    column.locations = down(column, in: host, stops)
  }

  // Locations given top down, turned around when the host's space runs bottom up, since whether a
  // view's layer is flipped follows AppKit's choice for that view and not this code's. The host is
  // asked rather than the mask, which has no superlayer and so always answers unflipped.
  private static func down(_ layer: CAGradientLayer, in host: CALayer?, _ stops: [CGFloat]) -> [NSNumber] {
    if host?.contentsAreFlipped() == true { return stops.map { NSNumber(value: Double($0)) } }
    layer.colors = layer.colors?.reversed()
    return stops.reversed().map { NSNumber(value: Double(1 - $0)) }
  }
}
