// The stage, the one thing the chooser panel talks to, docs/DESIGN-APP.md. It holds what every list
// shares and no list decides, the query and its generation, the highlight, the slots, Command and a
// digit, Return and the keys its field answers, Bars.swift, the empty text, the icons and the redraw that
// skips an answer that changed nothing, so a source only answers rows and effects and never meets
// the panel. The panel is the swift chooser's own, OlmChooser, in the swift chooser's own look,
// Look.swift.
//
// Everything here runs on the main thread and holds only the input field and the list, rule 8 of
// docs/PLAN-STANDALONE.md. A source answers on its own actor and the search ranks on its own, so
// typing never waits on either. Every keystroke raises the generation and cancels the task before
// it, and an answer for an older generation is dropped.
//
// THE PREVIEW PANE, step 1.4a. A list whose manifest has one opens with the window already wide,
// Look's placement, and the pane follows the highlight as the Lua file search's does,
// plugins/filesearch/chooser.lua's onHighlight. The highlight resting for the level's settle time
// asks the source for the row's Preview on the source's own actor, PanePainter lays it out on a
// task off the main thread, and only the drawing lands here, dropped when a newer row was asked
// for since. A row already on screen is left where it is scrolled, a row being read is not asked
// for twice, and no row, a status in place of the rows, shows the pane's empty state. The scroll
// verbs, Hyper with D or U heard by Hammerspoon, move it by the step the Lua pane's scroll
// keys move, and a scroll over it is
// the native view's own.
//
// PICTURES, step 1.4b. A body's picture is a file the source names, read and decoded at the pixels
// it is shown at by PanePicture on the same task the pane is laid out on, so the main thread draws
// pixels already decoded. A preview that says something is still pending, a picture being rendered,
// is drawn as it stands and the same row is then asked again, previewLanded, on the same generation,
// and drawn where it is scrolled, as the Lua pane repaints when its thumbnail lands. A newer row
// cancels the wait, which drops the late answer and lets the source end a render nobody waits on.

import AppKit
import OlmKit
@preconcurrency @testable import OlmChooser

@MainActor
public final class Stage {
  private let searcher: Searcher
  private lazy var panel = ChooserPanel(source: self)
  // The action whose quickLook effect opened the Quick Look pane, which the pane asks again for
  // each row the highlight lands on, since it follows the highlight, step 1.4c.
  private var lookAction: String?
  private var source: (any ListSource)?
  private var level: Level?
  private var rows: [OlmKit.Row] = []
  private var highlight = 1
  private var text = ""
  private var generation = 0
  private var task: Task<Void, Never>?
  // The swift chooser's look as the bridge last wrote it, read on every open.
  private var look: Look?
  // The bar under the list and whether its info pane is open, Bars.swift, read on every open.
  private var bars = Bars()
  private var bar: BottomBar? { bars.bar }
  private var infoOpen = false
  // The bar as the open info pane draws it, its lines in the words the source gives them over the
  // highlighted row, Copy Folder over a folder, and the count of info pane opens, so words landing
  // after the pane closed or opened again are dropped.
  private var infoBar: BottomBar?
  private var infoGeneration = 0
  // An Escape that closed a pane, so its autorepeat does not go on to close the list, as the
  // engine's _escapeClosedKeys does.
  private var escapeClosedInfo = false
  // The actions pane over the list, piece three, its rows the share's whose gate the source answers
  // yes to over the row it opened on. What is typed while it is open filters its rows, and the
  // list's own text and highlight are kept and given back as it closes, host/actionspane's _leave.
  private struct ActionsPane {
    var rows: [Bars.ActionRow]
    // The rows the typed text kept, indices into rows, in ranked order, and the lit one, one based.
    var shown: [Int]
    var lit: Int
    var query = ""
    let savedText: String
    let savedHighlight: Int
  }
  private var actionsPane: ActionsPane?
  private var actionsGeneration = 0
  // The status the last redraw showed, so a redraw for the bar alone keeps it.
  private var status: String?
  // Each file's icon once it has been drawn, so a row is sent with its icon whenever it has one.
  // A row sent without one is drawn blank until the list asks for it, which flickered every icon
  // on every keystroke, reported in the 1.3d trial on 2026-11-08.
  private let icons = NSCache<NSString, NSImage>()
  // The preview pane, made with the panel the first time a list with one opens.
  private var paneHost: PaneHost?
  // The pane of the list open now, its size and its tokens, nil for a list with none.
  private var pane: (frame: PaneFrame, tokens: PaneTokens, emptyText: String)?
  private let paneMeasure = PaneMeasure()
  private var settleTask: Task<Void, Never>?
  private var staleTask: Task<Void, Never>?
  private var previewTask: Task<Void, Never>?
  // Raised by every row asked for and every clear, so a late answer is dropped.
  private var previewGeneration = 0
  // The row on the pane, and the row being read for it.
  private var previewShown: String?
  private var previewAsking: String?
  // An open waits to show the window until its first rows have landed and, with a pane, the first
  // row is described, so it never shows blank and then fills in two steps, reported in the 1.4a
  // trial on 2026-11-08. The wait is capped, revealCapMs, so a slow read still shows the window.
  // A pane draws only into a visible window, so a paint made while waiting is held and drawn as the
  // window shows.
  private var revealPending = false
  private var revealTask: Task<Void, Never>?
  private var heldPaint: PanePaint?
  private var heldBusy = false
  // The placement choice the list was last opened with, for a reopen.
  private var screenMode: String?
  private static let revealCapMs: UInt64 = 150
  // The tool whose list is up, told through onShowing as it goes up and comes down, step 1.4f,
  // docs/DESIGN-APP-LIST-KEYS.md, so Hammerspoon routes its list keys here.
  private var shown: String?
  /// Told a tool's name and true as its list opens and false as it hides. Olm.app's composition
  /// root posts it to Hammerspoon.
  public var onShowing: ((String, Bool) -> Void)?
  // The verbs this step does not run yet, said once each.
  private var unknownVerbs: Set<String> = []

  public init(searcher: Searcher = Searcher()) {
    self.searcher = searcher
  }

  /// Opens a source's list with the query in the input field, on the screen the placement choice
  /// names, lib/overlaydisplay.lua's mode.
  public func open(_ next: any ListSource, query: String, screen mode: String? = nil) {
    if let source, source !== next { Task { await source.close() } }
    source = next
    tell(next.manifest.name)
    screenMode = mode
    level = nil
    generation += 1
    task?.cancel()
    look = Look.read()
    bars = Bars.read(next.manifest.name)
    infoOpen = false
    infoGeneration += 1
    actionsPane = nil
    actionsGeneration += 1
    resetPane()
    pane = nil
    if let look, let screen = Look.screen(for: mode) {
      panel.applyStyle(look.style())
      let tokens = next.manifest.previewPane != nil ? look.paneTokens() : nil
      let (placement, frame) = look.placement(on: screen, pane: tokens != nil)
      panel.place(placement)
      if let tokens, let frame, let rect = placement.previewPane, let spec = next.manifest.previewPane {
        pane = (frame, tokens, spec.emptyText)
        if paneHost == nil { paneHost = PaneHost(panel: panel) }
        paneHost?.place(rect)
      }
    } else {
      // No look has been written yet, so the panel draws on its own defaults until Hammerspoon
      // loads with the piece on.
      NSLog("Olm: no chooser look at %@, the panel's defaults are used", Look.path)
      panel.place(Look.fallback())
    }
    // A list with no pane opened over one that had it leaves no pane behind.
    if pane == nil { paneHost?.close() }
    rows = []
    text = query
    panel.setRows([])
    apply(status: nil)
    panel.start()
    panel.setText(query)
    revealPending = true
    heldPaint = nil
    revealTask?.cancel()
    revealTask = Task {
      try? await Task.sleep(nanoseconds: Self.revealCapMs * 1_000_000)
      if Task.isCancelled { return }
      self.reveal()
    }
    let mine = generation
    task = Task {
      let level = await next.open(query: query)
      guard mine == self.generation else { return }
      self.level = level
      self.search(self.text)
    }
  }

  // Shows the window an open is holding back, with the paint it held or the pane's empty state.
  private func reveal() {
    guard revealPending else { return }
    revealPending = false
    revealTask?.cancel()
    // The bridge starts the app hidden, `open -j`, as the shadow is wired, and a hidden app's
    // panel takes key but is never drawn, found in the 1.3f trial on 2026-11-08.
    if NSApp.isHidden { NSApp.unhide(nil) }
    panel.show()
    guard let pane, let paneHost else { return }
    let paint = heldPaint ?? PanePainter.empty(pane.emptyText, frame: pane.frame, tokens: pane.tokens, measure: paneMeasure)
    heldPaint = nil
    paneHost.draw(paint, radius: paneRadius, reset: true, busy: heldBusy)
    heldBusy = false
  }

  private var paneRadius: CGFloat { CGFloat(look?.style().radius ?? 0) }

  // A paint for the pane, held while an open is waiting to show the window, which it then shows.
  // reset false keeps where the pane is scrolled, for the same row painted again.
  private func drawPane(_ paint: PanePaint, reset: Bool = true, busy: Bool = false) {
    if revealPending {
      heldPaint = paint
      heldBusy = busy
      reveal()
      return
    }
    paneHost?.draw(paint, radius: paneRadius, reset: reset, busy: busy)
  }

  // A body's shortcut as the actions pane names it, its title and its first chord's glyphs with
  // nothing between them, lib/kbd.lua's text, or nil where the list has no such action.
  private func spelled(_ verb: String?) -> (title: String, chord: String)? {
    guard let verb, let action = bars.actions.first(where: { $0.verb == verb }),
      let chord = action.row.chord.first, !chord.isEmpty else { return nil }
    return (action.row.title, chord.map(\.glyph).joined())
  }

  // The pixels to the point of the screens the pane can stand on, which a picture is decoded at.
  private var paneScale: Double { Double(NSScreen.screens.map(\.backingScaleFactor).max() ?? 2) }

  // A preview laid out off the main thread, its picture read there first.
  private nonisolated static func paint(_ preview: OlmKit.Preview, pane: (frame: PaneFrame, tokens: PaneTokens, emptyText: String),
                                        measure: PaneMeasure, scale: Double,
                                        shortcut: (title: String, chord: String)? = nil) async -> PanePaint {
    await Task.detached(priority: .userInitiated) {
      let width = PanePainter.bodyWidth(pane.frame, tokens: pane.tokens)
      let image = preview.body?.picture.flatMap { PanePicture.load($0, width: width, scale: scale) }
      return PanePainter.paint(preview, frame: pane.frame, tokens: pane.tokens, measure: measure, image: image,
        shortcut: shortcut)
    }.value
  }

  public func hide() {
    let waiting = revealPending
    revealPending = false
    revealTask?.cancel()
    heldPaint = nil
    infoOpen = false
    infoGeneration += 1
    actionsPane = nil
    actionsGeneration += 1
    tell(nil)
    guard panel.isVisible || waiting else { return }
    generation += 1
    task?.cancel()
    resetPane()
    panel.hide()
    // After the hide, as the Lua file search's onClose destroys its pane once the stage hid.
    paneHost?.close()
    panel.stop()
    if let source { Task { await source.close() } }
  }

  private func search(_ text: String) {
    self.text = text
    generation += 1
    task?.cancel()
    // Until the source has opened its level, the text is kept, and the open searches it.
    guard let source, let level else { return }
    let mine = generation
    let searcher = searcher
    task = Task {
      guard let answer = try? await source.rows(Query(text: text, generation: mine)) else { return }
      let ranked = await searcher.rank(answer, query: text, level: level)
      guard mine == self.generation else { return }
      self.land(ranked.rows, status: answer.status ?? (ranked.rows.isEmpty ? answer.emptyStatus : nil))
    }
  }

  private func land(_ next: [OlmKit.Row], status: String?) {
    // The same rows in the same order are left as they are drawn, so a keystroke that does not
    // change the results redraws nothing.
    if next.map(\.key) != rows.map(\.key) {
      rows = next
      panel.setRows(next.map(panelRow))
    }
    highlight = next.isEmpty ? 0 : 1
    apply(status: status)
    // The first rows of an open show the window, at once without a pane and once the first row is
    // described with one, which the open asks for without the settle, as the Lua pane's first dock.
    if revealPending {
      if pane == nil { reveal() } else { describe() }
      return
    }
    settlePreview()
  }

  // MARK: The preview pane

  // Forgets the row on the pane and any read on its way, so nothing late is drawn.
  private func resetPane() {
    settleTask?.cancel()
    staleTask?.cancel()
    previewTask?.cancel()
    previewGeneration += 1
    previewShown = nil
    previewAsking = nil
  }

  // The empty state, for no highlight or a status in place of the rows.
  private func clearPane() {
    guard let pane else { return }
    resetPane()
    drawPane(PanePainter.empty(pane.emptyText, frame: pane.frame, tokens: pane.tokens, measure: paneMeasure))
  }

  // The highlight moved or the rows changed, so the row it rests on is described once it settles.
  private func settlePreview() {
    guard pane != nil else { return }
    watchStale()
    settleTask?.cancel()
    let ms = level?.previewSettleMs ?? 60
    settleTask = Task {
      try? await Task.sleep(nanoseconds: UInt64(max(0, ms)) * 1_000_000)
      if Task.isCancelled { return }
      self.describe()
    }
  }

  // The pane never shows a row the highlight has left for longer than staleMs, whatever the read
  // is waiting on. Past it the old row is cleared and the spinner turns in its place until the new
  // row is drawn, Milos's rule from the 1.4b trial on 2026-11-09. The read keeps going, and the row
  // left is forgotten as shown, so coming back to it reads it again.
  private static let staleMs: UInt64 = 150

  private func watchStale() {
    staleTask?.cancel()
    staleTask = Task {
      try? await Task.sleep(nanoseconds: Self.staleMs * 1_000_000)
      if Task.isCancelled || self.revealPending { return }
      guard let pane = self.pane, self.highlight >= 1, self.highlight <= self.rows.count,
        self.rows[self.highlight - 1].key != self.previewShown else { return }
      self.previewShown = nil
      // The row's own name heads the pane, the one thing known before any read.
      let named = OlmKit.Preview(name: self.rows[self.highlight - 1].title)
      let paint = PanePainter.paint(named, frame: pane.frame, tokens: pane.tokens, measure: self.paneMeasure)
      self.drawPane(paint, busy: true)
    }
  }

  private func describe() {
    guard let pane, let source else { return }
    guard highlight >= 1, highlight <= rows.count else {
      clearPane()
      return
    }
    let key = rows[highlight - 1].key
    // Already on the pane, where it is scrolled, or already being read.
    if key == previewShown || key == previewAsking { return }
    previewTask?.cancel()
    previewGeneration += 1
    let mine = previewGeneration
    previewAsking = key
    let pick = Pick(key: key, query: text)
    let measure = paneMeasure
    let scale = paneScale
    previewTask = Task {
      guard let preview = await source.preview(pick) else {
        if mine == self.previewGeneration { self.reveal() }
        return
      }
      guard mine == self.previewGeneration else { return }
      // A preview still on its way says so with the spinner rather than its words, the body's
      // heading drawn alone, or with its words over a meter where it says how far it has come.
      var drawn = preview
      if preview.pending, preview.progress == nil { drawn.body?.facts = nil }
      let paint = await Self.paint(drawn, pane: pane, measure: measure, scale: scale,
        shortcut: self.spelled(drawn.body?.shortcut))
      guard mine == self.previewGeneration else { return }
      self.previewAsking = nil
      self.previewShown = key
      self.drawPane(paint, busy: Self.spins(preview))
      // What the preview said was on its way, drawn where the pane is scrolled once it lands.
      // Asked again while it is still pending, since a download can land as a render begins.
      var waiting = preview.pending
      while waiting {
        guard let landed = await source.previewLanded(pick), !Task.isCancelled,
          mine == self.previewGeneration else { return }
        var drawn = landed
        if landed.pending, landed.progress == nil { drawn.body?.facts = nil }
        let repaint = await Self.paint(drawn, pane: pane, measure: measure, scale: scale,
          shortcut: self.spelled(drawn.body?.shortcut))
        guard mine == self.previewGeneration else { return }
        self.drawPane(repaint, reset: false, busy: Self.spins(landed))
        waiting = landed.pending
      }
    }
  }

  // The spinner turns for a preview on its way that cannot say how far it has come, since one
  // that can draws its own meter, asked for in the 1.4i trial on 2026-11-11.
  private static func spins(_ preview: OlmKit.Preview) -> Bool { preview.pending && preview.progress == nil }

  // The state the Lua view sends, providers/swift/view.lua's redraw. The first nine rows carry
  // Command and their digit wherever the list scrolls, the selected row Return, and a typed query
  // with no rows says so in the canvas view's words, or the source's status where it has one.
  private func apply(status: String?) {
    self.status = status
    var state = ViewState()
    state.bottomBar = infoOpen ? (infoBar ?? bar) : bar
    state.infoOpen = infoOpen && bar != nil
    state.placeholder = level?.placeholder ?? ""
    state.highlight = highlight
    // Over the actions pane the bar is the share's open bar, Return labelled by the lit row as
    // bottomBarModel labels it, and the list behind holds the highlight it had.
    if let actionsPane, var open = bars.panelBar {
      let lit = actionsPane.lit >= 1 && actionsPane.lit <= actionsPane.shown.count
        ? actionsPane.rows[actionsPane.shown[actionsPane.lit - 1]].row.title : ""
      if !open.right.isEmpty { open.right[0].label = lit.isEmpty ? "Run" : lit }
      // The list's field keeps showing the text the pane opened over while the caret is in the
      // pane's own field, whose placeholder the share carries.
      open.panelHeld = actionsPane.savedText
      state.bottomBar = open
      state.infoOpen = false
      state.highlight = nil
      state.actions = actionsPane.shown.map { actionsPane.rows[$0].row }
      state.actionsHighlight = actionsPane.lit
    }
    state.lineBreak = level?.titleLineBreak.map { ViewState.lineBreak($0) } ?? look?.lineBreak ?? .byTruncatingTail
    if look?.showNumbers == true, !rows.isEmpty { state.slots = Array(1...min(9, rows.count)) }
    state.empty = rows.isEmpty && (status != nil || !text.isEmpty)
    state.emptyText = status ?? "No results"
    panel.update(state)
  }

  private func panelRow(_ r: OlmKit.Row) -> OlmChooser.Row {
    var row = OlmChooser.Row()
    row.title = r.title
    row.subtitle = r.subtitle
    switch r.icon {
    case .file(let path)?: row.image = icons.object(forKey: path as NSString)
    case .symbol?:
      row.image = icon(r)
      row.tint = true
    case nil: break
    }
    return row
  }

  private func icon(_ r: OlmKit.Row) -> NSImage? {
    switch r.icon {
    case .file(let path)?:
      if let image = icons.object(forKey: path as NSString) { return image }
      let image = NSWorkspace.shared.icon(forFile: path)
      icons.setObject(image, forKey: path as NSString)
      return image
    case .symbol(let name)?:
      let key = "symbol:" + name as NSString
      if let image = icons.object(forKey: key) { return image }
      // A template the list tints with the row's ink, at a size the list scales down crisply.
      guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 64, weight: .regular)) else { return nil }
      image.isTemplate = true
      icons.setObject(image, forKey: key)
      return image
    case nil:
      return nil
    }
  }

  // Whether a row's icon is one colour the list tints, a symbol's.
  private static func tinted(_ r: OlmKit.Row) -> Bool {
    if case .symbol? = r.icon { return true }
    return false
  }

  // Return, or an action, on the row at a one based index.
  // closingPanes leaves the info pane and the actions pane standing until the answer is back, so
  // an answer that hides the list fades them whole with it, and only one that keeps it up closes
  // them, Milos's report in step 1.4f's piece four, where a pane folding under the list's fade was
  // cut halfway. While the actions pane is open the list's text and highlight are its own still.
  private func act(on index: Int, action: String? = nil, closingPanes: Bool = false) {
    guard index >= 1, index <= rows.count, let source else {
      if closingPanes { closeInfo(); closeActions() }
      return
    }
    let pick = Pick(key: rows[index - 1].key, query: text)
    let mine = generation
    Task {
      let effects = if let action { await source.run(action, on: pick) } else { await source.choose(pick) }
      if let action, effects.contains(where: { if case .quickLook = $0 { true } else { false } }) {
        self.lookAction = action
      }
      if closingPanes, !effects.contains(.hide), mine == self.generation {
        self.closeInfo()
        self.closeActions()
        if index <= self.rows.count, self.highlight != index {
          self.highlight = index
          self.apply(status: self.status)
        }
      }
      self.perform(effects)
    }
  }

  // Quick Look following the highlight, the action that opened it asked again for the row the
  // highlight landed on and its file taken in place, never closing the pane. A row the action
  // has no file for leaves the pane on the file it shows.
  private func followQuickLook() {
    guard panel.quickLookPath != nil, let action = lookAction, let source,
      highlight >= 1, highlight <= rows.count else { return }
    let pick = Pick(key: rows[highlight - 1].key, query: text)
    let mine = generation
    let index = highlight
    Task {
      let effects = await source.run(action, on: pick)
      guard mine == self.generation, index == self.highlight, self.panel.quickLookPath != nil else { return }
      for case .quickLook(let path) in effects { self.panel.quickLook(path) }
    }
  }

  // A hide first, then the rest in order, so work that opens another app never lands in this one.
  private func perform(_ effects: [Effect]) {
    if effects.contains(.hide) { hide() }
    for effect in effects {
      switch effect {
      case .hide: break
      case .openFile(let path): NSWorkspace.shared.open(URL(fileURLWithPath: path))
      case .revealFile(let path): NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
      case .openURL(let text): if let url = URL(string: text) { NSWorkspace.shared.open(url) }
      case .reopen: if let source { open(source, query: "", screen: screenMode) }
      // The file already shown closes the pane and another shows in it, the panel's own Quick Look,
      // native/QuickLook.swift.
      case .quickLook(let path): panel.quickLook(panel.quickLookPath == path ? nil : path)
      case .setQuery(let text):
        panel.setText(text)
        search(text)
      case .copyText(let text):
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
      case .copyFile(let path):
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([URL(fileURLWithPath: path) as NSURL])
      // Forgotten as shown and asked again, where the pane is scrolled, step 1.4i.
      case .refreshPreview:
        previewShown = nil
        previewAsking = nil
        describe()
      }
    }
  }

  // Says which tool's list is up, a down for the one before when another opens over it.
  private func tell(_ tool: String?) {
    guard tool != shown else { return }
    if let shown { onShowing?(shown, false) }
    shown = tool
    if let tool { onShowing?(tool, true) }
  }

  /// Answers Hammerspoon asking what is up, after a reload forgot it.
  public func tellState() {
    if let shown { onShowing?(shown, true) }
  }

  /// One list verb from Hammerspoon's leaders, step 1.4f, run on this list's own highlight. The name
  /// is the method lib/nav.lua routes to. A verb for a tool whose list is not up is dropped.
  public func verb(_ tool: String, _ name: String) {
    guard tool == shown, let source else { return }
    // Every verb but the info pane's own closes it first, a key that acts on the list being a
    // person done reading it, stated by Milos in piece two's trial on 2026-11-09.
    if name != "showInfo" { closeInfo() }
    if actionsPane != nil, actionsVerb(name) { return }
    switch name {
    case "openActionsPane": toggleActions()
    case "selectNext": panel.move(1)
    case "selectPrev": panel.move(-1)
    case "hide": hide()
    case "insertSelected": act(on: highlight)
    case "showInfo": toggleInfo()
    case "scrollPreviewDown", "scrollPreviewUp":
      if pane != nil, previewShown != nil {
        paneHost?.scrollBy(name == "scrollPreviewDown" ? Self.paneScrollStep : -Self.paneScrollStep)
      }
    default:
      if source.manifest.actions.contains(where: { $0.id == name }) {
        act(on: highlight, action: name)
      } else if unknownVerbs.insert(name).inserted {
        NSLog("Olm: the list verb %@ is not run by the app yet", name)
      }
    }
  }

  // The info pane over the list, opened by Command and ?, Hyper and its key or the bar's button,
  // and closed by the same or a press in the list, as the engine's toggleInfo and closeInfo do.
  // It opens once the source has given its lines their words over the highlighted row, so a line
  // never shows Copy File and then turns into Copy Folder.
  private func toggleInfo() {
    infoGeneration += 1
    if infoOpen {
      infoOpen = false
      apply(status: status)
      return
    }
    guard let bar, panel.isVisible else { return }
    let pick = source != nil && highlight >= 1 && highlight <= rows.count
      ? Pick(key: rows[highlight - 1].key, query: text) : nil
    let mine = infoGeneration
    Task {
      var words = bar
      if let source = self.source, let pick {
        for i in words.keys.indices {
          guard let verb = words.keys[i].action, let word = await source.label(verb, on: pick) else { continue }
          words.keys[i].label = word
        }
      }
      guard mine == self.infoGeneration, self.panel.isVisible else { return }
      self.infoBar = words
      self.infoOpen = true
      self.apply(status: self.status)
    }
  }

  private func closeInfo() {
    infoGeneration += 1
    if infoOpen { toggleInfo() }
  }

  // MARK: The actions pane, piece three

  // A row the app can run, Return's own verb or one of the source's actions. A verb that asks
  // first or offers choices opens a level in the Lua pane, which the app does not have yet, and
  // file search declares none, so such a row is left out and said once.
  private func runnable(_ row: Bars.ActionRow) -> Bool {
    guard let source else { return false }
    if row.confirm || row.choices {
      if unknownVerbs.insert(row.verb).inserted { NSLog("Olm: the actions pane has no level for %@ yet", row.verb) }
      return false
    }
    return row.verb == "insertSelected" || source.manifest.actions.contains(where: { $0.id == row.verb })
  }

  // Opens the pane over the highlighted row, or closes it. Opening it closes the info pane, as the
  // engine's toggleInfo and the actions pane never stand open together.
  private func toggleActions() {
    if actionsPane != nil {
      closeActions()
      return
    }
    guard bars.panelBar != nil, panel.isVisible, let source, highlight >= 1, highlight <= rows.count else { return }
    closeInfo()
    let pick = Pick(key: rows[highlight - 1].key, query: text)
    let candidates = bars.actions.filter { runnable($0) }
    actionsGeneration += 1
    let mine = actionsGeneration
    Task {
      var kept: [Bars.ActionRow] = []
      for var row in candidates {
        if let gate = row.applies, !(await source.applies(gate, on: pick)) { continue }
        // The row's word over this row, Copy Folder over a folder, the Lua pane's labels.
        if let word = await source.label(row.verb, on: pick) { row.row.title = word }
        kept.append(row)
      }
      guard mine == self.actionsGeneration, self.panel.isVisible, self.actionsPane == nil else { return }
      self.actionsPane = ActionsPane(rows: kept, shown: Array(kept.indices), lit: kept.isEmpty ? 0 : 1,
        savedText: self.text, savedHighlight: self.highlight)
      self.panel.setText("")
      self.apply(status: self.status)
    }
  }

  // The list's own text and highlight back, the rows behind never having changed.
  private func closeActions() {
    guard let actionsPane else { return }
    self.actionsPane = nil
    actionsGeneration += 1
    panel.setText(actionsPane.savedText)
    text = actionsPane.savedText
    highlight = actionsPane.savedHighlight
    apply(status: status)
  }

  private func litActions(_ delta: Int) {
    guard var pane = actionsPane, !pane.shown.isEmpty else { return }
    pane.lit = min(max(1, pane.lit + delta), pane.shown.count)
    actionsPane = pane
    apply(status: status)
  }

  // A row of the pane chosen, by Return, a press or its own key. The pane closes first, giving the
  // list back its row, and the verb then runs on that row, as the Lua pane's _leave runs it.
  private func chooseActions(_ index: Int) {
    guard let pane = actionsPane, index >= 1, index <= pane.shown.count, let shown else { return }
    let verb = pane.rows[pane.shown[index - 1]].verb
    if verb == "insertSelected" { return act(on: pane.savedHighlight, closingPanes: true) }
    if source?.manifest.actions.contains(where: { $0.id == verb }) == true {
      return act(on: pane.savedHighlight, action: verb, closingPanes: true)
    }
    closeActions()
    self.verb(shown, verb)
  }

  // What the typed text keeps of the pane's rows, by the shared search, as the Lua pane ranks its
  // own rows with the instance's matcher.
  private func filterActions(_ query: String) {
    guard var pane = actionsPane else { return }
    pane.query = query
    actionsPane = pane
    let answer = RowsAnswer(rows: pane.rows.enumerated().map {
      OlmKit.Row(key: String($0.offset), title: $0.element.row.title, filterText: $0.element.row.title)
    })
    let mine = actionsGeneration
    let searcher = searcher
    Task {
      let ranked = await searcher.rank(answer, query: query, level: Level())
      guard mine == self.actionsGeneration, var pane = self.actionsPane, pane.query == query else { return }
      pane.shown = ranked.rows.compactMap { Int($0.key) }
      pane.lit = pane.shown.isEmpty ? 0 : 1
      self.actionsPane = pane
      self.apply(status: self.status)
    }
  }

  // A verb while the pane is open, answered true when the pane took it. Moving and Return are the
  // pane's, its own key closes it, and a key on a verb the pane lists chooses that row, so the key
  // a row shows does what the row does. Any other key closes the pane and goes on to the list,
  // stated by Milos on 2026-11-09, and the info pane's key closes it and opens the info pane.
  private func actionsVerb(_ name: String) -> Bool {
    guard let pane = actionsPane else { return false }
    switch name {
    case "selectNext": litActions(1)
    case "selectPrev": litActions(-1)
    case "insertSelected": chooseActions(pane.lit)
    case "openActionsPane": closeActions()
    default:
      if let at = pane.rows.firstIndex(where: { $0.verb == name }) {
        if let shownAt = pane.shown.firstIndex(of: at) {
          chooseActions(shownAt + 1)
        } else {
          // Listed but filtered out by what was typed, still the row's own key.
          closeActions()
          if let shown { verb(shown, name) }
        }
        return true
      }
      closeActions()
      return false
    }
    return true
  }

  // Escape closes the info pane when it is open and the list otherwise. A held Escape that closed
  // the pane goes on repeating, and every repeat of that press is swallowed until a fresh one.
  private func dismissKey(_ data: Data?) {
    let repeating = data.flatMap { CGEvent(withDataAllocator: nil, data: $0 as CFData) }
      .map { $0.getIntegerValueField(.keyboardEventAutorepeat) != 0 } ?? false
    if repeating && escapeClosedInfo { return }
    escapeClosedInfo = false
    if actionsPane != nil {
      escapeClosedInfo = true
      closeActions()
      return
    }
    if infoOpen {
      escapeClosedInfo = true
      closeInfo()
      return
    }
    hide()
  }

  // How far one scroll key moves the pane, chooser.lua's PANE_SCROLL_STEP.
  private static let paneScrollStep: CGFloat = 120

  // The digit keys one through nine, as virtual key codes.
  private static let digitKeys: [Int64] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

  // A list key the panel did not take, answered true when the stage took it.
  private func listKey(_ data: Data) -> Bool {
    guard let event = CGEvent(withDataAllocator: nil, data: data as CFData) else { return false }
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    // Command and a digit opens the row in that slot, as the engine's _chooseSlot does, whether or
    // not the list shows its numbers, the highlight moved onto it first as _choose moves it. Over
    // an open actions pane the pane closes and the digit is the list's, stated by Milos on
    // 2026-11-10, checked against the Lua list in step 1.4f's piece four.
    if event.flags.contains(.maskCommand), let slot = Self.digitKeys.firstIndex(of: code) {
      if actionsPane == nil, slot + 1 <= rows.count, highlight != slot + 1 {
        highlight = slot + 1
        apply(status: status)
      }
      act(on: slot + 1, closingPanes: true)
      return true
    }
    // A key the list's own field answers in the Lua list, from the share, Command and Return
    // revealing the file and Command and ? the info pane, run as the verb Hammerspoon would send.
    if let verb = bars.verb(code: code, flags: event.flags), let shown {
      self.verb(shown, verb)
      return true
    }
    guard code == 36 || code == 76 else { return false }
    closeInfo()
    if let pane = actionsPane {
      chooseActions(pane.lit)
      return true
    }
    act(on: highlight)
    return true
  }

  fileprivate func handle(_ event: String, _ args: [PanelValue]) -> Bool {
    switch event {
    case "dismiss":
      if case .bytes(let data)? = args.first { dismissKey(data) } else { dismissKey(nil) }
    case "resignedKey", "pressOutside":
      hide()
    case "quickLookOpen":
      // The pane's open button is Return on the highlighted row, the file it shows.
      act(on: highlight)
    case "text":
      closeInfo()
      if case .string(let text)? = args.first {
        if actionsPane != nil { filterActions(text) } else { search(text) }
      }
    case "emptyBackspace":
      closeInfo()
      closeActions()
    case "leftover":
      // The arrows over the actions pane move its lit row, the native list leaving them to it.
      if actionsPane != nil, case .bytes(let data)? = args.first,
        let event = CGEvent(withDataAllocator: nil, data: data as CFData) {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if code == 125 { litActions(1) } else if code == 126 { litActions(-1) }
      }
    case "hover":
      if case .int(let index)? = args.first, var pane = actionsPane, index >= 1, index <= pane.shown.count, index != pane.lit {
        pane.lit = index
        actionsPane = pane
        apply(status: status)
      }
    case "highlighted":
      // A move by key closes the info pane, a pointer passing over a row does not.
      if args.count > 1, case .bool(false) = args[1] { closeInfo() }
      if case .int(let index)? = args.first, index != highlight {
        highlight = index
        settlePreview()
        followQuickLook()
      }
    case "choose":
      if case .int(let index)? = args.first {
        if actionsPane != nil { chooseActions(index) } else { act(on: index) }
      }
    case "wantIcons":
      guard case .string(let list)? = args.first else { break }
      let images = list.split(separator: ",").compactMap { Int($0) }
        .filter { $0 >= 1 && $0 <= rows.count }
        .compactMap { i in icon(rows[i - 1]).map { (i - 1, $0, Self.tinted(rows[i - 1])) } }
      if !images.isEmpty { panel.setImages(images) }
    case "listKey":
      if case .bytes(let data)? = args.first { return listKey(data) }
    case "toggleInfo":
      closeActions()
      toggleInfo()
    case "closeInfo":
      closeInfo()
    case "closePanes":
      closeInfo()
      closeActions()
    case "bottomBarAction":
      if case .string(let name)? = args.first, let shown { verb(shown, name) }
    default:
      break
    }
    return false
  }
}

// The panel asks on the main thread, ChooserSource says so.
extension Stage: @preconcurrency ChooserSource {
  public func ask(_ event: String, _ args: [PanelValue]) -> Bool { handle(event, args) }
}
