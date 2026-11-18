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
//
// A LIST OVER A LIST, step 3.3, docs/DESIGN-APP-HOSTED.md. A source's push effect shows the list its
// pushed names in the same window, the one below parked with its text, its highlight, its rows and
// its height, and Backspace on the empty field asks the list on top's back, giving the one below back
// as it was when the list declines. The height glides between the two on the fit curve, as the Lua
// stage's does. A hide closes every list, the top first.

import AppKit
import OlmKit
import OlmLook
@preconcurrency @testable import OlmChooser

@MainActor
public final class Stage {
  private let searcher: Searcher
  private lazy var panel: ChooserPanel = {
    let panel = ChooserPanel(source: self)
    panel.onDown = { [weak self] in self?.wakeDown() }
    return panel
  }()
  // The action whose quickLook effect opened the Quick Look pane, which the pane asks again for
  // each row the highlight lands on, since it follows the highlight, step 1.4c.
  private var lookAction: String?
  private var source: (any ListSource)?
  private var level: Level?
  private var rows: [OlmKit.Row] = []
  private var highlight = 1
  private var text = ""
  // The word a typed hand over kept in the field before the list's own text, step 3.3e, the Lua
  // stage's push prefix. The field shows it and the text after it, the source is asked only the
  // text, and deleting into it gives the list below back with the field at what is left.
  private var prefix = ""
  private var generation = 0
  private var task: Task<Void, Never>?
  // The swift chooser's look as the bridge last wrote it, read on every open.
  private var look: Look?
  // The room a row's text has and the subtitle's font, for a folder fitted to its row, and each
  // character's width in that font, measure.lua's per character sum the Lua list fits with.
  private var rowBudget = 0.0
  private var rowFont: NSFont?
  private var charWidths: [String: Double] = [:]
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
    // The level an action with choices or a confirm opened, step 3.3b, nil at the pane's top.
    var level: PaneLevel?
  }
  // What a level of the actions pane replaced and what its rows choose, the Lua pane's _level.
  private struct PaneLevel {
    let verb: String
    let title: String
    let root: [Bars.ActionRow]
    let choices: [Choice]
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
  // A list just pushed, whose first rows are described at once rather than after the settle, so its
  // preview lands while the window is still widening, Milos's call on 2026-11-17.
  private var describeFirst = false
  private var heldBusy = false
  // A pane a hosted list draws in Lua, step 3.3d: what it drew while an open waited, the highlight
  // generation it was last told, and where the list and its pane were placed, which it is told
  // before any highlight.
  private var heldDrawn: (elements: [PaneElement], height: Double)?
  private var toldGeneration = -1
  private var placedRects: (frame: ScreenRect?, pane: ScreenRect?) = (nil, nil)
  // The placement choice the list was last opened with, for a reopen.
  private var screenMode: String?
  // A list that fits its rows, docs/DESIGN-FIT-HEIGHT.md. The screen and the pane it was placed
  // with, the count the window stands at, and each list's count when it last closed, which a list
  // whose first rows come after the reveal's cap opens at, so it opens at its height as a rule.
  private var placedScreen: NSScreen?
  private var placedPane = false
  private var fitShown: Int?
  private var fitLast: [String: Int] = [:]
  private static let revealCapMs: UInt64 = 150
  // The tool whose list is up, told through onShowing as it goes up and comes down, step 1.4f,
  // docs/DESIGN-APP-LIST-KEYS.md, so Hammerspoon routes its list keys here.
  private var shown: String?
  /// Told a tool's name and true as its list opens and false as it hides. Olm.app's composition
  /// root posts it to Hammerspoon.
  public var onShowing: ((String, Bool) -> Void)?
  /// Whether Hammerspoon serves the keys of a tool's list itself, the serves share, step 3.4. A list
  /// of such a tool pushed over another is told up and the one under it down, so its own keys are
  /// the live ones, and a pop tells the one under it up again. Any other push, a hosted Lua level,
  /// keeps the list under it up, since its keys go through that list. Olm.app's root hands it.
  public var servesKeys: (String) -> Bool = { _ in false }
  /// Told the room a row's text has whenever an open finds it changed, which the composition root
  /// sends Hammerspoon as the bridge's metrics, step 3.2.
  public var onTextBudget: ((Double) -> Void)?
  // Raised on every move of the highlight, so a source over the bridge can say which highlight a
  // Return was pressed on, the bridge's h, step 3.2.
  private var highlightGeneration = 0
  // The close a hide sent its source, which the next open of that source waits for, so a level a
  // source opens for each show is never closed by the hide before it, step 3.2.
  private var closing: Task<Void, Never>?
  // A hide's fade not ended yet, and who waits for it to end. The window stays key while it fades,
  // so the source is told the list closed only once it is ordered out, the protocol's hidden, which
  // a window action run after it would otherwise find focused, found in 3.2's trial on 2026-11-13.
  // A show cuts the fade short and wakes them, and so does downCapMs, so nothing waits for good.
  private var downPending = false
  private var downWaiters: [CheckedContinuation<Void, Never>] = []
  private var downGeneration = 0
  private static let downCapMs: UInt64 = 1000
  // The verbs this step does not run yet, said once each.
  private var unknownVerbs: Set<String> = []
  // The pane element kinds a drawn pane held that the app cannot draw, said once each.
  private var unsupportedPane: Set<String> = []
  // The lists under the one shown, the nearest last, each as it stood when a push covered it.
  private struct Parked {
    let source: any ListSource
    let level: Level
    let text: String
    let prefix: String
    let highlight: Int
    let rows: [OlmKit.Row]
    let status: String?
    let fitShown: Int?
    // The tool told up while this list was on top, told up again when it is given back, step 3.4.
    let shown: String?
  }
  private var parked: [Parked] = []

  public init(searcher: Searcher = Searcher()) {
    self.searcher = searcher
    // OLM_PERF set, the main thread probe the swift chooser uses, its notes written on each hide.
    if ProcessInfo.processInfo.environment["OLM_PERF"] != nil { Perf.start() }
  }

  // The probe's notes since the last hide, appended to ~/.olm/cache/perf.log.
  private func writePerf() {
    guard Perf.on, !Perf.notes.isEmpty else { return }
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".olm/cache/perf.log")
    let text = Perf.notes.joined(separator: "\n") + "\n---\n"
    Perf.notes = []
    if let handle = try? FileHandle(forWritingTo: url) {
      handle.seekToEndOfFile()
      handle.write(Data(text.utf8))
      try? handle.close()
    } else {
      try? text.write(to: url, atomically: true, encoding: .utf8)
    }
  }

  /// Opens a source's list with the query in the input field, on the screen the placement choice
  /// names, lib/overlaydisplay.lua's mode.
  public func open(_ next: any ListSource, query: String, screen mode: String? = nil) {
    wakeDown()
    warmTask?.cancel()
    if let source, source !== next { Task { await source.close() } }
    // Lists a hide did not reach, never the one opening, which closes its own level.
    for stale in parked where stale.source !== next { Task { await stale.source.close() } }
    parked = []
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
    fitShown = nil
    placedScreen = nil
    if let look, let screen = Look.screen(for: mode) {
      panel.applyStyle(look.style())
      let tokens = next.manifest.previewPane != nil ? look.paneTokens() : nil
      placedScreen = screen
      placedPane = tokens != nil
      let (placement, frame) = look.placement(on: screen, pane: tokens != nil)
      panel.place(placement)
      let budget = look.textBudget(on: screen, pane: tokens != nil)
      if budget != rowBudget { onTextBudget?(budget) }
      rowBudget = budget
      let font = look.style().subFont
      if font != rowFont { charWidths = [:] }
      rowFont = font
      if let tokens, let frame, let rect = placement.previewPane, let spec = next.manifest.previewPane {
        pane = (frame, tokens, spec.emptyText)
        if paneHost == nil { paneHost = PaneHost(panel: panel) }
        paneHost?.place(rect)
      }
      placedRects = Self.rects(placement, pane: pane != nil)
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
    prefix = ""
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
    let closing = self.closing
    let placed = placedRects
    task = Task {
      await closing?.value
      if next.manifest.previewPane?.drawn == true { await next.positioned(frame: placed.frame, pane: placed.pane) }
      let level = await next.open(query: query)
      guard mine == self.generation else { return }
      self.level = level
      // Laid out hidden at the count it closed at, so a reveal before the rows lands at it.
      if level.fit, let last = self.fitLast[next.manifest.name] { self.fit(last) }
      self.search(self.text)
    }
  }

  // The system switched between light and dark while the list is up, the panel's watch. The glass
  // follows by itself, so the style, the pane's tokens and the row symbols are read again for the
  // new half and everything on screen is drawn again in it, the preview pane included. Without it
  // the text and icons stayed on the half the list opened on, found on 2026-11-18.
  private func followAppearance() {
    guard let look else { return }
    panel.applyStyle(look.style())
    if let old = pane, let tokens = look.paneTokens() {
      pane = (old.frame, tokens, old.emptyText)
    }
    // The symbols are painted in the title's colour, keyed by it, so the rows take the new half's.
    panel.setRows(rows.map(panelRow))
    apply(status: status)
    guard pane != nil else { return }
    if paneDrawn {
      highlightGeneration += 1
      tellHighlight()
    } else {
      resetPane()
      describe()
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
    if let held = heldDrawn {
      heldDrawn = nil
      heldPaint = nil
      paneHost.draw(elements: held.elements, height: held.height, radius: paneRadius, reset: true)
      return
    }
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
    downPending = true
    downGeneration += 1
    let down = downGeneration
    Task {
      try? await Task.sleep(nanoseconds: Self.downCapMs * 1_000_000)
      if down == self.downGeneration { self.wakeDown() }
    }
    panel.hide()
    writePerf()
    // After the hide, as the Lua file search's onClose destroys its pane once the stage hid.
    paneHost?.close()
    panel.stop()
    if let source {
      // Every list on the stack, the top first, as the Lua stage closes its stack.
      let stack = [source] + parked.reversed().map(\.source)
      parked = []
      closing = Task {
        await self.panelDown()
        for list in stack { await list.close() }
      }
    }
    warmSoon()
  }

  // The window back at the chooser's own height when a list stops fitting its rows, a claim ending
  // or the list below a fitting one given back, on the fit curve while it is up.
  private func unfit() {
    guard fitShown != nil, let look, let screen = placedScreen else { return }
    fitShown = nil
    let (placement, _) = look.placement(on: screen, pane: placedPane)
    panel.place(placement)
  }

  /// The field's text with a level's prefix taken off, the query its source is asked, or nil when the
  /// text no longer starts with the prefix, a delete into the word that reached the level, which gives
  /// the level below back, step 3.3e. host/stage's _strip, test/fixtures/stage/prefix.json.
  public nonisolated static func strip(_ text: String, prefix: String) -> String? {
    guard !prefix.isEmpty else { return text }
    return text.hasPrefix(prefix) ? String(text.dropFirst(prefix.count)) : nil
  }

  // The list a push names shown over the one up now, in the same window, which is parked as it
  // stands. Its level is open on its side already, so only its rows are asked. A typed word's hand
  // over, step 3.3e, keeps the word in the field as the level's prefix and the rest as its text.
  private func push(_ token: String, from parent: any ListSource, handOver: HandOver? = nil) {
    Task {
      guard let child = await parent.pushed(token) else { return }
      guard self.source === parent, let level = self.level, self.panel.isVisible || self.revealPending else {
        await child.close()
        return
      }
      self.closeInfo()
      self.closeActions()
      self.parked.append(Parked(source: parent, level: level, text: self.text, prefix: self.prefix,
        highlight: self.highlight, rows: self.rows, status: self.status, fitShown: self.fitShown, shown: self.shown))
      self.source = child
      self.level = nil
      self.generation += 1
      self.task?.cancel()
      self.resetPane()
      self.describeFirst = true
      self.placeAgain(for: child)
      self.bars = Bars.read(child.manifest.name)
      if self.servesKeys(child.manifest.name) { self.tell(child.manifest.name) }
      self.prefix = handOver?.prefix ?? ""
      self.text = handOver?.query ?? ""
      self.panel.setText(self.prefix + self.text)
      let mine = self.generation
      let placed = self.placedRects
      self.task = Task {
        if child.manifest.previewPane?.drawn == true { await child.positioned(frame: placed.frame, pane: placed.pane) }
        let level = await child.open(query: "")
        guard mine == self.generation else { return }
        self.level = level
        self.search(self.text)
      }
    }
  }

  // Backspace on the empty field of a list over another. The list's own back answers first, and a
  // decline gives the list below back as it was parked, its height with it, and asks its rows again
  // keeping the highlight, as the Lua stage's _back pops.
  // A list opened alone, a tool's own key, step 3.8, is asked too, for a page of its own to leave,
  // and with nothing under it a back it declines does nothing, as the Lua stage does.
  private func back() {
    guard let child = source else { return }
    Task {
      if await child.back() {
        if self.source === child { self.search(self.text, keepHighlight: true) }
        return
      }
      guard self.source === child, self.text.isEmpty, !self.parked.isEmpty else { return }
      self.popChild(child)
    }
  }

  // The list below given back as it was parked, its height with it, its rows asked again keeping
  // the highlight, and the child closed, for a back the child declined or its own pop, step 3.3c.
  // field, the text a delete into the prefix left, is what the field shows then, step 3.3e.
  private func popChild(_ child: any ListSource, field: String? = nil) {
    guard source === child, let parent = parked.popLast() else { return }
    generation += 1
    task?.cancel()
    source = parent.source
    level = parent.level
    resetPane()
    placeAgain(for: parent.source)
    if parent.source.manifest.previewPane?.drawn == true {
      let placed = placedRects, list = parent.source
      Task { await list.positioned(frame: placed.frame, pane: placed.pane) }
    }
    bars = Bars.read(parent.source.manifest.name)
    tell(parent.shown)
    prefix = parent.prefix
    text = field.map { String($0.dropFirst(prefix.count)) } ?? parent.text
    panel.setText(prefix + text)
    rows = parent.rows
    highlight = parent.highlight
    highlightGeneration += 1
    panel.setRows(parent.rows.map(panelRow))
    if let count = parent.fitShown { fit(count) } else { unfit() }
    apply(status: parent.status)
    Task { await child.close() }
    search(text, keepHighlight: field == nil)
  }

  // The window placed again for a list pushed over another or given back, with a pane where its
  // manifest has one and none where it has none, step 3.3d, since a tool's list hosted in the
  // launcher brings a pane the launcher has not. A list with the pane the window already has is
  // placed again only where it draws its pane in Lua, which is then told where it stands.
  private func placeAgain(for list: any ListSource) {
    let wants = list.manifest.previewPane != nil
    guard wants != (pane != nil) || list.manifest.previewPane?.drawn == true else { return }
    guard let look, let screen = placedScreen else { return }
    pane = nil
    fitShown = nil
    let tokens = wants ? look.paneTokens() : nil
    placedPane = tokens != nil
    let (placement, frame) = look.placement(on: screen, pane: placedPane)
    panel.place(placement)
    let budget = look.textBudget(on: screen, pane: placedPane)
    if budget != rowBudget { onTextBudget?(budget) }
    rowBudget = budget
    if let tokens, let frame, let rect = placement.previewPane, let spec = list.manifest.previewPane {
      pane = (frame, tokens, spec.emptyText)
      if paneHost == nil { paneHost = PaneHost(panel: panel) }
      paneHost?.place(rect)
    }
    if pane == nil { paneHost?.close() }
    placedRects = Self.rects(placement, pane: pane != nil)
  }

  // The list's and the pane's rects in Hammerspoon's space, as the Lua stage tells onPositioned.
  private static func rects(_ placement: Placement, pane: Bool) -> (frame: ScreenRect?, pane: ScreenRect?) {
    func r(_ n: NSRect) -> ScreenRect { ScreenRect(x: n.minX, y: n.minY, w: n.width, h: n.height) }
    return (r(placement.canvas), pane ? placement.previewPane.map(r) : nil)
  }

  // Whether the list up now draws its pane in Lua and hands the stage what it drew, step 3.3d.
  private var paneDrawn: Bool { pane != nil && source?.manifest.previewPane?.drawn == true }

  // The row the highlight rests on told to a list that draws its pane, once per generation, a status
  // or no row told as none, so its own describer draws the empty state.
  private func tellHighlight() {
    guard let source, highlightGeneration != toldGeneration else { return }
    toldGeneration = highlightGeneration
    var pick: Pick?
    if highlight >= 1, highlight <= rows.count, !rows[highlight - 1].inert {
      pick = Pick(key: rows[highlight - 1].key, query: text, row: highlight, highlight: highlightGeneration)
    }
    let told = pick
    Task { await source.highlighted(told) }
  }

  /// What a hosted list's pane drew in Lua, drawn where the list is up, step 3.3d. A drawing made for
  /// a highlight the stage has since moved from is dropped, the protocol's Generations, the next one
  /// coming once the list is told the new row.
  public func drawn(_ list: any ListSource, _ drawing: DrawnPane) {
    guard let source, source === list, let pane, paneDrawn, drawing.highlight == highlightGeneration else { return }
    let (elements, unsupported) = PaneElements.read(drawing.elements,
      size: NSSize(width: pane.frame.w, height: pane.frame.h))
    for kind in unsupported where !unsupportedPane.contains(kind) {
      unsupportedPane.insert(kind)
      NSLog("Olm: a pane element the app cannot draw was left out, %@", kind)
    }
    let height = max(drawing.height, pane.frame.h)
    if revealPending {
      heldDrawn = (elements, height)
      reveal()
      return
    }
    paneHost?.draw(elements: elements, height: height, radius: paneRadius, reset: !drawing.keepScroll)
  }

  /// Effects a hosted list's own code asked for outside any request, the bridge's effects
  /// notification, step 3.8, applied where that list is on screen and nowhere else.
  public func applyEffects(_ list: any ListSource, _ effects: [Effect]) {
    guard let source, source === list, panel.isVisible else { return }
    perform(effects, from: list)
  }

  /// A source's list redrawn where it is on screen, its rows asked again for the same text, hold
  /// keeping the highlight on its row, the bridge's effects notification, step 3.3. A list not up
  /// is left alone.
  public func redraw(_ list: any ListSource, hold: Bool) {
    guard let source, source === list, panel.isVisible else { return }
    search(text, keepHighlight: hold)
  }

  // A list that fits its rows placed at a count, only when it differs from the one the window stands
  // at, laid out at once while the window is hidden and reshaped on the fit curve while it is up,
  // the native panel's own place, docs/DESIGN-FIT-HEIGHT.md.
  private func fit(_ count: Int) {
    guard count != fitShown, let look, let screen = placedScreen else { return }
    fitShown = count
    if let name = source?.manifest.name { fitLast[name] = count }
    let (placement, _) = look.placement(on: screen, pane: placedPane, fitRows: count)
    panel.place(placement)
  }

  // The fade of a hide has ended, or a show cut it short.
  private func wakeDown() {
    downPending = false
    let waiting = downWaiters
    downWaiters = []
    for w in waiting { w.resume() }
  }

  // Returns once the window a hide took down is ordered out.
  private func panelDown() async {
    guard downPending else { return }
    await withCheckedContinuation { downWaiters.append($0) }
  }

  // MARK: Warm while hidden

  // A first open after the app sat idle answered its first keys late, traced in step 1.5 on
  // 2026-11-12, the rows, their icons and the top row's preview all read cold, and Milos asked that
  // it be ready in the background. So while the list is hidden the stage reads what a first open
  // reads, the source's prepare and the icons and preview of the rows a screen shows, at launch, a
  // moment after every close and every warmEvery while it sits idle. Nothing is drawn.
  public static let warmEvery: TimeInterval = 600
  private static let warmAfterCloseMs: UInt64 = 1000
  private static let warmRows = 16
  private var warmSources: () -> [any ListSource] = { [] }
  private var warmTimer: Timer?
  private var warmTask: Task<Void, Never>?

  /// Keeps the first open of each source warm from now on, the sources asked again at every warm,
  /// the ones the app serves at that moment.
  public func keepWarm(_ sources: @escaping () -> [any ListSource]) {
    warmSources = sources
    warmTimer?.invalidate()
    warmTimer = Timer.scheduledTimer(withTimeInterval: Self.warmEvery, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.warm() }
    }
    warm()
  }

  private func warmSoon() {
    warmTask?.cancel()
    warmTask = Task {
      try? await Task.sleep(nanoseconds: Self.warmAfterCloseMs * 1_000_000)
      if Task.isCancelled { return }
      self.warm()
    }
  }

  private func warm() {
    guard !panel.isVisible, !revealPending else { return }
    let sources = warmSources()
    guard !sources.isEmpty else { return }
    warmTask?.cancel()
    warmTask = Task {
      for source in sources {
        guard let answer = await source.prepare(), !Task.isCancelled, !self.panel.isVisible else { return }
        let shown = answer.rows.filter { !$0.inert }.prefix(Self.warmRows)
        for row in shown { _ = self.icon(row) }
        if source.manifest.previewPane != nil, let first = shown.first {
          _ = await source.preview(Pick(key: first.key, query: ""))
        }
      }
    }
  }

  private func search(_ text: String, keepHighlight: Bool = false) {
    self.text = text
    generation += 1
    task?.cancel()
    // Until the source has opened its level, the text is kept, and the open searches it.
    guard let source, let level else { return }
    let mine = generation
    let searcher = searcher
    task = Task {
      let query = Query(text: text, generation: mine)
      guard var answer = try? await source.rows(query) else { return }
      var ranked = await searcher.rank(answer, query: text, level: level)
      guard mine == self.generation else { return }
      self.land(ranked.rows, status: answer.status ?? (ranked.rows.isEmpty ? answer.emptyStatus : nil),
        keepHighlight: keepHighlight, fit: answer.fit)
      // A typed word handing the list over, step 3.3e, pushed while this text is still the field's,
      // which the generation says, the claim's rows drawn meanwhile as the Lua launcher draws them.
      if let handOver = answer.handOver { self.push(handOver.token, from: source, handOver: handOver) }
      // A newer answer on its way, an index being rebuilt, drawn where the person is when it lands.
      while answer.pending {
        guard let next = try? await source.rowsLanded(query), !Task.isCancelled else { return }
        answer = next
        ranked = await searcher.rank(answer, query: text, level: level)
        guard mine == self.generation else { return }
        self.land(ranked.rows, status: answer.status ?? (ranked.rows.isEmpty ? answer.emptyStatus : nil),
          keepHighlight: true, fit: answer.fit)
      }
    }
  }

  /// keepHighlight holds the highlight on the row it rests on where the new rows still hold it, for
  /// an answer landing under a query the person has not changed. fit is the answer's own, a claim's
  /// in the launcher, the window as tall as the rows while it holds.
  private func land(_ next: [OlmKit.Row], status: String?, keepHighlight: Bool = false, fit answerFit: Bool = false) {
    // A status the list draws as a row joins the rows, the Lua chooser's statusRow.
    var next = next, status = status
    if let said = status, let row = source?.manifest.statusRow(said) {
      next.append(row)
      status = nil
    }
    let resting = highlight >= 1 && highlight <= rows.count ? rows[highlight - 1].key : nil
    // The same rows in the same order are left as they are drawn, so a keystroke that does not
    // change the results redraws nothing.
    if next != rows {
      rows = next
      panel.setRows(next.map(panelRow))
      Perf.note("rows set")
    }
    let was = highlight
    if level?.fit == true || answerFit { fit(max(1, next.count)) } else { unfit() }
    if keepHighlight, let resting, let at = next.firstIndex(where: { $0.key == resting }) {
      highlight = at + 1
    } else {
      highlight = next.isEmpty ? 0 : 1
    }
    if highlight != was || resting != (highlight >= 1 ? next[highlight - 1].key : nil) { highlightGeneration += 1 }
    apply(status: status)
    // The first rows of an open show the window, at once without a pane and once the first row is
    // described with one, which the open asks for without the settle, as the Lua pane's first dock.
    if revealPending {
      if pane == nil { reveal() } else { describe() }
      return
    }
    if describeFirst, pane != nil {
      describeFirst = false
      if !paneDrawn { watchStale() }
      describe()
      return
    }
    describeFirst = false
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
    toldGeneration = -1
    heldDrawn = nil
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
    if !paneDrawn { watchStale() }
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
    if paneDrawn {
      tellHighlight()
      return
    }
    guard highlight >= 1, highlight <= rows.count else {
      clearPane()
      return
    }
    // A status or a help line has nothing to describe, so the pane shows its empty state.
    if rows[highlight - 1].inert {
      clearPane()
      return
    }
    let key = rows[highlight - 1].key
    Perf.note("describe asked")
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
      Perf.note("preview read")
      // A preview still on its way says so with the spinner rather than its words, the body's
      // heading drawn alone, or with its words over a meter where it says how far it has come.
      var drawn = preview
      if preview.pending, preview.progress == nil { drawn.body?.facts = nil }
      let paint = await Self.paint(drawn, pane: pane, measure: measure, scale: scale,
        shortcut: self.spelled(drawn.body?.shortcut))
      guard mine == self.previewGeneration else { return }
      Perf.note("preview laid out")
      self.previewAsking = nil
      self.previewShown = key
      self.drawPane(paint, busy: Self.spins(preview))
      Perf.note("pane handed")
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
      open.panelHeld = prefix + actionsPane.savedText
      open.panelTitle = actionsPane.level?.title
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

  // A subtitle that is a folder after a lead, fitted to the row by dropping whole folders from its
  // middle, the Lua list's fitDir, the subtitle as given otherwise.
  private func fitted(_ r: OlmKit.Row) -> String {
    guard let lead = r.pathLead, let font = rowFont, rowBudget > 0, r.subtitle.hasPrefix(lead) else { return r.subtitle }
    let width = { (s: String) -> Double in
      var total = 0.0
      for ch in s {
        let k = String(ch)
        if let w = self.charWidths[k] { total += w; continue }
        let w = Double((k as NSString).size(withAttributes: [.font: font]).width)
        self.charWidths[k] = w
        total += w
      }
      return total
    }
    let dir = String(r.subtitle.dropFirst(lead.count))
    return lead + PathFit.elide(dir, budget: rowBudget - width(lead), width: width)
  }

  private func panelRow(_ r: OlmKit.Row) -> OlmChooser.Row {
    var row = OlmChooser.Row()
    row.title = r.title
    row.subtitle = fitted(r)
    row.enabled = !r.inert
    switch r.icon {
    case .file(let path)?: row.image = icons.object(forKey: path as NSString)
    case .symbol?:
      row.image = icon(r)
      row.tint = true
    case .app(let id)?: row.image = icons.object(forKey: "app:" + id as NSString)
    case .emoji(let glyph)?: row.image = icons.object(forKey: "emoji:" + glyph as NSString)
    case .picture(let path)?: row.image = icons.object(forKey: "picture:" + path as NSString)
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
      // Painted as lib/icons/sources/sf.lua paints it, at the look's symbol weight, in the row
      // title's colour, into a bitmap the list redraws in the ink where it stands, so every icon
      // looks the same here as in Hammerspoon's list, stated by Milos on 2026-11-16. A template
      // image drew in AppKit's grey and kept it on the highlight, since the list recolours a
      // bitmap only.
      let style = look?.style() ?? Style()
      let key = "symbol:\(name):\(style.text.description):\(style.symbolWeight.rawValue)" as NSString
      if let image = icons.object(forKey: key) { return image }
      guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 64, weight: style.symbolWeight)),
        let image = Self.painted(symbol, style.text) else { return nil }
      icons.setObject(image, forKey: key)
      return image
    case .app(let id)?:
      let key = "app:" + id as NSString
      if let image = icons.object(forKey: key) { return image }
      guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
      let image = NSWorkspace.shared.icon(forFile: url.path)
      icons.setObject(image, forKey: key)
      return image
    case .emoji(let glyph)?:
      let key = "emoji:" + glyph as NSString
      if let image = icons.object(forKey: key) { return image }
      let image = Self.emojiImage(glyph)
      icons.setObject(image, forKey: key)
      return image
    case .picture(let path)?:
      let key = "picture:" + path as NSString
      if let image = icons.object(forKey: key) { return image }
      guard let image = NSImage(contentsOfFile: path) else { return nil }
      icons.setObject(image, forKey: key)
      return image
    case nil:
      return nil
    }
  }

  // An emoji as Olm's emoji icon source draws it, the glyph at 60 points on a 72 point square,
  // lib/icons, which the list scales down to a row's icon.
  private static func emojiImage(_ glyph: String) -> NSImage {
    let side = 72.0
    return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
      let text = glyph as NSString
      // look-exempt, the emoji source's glyph box, 60 of 72 points, a picture and not text.
      let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 60)]
      let size = text.size(withAttributes: attributes)
      text.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2),
        withAttributes: attributes)
      return true
    }
  }

  // A symbol drawn into a square bitmap 72 points on a side at the sharpest screen's scale, its
  // longest side 60 points, then filled with color through its own alpha, source in, the same box
  // and the same fill lib/icons/sources/sf.lua renders with.
  private static func painted(_ symbol: NSImage, _ color: NSColor) -> NSImage? {
    let side: CGFloat = 72, art: CGFloat = 60
    let scale = max(1, NSScreen.screens.map(\.backingScaleFactor).max() ?? 2)
    let px = Int((side * scale).rounded(.up))
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
      bitsPerPixel: 0) else { return nil }
    // The size in points before the context, which takes its scale from it, or it draws at 1x into
    // the bottom left quarter.
    rep.size = NSSize(width: side, height: side)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let size = symbol.size, k = art / max(size.width, size.height, 1)
    let w = size.width * k, h = size.height * k
    symbol.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
    color.set()
    NSRect(x: 0, y: 0, width: side, height: side).fill(using: .sourceIn)
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: rep.size)
    image.addRepresentation(rep)
    return image
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
  private func act(on index: Int, action: String? = nil, choice: String? = nil, closingPanes: Bool = false) {
    guard index >= 1, index <= rows.count, !rows[index - 1].inert, let source else {
      if closingPanes { closeInfo(); closeActions() }
      return
    }
    let pick = Pick(key: rows[index - 1].key, query: text, row: index, highlight: highlightGeneration)
    let mine = generation
    Task {
      let effects = if let action { await source.run(action, on: pick, choice: choice) } else { await source.choose(pick) }
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
      self.perform(effects, from: source)
    }
  }

  // Quick Look following the highlight, the action that opened it asked again for the row the
  // highlight landed on and its file taken in place, never closing the pane. A row the action
  // has no file for leaves the pane on the file it shows.
  private func followQuickLook() {
    guard panel.quickLookPath != nil, let action = lookAction, let source,
      highlight >= 1, highlight <= rows.count, !rows[highlight - 1].inert else { return }
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
  private func perform(_ effects: [Effect], from answered: (any ListSource)? = nil) {
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
        panel.setText(prefix + text)
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
      case .requery: search(text)
      // A pop asks the rows of the list it gives back, so a redraw beside it is done.
      case .rows(let hold): if !effects.contains(.pop) { search(text, keepHighlight: hold) }
      case .push(let token): if let answered { push(token, from: answered) }
      case .pop: if let answered { popChild(answered) }
      case .setPlaceholder(let text):
        level?.placeholder = text
        apply(status: status)
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
      if source.manifest.actions.contains(where: { $0.id == name }) || source.runsEveryVerb {
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
    if row.verb == "insertSelected" { return true }
    guard source.manifest.actions.contains(where: { $0.id == row.verb }) else {
      if (row.confirm || row.choices), unknownVerbs.insert(row.verb).inserted {
        NSLog("Olm: the actions pane has no level for %@ yet", row.verb)
      }
      return false
    }
    return true
  }

  // Opens the pane over the highlighted row, or closes it. Opening it closes the info pane, as the
  // engine's toggleInfo and the actions pane never stand open together.
  private func toggleActions() {
    if actionsPane != nil {
      closeActions()
      return
    }
    guard bars.panelBar != nil, panel.isVisible, let source, highlight >= 1, highlight <= rows.count,
      !rows[highlight - 1].inert else { return }
    closeInfo()
    let pick = Pick(key: rows[highlight - 1].key, query: text)
    let candidates = bars.actions.filter { runnable($0) }
    actionsGeneration += 1
    let mine = actionsGeneration
    Task {
      // A source that answers for its own actions says which apply and what each is called, the
      // Lua pane's answer for a hosted list, step 3.3b. The primary stays, Return on the row.
      let answered = await source.actions(on: pick)
      var kept: [Bars.ActionRow] = []
      for var row in candidates {
        if let answered {
          guard row.verb == "insertSelected" || answered[row.verb] != nil else { continue }
          if let word = answered[row.verb], row.verb != "insertSelected" { row.row.title = word }
          kept.append(row)
          continue
        }
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
    panel.setText(prefix + actionsPane.savedText)
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
    let chosen = pane.rows[pane.shown[index - 1]]
    // A row of a level runs its verb with the choice, Cancel steps back and a dimmed one does nothing.
    if let level = pane.level {
      let choice = level.choices[pane.shown[index - 1]]
      if choice.cancel { return stepBackActions() }
      guard choice.enabled else { return }
      if choice.on != nil { return flipChoice(level, at: index) }
      return act(on: pane.savedHighlight, action: level.verb, choice: choice.ref, closingPanes: true)
    }
    if chosen.confirm || chosen.choices { return openLevel(chosen) }
    let verb = chosen.verb
    if verb == "insertSelected" { return act(on: pane.savedHighlight, closingPanes: true) }
    if source?.manifest.actions.contains(where: { $0.id == verb }) == true {
      return act(on: pane.savedHighlight, action: verb, closingPanes: true)
    }
    closeActions()
    self.verb(shown, verb)
  }

  // The level an action with choices or a confirm opens, its rows asked of the source over the row
  // the pane opened on, the pane's own field emptied, as the Lua pane's _choose opens it.
  private func openLevel(_ row: Bars.ActionRow) {
    guard let pane = actionsPane, let source, pane.savedHighlight >= 1, pane.savedHighlight <= rows.count else { return }
    let pick = Pick(key: rows[pane.savedHighlight - 1].key, query: pane.savedText)
    let mine = actionsGeneration
    Task {
      let choices = await source.choices(row.verb, on: pick)
      guard mine == self.actionsGeneration, var pane = self.actionsPane, pane.level == nil else { return }
      let levelRows = self.levelRows(choices, verb: row.verb)
      pane.level = PaneLevel(verb: row.verb, title: row.row.title, root: pane.rows, choices: choices)
      pane.rows = levelRows
      pane.shown = Array(levelRows.indices)
      pane.lit = levelRows.isEmpty ? 0 : 1
      pane.query = ""
      self.actionsPane = pane
      self.panel.setText("")
      self.apply(status: self.status)
    }
  }

  // A switch of a level flipped where it stands, the verb run over the row the pane opened on and
  // the level's rows asked again for their marks, the lit row kept, as the Lua pane's toggle runs.
  private func flipChoice(_ level: PaneLevel, at index: Int) {
    guard let pane = actionsPane, let source, pane.savedHighlight >= 1, pane.savedHighlight <= rows.count else { return }
    let choice = level.choices[pane.shown[index - 1]]
    let pick = Pick(key: rows[pane.savedHighlight - 1].key, query: pane.savedText, row: pane.savedHighlight)
    let mine = actionsGeneration
    Task {
      let effects = await source.run(level.verb, on: pick, choice: choice.ref)
      let choices = await source.choices(level.verb, on: pick)
      guard mine == self.actionsGeneration, var pane = self.actionsPane, pane.level?.verb == level.verb else { return }
      pane.level = PaneLevel(verb: level.verb, title: level.title, root: level.root, choices: choices)
      pane.rows = self.levelRows(choices, verb: level.verb)
      pane.shown = Array(pane.rows.indices)
      pane.lit = min(max(1, index), max(1, pane.rows.count))
      pane.query = ""
      self.actionsPane = pane
      self.apply(status: self.status)
      // What the verb asked of the list beneath, a redraw once the switch changed what it lists.
      self.perform(effects.filter { $0 != .hide }, from: source)
    }
  }

  private func levelRows(_ choices: [Choice], verb: String) -> [Bars.ActionRow] {
    choices.map { c -> Bars.ActionRow in
      let r = OlmKit.Row(key: c.ref, title: c.title, subtitle: c.subtitle, icon: c.icon, inert: !c.enabled)
      var drawn = panelRow(r)
      drawn.subtitle = c.subtitle
      return Bars.ActionRow(row: drawn, verb: verb, applies: nil, confirm: false, choices: false)
    }
  }

  // Out of a level back to the pane's own rows, or out of the pane at its top, the Lua pane's _stepBack.
  private func stepBackActions() {
    guard var pane = actionsPane else { return }
    guard let level = pane.level else { return closeActions() }
    actionsGeneration += 1
    pane.level = nil
    pane.rows = level.root
    pane.shown = Array(level.root.indices)
    pane.lit = level.root.isEmpty ? 0 : 1
    pane.query = ""
    actionsPane = pane
    panel.setText("")
    apply(status: status)
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
    case "appearance":
      followAppearance()
    case "quickLookOpen":
      // The pane's open button is Return on the highlighted row, the file it shows.
      act(on: highlight)
    case "text":
      closeInfo()
      if case .string(let text)? = args.first {
        if actionsPane != nil {
          filterActions(text)
        } else if let query = Self.strip(text, prefix: prefix) {
          search(query)
        } else if let source {
          // A delete into the word a hand over kept, the list below given back with what is left.
          popChild(source, field: text)
        }
      }
    case "emptyBackspace":
      let paneWasOpen = actionsPane != nil
      closeInfo()
      if actionsPane?.level != nil { stepBackActions(); break }
      closeActions()
      if !paneWasOpen { back() }
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
        highlightGeneration += 1
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
