// What you actually use, step 1.4d of docs/PLAN-STANDALONE.md, the port of
// plugins/filesearch/frecency.lua, docs/DESIGN-APP-FRECENCY.md. One number and one time per path,
// decayed by the half life when it is read and raised by one on a use, so a file used ten times
// last year sinks below one used twice this week with no list of times to keep. The weakest are
// dropped past maxEntries, and a gone path is forgotten as top passes over it.
//
// The list that serves file search records the uses, so the app keeps its own store, under the
// plugin's state folder. The Lua history comes over through `<tool>history.json`, which the root
// writes for a list the app serves, and the app takes it whenever it holds a use newer than the
// newest it took last time. While the app serves, the Lua side records nothing, so a reload takes
// nothing, and after a back out and more use there the next flip takes the newer history.

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
  // The newest use of the Lua history taken, so the same history is never taken twice.
  private var took = 0
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

  /// The app's own store, then the Lua history in its place when that holds a newer use than the
  /// newest taken last time. Asked on every open, so a flip takes the history on its first open.
  public func refresh() {
    if !loaded {
      loaded = true
      if let doc = Self.read(file) {
        entries = Self.entries(doc["entries"])
        took = (doc["took"] as? NSNumber)?.intValue ?? 0
      }
    }
    guard let doc = Self.read(history) else { return }
    let lua = Self.entries(doc["entries"])
    let newest = lua.values.map(\.at).max() ?? 0
    guard newest > took else { return }
    entries = lua
    took = newest
    trim(now())
    save()
  }

  private func save() {
    guard let file else { return }
    var raw: [String: Any] = [:]
    for (path, e) in entries { raw[path] = ["score": e.score, "at": e.at] }
    guard let data = try? JSONSerialization.data(withJSONObject: ["took": took, "entries": raw]) else { return }
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

  /// The paths used most, best first, the path breaking a tie. Existence is checked only on those
  /// returned, and a gone one is forgotten as it is passed over.
  public func top(_ n: Int) -> [String] {
    guard n > 0 else { return [] }
    let t = now()
    let ranked = entries.map { ($0.key, decayed($0.value, t)) }
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
