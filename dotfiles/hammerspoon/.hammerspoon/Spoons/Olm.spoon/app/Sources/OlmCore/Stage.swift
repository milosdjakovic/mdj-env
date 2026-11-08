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

  public init(searcher: Searcher = Searcher()) {
    self.searcher = searcher
  }

  /// Opens a source's list with the query in the input field, on the screen the placement choice
  /// names, lib/overlaydisplay.lua's mode.
  public func open(_ next: any ListSource, query: String, screen mode: String? = nil) {
    if let source, source !== next { Task { await source.close() } }
    source = next
    level = nil
    generation += 1
    task?.cancel()
    look = Look.read()
    if let look, let screen = Look.screen(for: mode) {
      panel.applyStyle(look.style())
      panel.place(look.placement(on: screen))
    } else {
      // No look has been written yet, so the panel draws on its own defaults until Hammerspoon
      // loads with the piece on.
      NSLog("Olm: no chooser look at %@, the panel's defaults are used", Look.path)
      panel.place(Look.fallback())
    }
    rows = []
    text = query
    panel.setRows([])
    apply(status: nil)
    panel.start()
    // The bridge starts the app hidden, `open -j`, as the shadow is wired, and a hidden app's
    // panel takes key but is never drawn, found in the 1.3f trial on 2026-11-08.
    if NSApp.isHidden { NSApp.unhide(nil) }
    panel.show()
    panel.setText(query)
    let mine = generation
    task = Task {
      let level = await next.open(query: query)
      guard mine == self.generation else { return }
      self.level = level
      self.search(self.text)
    }
  }

  public func hide() {
    guard panel.isVisible else { return }
    generation += 1
    task?.cancel()
    panel.hide()
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
      }
    }
  }

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
      if case .int(let index)? = args.first { highlight = index }
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
