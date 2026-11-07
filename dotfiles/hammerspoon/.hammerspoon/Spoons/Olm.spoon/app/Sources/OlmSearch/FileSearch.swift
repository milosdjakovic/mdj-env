// File search's engine in the app, step 1.3d of docs/PLAN-STANDALONE.md, the counterpart of
// plugins/filesearch/engine.lua for the unscoped search and the recent list.
//
// Every query is parsed with the grammar, answered by the index on its own queue, and ranked on a
// queue of its own with the shared ranking, the row's file name its only searched field as on the
// Lua side, filterText set to the title. Nothing of that runs on the main thread, which only hears
// the answer, so typing never waits. Each query raises a generation and an answer for an older one
// is dropped.
//
// It narrows as the Lua engine does. When the rows held came from a search, were not cut by the
// retain cap and the new query only grew the text over the same files, query.narrows, the held
// rows are ranked again with no ask. Otherwise the index is asked, and while it answers the rows
// on screen stay. An unscoped query shorter than minChars asks for the recent list and ranks it by
// the text typed so far, as the Lua side does, which hands its recent rows to the shared search. A scoped query, a folder walk on the Lua side, is not answered yet, a later step's work,
// and says so.
//
// Frecency, the row's bonus on the Lua side, is step 1.4d, so every bonus here is zero.

import Foundation

public struct FileSearchSettings: Equatable {
  public var types: [String: [String]] = [:]
  public var retainCap = 2000
  public var rowLimit = 200
  public var minChars = 3
  public var recentDays = 7
  public var recentCount = 40
  public init() {}
}

public struct FileSearchAnswer {
  public var rows: [IndexRow]
  /// How many ranked rows the row limit cut, zero for none.
  public var more: Int
  /// What the list says when it shows no rows, nil when it shows some.
  public var status: String?
}

public final class FileSearchEngine {
  public var settings: FileSearchSettings
  private let index: FileIndex
  private let rankQueue = DispatchQueue(label: "olm.filesearch.rank", qos: .userInitiated)
  // Owned by the rank queue alone, since its caches are not safe across threads.
  private let fuzzy = Fuzzy()
  private var generation = 0
  // What the rows held answer, set only from an index answer.
  private var held: (query: FileQuery, rows: [IndexRow], narrowable: Bool)?
  /// How many times the index was asked, for a check that narrowing asks nothing.
  public private(set) var asks = 0

  public init(index: FileIndex, settings: FileSearchSettings) {
    self.index = index
    self.settings = settings
  }

  /// Forgets the rows held, so the next query asks the index again, which a show calls, since
  /// files change between two opens.
  public func reset() {
    generation += 1
    held = nil
  }

  /// Answers raw on the main queue, unless a newer query came first. Called on the main queue.
  public func query(_ raw: String, answer: @escaping (FileSearchAnswer) -> Void) {
    generation += 1
    let mine = generation
    let q = FileQueryGrammar.parse(raw, types: settings.types)
    if q.scope != nil {
      answer(FileSearchAnswer(rows: [], more: 0, status: "A folder search comes with a later step"))
      return
    }
    // What the index is asked for. An unscoped search too short to be worth asking is the recent
    // list, the Lua side's minChars, and the rows are still ranked by what was typed.
    let short = q.kind == .search && q.text.utf8.count < settings.minChars
    let asked = short ? FileQueryGrammar.parse("", types: settings.types) : q
    if let held, held.narrowable, FileQueryGrammar.narrows(held.query, asked) {
      rank(held.rows, for: q, generation: mine, answer: answer)
      return
    }
    // The recent list held already answers any short text, the same list ranked again.
    if let held, asked.kind != .search, held.query == asked {
      rank(held.rows, for: q, generation: mine, answer: answer)
      return
    }
    asks += 1
    index.recentDays = settings.recentDays
    let cap = asked.kind == .recent ? settings.recentCount : settings.retainCap
    index.ask(asked, cap: cap) { [weak self] rows in
      guard let self, self.generation == mine else { return }
      guard let rows else {
        self.held = nil
        answer(FileSearchAnswer(rows: [], more: 0, status: "The file index could not be read"))
        return
      }
      self.held = (asked, rows, asked.kind == .search && rows.count < self.settings.retainCap)
      self.rank(rows, for: q, generation: mine, answer: answer)
    }
  }

  private func rank(_ rows: [IndexRow], for q: FileQuery, generation mine: Int,
                    answer: @escaping (FileSearchAnswer) -> Void) {
    let limit = settings.rowLimit
    rankQueue.async { [weak self] in
      guard let self else { return }
      let ranked: [IndexRow]
      var more = 0
      if !q.text.isEmpty {
        let rankRows = rows.map { RankRow(title: $0.name, filterText: $0.name) }
        let result = Rank.apply(rankRows, query: q.text, rowLimit: limit, using: self.fuzzy)
        ranked = result.order.map { rows[$0] }
        more = result.more?.count ?? 0
      } else {
        ranked = Array(rows.prefix(limit))
        more = max(0, rows.count - limit)
      }
      DispatchQueue.main.async {
        guard self.generation == mine else { return }
        let status: String? = ranked.isEmpty ? (q.kind == .search ? "No matches" : "Nothing changed lately") : nil
        answer(FileSearchAnswer(rows: ranked, more: more, status: status))
      }
    }
  }
}
