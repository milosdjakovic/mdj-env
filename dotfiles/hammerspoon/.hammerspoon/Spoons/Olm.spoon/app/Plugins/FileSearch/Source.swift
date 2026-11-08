// File search, the app's first native plugin, docs/DESIGN-APP.md, the counterpart of
// plugins/filesearch/engine.lua for the unscoped search and the recent list.
//
// It answers through ListSource and knows nothing of the panel. Every query is parsed with the
// grammar and answered by the index, and the rows go to the stage in the index's order with the
// free text the grammar parsed out of the query to rank them by, the presentation's searchText on
// the Lua side. The stage ranks them with the shared search, each row searched by its file name
// alone, filterText set to the title, as on the Lua side.
//
// It narrows as the Lua engine does. When the rows held came from a search, were not cut by the
// retain cap and the new query only grew the text over the same files, query.narrows, the held
// rows are handed over again with no ask. An unscoped query shorter than minChars hands over the
// recent list, which the stage ranks by the text typed so far, as the Lua side hands its recent
// rows to the shared search. A scoped query, a folder walk on the Lua side, is step 1.4e and says
// so. Frecency, the row's bonus on the Lua side, is step 1.4d, so every bonus here is zero.
//
// It answers the preview pane too, step 1.4a, Preview.swift, the highlighted row read in process on
// a thread of its own and described as the Lua side pane describes it.
//
// The settings, file search's types, limits and preview block and its placeholder, are
// config/filesearch.lua's,
// written by the bridge to ~/.olm/run/filesearch.json where the olmapp piece is on and read on
// every open, so the config keeps one owner.

import Foundation
import OlmKit

public struct FileSearchSettings: Equatable, Sendable {
  public var types: [String: [String]] = [:]
  public var retainCap = 2000
  public var rowLimit = 200
  public var minChars = 3
  public var recentDays = 7
  public var recentCount = 40
  public var placeholder = ""
  /// The preview block, what one highlighted row may cost.
  public var preview = PreviewLimits()
  public init() {}

  /// config/filesearch.lua's settings as the bridge wrote them, or the Lua defaults.
  public static func read(from run: URL) -> FileSearchSettings {
    var settings = FileSearchSettings()
    guard let data = try? Data(contentsOf: run.appendingPathComponent("filesearch.json")),
      let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return settings }
    if let types = doc["types"] as? [String: [String]] { settings.types = types }
    let limits = doc["limits"] as? [String: Any] ?? [:]
    if let n = limits["retainCap"] as? Int { settings.retainCap = n }
    if let n = limits["minChars"] as? Int { settings.minChars = n }
    if let n = limits["recentDays"] as? Int { settings.recentDays = n }
    if let n = limits["recentCount"] as? Int { settings.recentCount = n }
    settings.placeholder = doc["placeholder"] as? String ?? ""
    settings.preview = PreviewLimits(doc["preview"] as? [String: Any] ?? [:])
    return settings
  }
}

public actor FileSearchSource: ListSource {
  public nonisolated let manifest = Manifest(name: "filesearch", title: "File Search", actions: [
    Action(id: "reveal", title: "Reveal in Finder", chord: ["cmd", "return"]),
  ], previewPane: PreviewPane(emptyText: FileSearchSource.paneEmptyText))

  /// What the pane says while nothing is highlighted, plugins/filesearch/chooser.lua's emptyText.
  public static let paneEmptyText = "Highlight a file to preview it"

  private let context: PluginContext
  private let index: FileIndex
  public private(set) var settings: FileSearchSettings
  // What the rows held answer, set only from an index answer.
  private var held: (query: FileQuery, rows: [IndexRow], narrowable: Bool)? {
    didSet { folders = nil }
  }
  // Which held rows are folders, by path, built the first time a preview asks.
  private var folders: Set<String>?
  /// How many times the index was asked, for a check that narrowing asks nothing.
  public private(set) var asks = 0

  public init(context: PluginContext, index: FileIndex? = nil, settings: FileSearchSettings? = nil) {
    self.context = context
    self.index = index ?? FileIndex(
      helper: context.resources.appendingPathComponent("fileindex").path,
      index: context.cache.appendingPathComponent("filesearch/file-index.txt").path)
    self.settings = settings ?? FileSearchSettings.read(from: context.run)
  }

  /// Reads the settings again and forgets the rows held, since files change between two opens.
  public func open(query: String) async -> Level {
    settings = FileSearchSettings.read(from: context.run)
    held = nil
    return Level(placeholder: settings.placeholder, ranking: .app, rowLimit: settings.rowLimit,
      titleLineBreak: "truncateMiddle", previewSettleMs: settings.preview.settleMs)
  }

  /// The same with settings handed in rather than read, for a check and for the shadow.
  public func open(settings: FileSearchSettings) {
    self.settings = settings
    held = nil
  }

  public func rows(_ query: Query) async throws -> RowsAnswer {
    let q = FileQueryGrammar.parse(query.text, types: settings.types)
    if q.scope != nil { return RowsAnswer(rows: [], status: "A folder search comes with a later step") }
    let empty = q.kind == .search ? "No matches" : "Nothing changed lately"
    // What the index is asked for. An unscoped search too short to be worth asking is the recent
    // list, the Lua side's minChars, and the rows are still ranked by what was typed.
    let short = q.kind == .search && q.text.utf8.count < settings.minChars
    let asked = short ? FileQueryGrammar.parse("", types: settings.types) : q
    if let held, held.narrowable, FileQueryGrammar.narrows(held.query, asked) {
      return answer(held.rows, q, empty)
    }
    // The recent list held already answers any short text, the same list ranked again.
    if let held, asked.kind != .search, held.query == asked {
      return answer(held.rows, q, empty)
    }
    asks += 1
    index.recentDays = settings.recentDays
    let cap = asked.kind == .recent ? settings.recentCount : settings.retainCap
    let rows: [IndexRow]
    do {
      rows = try await index.ask(asked, cap: cap)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      held = nil
      return RowsAnswer(rows: [], status: "The file index could not be read")
    }
    held = (asked, rows, asked.kind == .search && rows.count < settings.retainCap)
    return answer(rows, q, empty)
  }

  private func answer(_ rows: [IndexRow], _ q: FileQuery, _ empty: String) -> RowsAnswer {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return RowsAnswer(rows: rows.map { Self.row($0, home: home) }, rankText: q.text, emptyStatus: empty)
  }

  static func row(_ r: IndexRow, home: String) -> Row {
    let dir = (r.path as NSString).deletingLastPathComponent
    let shown = dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir
    return Row(key: r.path, title: r.name, subtitle: shown, icon: .file(r.path), filterText: r.name)
  }

  public func choose(_ pick: Pick) async -> [Effect] { [.hide, .openFile(pick.key)] }

  public func run(_ action: String, on pick: Pick) async -> [Effect] {
    action == "reveal" ? [.hide, .revealFile(pick.key)] : []
  }

  /// What the pane beside the list says about a row, sidepanel.lua's show. The read runs on a
  /// thread of its own rather than on this actor, so the rows of the next keystroke never wait on
  /// it, and it is bounded by peekSeconds, after which the row is described by its name alone, as
  /// the Lua pane does when the helper does not answer in time.
  public func preview(_ pick: Pick) async -> Preview? {
    // A folder by the index's word for it, as the Lua row's isDir, and by the read's own stat for a
    // row the rows held no longer name.
    if folders == nil { folders = Set(held?.rows.filter(\.isDir).map(\.path) ?? []) }
    let listed = held?.rows.contains { $0.path == pick.key } ?? false
    let limits = settings.preview
    let peek = await Self.peek(pick.key, limits: limits)
    if Task.isCancelled { return nil }
    let isDir = listed ? (folders?.contains(pick.key) ?? false) : (peek?.attrs?.isDir ?? false)
    return PreviewDescriber.describe(path: pick.key, isDir: isDir, peek: peek, limits: limits,
      now: Int(Date().timeIntervalSince1970), home: FileManager.default.homeDirectoryForCurrentUser.path)
  }

  // The read, or nil once peekSeconds pass first. A read stuck on a disk that is not there finishes
  // on its own thread and is dropped.
  static func peek(_ path: String, limits: PreviewLimits) async -> Peek? {
    let once = Once()
    return await withCheckedContinuation { (done: CheckedContinuation<Peek?, Never>) in
      DispatchQueue.global(qos: .userInitiated).async {
        let peek = Peek.read(path, readCap: limits.readCap, entries: limits.folderEntries)
        if once.claim() { done.resume(returning: peek) }
      }
      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0, limits.peekSeconds)) {
        if once.claim() { done.resume(returning: nil) }
      }
    }
  }

  // The first of two answers to arrive, the other dropped.
  private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
      lock.withLock {
        if done { return false }
        done = true
        return true
      }
    }
  }

  public func close() async {}

  /// Why the shadow of step 1.3e leaves a query out, or nil to compare it. A folder search is step
  /// 1.4e, and the recent list is ordered by frecency on the Lua side, step 1.4d.
  public static func shadowSkip(_ raw: String, settings: FileSearchSettings) -> String? {
    let q = FileQueryGrammar.parse(raw, types: settings.types)
    if q.scope != nil { return "a folder search, step 1.4e" }
    if q.kind != .search || q.text.utf8.count < settings.minChars {
      return "the recent list, ordered by frecency on the Lua side, step 1.4d"
    }
    return nil
  }
}
