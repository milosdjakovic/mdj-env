// How the app's chooser looks and where it stands, the swift chooser's own. The bridge writes
// `~/.olm/run/chooser.json` on every load where the olmapp piece is on, from the very tables the
// Lua view sends Hammerspoon's panel, look in lib/chooser/providers/swift/init.lua, so the style is
// read here through the same field list Hammerspoon's panel reads, Fields.swift, and the rectangles
// come from the port of the Lua geometry, OlmLook. Nothing about the look is written in Swift, so a
// change in config/settings.lua, the theme or the typography reaches the app on the next load.
//
// The file holds both halves, so the app follows the system's light and dark switch by itself.
//
// A list whose manifest has a preview pane is placed with one as wide as the list, as the Lua
// presentation's previewPaneWidth answers true, so the window opens at its full width, and the
// window, the list's frame and the pane's region inside it are View colon place's, windowRects in
// lib/chooser/providers/swift/view.lua. The pane is laid out with the pane tokens the bridge wrote
// beside the style, step 1.4a.

import AppKit
@preconcurrency @testable import OlmChooser
import OlmLook

@MainActor
struct Look {
  let dark: Style
  let light: Style
  let metrics: [String: Any]
  let layout: ChooserLayout
  // lib/chooser/providers/default/geometry.lua's titleLineBreak, the engine's lineBreak.
  let lineBreak: NSLineBreakMode
  // What a preview pane is laid out with, each half's, nil in a look written before step 1.4a.
  let paneDark: PaneTokens?
  let paneLight: PaneTokens?

  static let path = FileManager.default.homeDirectoryForCurrentUser.path + "/.olm/run/chooser.json"

  // The look the bridge last wrote, or nil when there is none, a machine whose Hammerspoon has not
  // loaded with the piece on since the app was built. The motion is applied as it is read.
  static func read() -> Look? {
    guard let data = FileManager.default.contents(atPath: path),
      let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let style = doc["style"] as? [String: Any],
      let layout = doc["layout"] as? [String: Any]
    else { return nil }
    Motion.apply(JSONFields(doc["motion"]))
    let breaks: [String: NSLineBreakMode] = [
      "truncateTail": .byTruncatingTail, "truncateMiddle": .byTruncatingMiddle,
      "truncateHead": .byTruncatingHead, "clip": .byClipping,
    ]
    let pane = doc["pane"] as? [String: Any]
    return Look(
      dark: Style(JSONFields(style["dark"])),
      light: Style(JSONFields(style["light"])),
      metrics: doc["metrics"] as? [String: Any] ?? [:],
      layout: ChooserLayout(layout),
      lineBreak: breaks[layout["titleLineBreak"] as? String ?? ""] ?? .byTruncatingTail,
      paneDark: PaneTokens(pane?["dark"]),
      paneLight: PaneTokens(pane?["light"])
    )
  }

  private static var isDark: Bool {
    NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
  }

  // The half the system is on, as lib/ui/style.lua asks hs.host.interfaceStyle.
  func style() -> Style { Self.isDark ? dark : light }

  // The pane tokens of the same half, nil when the look carries none.
  func paneTokens() -> PaneTokens? { Self.isDark ? paneDark : paneLight }

  var showNumbers: Bool { JSONFields(metrics).bool("showNumbers") ?? false }

  // The placement the Lua view's place would hand the panel on this screen, with a preview pane
  // as wide as the list when pane is true, the screen's frame less the menu bar and the Dock as
  // hs.screen's frame is, in Hammerspoon's space. The pane's size goes with it, and how much of its
  // bottom the bar covers, which the pane's content is laid out above.
  func placement(on screen: NSScreen, pane: Bool = false) -> (Placement, PaneFrame?) {
    let primary = NSScreen.screens.first?.frame.height ?? screen.frame.maxY
    let v = screen.visibleFrame
    let frame = LayoutRect(x: v.minX, y: primary - v.maxY, w: v.width, h: v.height)
    let r = Geometry.resolve(screen: frame, layout: layout, previewPaneWidth: pane ? .list : .none)
    func fields(_ rect: LayoutRect?, from origin: LayoutRect? = nil) -> Any {
      guard let rect else { return NSNull() }
      let o = origin ?? LayoutRect(x: 0, y: 0, w: 0, h: 0)
      return ["x": rect.x - o.x, "y": rect.y - o.y, "w": rect.w, "h": rect.h]
    }
    var table = metrics
    table["canvas"] = fields(r.canvas)
    if let p = r.previewPane {
      // spanOf in view.lua, the canvas, the gap and the pane in one window.
      let x0 = min(r.canvas.x, p.x), y0 = min(r.canvas.y, p.y)
      let x1 = max(r.canvas.x + r.canvas.w, p.x + p.w), y1 = max(r.canvas.y + r.canvas.h, p.y + p.h)
      let window = LayoutRect(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
      table["window"] = fields(window)
      table["listFrame"] = fields(r.canvas, from: window)
      table["paneFrame"] = fields(p, from: window)
      table["previewPane"] = fields(p)
    } else {
      table["window"] = fields(r.canvas)
      table["listFrame"] = ["x": 0, "y": 0, "w": r.canvas.w, "h": r.canvas.h]
    }
    table["field"] = fields(r.field, from: r.canvas)
    table["list"] = fields(r.list, from: r.canvas)
    table["bottomBar"] = fields(r.bottomBar, from: r.canvas)
    let paneFrame = r.previewPane.map { PaneFrame(w: $0.w, h: $0.h, under: $0.under ?? 0) }
    return (Placement(JSONFields(table)), paneFrame)
  }

  // Only while no look has been written. A chooser 680 points wide a fifth of the way down the
  // screen under the pointer, in Hammerspoon's space, y measured down from the top of the primary
  // screen, which is what the panel is placed in. Eight rows show at once.
  static func fallback() -> Placement {
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let primary = NSScreen.screens.first?.frame.height ?? visible.maxY
    let width: CGFloat = 680
    let rowH: CGFloat = 44
    let height: CGFloat = 64 + rowH * 8 + 8
    let top = primary - visible.maxY + visible.height * 0.18
    var p = Placement()
    p.canvas = NSRect(x: visible.midX - width / 2, y: top, width: width, height: height)
    p.window = p.canvas
    p.listFrame = NSRect(x: 0, y: 0, width: width, height: height)
    p.field = NSRect(x: 20, y: 14, width: width - 40, height: 40)
    p.list = NSRect(x: 8, y: 64, width: width - 16, height: height - 72)
    p.rowH = rowH
    p.iconSize = 28
    p.iconFrame = 32
    p.iconPad = (rowH - 28) / 2
    p.iconPadLeft = 12
    p.iconGap = 10
    p.padX = 12
    p.pad = 8
    return p
  }

  // The screen the Lua chooser opens on for the placement choice the URL carries,
  // lib/overlaydisplay.lua. cursor is the screen under the pointer. activeWindow is the screen
  // holding most of the frontmost application's front window, as hs.window's screen answers,
  // found through the window list, which asks for no grant, and the main screen when there is none.
  static func screen(for mode: String?) -> NSScreen? {
    if mode == "cursor" {
      let mouse = NSEvent.mouseLocation
      return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.screens.first
    }
    guard let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
      let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]],
      let window = windows.first(where: {
        ($0[kCGWindowOwnerPID as String] as? pid_t) == front && ($0[kCGWindowLayer as String] as? Int) == 0
      }),
      let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
    else { return NSScreen.main ?? NSScreen.screens.first }
    // The window list measures from the top of the primary screen, as Hammerspoon does.
    let primary = NSScreen.screens.first?.frame.height ?? 0
    let rect = NSRect(x: bounds["X"] ?? 0, y: primary - (bounds["Y"] ?? 0) - (bounds["Height"] ?? 0),
      width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
    let best = NSScreen.screens.max { a, b in
      let ia = a.frame.intersection(rect), ib = b.frame.intersection(rect)
      return ia.width * ia.height < ib.width * ib.height
    }
    return best ?? NSScreen.main
  }
}
