// The one rank engine, the Swift port of lib/chooser/rank.lua, step 1.3b of
// docs/PLAN-STANDALONE.md. That file's header states the row vocabulary and what each field
// means, and test/fixtures/ranking/ pins both the rules and a recorded corpus, so this file only
// says where the port has to take care.
//
// The comparison ends on the row's place in the supplier's list, so it is a total order and any
// sort answers the same as Lua's unstable table.sort does. The port matches through the shared
// fuzzy alone, so every entry is graded, and the branch rank.lua keeps for a matcher answering
// only a score has no counterpart here.

import Foundation

/// One row as rank.lua reads it. A field of the wrong type in Lua reads as absent, which a
/// caller here expresses by leaving it nil or at its default.
public struct RankRow {
  public var title: String?
  public var subTitle: String?
  /// When set, the primary field in place of the title, and the subtitle is not searched.
  public var filterText: String?
  /// What the row answers to without showing it, each a declared secondary field.
  public var keywords: [String]
  /// Further names never shown, matched like the primary.
  public var names: [String]?
  public var pinned: Bool
  public var fromQuery: Bool
  /// Smaller sorts first among ranked rows. NaN reads as zero.
  public var tier: Double
  /// From zero to one, clamped. NaN reads as zero.
  public var bonus: Double

  public init(title: String? = nil, subTitle: String? = nil, filterText: String? = nil,
              keywords: [String] = [], names: [String]? = nil, pinned: Bool = false,
              fromQuery: Bool = false, tier: Double = 0, bonus: Double = 0) {
    self.title = title
    self.subTitle = subTitle
    self.filterText = filterText
    self.keywords = keywords
    self.names = names
    self.pinned = pinned
    self.fromQuery = fromQuery
    self.tier = tier
    self.bonus = bonus
  }

  var tierValue: Double { tier.isNaN ? 0 : tier }
  var bonusValue: Double { bonus.isNaN ? 0 : min(max(bonus, 0), 1) }

  /// rank.lua's fieldsOf, the fields the shared search reads for this row.
  public var fields: SearchFields {
    var secondary: [(text: String, declared: Bool)] = []
    let primary: String
    if let f = filterText {
      primary = f
    } else {
      primary = title ?? ""
      if let s = subTitle, !s.isEmpty { secondary.append((s, false)) }
    }
    for k in keywords where !k.isEmpty { secondary.append((k, true)) }
    return SearchFields(primary: primary, names: names, secondary: secondary)
  }
}

/// What a row limit cut, rank.lua's third answer.
public struct RankCut: Equatable {
  /// How many rows were cut.
  public let count: Int
  /// The 0 based index in the answer just after the last row the limit counts, where a caller
  /// offers the rest. rank.lua answers the same place 1 based.
  public let at: Int
}

public struct Ranked: Equatable {
  /// Indices into the rows handed in, in the order shown.
  public let order: [Int]
  public let more: RankCut?
}

public enum Rank {
  struct Entry {
    let idx: Int
    let match: FuzzyMatch
    let tier: Double
    let bonus: Double
  }

  // M.before, tier ascending, level sum, phrase and fewer further name words, then the bonus,
  // the score and the supplier's place.
  static func before(_ a: Entry, _ b: Entry) -> Bool {
    if a.tier != b.tier { return a.tier < b.tier }
    if a.match.level != b.match.level { return a.match.level > b.match.level }
    if a.match.phrase != b.match.phrase { return a.match.phrase }
    if a.match.fromNames != b.match.fromNames { return a.match.fromNames < b.match.fromNames }
    if a.bonus != b.bonus { return a.bonus > b.bonus }
    if a.match.score != b.match.score { return a.match.score > b.match.score }
    return a.idx < b.idx
  }

  // The supplier's order cut to the limit, every pinned and fromQuery row kept where it stands.
  static func limited(_ rows: [RankRow], _ limit: Int?) -> Ranked {
    let all = Array(rows.indices)
    guard let limit, rows.count > limit else { return Ranked(order: all, more: nil) }
    var out: [Int] = []
    var counted = 0, cut = 0
    var at: Int? = nil
    for i in all {
      if rows[i].fromQuery || rows[i].pinned {
        out.append(i)
      } else if counted < limit {
        counted += 1
        out.append(i)
        at = out.count
      } else {
        cut += 1
      }
    }
    if cut == 0 { return Ranked(order: out, more: nil) }
    return Ranked(order: out, more: RankCut(count: cut, at: at ?? out.count))
  }

  /// M.apply with the shared fuzzy matcher. An empty query, or a searchText answering no text,
  /// keeps the supplier's order. Otherwise fromQuery rows lead, the ranked rows follow cut to
  /// rowLimit, and pinned rows trail, each kept group in the supplier's order. A rowLimit below
  /// one is read as none.
  public static func apply(_ rows: [RankRow], query: String, rowLimit: Int? = nil,
                           searchText: ((String) -> String)? = nil,
                           using fuzzy: Fuzzy = Fuzzy()) -> Ranked {
    let limit = (rowLimit ?? 0) >= 1 ? rowLimit : nil
    if query.isEmpty { return limited(rows, limit) }
    var query = query
    if let searchText {
      let answer = searchText(query)
      if !answer.utf8.contains(where: { !Fuzzy.isSpace($0) }) { return limited(rows, limit) }
      query = answer
    }
    var lead: [Int] = [], trail: [Int] = [], ranked: [Entry] = []
    for (i, row) in rows.enumerated() {
      if row.fromQuery {
        lead.append(i)
      } else if row.pinned {
        trail.append(i)
      } else if let m = fuzzy.match(query, row.fields) {
        ranked.append(Entry(idx: i, match: m, tier: row.tierValue, bonus: row.bonusValue))
      }
    }
    ranked.sort(by: before)
    var out = lead
    for (n, e) in ranked.enumerated() {
      if let limit, n >= limit { break }
      out.append(e.idx)
    }
    var more: RankCut? = nil
    if let limit, ranked.count > limit { more = RankCut(count: ranked.count - limit, at: out.count) }
    out += trail
    return Ranked(order: out, more: more)
  }
}
