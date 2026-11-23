// Where a window action puts the focused window, deciding and changing nothing, step 6.3 of
// docs/PLAN-STANDALONE.md. A port of plugins/windowmanager/plan.lua rule for rule, checked against
// test/fixtures/windows/plan.json, which is recorded from the Lua, so the app places a window exactly
// where Hammerspoon would. Every coordinate is Hammerspoon's, the top left of the main screen at
// zero and y growing down, the space Accessibility answers a window's position in.

import Foundation

public struct WindowRect: Sendable, Equatable {
  public var x: Double, y: Double, w: Double, h: Double
  public init(x: Double, y: Double, w: Double, h: Double) {
    self.x = x
    self.y = y
    self.w = w
    self.h = h
  }
}

/// A screen by its uuid and its visible frame, below the menu bar and beside the Dock.
public struct WindowScreen: Sendable, Equatable {
  public var uuid: String
  public var frame: WindowRect
  /// The Mac's own panel, which a named size may ask for.
  public var builtin: Bool
  public init(uuid: String, frame: WindowRect, builtin: Bool = false) {
    self.uuid = uuid
    self.frame = frame
    self.builtin = builtin
  }
}

/// A named size, plan.lua's s.named: points or a percent of the canvas, an anchor and a display.
public struct WindowNamedSize: Sendable, Equatable {
  public var width: Double, height: Double
  public var percent: Bool
  public var anchor: String
  public var display: String
  public init(width: Double, height: Double, percent: Bool = false, anchor: String = "center", display: String = "current") {
    self.width = width
    self.height = height
    self.percent = percent
    self.anchor = anchor
    self.display = display
  }
}

public struct WindowMargins: Sendable, Equatable {
  public var top: Double, right: Double, bottom: Double, left: Double
  public init(top: Double = 0, right: Double = 0, bottom: Double = 0, left: Double = 0) {
    self.top = top
    self.right = right
    self.bottom = bottom
    self.left = left
  }
}

/// config/settings.lua's windowSizing block, each field nil where the file leaves it out.
public struct WindowSizing: Sendable, Equatable {
  public var maxWidth: Double?, maxHeight: Double?, fullHeightMaxWidth: Double?
  public var movePixels: Double?, movePixelsHeld: Double?, resizePixels: Double?, resizePixelsHeld: Double?
  public var holdGrace: Double?, minWidth: Double?, minHeight: Double?
  public var screenRecording: (width: Double?, height: Double?)?
  public var smallSize: (width: Double?, height: Double?)?
  public init() {}

  public static func == (a: WindowSizing, b: WindowSizing) -> Bool {
    a.maxWidth == b.maxWidth && a.maxHeight == b.maxHeight && a.fullHeightMaxWidth == b.fullHeightMaxWidth
      && a.movePixels == b.movePixels && a.movePixelsHeld == b.movePixelsHeld && a.resizePixels == b.resizePixels
      && a.resizePixelsHeld == b.resizePixelsHeld && a.holdGrace == b.holdGrace && a.minWidth == b.minWidth
      && a.minHeight == b.minHeight && a.screenRecording?.width == b.screenRecording?.width
      && a.screenRecording?.height == b.screenRecording?.height && a.smallSize?.width == b.smallSize?.width
      && a.smallSize?.height == b.smallSize?.height
  }
}

/// What an action reads, plan.lua's s.
public struct WindowInput: Sendable {
  public var window: WindowRect?
  public var id: UInt32?
  public var screen: String?
  public var screens: [WindowScreen] = []
  public var margins = WindowMargins()
  public var gap: Double = 0
  public var sizing = WindowSizing()
  public var depth: Int = 0
  public var size: (width: Double, height: Double)?
  public var target: String?
  public var named: WindowNamedSize?
  public var pointer: (x: Double, y: Double)?
  public var memory: [String: WindowRect] = [:]
  public init() {}
}

public struct WindowResult: Sendable, Equatable {
  public var frame: WindowRect
  /// The screen it lands on, given for a move between screens.
  public var screen: String?
  /// The frame the window leaves a screen with, for the memory.
  public var remember: (screen: String, frame: WindowRect)?
  /// Whether the write is read back and retried on a miss.
  public var verify: Bool

  public init(frame: WindowRect, screen: String? = nil, remember: (screen: String, frame: WindowRect)? = nil, verify: Bool = false) {
    self.frame = frame
    self.screen = screen
    self.remember = remember
    self.verify = verify
  }

  public static func == (a: WindowResult, b: WindowResult) -> Bool {
    a.frame == b.frame && a.screen == b.screen && a.verify == b.verify
      && a.remember?.screen == b.remember?.screen && a.remember?.frame == b.remember?.frame
  }
}

public enum WindowPlan {
  /// plan.lua's clampBetween, the two bounds taken in either order.
  static func clamp(_ value: Double, _ a: Double, _ b: Double) -> Double {
    min(max(value, min(a, b)), max(a, b))
  }

  /// A screen's canvas, its visible frame less the margins.
  public static func canvas(_ f: WindowRect, _ m: WindowMargins) -> WindowRect {
    WindowRect(x: f.x + m.left, y: f.y + m.top, w: f.w - m.left - m.right, h: f.h - m.top - m.bottom)
  }

  static func holdStep(_ sizing: WindowSizing, _ press: Double, _ held: Double, _ depth: Int) -> Double {
    Double(depth) < (sizing.holdGrace ?? 1) ? press : held
  }

  public static func moveStep(_ sizing: WindowSizing, _ depth: Int) -> Double {
    let press = sizing.movePixels ?? 20
    return holdStep(sizing, press, sizing.movePixelsHeld ?? press * 2, depth)
  }

  public static func resizeStep(_ sizing: WindowSizing, _ depth: Int) -> Double {
    let press = sizing.resizePixels ?? 30
    return holdStep(sizing, press, sizing.resizePixelsHeld ?? press + 20, depth)
  }

  // To whole pixels by an even number, half rounded away from zero as plan.lua rounds it.
  static func wholePair(_ value: Double) -> Double {
    let half = value / 2
    let rounded = half >= 0 ? (half + 0.5).rounded(.down) : -(-half + 0.5).rounded(.down)
    return rounded * 2
  }

  static func adjust(_ f: WindowRect, _ c: WindowRect, _ sizing: WindowSizing, _ amount: Double) -> WindowRect? {
    let longest = max(c.w, c.h)
    let shareW = longest > 0 ? c.w / longest : 1
    let shareH = longest > 0 ? c.h / longest : 1
    var amountW = wholePair(amount * shareW), amountH = wholePair(amount * shareH)
    if amount < 0 {
      amountW = -min(-amountW, max(0, f.w - (sizing.minWidth ?? 400)))
      amountH = -min(-amountH, max(0, f.h - (sizing.minHeight ?? 300)))
      if amountW == 0 && amountH == 0 { return nil }
    }
    let roomLeft = max(0, f.x - c.x)
    let roomRight = max(0, (c.x + c.w) - (f.x + f.w))
    let roomTop = max(0, f.y - c.y)
    let roomBottom = max(0, (c.y + c.h) - (f.y + f.h))
    var left = min(amountW / 2, roomLeft), right = min(amountW / 2, roomRight)
    var top = min(amountH / 2, roomTop), bottom = min(amountH / 2, roomBottom)
    let newLeft = f.x - left
    if newLeft < c.x {
      right += c.x - newLeft
      left = f.x - c.x
    }
    let newTop = f.y - top
    if newTop < c.y {
      bottom += c.y - newTop
      top = f.y - c.y
    }
    return WindowRect(x: f.x - left, y: f.y - top, w: f.w + left + right, h: f.h + top + bottom)
  }

  static func move(_ frame: WindowRect, _ c: WindowRect, _ direction: String, _ pixels: Double) -> WindowRect {
    var f = frame
    switch direction {
    case "left", "right":
      f.x += direction == "right" ? pixels : -pixels
      f.x = clamp(f.x, c.x, c.x + c.w - f.w)
    default:
      f.y += direction == "down" ? pixels : -pixels
      f.y = clamp(f.y, c.y, c.y + c.h - f.h)
    }
    return f
  }

  static func sized(_ f: WindowRect, _ width: Double?, _ height: Double?) -> WindowRect {
    let w = min(width ?? f.w, f.w), h = min(height ?? f.h, f.h)
    return WindowRect(x: f.x + (f.w - w) / 2, y: f.y + (f.h - h) / 2, w: w, h: h)
  }

  static func place(_ s: WindowInput, _ frame: WindowRect, _ source: WindowScreen, _ target: WindowScreen) -> WindowResult {
    let remember = s.id != nil ? (screen: source.uuid, frame: frame) : nil
    let tc = canvas(target.frame, s.margins)
    if s.id != nil, let r = s.memory[target.uuid],
      r.x >= tc.x, r.y >= tc.y, r.x + r.w <= tc.x + tc.w, r.y + r.h <= tc.y + tc.h {
      return WindowResult(frame: WindowRect(x: r.x.rounded(.down), y: r.y.rounded(.down), w: r.w.rounded(.down), h: r.h.rounded(.down)),
        screen: target.uuid, remember: remember, verify: true)
    }
    let sc = canvas(source.frame, s.margins)
    let newW = min(frame.w, tc.w), newH = min(frame.h, tc.h)
    let cx = sc.w > 0 ? (frame.x + frame.w / 2 - sc.x) / sc.w : 0.5
    let cy = sc.h > 0 ? (frame.y + frame.h / 2 - sc.y) / sc.h : 0.5
    let x = clamp(tc.x + cx * tc.w - newW / 2, tc.x, tc.x + tc.w - newW)
    let y = clamp(tc.y + cy * tc.h - newH / 2, tc.y, tc.y + tc.h - newH)
    return WindowResult(frame: WindowRect(x: x.rounded(.down), y: y.rounded(.down), w: newW.rounded(.down), h: newH.rounded(.down)),
      screen: target.uuid, remember: remember, verify: true)
  }

  static let moves = ["moveLeft": "left", "moveRight": "right", "moveUp": "up", "moveDown": "down"]

  /// plan.lua's ANCHORS, each a fraction across and down the room a named size leaves.
  public static let anchors: [String: (Double, Double)] = [
    "topLeft": (0, 0), "top": (0.5, 0), "topRight": (1, 0), "left": (0, 0.5), "center": (0.5, 0.5),
    "right": (1, 0.5), "bottomLeft": (0, 1), "bottom": (0.5, 1), "bottomRight": (1, 1),
  ]

  /// plan.lua's displayFor, the screen a named size lands on, the window's own when the one asked for
  /// is not there.
  static func display(_ s: WindowInput, _ current: WindowScreen, _ choice: String) -> WindowScreen {
    for screen in s.screens {
      if choice == "builtin" && screen.builtin { return screen }
      if choice == "external" && !screen.builtin { return screen }
      if choice == "pointer", let p = s.pointer {
        let f = screen.frame
        if p.x >= f.x && p.x < f.x + f.w && p.y >= f.y && p.y < f.y + f.h { return screen }
      }
    }
    return current
  }

  /// plan.lua's named, a named size stood at its anchor on its screen.
  static func named(_ s: WindowInput, _ f: WindowRect, _ screen: WindowScreen) -> WindowResult? {
    guard let z = s.named, z.width > 0, z.height > 0 else { return nil }
    let target = display(s, screen, z.display)
    let c = canvas(target.frame, s.margins)
    var w = z.width, h = z.height
    if z.percent { w = c.w * w / 100; h = c.h * h / 100 }
    w = min(w, c.w); h = min(h, c.h)
    let a = anchors[z.anchor] ?? (0.5, 0.5)
    var result = WindowResult(frame: WindowRect(x: c.x + (c.w - w) * a.0, y: c.y + (c.h - h) * a.1, w: w, h: h))
    if target.uuid != screen.uuid {
      result.screen = target.uuid
      result.remember = s.id != nil ? (screen: screen.uuid, frame: f) : nil
      result.verify = true
    }
    return result
  }

  /// plan.lua's LAYOUTS, a grid of columns and rows and its tiles in order, each a column, a row and
  /// the columns and rows it spans, all from zero.
  public struct Layout: Sendable {
    public let columns: Int, rows: Int
    public let tiles: [(Int, Int, Int, Int)]
  }

  public static let layouts: [String: Layout] = [
    "cycleHalves": Layout(columns: 2, rows: 1, tiles: [(0, 0, 1, 1), (1, 0, 1, 1)]),
    "cycleHalvesStacked": Layout(columns: 1, rows: 2, tiles: [(0, 0, 1, 1), (0, 1, 1, 1)]),
    "cycleThirds": Layout(columns: 3, rows: 1, tiles: [(0, 0, 1, 1), (1, 0, 1, 1), (2, 0, 1, 1)]),
    "cycleTwoThirds": Layout(columns: 3, rows: 1, tiles: [(0, 0, 2, 1), (1, 0, 2, 1)]),
    "cycleFourths": Layout(columns: 4, rows: 1, tiles: [(0, 0, 1, 1), (1, 0, 1, 1), (2, 0, 1, 1), (3, 0, 1, 1)]),
    "cycleQuarters": Layout(columns: 2, rows: 2, tiles: [(0, 0, 1, 1), (1, 0, 1, 1), (0, 1, 1, 1), (1, 1, 1, 1)]),
  ]

  /// plan.lua's tile, a tile's frame in a canvas with the gap between every two columns and rows.
  public static func tile(_ c: WindowRect, _ layout: Layout, _ t: (Int, Int, Int, Int), _ gap: Double) -> WindowRect {
    let cw = (c.w - gap * Double(layout.columns - 1)) / Double(layout.columns)
    let ch = (c.h - gap * Double(layout.rows - 1)) / Double(layout.rows)
    return WindowRect(x: c.x + Double(t.0) * (cw + gap), y: c.y + Double(t.1) * (ch + gap),
      w: Double(t.2) * cw + Double(t.2 - 1) * gap, h: Double(t.3) * ch + Double(t.3 - 1) * gap)
  }

  /// plan.lua's cycle, the tile after the one the window stands on, the first when it stands on none.
  static func cycle(_ layout: Layout, _ c: WindowRect, _ f: WindowRect, _ gap: Double) -> WindowRect {
    let at = layout.tiles.firstIndex { t in
      let r = tile(c, layout, t, gap)
      return abs(f.x - r.x) <= 4 && abs(f.y - r.y) <= 4 && abs(f.w - r.w) <= 24 && abs(f.h - r.h) <= 24
    }
    return tile(c, layout, layout.tiles[at.map { ($0 + 1) % layout.tiles.count } ?? 0], gap)
  }

  /// plan.lua's plan, nil where the action does nothing now.
  public static func plan(_ action: String, _ s: WindowInput) -> WindowResult? {
    guard let window = s.window, let index = s.screens.firstIndex(where: { $0.uuid == s.screen }) else { return nil }
    let screen = s.screens[index]
    let sizing = s.sizing
    let c = canvas(screen.frame, s.margins)
    var f = window
    switch action {
    case "maximize":
      return WindowResult(frame: c)
    case "center":
      f.x = c.x + (c.w - f.w) / 2
      f.y = c.y + (c.h - f.h) / 2
      return WindowResult(frame: f)
    case "fullHeightReasonableWidth":
      f.h = c.h
      f.w = min(c.w - 140, sizing.fullHeightMaxWidth ?? 2400)
      f.x = c.x + (c.w - f.w) / 2
      f.y = c.y
      return WindowResult(frame: f)
    case "fullHeight":
      f.h = c.h
      f.y = c.y
      return WindowResult(frame: f)
    case "reasonableSize":
      let w = min(sizing.maxWidth ?? 1800, c.w - 80), h = min(sizing.maxHeight ?? 1200, c.h - 80)
      return WindowResult(frame: WindowRect(x: c.x + (c.w - w) / 2, y: c.y + (c.h - h) / 2, w: w, h: h))
    case "leftHalf":
      return WindowResult(frame: WindowRect(x: c.x, y: c.y, w: (c.w - s.gap) / 2, h: c.h))
    case "rightHalf":
      return WindowResult(frame: WindowRect(x: c.x + (c.w + s.gap) / 2, y: c.y, w: (c.w - s.gap) / 2, h: c.h))
    case _ where layouts[action] != nil:
      return WindowResult(frame: cycle(layouts[action]!, c, f, s.gap))
    case "increaseSize", "decreaseSize":
      let step = resizeStep(sizing, s.depth)
      return adjust(f, c, sizing, action == "increaseSize" ? step : -step).map { WindowResult(frame: $0) }
    case "namedSize":
      return named(s, f, screen)
    case "exactSize":
      guard let size = s.size else { return nil }
      return WindowResult(frame: sized(screen.frame, size.width, size.height))
    case "nextDisplay", "previousDisplay":
      // hs.screen's next and previous, wrapping, a single screen placing the window back onto itself.
      // Lua's modulo floors, so the previous of the first is the last, which Swift's % would not give.
      let n = s.screens.count
      let to = action == "nextDisplay" ? (index + 1) % n : ((index - 1) % n + n) % n
      return place(s, f, screen, s.screens[to])
    case "toScreen":
      guard let target = s.screens.first(where: { $0.uuid == s.target }) else { return nil }
      return place(s, f, screen, target)
    default:
      if let direction = moves[action] { return WindowResult(frame: move(f, c, direction, moveStep(sizing, s.depth))) }
      return nil
    }
  }
}

// MARK: Read from JSON, as the fixtures record a case and as Hammerspoon reports a press

extension WindowRect {
  /// { x, y, w, h } as Foundation answers JSON, nil for anything else.
  public init?(json any: Any?) {
    guard let o = any as? [String: Any] else { return nil }
    func n(_ k: String) -> Double { (o[k] as? NSNumber)?.doubleValue ?? 0 }
    self.init(x: n("x"), y: n("y"), w: n("w"), h: n("h"))
  }
}

extension WindowInput {
  /// plan.lua's s as Foundation answers JSON.
  public init(json o: [String: Any]) {
    self.init()
    window = WindowRect(json: o["window"])
    id = (o["id"] as? NSNumber).map { UInt32(truncating: $0) }
    screen = o["screen"] as? String
    screens = (o["screens"] as? [[String: Any]] ?? []).compactMap { sc in
      guard let uuid = sc["uuid"] as? String, let f = WindowRect(json: sc["frame"]) else { return nil }
      return WindowScreen(uuid: uuid, frame: f, builtin: sc["builtin"] as? Bool ?? false)
    }
    if let z = o["named"] as? [String: Any] {
      named = WindowNamedSize(width: (z["width"] as? NSNumber)?.doubleValue ?? 0,
        height: (z["height"] as? NSNumber)?.doubleValue ?? 0, percent: z["unit"] as? String == "percent",
        anchor: z["anchor"] as? String ?? "center", display: z["display"] as? String ?? "current")
    }
    if let p = o["pointer"] as? [String: Any], let x = p["x"] as? NSNumber, let y = p["y"] as? NSNumber {
      pointer = (x.doubleValue, y.doubleValue)
    }
    if let m = o["margins"] as? [String: Any] {
      func n(_ k: String) -> Double { (m[k] as? NSNumber)?.doubleValue ?? 0 }
      margins = WindowMargins(top: n("top"), right: n("right"), bottom: n("bottom"), left: n("left"))
    }
    gap = (o["gap"] as? NSNumber)?.doubleValue ?? 0
    if let z = o["sizing"] as? [String: Any] {
      func n(_ k: String) -> Double? { (z[k] as? NSNumber)?.doubleValue }
      func pair(_ k: String) -> (width: Double?, height: Double?)? {
        guard let p = z[k] as? [String: Any] else { return nil }
        return ((p["width"] as? NSNumber)?.doubleValue, (p["height"] as? NSNumber)?.doubleValue)
      }
      sizing.maxWidth = n("maxWidth"); sizing.maxHeight = n("maxHeight")
      sizing.fullHeightMaxWidth = n("fullHeightMaxWidth")
      sizing.movePixels = n("movePixels"); sizing.movePixelsHeld = n("movePixelsHeld")
      sizing.resizePixels = n("resizePixels"); sizing.resizePixelsHeld = n("resizePixelsHeld")
      sizing.holdGrace = n("holdGrace"); sizing.minWidth = n("minWidth"); sizing.minHeight = n("minHeight")
      sizing.screenRecording = pair("screenRecording"); sizing.smallSize = pair("smallSize")
    }
    depth = (o["depth"] as? NSNumber)?.intValue ?? 0
    if let z = o["size"] as? [String: Any], let w = z["width"] as? NSNumber, let h = z["height"] as? NSNumber,
      !(z["width"] is String), !(z["height"] is String) {
      size = (w.doubleValue, h.doubleValue)
    }
    target = o["target"] as? String
    for (uuid, f) in o["memory"] as? [String: Any] ?? [:] { if let r = WindowRect(json: f) { memory[uuid] = r } }
  }
}

extension WindowResult {
  /// plan.lua's result as Foundation answers JSON, nil without a frame.
  public init?(json o: [String: Any]) {
    guard let frame = WindowRect(json: o["frame"]) else { return nil }
    let r = o["remember"] as? [String: Any]
    let remember = (r?["screen"] as? String).flatMap { s in WindowRect(json: r?["frame"]).map { (screen: s, frame: $0) } }
    self.init(frame: frame, screen: o["screen"] as? String, remember: remember, verify: o["verify"] as? Bool ?? false)
  }
}

// MARK: The settings the app holds, Olm's own, step 6.3b

/// The margins, gap and sizing a plan reads, from Olm's settings, by each setting's key in the window
/// manager's manifest, movePixels, gap, smallWidth. A key not given takes plan.lua's own default.
public struct WindowSettings: Sendable {
  public var margins = WindowMargins()
  public var gap: Double = 0
  public var sizing = WindowSizing()
  /// The named sizes by the action each is, smallSize for Small.
  public var sizes: [String: WindowNamedSize] = [:]
  public init() {}

  public init(values v: [String: Double]) {
    self.init()
    gap = v["gap"] ?? 0
    margins = WindowMargins(top: gap, right: gap, bottom: gap, left: gap)
    sizing.maxWidth = v["maxWidth"]; sizing.maxHeight = v["maxHeight"]
    sizing.fullHeightMaxWidth = v["fullHeightMaxWidth"]
    sizing.movePixels = v["movePixels"]; sizing.movePixelsHeld = v["movePixelsHeld"]
    sizing.resizePixels = v["resizePixels"]; sizing.resizePixelsHeld = v["resizePixelsHeld"]
    sizing.holdGrace = v["holdGrace"]; sizing.minWidth = v["minWidth"]; sizing.minHeight = v["minHeight"]
    if v["smallWidth"] != nil || v["smallHeight"] != nil { sizing.smallSize = (v["smallWidth"], v["smallHeight"]) }
    if v["recordingWidth"] != nil || v["recordingHeight"] != nil {
      sizing.screenRecording = (v["recordingWidth"], v["recordingHeight"])
    }
  }
}
