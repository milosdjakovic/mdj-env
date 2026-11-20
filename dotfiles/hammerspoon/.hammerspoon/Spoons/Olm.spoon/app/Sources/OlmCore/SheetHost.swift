// A leader's cheat sheet drawn by Olm.app, step 5.2 of docs/PLAN-STANDALONE.md, docs/DESIGN-APP-KEYS.md.
// Hammerspoon still binds the keys, decides when a sheet shows and lays it out with lib/cheatsheet.lua,
// and lib/panel.lua hands what it drew to the bridge's sheet backend, which sends it here as the
// notification sheet. This puts it on screen through the swift chooser's own panel window,
// PanePanel with a panel's config, the window Hammerspoon's native backend draws a CanvasPanel in, so
// the sheet stands on the same glass at the same level with the same motion, and is never key.
//
// Main thread only.

import AppKit
@preconcurrency @testable import OlmChooser

@MainActor
public final class SheetHost {
  private var pane: PanePanel?
  private var unsupported: Set<String> = []

  public init() {}

  public var isShowing: Bool { pane?.isVisible ?? false }

  /// One sheet notification's params as Foundation answers them, a show with frame, radius and
  /// elements, or hide true.
  public func take(_ params: Any) {
    guard let o = params as? [String: Any] else { return }
    if o["hide"] as? Bool == true { return hide() }
    guard let f = o["frame"] as? [String: Any], let x = f["x"] as? Double, let y = f["y"] as? Double,
      let w = f["w"] as? Double, let h = f["h"] as? Double,
      let data = try? JSONSerialization.data(withJSONObject: o["elements"] ?? []) else { return }
    let (elements, missed) = PaneElements.read(data, size: NSSize(width: w, height: h))
    for kind in missed where !unsupported.contains(kind) {
      unsupported.insert(kind)
      NSLog("Olm: a cheat sheet element the app cannot draw was left out, %@", kind)
    }
    let pane = self.pane ?? PanePanel(findHost: { _ in nil }, config: PaneConfig(panel: true, level: .popUpMenu))
    self.pane = pane
    pane.place(NSRect(x: x, y: y, width: w, height: h))
    pane.draw(elements, radius: CGFloat(o["radius"] as? Double ?? 0),
      scroll: PaneScroll(height: CGFloat(h), reset: true, thumb: false))
    pane.show()
  }

  public func hide() { pane?.hide() }
}
