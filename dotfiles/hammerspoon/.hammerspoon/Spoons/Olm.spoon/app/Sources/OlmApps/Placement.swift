// Where a placed window lands, a port of the app toggler's geometry, plugins/apptoggler/init.lua,
// step 6.2, docs/DESIGN-APP-APPS.md. Pure arithmetic on the screen's visible frame and the window's
// own, in the top left origin coordinates Accessibility and hs.screen:frame() both use. Since 2026-11-23
// an app's own place from the Applications page as well, Placement.place.

import Foundation

/// A rectangle, top left origin.
public struct Box: Sendable, Equatable {
  public var x, y, w, h: Double
  public init(x: Double, y: Double, w: Double, h: Double) {
    self.x = x
    self.y = y
    self.w = w
    self.h = h
  }
}

/// Insets on each side, the toggler's normalizePadding: a number insets all four, x and y the pairs,
/// any of top, right, bottom and left exactly those, and nothing none.
public struct Padding: Sendable, Equatable {
  public var top = 0.0, right = 0.0, bottom = 0.0, left = 0.0
  public init() {}

  public init(_ json: Any?) {
    if let n = json as? Double {
      top = n; right = n; bottom = n; left = n
      return
    }
    guard let o = json as? [String: Any] else { return }
    func num(_ k: String) -> Double? { o[k] as? Double }
    if num("top") != nil || num("right") != nil || num("bottom") != nil || num("left") != nil {
      top = num("top") ?? 0; right = num("right") ?? 0; bottom = num("bottom") ?? 0; left = num("left") ?? 0
      return
    }
    let x = num("x") ?? 0, y = num("y") ?? 0
    top = y; bottom = y; left = x; right = x
  }
}

/// Which display a placed window goes to: the one it stands on, the one holding the window that was
/// in front when the key was pressed, or the one under the pointer then.
public enum PlaceDisplay: String, Sendable, Equatable {
  case was, active, pointer
}

/// One app's placement, in two forms. The style form, config/toggles.lua's, a width and a height in
/// points, the padding and a fractional anchor, always places the window on the display it stands on.
/// The Applications page's form, an app's own `place`, names a display, centres the window or keeps
/// where it stands, sizes it or keeps its size, a size in points or a percent of the display with a
/// least and a most, and the padding the window keeps from the display's edges.
public struct Placement: Sendable, Equatable {
  public var width: Double?
  public var height: Double?
  public var padding: Padding
  public var atX: Double?
  public var atY: Double?
  /// Whether the window is put at the anchor, half where none is given, or keeps where it stands.
  public var anchored = true
  public var display = PlaceDisplay.was
  /// The width and the height are percents of the display's visible frame.
  public var percent = false
  public var minWidth: Double?
  public var minHeight: Double?
  public var maxWidth: Double?
  public var maxHeight: Double?

  public init(width: Double? = nil, height: Double? = nil, padding: Padding = Padding(), atX: Double? = nil,
    atY: Double? = nil) {
    self.width = width
    self.height = height
    self.padding = padding
    self.atX = atX
    self.atY = atY
  }

  /// Read from the table appRun carries, its JSON as Foundation answers it, nil for anything else. A
  /// table naming display, center or size is the page's form, any other the style's.
  public init?(_ json: Any?) {
    guard let o = json as? [String: Any] else { return nil }
    if o["display"] != nil || o["center"] != nil || o["size"] != nil {
      self.init(padding: Padding(o["padding"]))
      display = PlaceDisplay(rawValue: o["display"] as? String ?? "") ?? .was
      anchored = o["center"] as? Bool ?? false
      if let s = o["size"] as? [String: Any] {
        width = s["width"] as? Double
        height = s["height"] as? Double
        percent = s["unit"] as? String == "percent"
        minWidth = s["minWidth"] as? Double
        minHeight = s["minHeight"] as? Double
        maxWidth = s["maxWidth"] as? Double
        maxHeight = s["maxHeight"] as? Double
      }
      return
    }
    let at = o["at"] as? [String: Any]
    self.init(width: o["width"] as? Double, height: o["height"] as? Double, padding: Padding(o["padding"]),
      atX: at?["x"] as? Double, atY: at?["y"] as? Double)
  }

  /// Whether placing can change anything at all, a display to go to, a position or a size.
  public var acts: Bool { display != .was || anchored || width != nil || height != nil }

  /// The screen's visible frame inset by the padding.
  public func box(_ screen: Box) -> Box {
    Box(x: screen.x + padding.left, y: screen.y + padding.top,
      w: screen.w - padding.left - padding.right, h: screen.h - padding.top - padding.bottom)
  }

  /// The frame inside the box, each size clamped to it and an omitted one kept from the window's own,
  /// placed along each axis by the anchor, half where none is given and clamped to 0 through 1.
  public func frame(in box: Box, current: Box) -> Box {
    let w = Swift.min(width ?? current.w, box.w)
    let h = Swift.min(height ?? current.h, box.h)
    func anchor(_ v: Double?) -> Double { Swift.max(0, Swift.min(1, v ?? 0.5)) }
    return Box(x: box.x + (box.w - w) * anchor(atX), y: box.y + (box.h - h) * anchor(atY), w: w, h: h)
  }

  /// Where the window goes, from the display it stands on to the one placing chose, nil when that is
  /// where it is already. A size is the one asked, a percent of the display's visible frame where it
  /// is one, held between its least and its most, and then to the display less the padding, which
  /// wins over the least, so the window never reaches the display's edge. A window keeping where it
  /// stands keeps its place on its display, the same distance from the display's corner on another
  /// one, and is moved in only as far as it has to be to fit.
  public func place(current: Box, from: Box, to: Box) -> Box? {
    let area = box(to)
    func size(_ asked: Double?, _ full: Double, _ own: Double, _ least: Double?, _ most: Double?, _ room: Double) -> Double {
      var d = asked.map { percent ? full * $0 / 100 : $0 } ?? own
      if let least { d = Swift.max(d, least) }
      if let most { d = Swift.min(d, most) }
      return Swift.max(1, Swift.min(d, room))
    }
    let w = size(width, to.w, current.w, minWidth, maxWidth, area.w)
    let h = size(height, to.h, current.h, minHeight, maxHeight, area.h)
    var out: Box
    if anchored {
      func anchor(_ v: Double?) -> Double { Swift.max(0, Swift.min(1, v ?? 0.5)) }
      out = Box(x: area.x + (area.w - w) * anchor(atX), y: area.y + (area.h - h) * anchor(atY), w: w, h: h)
    } else {
      let moved = from != to
      var x = moved ? to.x + (current.x - from.x) : current.x
      var y = moved ? to.y + (current.y - from.y) : current.y
      if moved || w != current.w || h != current.h {
        x = Swift.min(Swift.max(x, area.x), area.x + area.w - w)
        y = Swift.min(Swift.max(y, area.y), area.y + area.h - h)
      }
      out = Box(x: x, y: y, w: w, h: h)
    }
    let near = abs(out.x - current.x) < 1 && abs(out.y - current.y) < 1 && abs(out.w - current.w) < 1
      && abs(out.h - current.h) < 1
    return near ? nil : out
  }
}

/// The screen a window stands on, the one its frame overlaps most, as hs.window:screen() picks.
public func screenOf(_ window: Box, among screens: [Box]) -> Box? {
  func overlap(_ s: Box) -> Double {
    let w = Swift.min(window.x + window.w, s.x + s.w) - Swift.max(window.x, s.x)
    let h = Swift.min(window.y + window.h, s.y + s.h) - Swift.max(window.y, s.y)
    return w > 0 && h > 0 ? w * h : 0
  }
  let best = screens.max { overlap($0) < overlap($1) }
  return best.flatMap { overlap($0) > 0 ? $0 : nil } ?? screens.first
}
