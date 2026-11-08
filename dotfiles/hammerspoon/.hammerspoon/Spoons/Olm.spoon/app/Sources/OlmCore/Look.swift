// How the app's chooser looks and where it stands, the swift chooser's own. The bridge writes
// `~/.olm/run/chooser.json` on every load where the olmapp piece is on, from the very tables the
// Lua view sends Hammerspoon's panel, look in lib/chooser/providers/swift/init.lua, so the style is
// read here through the same field list Hammerspoon's panel reads, Fields.swift, and the rectangles
// come from the port of the Lua geometry, OlmLook. Nothing about the look is written in Swift, so a
// change in config/settings.lua, the theme or the typography reaches the app on the next load.
//
// The file holds both halves, so the app follows the system's light and dark switch by itself.

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
    return Look(
      dark: Style(JSONFields(style["dark"])),
      light: Style(JSONFields(style["light"])),
      metrics: doc["metrics"] as? [String: Any] ?? [:],
      layout: ChooserLayout(layout),
      lineBreak: breaks[layout["titleLineBreak"] as? String ?? ""] ?? .byTruncatingTail
    )
  }

  // The half the system is on, as lib/ui/style.lua asks hs.host.interfaceStyle.
  func style() -> Style {
    let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    return dark ? self.dark : self.light
  }

  var showNumbers: Bool { JSONFields(metrics).bool("showNumbers") ?? false }

  // The placement the Lua view's place would hand the panel on this screen, with no preview pane,
  // the screen's frame less the menu bar and the Dock as hs.screen's frame is, in Hammerspoon's
  // space.
  func placement(on screen: NSScreen) -> Placement {
    let primary = NSScreen.screens.first?.frame.height ?? screen.frame.maxY
    let v = screen.visibleFrame
    let frame = LayoutRect(x: v.minX, y: primary - v.maxY, w: v.width, h: v.height)
    let r = Geometry.resolve(screen: frame, layout: layout)
    func fields(_ rect: LayoutRect?, from origin: LayoutRect? = nil) -> Any {
      guard let rect else { return NSNull() }
      let o = origin ?? LayoutRect(x: 0, y: 0, w: 0, h: 0)
      return ["x": rect.x - o.x, "y": rect.y - o.y, "w": rect.w, "h": rect.h]
    }
    var table = metrics
    table["canvas"] = fields(r.canvas)
    table["window"] = fields(r.canvas)
    table["listFrame"] = ["x": 0, "y": 0, "w": r.canvas.w, "h": r.canvas.h]
    table["field"] = fields(r.field, from: r.canvas)
    table["list"] = fields(r.list, from: r.canvas)
    table["bottomBar"] = fields(r.bottomBar, from: r.canvas)
    return Placement(JSONFields(table))
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
