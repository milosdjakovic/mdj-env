// Where a chooser stands on a screen, a port of lib/chooser/providers/default/geometry.lua's resolve,
// so Olm.app places its list exactly where the swift chooser places it. The swift chooser's own
// layout is handed over by the bridge in `~/.olm/run/chooser.json`, and this answers the rectangles
// for whichever screen the app opens on, in Hammerspoon's space, y measured down from the top of the
// primary screen, which is what the panel is placed in. test/fixtures/chooser/geometry.json pins it,
// run by olm-fixtures. The arithmetic is the Lua's, step for step and in the same order, since a
// double added in another order can differ in its last bit and the fixtures compare exactly.

import Foundation

public struct LayoutRect: Equatable {
  public var x, y, w, h: Double
  // How much of a preview pane's bottom a spanning bottom bar covers, nil when none does.
  public var under: Double?

  public init(x: Double, y: Double, w: Double, h: Double, under: Double? = nil) {
    self.x = x
    self.y = y
    self.w = w
    self.h = h
    self.under = under
  }
}

// The fields of the engine's layout resolve reads, each the Lua's default when it is missing.
public struct ChooserLayout {
  public var width = 480.0
  public var baseH = 57.0
  public var rowH = 47.0
  public var rowCount = 9.0
  public var peek = 0.3
  public var marginX = 14.0
  public var marginY = 10.0
  public var bottomBarH = 0.0
  public var bottomBarSpan = false
  public var gap = 12.0
  public var topFrac = 0.06
  public var minVPad = 60.0
  public var paneMaxW = 480.0
  /// A row's icon and the room either side of its text, and the shortcut column, nil to take the
  /// icon's size, which textBudget reads.
  public var iconSize = 33.0
  public var iconGap = 14.0
  public var padX = 14.0
  public var numW: Double?

  public init() {}

  // The layout as JSON carries it, a number field read only when it is a number and not a boolean.
  public init(_ object: [String: Any]) {
    func number(_ name: String) -> Double? {
      guard let n = object[name] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
      return n.doubleValue
    }
    width = number("width") ?? width
    baseH = number("baseH") ?? baseH
    rowH = number("rowH") ?? rowH
    rowCount = number("rowCount") ?? rowCount
    peek = number("peek") ?? peek
    marginX = number("marginX") ?? marginX
    marginY = number("marginY") ?? marginY
    bottomBarH = number("bottomBarH") ?? bottomBarH
    gap = number("gap") ?? gap
    topFrac = number("topFrac") ?? topFrac
    minVPad = number("minVPad") ?? minVPad
    // The Lua's paneMaxW follows width when nothing sets it.
    paneMaxW = number("paneMaxW") ?? width
    iconSize = number("iconSize") ?? iconSize
    iconGap = number("iconGap") ?? iconGap
    padX = number("padX") ?? padX
    numW = number("numW")
    if let n = object["bottomBarSpan"] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() {
      bottomBarSpan = n.boolValue
    }
  }
}

// A preview pane's width as a presentation asks for one, as wide as the list, a width in points,
// or none, which is also what zero or a negative width means.
public enum PreviewPaneWidth {
  case none
  case list
  case points(Double)
}

public struct ChooserRects: Equatable {
  public var canvas, field, list: LayoutRect
  public var previewPane, bottomBar: LayoutRect?
  public var rowCount: Double
  public var viewRows: Double
}

public enum Geometry {
  // The row count trimmed to what the screen holds, never more than the layout asked for.
  static func trimmedRowCount(_ screen: LayoutRect, _ layout: ChooserLayout) -> Double {
    let avail = screen.h - 2 * layout.minVPad - layout.baseH - layout.marginY
      - layout.bottomBarH - layout.peek * layout.rowH
    let fit = (avail / layout.rowH).rounded(.down)
    return max(0, min(layout.rowCount, fit))
  }

  static func previewPaneWidth(_ width: PreviewPaneWidth, _ canvasWidth: Double, _ layout: ChooserLayout) -> Double {
    let w: Double
    switch width {
    case .none: return 0
    case .list: w = canvasWidth
    case .points(let points): w = points
    }
    if w <= 0 { return 0 }
    return min(w, layout.paneMaxW)
  }

  // The top fraction down the screen, never closer than the pad to either edge, the top pad
  // winning when the surface is too tall to keep both.
  static func topBiasedY(_ screen: LayoutRect, _ layout: ChooserLayout, _ canvasHeight: Double) -> Double {
    let lo = screen.y + layout.minVPad
    let hi = screen.y + screen.h - layout.minVPad - canvasHeight
    if hi < lo { return lo }
    let wanted = screen.y + (screen.h * layout.topFrac).rounded(.down)
    if wanted < lo { return lo }
    if wanted > hi { return hi }
    return wanted
  }

  /// geometry.lua's textBudget, the room a row's text has, the list's width less the icon's left
  /// pad, the icon and its gap, the trailing pad and the shortcut column.
  public static func textBudget(_ rects: ChooserRects, layout: ChooserLayout) -> Double {
    let (_, padLeft) = iconPad(rowH: layout.rowH, iconSize: layout.iconSize)
    let budget = rects.list.w - padLeft - layout.iconSize - layout.iconGap - layout.padX
      - (layout.numW ?? layout.iconSize)
    return max(0, budget)
  }

  public static func resolve(screen: LayoutRect, layout: ChooserLayout, previewPaneWidth: PreviewPaneWidth = .none) -> ChooserRects {
    let rowCount = trimmedRowCount(screen, layout)
    let viewRows = rowCount + (rowCount > 1 ? layout.peek : 0)
    let canvasW = layout.width
    let bottomBarH = layout.bottomBarH
    let canvasH = layout.marginY + layout.baseH + viewRows * layout.rowH + bottomBarH

    let paneW = Self.previewPaneWidth(previewPaneWidth, canvasW, layout)
    let total = canvasW + (paneW > 0 ? (layout.gap + paneW) : 0)
    let x = screen.x + ((screen.w - total) / 2).rounded(.down)
    let y = topBiasedY(screen, layout, canvasH)

    let canvas = LayoutRect(x: x, y: y, w: canvasW, h: canvasH)
    let field = LayoutRect(x: x + layout.marginX, y: y, w: canvasW - 2 * layout.marginX, h: layout.baseH)
    let list = LayoutRect(x: x + layout.marginX, y: y + layout.baseH,
      w: canvasW - 2 * layout.marginX, h: viewRows * layout.rowH + layout.marginY)
    let spans = layout.bottomBarSpan && paneW > 0 && bottomBarH > 0
    let bottomBar = bottomBarH > 0
      ? LayoutRect(x: x, y: y + canvasH - bottomBarH, w: spans ? total : canvasW, h: bottomBarH) : nil
    let previewPane = paneW > 0
      ? LayoutRect(x: x + canvasW + layout.gap, y: y, w: paneW, h: canvasH, under: spans ? bottomBarH : nil) : nil
    return ChooserRects(canvas: canvas, field: field, list: list, previewPane: previewPane,
      bottomBar: bottomBar, rowCount: rowCount, viewRows: viewRows)
  }

  // The room above and below a row's icon, and on its left, ICON_PAD_LEFT times the first.
  public static let iconPadLeft = 1.38

  public static func iconPad(rowH: Double, iconSize: Double) -> (Double, Double) {
    let pad = (rowH - iconSize) / 2
    return (pad, pad * iconPadLeft)
  }
}
