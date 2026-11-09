// The stage, the one thing the chooser panel talks to, docs/DESIGN-APP.md. It holds what every list
// shares and no list decides, the query and its generation, the highlight, the slots, Command and a
// digit, Return and the action on Command and Return, the empty text, the icons and the redraw that
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
// for twice, and no row, a status in place of the rows, shows the pane's empty state. Command and J
// or K scroll it by a wheel notch, the step the Lua pane's scroll keys move, and a scroll over it is
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
  private var source: (any ListSource)?
  private var level: Level?
  private var rows: [OlmKit.Row] = []
  private var highlight = 1
  private var text = ""
  private var generation = 0
  private var task: Task<Void, Never>?
  // The swift chooser's look as the bridge last wrote it, read on every open.
  private var look: Look?
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

  public init(searcher: Searcher = Searcher()) {
    self.searcher = searcher
  }

  /// Opens a source's list with the query in the input field, on the screen the placement choice
  /// names, lib/overlaydisplay.lua's mode.
  public func open(_ next: any ListSource, query: String, screen mode: String? = nil) {
    if let source, source !== next { Task { await source.close() } }
    source = next
    screenMode = mode
    level = nil
    generation += 1
    task?.cancel()
    look = Look.read()
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

  // The pixels to the point of the screens the pane can stand on, which a picture is decoded at.
  private var paneScale: Double { Double(NSScreen.screens.map(\.backingScaleFactor).max() ?? 2) }

  // A preview laid out off the main thread, its picture read there first.
  private nonisolated static func paint(_ preview: OlmKit.Preview, pane: (frame: PaneFrame, tokens: PaneTokens, emptyText: String),
                                        measure: PaneMeasure, scale: Double) async -> PanePaint {
    await Task.detached(priority: .userInitiated) {
      let width = PanePainter.bodyWidth(pane.frame, tokens: pane.tokens)
      let image = preview.body?.picture.flatMap { PanePicture.load($0, width: width, scale: scale) }
      return PanePainter.paint(preview, frame: pane.frame, tokens: pane.tokens, measure: measure, image: image)
    }.value
  }

  public func hide() {
    let waiting = revealPending
    revealPending = false
    revealTask?.cancel()
    heldPaint = nil
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
      // heading drawn alone.
      var drawn = preview
      if preview.pending { drawn.body?.facts = nil }
      let paint = await Self.paint(drawn, pane: pane, measure: measure, scale: scale)
      guard mine == self.previewGeneration else { return }
      self.previewAsking = nil
      self.previewShown = key
      self.drawPane(paint, busy: preview.pending)
      // What the preview said was on its way, drawn where the pane is scrolled once it lands.
      // Asked again while it is still pending, since a download can land as a render begins.
      var waiting = preview.pending
      while waiting {
        guard let landed = await source.previewLanded(pick), !Task.isCancelled,
          mine == self.previewGeneration else { return }
        var drawn = landed
        if landed.pending { drawn.body?.facts = nil }
        let repaint = await Self.paint(drawn, pane: pane, measure: measure, scale: scale)
        guard mine == self.previewGeneration else { return }
        self.drawPane(repaint, reset: false, busy: landed.pending)
        waiting = landed.pending
      }
    }
  }

  // The state the Lua view sends, providers/swift/view.lua's redraw. The first nine rows carry
  // Command and their digit wherever the list scrolls, the selected row Return, and a typed query
  // with no rows says so in the canvas view's words, or the source's status where it has one.
  private func apply(status: String?) {
    var state = ViewState()
    state.placeholder = level?.placeholder ?? ""
    state.highlight = highlight
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
    if case .file(let path)? = r.icon { row.image = icons.object(forKey: path as NSString) }
    return row
  }

  private func icon(_ r: OlmKit.Row) -> NSImage? {
    guard case .file(let path)? = r.icon else { return nil }
    if let image = icons.object(forKey: path as NSString) { return image }
    let image = NSWorkspace.shared.icon(forFile: path)
    icons.setObject(image, forKey: path as NSString)
    return image
  }

  // Return, or an action, on the row at a one based index.
  private func act(on index: Int, action: String? = nil) {
    guard index >= 1, index <= rows.count, let source else { return }
    let pick = Pick(key: rows[index - 1].key, query: text)
    Task {
      let effects = if let action { await source.run(action, on: pick) } else { await source.choose(pick) }
      self.perform(effects)
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
      }
    }
  }

  // How far one scroll key moves the pane, chooser.lua's PANE_SCROLL_STEP.
  private static let paneScrollStep: CGFloat = 120

  // The digit keys one through nine, as virtual key codes.
  private static let digitKeys: [Int64] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

  // A list key the panel did not take, answered true when the stage took it.
  private func listKey(_ data: Data) -> Bool {
    guard let event = CGEvent(withDataAllocator: nil, data: data as CFData) else { return false }
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    // Command and a digit opens the row in that slot, as the engine's _chooseSlot does, where the
    // list shows its numbers.
    if event.flags.contains(.maskCommand), look?.showNumbers == true, let slot = Self.digitKeys.firstIndex(of: code) {
      act(on: slot + 1)
      return true
    }
    // Command and J or K scroll the preview pane, the keys the Lua file search binds for
    // scrollPreviewDown and scrollPreviewUp with the list's leader held, which Hammerspoon passes on
    // as Command and the key while it is the app's list that is open.
    if pane != nil, code == 38 || code == 40, event.flags.contains(.maskCommand),
      event.flags.isDisjoint(with: [.maskControl, .maskAlternate, .maskShift]) {
      if previewShown != nil { paneHost?.scrollBy(code == 38 ? Self.paneScrollStep : -Self.paneScrollStep) }
      return true
    }
    guard code == 36 || code == 76 else { return false }
    if event.flags.contains(.maskCommand) {
      // The manifest's action on Command and Return, reveal for file search.
      let action = source?.manifest.actions.first { $0.chord == ["cmd", "return"] }
      if let action { act(on: highlight, action: action.id) }
      return true
    }
    act(on: highlight)
    return true
  }

  fileprivate func handle(_ event: String, _ args: [PanelValue]) -> Bool {
    switch event {
    case "dismiss", "resignedKey", "pressOutside":
      hide()
    case "text":
      if case .string(let text)? = args.first { search(text) }
    case "highlighted":
      if case .int(let index)? = args.first, index != highlight {
        highlight = index
        settlePreview()
      }
    case "choose":
      if case .int(let index)? = args.first { act(on: index) }
    case "wantIcons":
      guard case .string(let list)? = args.first else { break }
      let images = list.split(separator: ",").compactMap { Int($0) }
        .filter { $0 >= 1 && $0 <= rows.count }
        .compactMap { i in icon(rows[i - 1]).map { (i - 1, $0, false) } }
      if !images.isEmpty { panel.setImages(images) }
    case "listKey":
      if case .bytes(let data)? = args.first { return listKey(data) }
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
