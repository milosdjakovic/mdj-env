// The launcher's catalog built in the app, step 6.1 of docs/PLAN-STANDALONE.md,
// docs/DESIGN-APP-LAUNCHER.md. Every row that is not an application comes from
// ~/.olm/run/launchercatalog.json, which host/launcher writes once after a load and again after every
// pick, and the applications from AppScan. The order is host/launcher/init.lua's _orderedRows: the
// natural order, applications running first then by name and then the other rows as Hammerspoon
// listed them, with every row picked before above every row never picked, the most recent first,
// and a row of a kind that ignores usage keeping its natural place. It is pure, so the check drives
// it with no app and no Hammerspoon.

import Foundation
import OlmBridge
import OlmKit
@preconcurrency import OlmSearch

public struct CatalogShare: Sendable {
  public struct Entry: Sendable {
    /// The key it is remembered by, nil for a row that is never remembered.
    public var key: String?
    public var title: String
    public var subtitle: String
    public var keywords: [String]
    /// The word its subtitle leads with, which the kinds that ignore usage are named by.
    public var word: String?
    /// The gate it waits on, a Lua predicate's name.
    public var when: String?
    /// The icon as the wire names it, docs/PROTOCOL-BRIDGE.md Icon.
    public var icon: JSON
    /// What Hammerspoon runs when it is chosen, handed back as it came.
    public var item: JSON
  }

  public var entries: [Entry]
  /// An application's subtitle where it has a chord, closed and open, by bundle id.
  public var apps: [String: (closed: String, open: String)]
  public var recency: [String]
  public var ignoreUsage: Set<String>
  /// Hammerspoon's own bundle id, never promoted.
  public var selfBundle: String?
  public var appWord: String
  public var appOpen: String
  /// Whether the launcher a person opens builds its catalog in the app, the launcherCatalog switch.
  public var inApp: Bool

  public static func parse(_ data: Data) -> CatalogShare? {
    guard let j = JSON.decode(data), j["version"].int == 1 else { return nil }
    var apps: [String: (String, String)] = [:]
    for (id, a) in j["apps"].object ?? [:] {
      if let c = a["closed"].string, let o = a["open"].string { apps[id] = (c, o) }
    }
    let entries = (j["rows"].array ?? []).map { r -> Entry in
      var kw: [String] = []
      if let list = r["keywords"].array { kw = list.compactMap(\.string) } else if let s = r["keywords"].string { kw = [s] }
      return Entry(key: r["key"].string, title: r["title"].string ?? "", subtitle: r["subtitle"].string ?? "",
        keywords: kw, word: r["word"].string, when: r["when"].string, icon: r["icon"], item: r["item"])
    }
    return CatalogShare(entries: entries, apps: apps, recency: (j["recency"].array ?? []).compactMap(\.string),
      ignoreUsage: Set((j["ignoreUsage"].array ?? []).compactMap(\.string)), selfBundle: j["self"].string,
      appWord: j["appWord"].string ?? "Application", appOpen: j["appOpen"].string ?? "Application · Open",
      inApp: j["inApp"].bool ?? false)
  }
}

public struct Catalog: Sendable {
  public struct Built: Sendable {
    /// In the resting order.
    public var rows: [Row]
    /// The keys a pick is remembered by, every row's but one never remembered.
    public var remembered: Set<String>
    /// The keys whose kind ignores usage, which take no bonus.
    public var usageFree: Set<String>
    /// What Hammerspoon runs for each row the app built, by its key.
    public var items: [String: JSON]
  }

  /// The catalog in its resting order. gate answers a Lua predicate's name, an unknown one hiding
  /// its row, as the Lua catalog hides a row whose predicate it has none for.
  public static func build(_ share: CatalogShare, apps: [ScannedApp], gate: (String) -> Bool?,
                           icon: (JSON) -> Icon?) -> Built {
    struct Placed {
      var row: Row
      var n: Int
      var rank: Int?
    }
    var rank: [String: Int] = [:]
    for (i, k) in share.recency.enumerated() where rank[k] == nil { rank[k] = i }
    var placed: [Placed] = []
    var remembered = Set<String>(), usageFree = Set<String>()
    var items: [String: JSON] = [:]
    func push(_ row: Row, key: String?, word: String?, item: JSON) {
      let free = word.map(share.ignoreUsage.contains) ?? false
      if let key {
        remembered.insert(key)
        if free { usageFree.insert(key) }
      }
      items[row.key] = item
      placed.append(Placed(row: row, n: placed.count, rank: free ? nil : key.flatMap { rank[$0] }))
    }
    for app in apps {
      let key = "app:\(app.bundleID)"
      let worn = share.apps[app.bundleID]
      let subtitle = app.running ? (worn?.open ?? share.appOpen) : (worn?.closed ?? share.appWord)
      push(Row(key: key, title: app.name, subtitle: subtitle, icon: .app(app.bundleID), filterText: app.name,
        keywords: [share.appWord]), key: key, word: share.appWord,
        item: .object(["kind": .string("app"), "bundleID": .string(app.bundleID)]))
    }
    for (i, e) in share.entries.enumerated() {
      if let when = e.when, gate(when) != true { continue }
      let key = e.key ?? "olm:unremembered:\(i)"
      push(Row(key: key, title: e.title, subtitle: e.subtitle, icon: icon(e.icon), filterText: e.title,
        keywords: e.keywords), key: e.key, word: e.word, item: e.item)
    }
    let rows = placed.sorted { x, y in
      if (x.rank != nil) != (y.rank != nil) { return x.rank != nil }
      if let a = x.rank, let b = y.rank { return a < b }
      return x.n < y.n
    }.map(\.row)
    return Built(rows: rows, remembered: remembered, usageFree: usageFree, items: items)
  }

  /// The rows with the bonus the memory gives each for the query, as host/launcher's _memoryBonus,
  /// none for a row whose kind ignores usage and none on an empty query.
  public static func withBonus(_ built: Built, memory: [String: [String]], query: String) -> [Row] {
    let bonus = QueryMemory.bonus(QueryMemory.order(in: memory, for: query))
    return built.rows.map { row in
      var r = row
      r.bonus = built.usageFree.contains(row.key) ? 0 : bonus[row.key] ?? 0
      return r
    }
  }
}
