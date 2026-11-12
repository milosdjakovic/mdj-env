// What you actually use, step 1.4d of docs/PLAN-STANDALONE.md, the port of
// plugins/filesearch/frecency.lua, docs/DESIGN-APP-FRECENCY.md. One number and one time per path,
// decayed by the half life when it is read and raised by one on a use, so a file used ten times
// last year sinks below one used twice this week with no list of times to keep. The weakest are
// dropped past maxEntries, and a gone path is forgotten as top passes over it.
//
// The app keeps its own store, under the plugin's state folder. The Lua history comes over through
// `<tool>history.json`, which the root writes for a list the app serves, and the app merges it on
// an open whenever the file has changed, each path keeping whichever side used it last, `merge`.
// The Lua side merges this store the same way on every reload, so neither side ever loses a use,
// the launcher's slash scope recording on the Lua side after the flip, a back out and a flip
// again all adding up. Revised from taking the Lua history whole on 2026-11-12, Milos choosing it
// at the 1.5 flip, decisions/olm-standalone.md.

import Foundation

public final class Frecency {
  public struct Entry: Equatable, Sendable {
    public var score: Double
    public var at: Int
    public init(score: Double, at: Int) {
      self.score = score
      self.at = at
    }
  }

  public var halfLifeDays: Double = 14
  public var maxEntries = 500
  private let file: URL?
  private let history: URL?
  private let now: () -> Int
  private let exists: (String) -> Bool
  private var entries: [String: Entry] = [:]
  // When the Lua history merged last was written, so an unchanged one is not read again.
  private var merged: Date?
  private var loaded = false

  /// file is where the app's own store is kept, history the Lua history the root shares, either nil
  /// for a check that keeps nothing.
  public init(file: URL?, history: URL?, now: @escaping () -> Int = { Int(Date().timeIntervalSince1970) },
              exists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
    self.file = file
    self.history = history
    self.now = now
    self.exists = exists
  }

  /// Entries out of a JSON object, tolerating anything not of the shape written, since a store
  /// outlives the code that wrote it and a malformed entry must cost one row rather than the store.
  static func entries(_ raw: Any?) -> [String: Entry] {
    var out: [String: Entry] = [:]
    for (path, value) in raw as? [String: Any] ?? [:] {
      guard !path.isEmpty, let e = value as? [String: Any],
        let score = (e["score"] as? NSNumber)?.doubleValue ?? Double(e["score"] as? String ?? ""),
        let at = (e["at"] as? NSNumber)?.intValue else { continue }
      out[path] = Entry(score: score, at: at)
    }
    return out
  }

  private static func read(_ url: URL?) -> [String: Any]? {
    guard let url, let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

  /// Two stores as one, each path keeping the entry used last, the higher score breaking a tie, so
  /// merging the same store twice changes nothing. plugins/filesearch/frecency.lua's merge.
  public static func merge(_ mine: [String: Entry], _ other: [String: Entry]) -> [String: Entry] {
    var out = mine
    for (path, theirs) in other {
      guard let ours = out[path] else { out[path] = theirs; continue }
      if theirs.at > ours.at || (theirs.at == ours.at && theirs.score > ours.score) { out[path] = theirs }
    }
    return out
  }

  /// The app's own store, then the Lua history merged into it when that file has changed since it
  /// was merged last. Asked on every open, so a flip merges the history on its first open.
  public func refresh() {
    if !loaded {
      loaded = true
      if let doc = Self.read(file) { entries = Self.entries(doc["entries"]) }
    }
    guard let history,
      let stamp = (try? FileManager.default.attributesOfItem(atPath: history.path))?[.modificationDate] as? Date,
      stamp != merged, let doc = Self.read(history) else { return }
    merged = stamp
    let next = Self.merge(entries, Self.entries(doc["entries"]))
    guard next != entries else { return }
    entries = next
    trim(now())
    save()
  }

  private func save() {
    guard let file else { return }
    var raw: [String: Any] = [:]
    for (path, e) in entries { raw[path] = ["score": e.score, "at": e.at] }
    guard let data = try? JSONSerialization.data(withJSONObject: ["entries": raw]) else { return }
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: file, options: .atomic)
  }

  // What an entry is worth right now. Halves every halfLifeDays, so nothing has to be swept.
  private func decayed(_ e: Entry, _ now: Int) -> Double {
    let halfLife = halfLifeDays * 86400
    if halfLife <= 0 { return e.score }
    let age = Double(now - e.at)
    if age <= 0 { return e.score }
    return e.score * pow(0.5, age / halfLife)
  }

  private func trim(_ now: Int) {
    guard entries.count > maxEntries else { return }
    let ranked = entries.map { ($0.key, decayed($0.value, now)) }.sorted { $0.1 > $1.1 }
    for (path, _) in ranked.dropFirst(max(0, maxEntries)) { entries[path] = nil }
  }

  /// That this path was just used. Decay first and then add one, so a use is always worth the same
  /// at the moment it happens.
  public func note(_ path: String) {
    guard !path.isEmpty else { return }
    refresh()
    let t = now()
    entries[path] = Entry(score: entries[path].map { decayed($0, t) + 1 } ?? 1, at: t)
    trim(t)
    save()
  }

  /// Zero for anything never used, which is most paths.
  public func score(_ path: String) -> Double {
    guard let e = entries[path] else { return 0 }
    return decayed(e, now())
  }

  /// engine:preference, the row's bonus from zero to one, saturating so one heavily used file
  /// cannot run away with it, and two uses is already half of it.
  public func preference(_ path: String) -> Double {
    let used = score(path)
    return used <= 0 ? 0 : used / (used + 2)
  }

  /// When the path was last used, nil for one never used.
  public func usedAt(_ path: String) -> Int? { entries[path]?.at }

  /// frecency.orders, the ways the store ranks what it holds, higher first. The store holds two
  /// facts per path, how much it is used and when it was last used, and an order is only which of
  /// them leads, so the choice belongs to whoever composes the list. `use` is the decayed score,
  /// `lastUse` the moment of the last use.
  public enum Order: String, Sendable {
    case use, lastUse
  }

  private func key(_ e: Entry, _ order: Order, _ now: Int) -> Double {
    switch order {
    case .use: return decayed(e, now)
    case .lastUse: return Double(e.at)
    }
  }

  /// The paths best by the order, the path breaking a tie. Existence is checked only on those
  /// returned, and a gone one is forgotten as it is passed over.
  public func top(_ n: Int, by order: Order = .use) -> [String] {
    guard n > 0 else { return [] }
    let t = now()
    let ranked = entries.map { ($0.key, key($0.value, order, t)) }
      .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
    var out: [String] = []
    var forgot = false
    for (path, _) in ranked {
      if out.count >= n { break }
      if exists(path) {
        out.append(path)
      } else {
        entries[path] = nil
        forgot = true
      }
    }
    if forgot { save() }
    return out
  }
}
