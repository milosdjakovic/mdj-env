// What a preview pane draws for one Preview, step 1.4a of docs/PLAN-STANDALONE.md. The kit nodes
// are plugins/filesearch/viewers/sidepanel-nodes.lua's, the header over a body, and the painting is
// sidepanel.lua's paintRow under lib/previewpane.lua's native scroll, the path the swift chooser's
// pane takes. The header is laid out in the pane's padded box and clipped to it, the body below it
// is clipped from the header down to the inside of the pane's border, and the whole of it is laid
// out at its full height, the viewport grown by how far it overflows, so the native view scrolls
// the header with the body, as it does under the swift chooser. The empty state is
// lib/panel.lua's emptyStateElements, one centred caption a little above the middle.
//
// Every value is the tokens', so a plugin's Preview names roles alone. Pure and off the main
// thread, the elements are drawn by PaneHost.

import Foundation
import OlmKit

/// The preview pane rect's size, and how much of its bottom the chooser's bar floats over.
public struct PaneFrame: Equatable, Sendable {
  public var w, h, under: Double
  public init(w: Double, h: Double, under: Double = 0) {
    self.w = w
    self.h = h
    self.under = under
  }
}

/// A pane laid out, its elements in the pane's own space with the origin at its top left, and the
/// content's full height, the pane's own when it fits.
public struct PanePaint: Equatable, Sendable {
  public var items: [PaneItem]
  public var height: Double
}

public enum PanePainter {
  // sidepanel-nodes.lua's two gaps.
  static let gap = "m"
  static let headingGap = "xs"

  /// The shared empty state, one line of guidance.
  public static func empty(_ text: String, frame: PaneFrame, tokens: PaneTokens, measure: PaneMeasure) -> PanePaint {
    let engine = PaneLayoutEngine(T: tokens, measure: measure)
    let inner = innerBox(frame, tokens)
    let textH = tokens.role("caption").lineHeight
    let y = inner.h / 2 - textH
    let (items, _) = engine.layout(.text(text, "caption", align: "center", lineBreak: "wordWrap"),
      PaneRect(x: 0, y: y, w: inner.w, h: textH))
    return PanePaint(items: items.map { shifted($0, inner.x, inner.y) }, height: frame.h)
  }

  /// One row's preview, the header over the body, at the content's full height. image is the body's
  /// picture, read off the main thread by PanePicture, nil to draw its heading alone.
  public static func paint(_ preview: Preview, frame: PaneFrame, tokens: PaneTokens, measure: PaneMeasure,
                           image: PaneImage? = nil) -> PanePaint {
    let engine = PaneLayoutEngine(T: tokens, measure: measure)
    let inner = innerBox(frame, tokens)
    let (head, headH) = engine.layout(header(preview), inner, clip: true)
    let body = preview.body.map { self.body($0, inner.w, tokens, measure, image: image) }
    let bw = tokens.interiorInset
    let interior = PaneRect(x: bw, y: bw, w: frame.w - 2 * bw, h: frame.h - 2 * bw)

    func paintRow(_ grown: Double?) -> ([PaneItem], Double) {
      var items = head
      let bodyTop = inner.y + headH + (tokens.space[gap] ?? 0)
      let room = inner.y + inner.h - bodyTop
      guard let body, room > 0 else { return (items, 0) }
      let rect = PaneRect(x: inner.x, y: bodyTop, w: inner.w, h: room)
      let boxH = grown.map { interior.h + $0 } ?? interior.h
      let viewport = PaneRect(x: interior.x, y: bodyTop, w: interior.w, h: interior.y + boxH - bodyTop)
      let (content, bodyH) = engine.layout(body, rect, scrollY: 0, viewport: viewport)
      items.append(contentsOf: content)
      return (items, max(0, bodyH - room))
    }

    var (items, over) = paintRow(nil)
    let overflow = max(0, over)
    if overflow > 0 { (items, over) = paintRow(overflow) }
    return PanePaint(items: items, height: frame.h + overflow)
  }

  /// The width a body's picture is laid out in, so PanePicture decodes it at the size it is drawn.
  public static func bodyWidth(_ frame: PaneFrame, tokens: PaneTokens) -> Double { innerBox(frame, tokens).w }

  // pane.inner, the frame less the pad, and less the bar where it floats over the pane's bottom.
  static func innerBox(_ frame: PaneFrame, _ T: PaneTokens) -> PaneRect {
    PaneRect(x: T.pad, y: T.pad, w: frame.w - 2 * T.pad, h: frame.h - 2 * T.pad - frame.under)
  }

  private static func shifted(_ item: PaneItem, _ dx: Double, _ dy: Double) -> PaneItem {
    switch item {
    case .clip(let r, let radius): return .clip(PaneRect(x: r.x + dx, y: r.y + dy, w: r.w, h: r.h), radius: radius)
    case .resetClip: return .resetClip
    case .text(var t):
      t.frame = PaneRect(x: t.frame.x + dx, y: t.frame.y + dy, w: t.frame.w, h: t.frame.h)
      return .text(t)
    case .image(let img, let r, let alpha):
      return .image(img, PaneRect(x: r.x + dx, y: r.y + dy, w: r.w, h: r.h), alpha: alpha)
    }
  }

  // sidepanel-nodes.lua's header, the name, where it lives, then the facts.
  static func header(_ p: Preview) -> PaneNode {
    var identity: [PaneNode] = [.text(p.name, "title", color: "foreground")]
    if !p.dir.isEmpty { identity.append(.text(p.dir, "code", color: "subtext", wrap: true)) }
    let facts: [PaneNode] = p.facts.map { fact in
      .row([.text(fact.label, "caption", color: "subtext"),
            .text(fact.value, "caption", color: fact.color?.rawValue ?? "foreground", align: "right")],
           fillIndex: 2)
    }
    return .stack([.stack(identity, gap: headingGap), .stack(facts)], gap: gap)
  }

  // kit.heading, the label filling and the facts flush right.
  static func heading(_ label: String, _ facts: String?) -> PaneNode {
    guard let facts, !facts.isEmpty else { return .text(label, "section") }
    return .row([.text(label, "section"), .text(facts, "section", color: "subtext", align: "right")], fillIndex: 1)
  }

  // sidepanel-nodes.lua's remainderNote, what is left out in the units that are known.
  static func remainderNote(_ overLines: Int, _ shownBytes: Int, _ total: Int?, _ hasLines: Bool) -> String? {
    var parts: [String] = []
    if hasLines, overLines > 0 { parts.append("\(overLines) lines") }
    if let total, total > shownBytes { parts.append("\(total - shownBytes) characters") }
    if parts.isEmpty { return nil }
    return parts.joined(separator: ", ") + " more"
  }

  // sidepanel-nodes.lua's body, wrapped at w before the heading is written, so the heading can say
  // what the budget left out.
  static func body(_ b: Preview.Body, _ w: Double, _ T: PaneTokens, _ measure: PaneMeasure,
                   image: PaneImage? = nil) -> PaneNode {
    // A picture under its heading, as sidepanel-nodes.lua's body draws one.
    if let picture = b.picture {
      guard let image else { return heading(b.label, b.facts) }
      return .stack([heading(b.label, b.facts), .image(image, upscale: picture.upscale)], gap: headingGap)
    }
    var lines = b.lines
    if b.wrap {
      let code = T.role("code")
      lines = lines.flatMap { measure.wrap($0, code, w) }
    }
    var note: String?
    var shown = lines.count
    if let budget = b.budget, lines.count > budget + b.slack {
      var kept: [String] = []
      var bytes = 0
      for i in 0..<budget {
        kept.append(lines[i])
        bytes = bytes + lines[i].utf8.count + 1
      }
      let over = lines.count - budget
      shown = budget
      kept.append("...")
      lines = kept
      note = remainderNote(over, bytes, b.total, b.hasLines)
    }
    var facts = b.facts
    if note != nil, facts == nil { facts = "first \(shown) lines" }
    let head = heading(b.label, facts)
    if lines.isEmpty { return head }
    var block: [PaneNode] = [.codeBlock(lines)]
    if let note { block.append(.text(note, "caption", color: "subtext")) }
    return .stack([head, .stack(block)], gap: headingGap)
  }
}
