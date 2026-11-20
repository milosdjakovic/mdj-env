// Where a placed window lands, a port of the app toggler's geometry, plugins/apptoggler/init.lua,
// step 6.2, docs/DESIGN-APP-APPS.md. Pure arithmetic on the screen's visible frame and the window's
// own, in the top left origin coordinates Accessibility and hs.screen:frame() both use.

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

/// One app's placement table, width and height in points, the padding and the fractional anchor.
public struct Placement: Sendable, Equatable {
  public var width: Double?
  public var height: Double?
  public var padding: Padding
  public var atX: Double?
  public var atY: Double?

  public init(width: Double? = nil, height: Double? = nil, padding: Padding = Padding(), atX: Double? = nil,
    atY: Double? = nil) {
    self.width = width
    self.height = height
    self.padding = padding
    self.atX = atX
    self.atY = atY
  }

  /// Read from the table appRun carries, its JSON as Foundation answers it, nil for anything else.
  public init?(_ json: Any?) {
    guard let o = json as? [String: Any] else { return nil }
    let at = o["at"] as? [String: Any]
    self.init(width: o["width"] as? Double, height: o["height"] as? Double, padding: Padding(o["padding"]),
      atX: at?["x"] as? Double, atY: at?["y"] as? Double)
  }

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
