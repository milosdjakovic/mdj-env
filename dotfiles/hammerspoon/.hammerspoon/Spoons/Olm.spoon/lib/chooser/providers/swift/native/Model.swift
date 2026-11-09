// The plain data the Lua view hands over, each read off its Lua table in one place. None of it is
// a rule. Every colour, font and radius is a value the UI kit resolved, every rectangle and row
// metric is one the engine's geometry resolved, and the state is what the engine's scene says
// now. Swift only draws it, so nothing here is written by hand except the system fallbacks a
// panel shows before its first style arrives, which the engine always sends before a show.

import Cocoa

// Colours and fonts, resolved by the Lua view from the kit's tokens for the half the system is on.
struct Style {
  var text = NSColor.labelColor
  var textDim = NSColor.secondaryLabelColor
  var sub = NSColor.secondaryLabelColor
  var subDim = NSColor.tertiaryLabelColor
  var highlight = NSColor.selectedContentBackgroundColor
  var number = NSColor.secondaryLabelColor
  var background = NSColor.windowBackgroundColor
  var caption = NSColor.secondaryLabelColor
  var badge = NSColor.secondaryLabelColor
  // The chip a chord stands on, see KeyCap in Bar.swift.
  var keycap = NSColor.quaternaryLabelColor
  var fieldFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
  var titleFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
  var subFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
  var numberFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
  var captionFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
  // The row shortcuts, lib/kbd.lua's wire. numberKeys holds Command and each digit, one through
  // nine, by slot, and returnKey is the selected row's, which Return chooses.
  var numberKeys: [[KeyMark]] = []
  var returnKey: [[KeyMark]] = []
  var keycapFont = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
  // A list row's shortcut, the key cap's font at the row title's size.
  var rowKeyFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
  var radius: CGFloat = 0
  var highlightRadius: CGFloat = 0

  // The text of the highlighted row when the highlight is solid, the colour AppKit draws a
  // selected row's text in, white over the selection colour, as Finder and Spotlight do. A
  // translucent highlight, a wash over the glass, keeps the row's own colours and answers nil.
  var litText: NSColor? {
    let alpha = highlight.usingColorSpace(.sRGB)?.alphaComponent ?? highlight.alphaComponent
    return alpha >= 0.5 ? NSColor.alternateSelectedControlTextColor : nil
  }

  // The colours content takes where it stands, see Ink. lit is whether it stands on the highlight,
  // a lit row, a lit floating pane line, a lit bar group or the bar item under the pointer.
  func ink(lit: Bool) -> Ink {
    guard lit, let on = litText else {
      return Ink(text: text, textDim: textDim, sub: sub, subDim: subDim, caption: caption, number: number,
        keycap: keycap, icon: nil)
    }
    // Each role keeps the strength it has against the foreground on the glass, so a subtitle,
    // a dimmed word and a key chip stand to the lit text as they stand to the row title.
    let base = Ink.alpha(text)
    func over(_ role: NSColor) -> NSColor {
      on.withAlphaComponent(Ink.alpha(on) * (base > 0 ? min(1, Ink.alpha(role) / base) : 1))
    }
    return Ink(text: on, textDim: over(textDim), sub: over(sub), subDim: over(subDim), caption: over(caption),
      number: over(number), keycap: over(keycap), icon: on)
  }

  init() {}
}

// The colours of what stands on one surface, the words, the key chips and the one colour icons.
// On the glass, and on a translucent highlight, they are the palette's own, which the Lua view
// resolved from the kit. On a solid highlight, the accent colour set in System Settings, they are
// the selection's text colour, which AppKit draws a selected row's text in, as Finder and
// Spotlight do, each role at the strength it has against the foreground, so a key chip there is
// the lit text at the keycap's strength, ui.keycapColor's rule applied to the lit foreground.
// Every surface that lights, the list's rows, the floating panes' lines and the bar's groups and
// items, draws through it, so none of them decides a lit colour of its own.
struct Ink {
  var text: NSColor
  var textDim: NSColor
  var sub: NSColor
  var subDim: NSColor
  var caption: NSColor
  var number: NSColor
  var keycap: NSColor
  // The colour a one colour icon is redrawn in, see Crisp.tinted, nil to keep the icon's own.
  var icon: NSColor?

  static func alpha(_ color: NSColor) -> CGFloat {
    color.usingColorSpace(.sRGB)?.alphaComponent ?? color.alphaComponent
  }
}

// Where things sit. canvas, window and previewPane are in Hammerspoon's screen space, the top left
// of the primary display at the origin and y growing down. window spans the canvas and the
// preview pane when there is one, listFrame and paneFrame are where the list's content and the
// preview pane's region sit inside it, and preview pane is the rect a preview pane is matched on. field, list
// and bottomBar are the canvas's own, the same space and the same rectangles the canvas view draws
// into, so nothing inside the list moved when the window grew to hold the pane.
struct Placement {
  var canvas = NSRect.zero
  var window: NSRect?
  var listFrame: NSRect?
  var paneFrame: NSRect?
  var previewPane: NSRect?
  var field: NSRect?
  var list: NSRect?
  var bottomBar: NSRect?
  var rowH: CGFloat = 1
  var iconSize: CGFloat = 0
  var iconFrame: CGFloat = 0
  var iconPad: CGFloat = 0
  var iconPadLeft: CGFloat = 0
  var iconGap: CGFloat = 0
  var padX: CGFloat = 0
  var numW: CGFloat = 0
  var padBottom: CGFloat = 0
  // The kit's outer padding, where a preview pane's content rests below the pane's top edge.
  var pad: CGFloat = 0
  var showNumbers = false
  var barInset: CGFloat = 0
  var barGap: CGFloat = 0
  var barGapWide: CGFloat = 0
  var infoIcon: CGFloat = 0
  var keysPad: CGFloat = 0
  var barPad: CGFloat = 0
  var barPillH: CGFloat = 0
  var barPillPad: CGFloat = 0
  // A key cap's height, the room either side of its glyphs and between two keys, the kit's hint
  // badge.
  var keycapH: CGFloat = 0
  var keycapPadX: CGFloat = 0
  var keycapGap: CGFloat = 0
  // The word between two alternative keys, bottombar.lua's ALT_WORD.
  var keycapOr = "/"

  init() {}
}

// One key of a chord, lib/kbd.lua's glyph and the SF Symbol a key cap draws in its place, nil for
// a key drawn as its glyph.
struct KeyMark {
  var glyph: String
  var symbol: String?
}

struct Row {
  var title = ""
  var subtitle = ""
  // An actions pane row's chord, lib/kbd.lua's wire, empty for a list row.
  var chord: [[KeyMark]] = []
  var enabled = true
  // The engine's row of more, which ends a list its limit cut, drawn in the subtext colour so it
  // reads as part of the list rather than as one of its results.
  var muted = false
  var image: NSImage?
  // The image is one colour, an SF Symbol, so a row lit by a solid highlight draws it in the lit
  // text colour as it does the title. An emoji or a row's own picture keeps its colours.
  var tint = false
  // The heading an actions pane row is listed under, nil for a list row.
  var section: String?
}

// The bottom bar's model as lib/hints.lua's bottomBarModel shapes it, a chord as kbd's wire.
struct BottomBar {
  struct Entry {
    var label: String
    var chord: [[KeyMark]]
    var action: String? = nil
    // The heading a info pane line is listed under, nil for the legend that leads it.
    var section: String? = nil
    // Keys drawn bare before an info pane line's label, the legend's leader symbol.
    var lead: [[KeyMark]] = []
    // A bar label that gives up width, ending in an ellipsis, when the right side would reach
    // past the left side, the primary's and the secondary's.
    var fit = false
  }
  var right: [Entry] = []
  var keys: [Entry] = []
  var keysChord: [[KeyMark]] = []
  var keysImage: NSImage?
  // The keys image is one colour, see Row's tint.
  var keysTint = false
  var title: String?
  var panelOpen = false
  // The title of a level a verb opened in the actions pane, heading the floating pane, nil at the top.
  var panelTitle: String?
  // The actions pane's own input field, the list's text the list's field keeps showing while the
  // pane is open and the pane's placeholder, nil for a pane drawn with no field of its own.
  var panelHeld: String?
  var panelPlaceholder: String?

  init() {}
}

// What the engine's scene says now, apart from the rows, which travel on their own call.
struct ViewState {
  // The row the engine moved the highlight to, one based, 0 for none, or nil to leave the one
  // the list holds, which the person may have moved since.
  var highlight: Int?
  // Where the engine moves the viewport, or nil to leave it where the person scrolled it.
  var scrollTop: CGFloat?
  var placeholder = ""
  var bare = false
  var slots: [Int] = []
  var empty = false
  var emptyText = ""
  var lineBreak = NSLineBreakMode.byTruncatingTail
  var bottomBar: BottomBar?
  var infoOpen = false
  // The actions pane's rows and its highlight, one based, while it is open over the list.
  var actions: [Row]?
  var actionsHighlight = 0

  init() {}

  // The truncation mode names the canvas view hands hs.styledtext, as AppKit spells them.
  static func lineBreak(_ name: String?) -> NSLineBreakMode {
    switch name {
    case "truncateHead": return .byTruncatingHead
    case "truncateMiddle": return .byTruncatingMiddle
    case "clip": return .byClipping
    case "wordWrap": return .byWordWrapping
    case "charWrap": return .byCharWrapping
    default: return .byTruncatingTail
    }
  }
}
