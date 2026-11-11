// The preview pane on screen, step 1.4a of docs/PLAN-STANDALONE.md. It owns the swift chooser's own
// pane view, PanePanel in lib/chooser/providers/swift/native/Pane.swift, the one Hammerspoon's file
// search draws in, so the pane stands in the chooser panel's own window on the same glass and
// scrolls natively, and it hands that view what PanePainter laid out, the way
// lib/chooser/providers/swift/pane.lua hands it the Lua layout's elements. The pane finds the
// panel it is drawn into by the preview pane rect the panel was placed with, as Entry.swift's seam
// does for Hammerspoon.
//
// Main thread only, and it does no layout, only the drawing the layout answered.

import AppKit
@preconcurrency @testable import OlmChooser

@MainActor
final class PaneHost {
  private let pane: PanePanel
  // The system's spinning indicator, centred on the pane while a picture is being drawn, floating
  // over the scrolled content so it stays put, asked for in the 1.4b trial on 2026-11-09 in place
  // of the word rendering.
  private let spinner: NSProgressIndicator = {
    let spinner = NSProgressIndicator()
    spinner.style = .spinning
    spinner.controlSize = .regular
    spinner.isIndeterminate = true
    spinner.isDisplayedWhenStopped = false
    spinner.sizeToFit()
    spinner.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
    return spinner
  }()

  init(panel: ChooserPanel) {
    pane = PanePanel(findHost: { [weak panel] rect in
      guard let panel, panel.hostsPane(at: rect) else { return nil }
      return panel
    })
    pane.hostedView.addFloatingSubview(spinner, for: .vertical)
  }

  /// Onto the preview pane rect, in Hammerspoon's space.
  func place(_ rect: NSRect) { pane.place(rect) }

  /// Draws a laid out pane and shows it, back at the top when reset says the content changed, or
  /// where it is scrolled for a repaint of the same row, a picture landing.
  /// busy spins the system's indicator in the pane's centre, for a preview still on its way.
  func draw(_ paint: PanePaint, radius: CGFloat, reset: Bool, busy: Bool = false) {
    pane.draw(paint.items.map(Self.element), radius: radius,
      scroll: PaneScroll(height: CGFloat(paint.height), reset: reset, thumb: false))
    pane.show()
    if busy {
      let bounds = pane.hostedView.bounds
      let size = spinner.frame.size
      spinner.setFrameOrigin(NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
      spinner.startAnimation(nil)
    } else {
      spinner.stopAnimation(nil)
    }
  }

  /// Further down by points, answering whether the view moved.
  @discardableResult
  func scrollBy(_ points: CGFloat) -> Bool { pane.scrollBy(points) }

  /// Out of the chooser's window, on hide, as the Lua pane is destroyed when its list closes.
  func close() {
    spinner.stopAnimation(nil)
    pane.close()
  }

  // One laid out element as the pane view draws it, the hs.canvas element PaneReader would read.
  static func element(_ item: PaneItem) -> PaneElement {
    switch item {
    case .clip(let r, let radius):
      let rect = NSRect(x: r.x, y: r.y, width: r.w, height: r.h)
      return .shape(path: NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius), fill: nil, stroke: nil,
        clip: true)
    case .resetClip:
      return .resetClip
    case .text(let t):
      return .text(attributed(t), NSRect(x: t.frame.x, y: t.frame.y, width: t.frame.w, height: t.frame.h))
    case .fill(let r, let radius, let c):
      let rect = NSRect(x: r.x, y: r.y, width: r.w, height: r.h)
      return .shape(path: NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius),
        fill: NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha), stroke: nil, clip: false)
    case .image(let img, let r, let alpha):
      // The frame already holds the picture's aspect, imageFit's, so scaleProportionally at the top
      // left draws it to the frame, as PaneReader reads the Lua element.
      return .image(img.image ?? NSImage(), NSRect(x: r.x, y: r.y, width: r.w, height: r.h), CGFloat(alpha))
    }
  }

  // What hs.styledtext.new builds from layout.lua's textElement, the font, the colour and a
  // paragraph with the line height pinned both ways.
  static func attributed(_ t: PaneText) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    switch t.align {
    case "right": paragraph.alignment = .right
    case "center": paragraph.alignment = .center
    case "justified": paragraph.alignment = .justified
    default: paragraph.alignment = .left
    }
    switch t.lineBreak {
    case "charWrap": paragraph.lineBreakMode = .byCharWrapping
    case "clip": paragraph.lineBreakMode = .byClipping
    case "truncateHead": paragraph.lineBreakMode = .byTruncatingHead
    case "truncateTail": paragraph.lineBreakMode = .byTruncatingTail
    case "truncateMiddle": paragraph.lineBreakMode = .byTruncatingMiddle
    default: paragraph.lineBreakMode = .byWordWrapping
    }
    paragraph.minimumLineHeight = CGFloat(t.lineHeight)
    paragraph.maximumLineHeight = CGFloat(t.lineHeight)
    if t.tight { paragraph.tighteningFactorForTruncation = 0 }
    let c = t.color
    return NSAttributedString(string: t.string, attributes: [
      .font: fontOf(name: t.font, size: CGFloat(t.size)),
      .foregroundColor: NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha),
      .paragraphStyle: paragraph,
    ])
  }
}
