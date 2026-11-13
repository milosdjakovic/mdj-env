// The one search every list ranks with, docs/DESIGN-APP.md. An actor of its own, so ranking never
// runs on the main thread, rule 8 of docs/PLAN-STANDALONE.md, and the shared fuzzy's caches stay on
// one thread. The ranking is OlmSearch's port of lib/chooser/rank.lua, pinned by the rank fixtures.

import Foundation
import OlmKit
@preconcurrency import OlmSearch

public actor Searcher {
  private let fuzzy = Fuzzy()

  public init() {}

  /// A source's rows ranked for what is typed, as the level says, and how many the row limit cut.
  /// The text ranked by is the answer's rankText where it names one, the whole query otherwise.
  public func rank(_ answer: RowsAnswer, query: String, level: Level) -> (rows: [Row], more: Int) {
    let rows = answer.rows
    if level.ranking == .source {
      guard let limit = level.rowLimit, limit >= 1, rows.count > limit else { return (rows, 0) }
      return (Array(rows.prefix(limit)), rows.count - limit)
    }
    let ranked = Rank.apply(rows.map(Self.rankRow), query: answer.rankText ?? query,
      rowLimit: level.rowLimit, using: fuzzy)
    return (ranked.order.map { rows[$0] }, ranked.more?.count ?? 0)
  }

  static func rankRow(_ r: Row) -> RankRow {
    RankRow(title: r.title, subTitle: r.subtitle, filterText: r.filterText, keywords: r.keywords, names: r.names,
      pinned: r.pinned, fromQuery: r.fromQuery, tier: r.tier, bonus: r.bonus)
  }
}
