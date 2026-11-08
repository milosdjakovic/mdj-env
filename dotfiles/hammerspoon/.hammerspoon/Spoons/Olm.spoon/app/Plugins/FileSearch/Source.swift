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
// The settings, file search's types and limits and its placeholder, are config/filesearch.lua's,
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
    return settings
  }
}

public actor FileSearchSource: ListSource {
  public nonisolated let manifest = Manifest(name: "filesearch", title: "File Search", actions: [
    Action(id: "reveal", title: "Reveal in Finder", chord: ["cmd", "return"]),
  ])

  private let context: PluginContext
  private let index: FileIndex
  public private(set) var settings: FileSearchSettings
  // What the rows held answer, set only from an index answer.
  private var held: (query: FileQuery, rows: [IndexRow], narrowable: Bool)?
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
      titleLineBreak: "truncateMiddle")
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
