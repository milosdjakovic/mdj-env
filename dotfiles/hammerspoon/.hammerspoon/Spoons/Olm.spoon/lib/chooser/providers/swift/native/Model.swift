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
  var divider = NSColor.separatorColor
  var fieldFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
  var titleFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
  var subFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
  var numberFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
  var captionFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
  var badgeFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
  var radius: CGFloat = 0
  var highlightRadius: CGFloat = 0

  init() {}

  init(_ r: LuaReader, _ t: Int32) {
    text = r.color(t, "text") ?? text
    textDim = r.color(t, "textDim") ?? textDim
    sub = r.color(t, "sub") ?? sub
    subDim = r.color(t, "subDim") ?? subDim
    highlight = r.color(t, "highlight") ?? highlight
    number = r.color(t, "number") ?? number
    background = r.color(t, "background") ?? background
    caption = r.color(t, "caption") ?? caption
    badge = r.color(t, "badge") ?? badge
    divider = r.color(t, "divider") ?? divider
    fieldFont = r.font(t, "fieldFont") ?? fieldFont
    titleFont = r.font(t, "titleFont") ?? titleFont
    subFont = r.font(t, "subFont") ?? subFont
    numberFont = r.font(t, "numberFont") ?? numberFont
    captionFont = r.font(t, "captionFont") ?? captionFont
    badgeFont = r.font(t, "badgeFont") ?? badgeFont
    radius = r.number(t, "radius") ?? radius
    highlightRadius = r.number(t, "highlightRadius") ?? highlightRadius
  }
}

// Where things sit. canvas, window and companion are in Hammerspoon's screen space, the top left
// of the primary display at the origin and y growing down. window spans the canvas and the
// companion when there is one, listFrame, paneFrame and dividerFrame are where the list's content,
// the docked pane's region and the hairline between them sit inside it, and companion is the rect a docked pane is matched on. field, list
// and footer are the canvas's own, the same space and the same rectangles the canvas view draws
// into, so nothing inside the list moved when the window grew to hold the pane.
struct Placement {
  var canvas = NSRect.zero
  var window: NSRect?
  var listFrame: NSRect?
  var paneFrame: NSRect?
  var dividerFrame: NSRect?
  var companion: NSRect?
  var field: NSRect?
  var list: NSRect?
  var footer: NSRect?
  var rowH: CGFloat = 1
  var iconSize: CGFloat = 0
  var iconFrame: CGFloat = 0
  var iconPad: CGFloat = 0
  var iconPadLeft: CGFloat = 0
  var iconGap: CGFloat = 0
  var padX: CGFloat = 0
  var numW: CGFloat = 0
  var padBottom: CGFloat = 0
  var showNumbers = false
  var barInset: CGFloat = 0
  var barGap: CGFloat = 0
  var barGapWide: CGFloat = 0
  var keysIcon: CGFloat = 0
  var keysPad: CGFloat = 0
  var barPad: CGFloat = 0
  var barPillH: CGFloat = 0
  var barPillPad: CGFloat = 0

  init() {}

  init(_ r: LuaReader, _ t: Int32) {
    canvas = r.rect(t, "canvas") ?? canvas
    window = r.rect(t, "window")
    listFrame = r.rect(t, "listFrame")
    paneFrame = r.rect(t, "paneFrame")
    dividerFrame = r.rect(t, "dividerFrame")
    companion = r.rect(t, "companion")
    field = r.rect(t, "field")
    list = r.rect(t, "list")
    footer = r.rect(t, "footer")
    rowH = max(1, r.number(t, "rowH") ?? rowH)
    iconSize = r.number(t, "iconSize") ?? iconSize
    iconFrame = r.number(t, "iconFrame") ?? iconSize
    iconPad = r.number(t, "iconPad") ?? iconPad
    iconPadLeft = r.number(t, "iconPadLeft") ?? iconPadLeft
    iconGap = r.number(t, "iconGap") ?? iconGap
    padX = r.number(t, "padX") ?? padX
    numW = r.number(t, "numW") ?? numW
    padBottom = r.number(t, "padBottom") ?? padBottom
    showNumbers = r.bool(t, "showNumbers") ?? showNumbers
    barInset = r.number(t, "barInset") ?? barInset
    barGap = r.number(t, "barGap") ?? barGap
    barGapWide = r.number(t, "barGapWide") ?? barGapWide
    keysIcon = r.number(t, "keysIcon") ?? keysIcon
    keysPad = r.number(t, "keysPad") ?? keysPad
    barPad = r.number(t, "barPad") ?? barPad
    barPillH = r.number(t, "barPillH") ?? barPillH
    barPillPad = r.number(t, "barPillPad") ?? barPillPad
  }
}

struct Row {
  var title = ""
  var subtitle = ""
  var enabled = true
  var image: NSImage?

  init(_ r: LuaReader, _ t: Int32) {
    title = r.string(t, "title") ?? ""
    subtitle = r.string(t, "subtitle") ?? ""
    enabled = r.bool(t, "enabled") ?? true
    image = r.image(t, "image")
  }
}

// The action bar's model as lib/hints.lua's footerModel shapes it, flattened to strings.
struct Footer {
  struct Entry {
    var label: String
    var chord: String
    var action: String? = nil
  }
  var right: [Entry] = []
  var keys: [Entry] = []
  var keysChord: String?
  var keysImage: NSImage?
  var title: String?
  var panelOpen = false

  init() {}

  init(_ r: LuaReader, _ t: Int32) {
    r.each(t, "right") { e in
      right.append(Entry(label: r.string(e, "label") ?? "", chord: r.string(e, "chord") ?? "",
        action: r.string(e, "action")))
    }
    r.each(t, "keys") { e in keys.append(Entry(label: r.string(e, "label") ?? "", chord: r.string(e, "chord") ?? "")) }
    keysChord = r.string(t, "keysChord")
    keysImage = r.image(t, "keysImage")
    title = r.string(t, "title")
    panelOpen = r.bool(t, "panelOpen") ?? false
  }
}

// What the engine's scene says now, apart from the rows, which travel on their own call.
struct ViewState {
  var highlight = 0
  var scrollTop: CGFloat = 0
  var placeholder = ""
  var bare = false
  var slots: [Int] = []
  var empty = false
  var emptyText = ""
  var lineBreak = NSLineBreakMode.byTruncatingTail
  var footer: Footer?
  var keysOpen = false
  // The action panel's rows and its highlight, one based, while it is open over the list.
  var actions: [Row]?
  var actionsHighlight = 0

  init() {}

  init(_ r: LuaReader, _ t: Int32) {
    highlight = r.integer(t, "highlight") ?? 0
    scrollTop = r.number(t, "scrollTop") ?? 0
    placeholder = r.string(t, "placeholder") ?? ""
    bare = r.bool(t, "bare") ?? false
    r.each(t, "slots") { e in slots.append(r.integer(at: e) ?? 0) }
    empty = r.bool(t, "empty") ?? false
    emptyText = r.string(t, "emptyText") ?? ""
    lineBreak = ViewState.lineBreak(r.string(t, "lineBreak"))
    footer = r.field(t, "footer") { r.isTable($0) ? Footer(r, $0) : nil }
    keysOpen = r.bool(t, "keysOpen") ?? false
    if r.field(t, "actions", { r.isTable($0) }) == true {
      var rows: [Row] = []
      r.each(t, "actions") { e in rows.append(Row(r, e)) }
      actions = rows
    }
    actionsHighlight = r.integer(t, "actionsHighlight") ?? 0
  }

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
