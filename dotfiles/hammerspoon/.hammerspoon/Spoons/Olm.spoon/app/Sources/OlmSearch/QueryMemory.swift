// The launcher's learned memory, what was picked under which query, the Swift port of
// lib/queryassoc.lua, step 2.3 of docs/PLAN-STANDALONE.md. That file's header says why it is one
// decayed number per pair on a clock of picks, with a sticky leader, and
// test/fixtures/ranking/memory.json and launcher.json pin it, so this file only says where the port
// has to take care.
//
// The app does not record picks yet. Hammerspoon does, and sends the memory whole on the launcher's
// open and the queries that moved after each pick, docs/PROTOCOL-BRIDGE.md, and the app reads it
// through `QueryMemory.order(in:for:)`, the same lookup the store's own orderFor walks. The store is
// ported now so the fixtures pin that lookup end to end, and stage 3 finds it ready.

import Foundation

public enum QueryMemory {
  /// Lua's string.lower, A to Z only, byte by byte, never Unicode's case rules, so a query with a
  /// capital outside ASCII finds the same memory the Lua side keeps.
  public static func lowered(_ s: String) -> [UInt8] {
    s.utf8.map { $0 >= 0x41 && $0 <= 0x5A ? $0 + 0x20 : $0 }
  }

  /// The order remembered for the query, or for its longest remembered prefix, best first, the
  /// store's orderFor over the memory Hammerspoon sent. A prefix cut inside a letter is never
  /// looked for, since the bridge never sends one, serve.lua's memoryOut.
  public static func order(in memory: [String: [String]], for query: String) -> [String] {
    let q = lowered(query)
    var i = q.count
    while i >= 1 {
      if let prefix = String(validatingUTF8Bytes: q[0..<i]), let order = memory[prefix], !order.isEmpty {
        return order
      }
      i -= 1
    }
    return []
  }

  /// The launcher's _memoryBonus over an order, one for the leader down to one over the count for
  /// the last, a key named twice keeping its first.
  public static func bonus(_ order: [String]) -> [String: Double] {
    var out: [String: Double] = [:]
    let n = Double(order.count)
    for (i, key) in order.enumerated() where out[key] == nil {
      out[key] = (n - Double(i)) / n
    }
    return out
  }
}

extension String {
  /// The bytes as a string when they are UTF-8, nil when they are not.
  init?(validatingUTF8Bytes bytes: ArraySlice<UInt8>) {
    guard let s = String(bytes: bytes, encoding: .utf8) else { return nil }
    self = s
  }
}

/// lib/queryassoc.lua's instance, one decayed number per query and key.
public final class QueryMemoryStore {
  public struct Options {
    public var decay = 0.80
    public var margin = 0.6
    public var floor = 0.05
    public var maxQueries = 400
    public var minPrefix = 2
    public var maxPrefix = 12
    public init() {}
  }

  struct Record { var v: Double; var k: Int }
  struct Entry { var lead: String?; var n: Int; var s: [String: Record] }

  // Keyed by the query's bytes, since a spelling is cut by bytes and may end inside a letter.
  private var store: [[UInt8]: Entry] = [:]
  private let o: Options

  public init(options: Options = Options(), stored: Any? = nil) {
    o = options
    load(stored)
  }

  private func value(_ r: Record, _ n: Int) -> Double {
    let age = n - r.k
    if age <= 0 { return r.v }
    return r.v * pow(o.decay, Double(age))
  }

  // What hs.settings held, in the shape the Lua store writes, anything else dropped, its loaded().
  private func load(_ raw: Any?) {
    guard let raw = raw as? [String: Any] else { return }
    for (query, e) in raw {
      guard let e = e as? [String: Any], let s = e["s"] as? [String: Any] else { continue }
      var kept: [String: Record] = [:]
      for (key, rec) in s {
        guard let rec = rec as? [String: Any], let v = (rec["v"] as? NSNumber)?.doubleValue,
          let k = (rec["k"] as? NSNumber)?.doubleValue else { continue }
        kept[key] = Record(v: v, k: Int(k))
      }
      guard !kept.isEmpty else { continue }
      let lead = (e["lead"] as? String).flatMap { kept[$0] != nil ? $0 : nil }
      store[Array(query.utf8)] = Entry(lead: lead, n: (e["n"] as? NSNumber)?.intValue ?? 0, s: kept)
    }
  }

  private func trim() {
    guard store.count > o.maxQueries else { return }
    let ranked = store.map { (q, e) -> (q: [UInt8], best: Double) in
      (q, e.s.values.map { value($0, e.n) }.max() ?? 0)
    }.sorted { a, b in a.best != b.best ? a.best > b.best : a.q.lexicographicallyPrecedes(b.q) }
    for r in ranked.dropFirst(o.maxQueries) { store[r.q] = nil }
  }

  private func spellings(_ q: [UInt8]) -> [[UInt8]] {
    let len = q.count
    let from = len >= o.minPrefix ? o.minPrefix : len
    var out: [[UInt8]] = []
    if from <= min(len, o.maxPrefix) {
      for i in from...min(len, o.maxPrefix) { out.append(Array(q[0..<i])) }
    }
    if len > o.maxPrefix { out.append(q) }
    return out
  }

  private func bump(_ query: [UInt8], _ key: String) {
    var e = store[query] ?? Entry(lead: nil, n: 0, s: [:])
    let n = e.n + 1
    e.n = n
    if let rec = e.s[key] {
      e.s[key] = Record(v: value(rec, n) + 1, k: n)
    } else {
      e.s[key] = Record(v: 1, k: n)
    }
    let v = e.s[key]!.v
    for (other, r) in e.s where other != key && value(r, n) < o.floor { e.s[other] = nil }
    if let lead = e.lead, let leader = e.s[lead] {
      if lead != key && v > value(leader, n) + o.margin { e.lead = key }
    } else {
      e.lead = key
    }
    store[query] = e
  }

  /// Records that this key was chosen while this query was in the field.
  public func note(_ query: String, _ key: String) {
    guard !query.isEmpty, !key.isEmpty else { return }
    for spelling in spellings(QueryMemory.lowered(query)) { bump(spelling, key) }
    trim()
  }

  private func entry(for query: String) -> Entry? {
    let q = QueryMemory.lowered(query)
    var i = q.count
    while i >= 1 {
      if let e = store[Array(q[0..<i])] { return e }
      i -= 1
    }
    return nil
  }

  private static func order(_ e: Entry, value: (Record, Int) -> Double) -> [String] {
    let ranked = e.s.map { (key: $0.key, v: value($0.value, e.n)) }
      .sorted { a, b in a.v != b.v ? a.v > b.v : a.key < b.key }
    var out = ranked.map(\.key).filter { $0 != e.lead }
    if let lead = e.lead { out.insert(lead, at: 0) }
    return out
  }

  /// Every key remembered for the query or its longest remembered prefix, best first.
  public func orderFor(_ query: String) -> [String] {
    guard !query.isEmpty, let e = entry(for: query) else { return [] }
    return Self.order(e, value: value)
  }

  /// Drops every key inScope claims and validKeys does not list, an emptied query with it.
  public func prune(valid: [String], inScope: (String) -> Bool) {
    let keep = Set(valid)
    for (q, var e) in store {
      for key in e.s.keys where inScope(key) && !keep.contains(key) {
        e.s[key] = nil
        if e.lead == key { e.lead = nil }
      }
      store[q] = e.s.isEmpty ? nil : e
    }
  }

  /// How many queries are held.
  public var count: Int { store.count }

  /// Every query and its order as Hammerspoon sends the memory, Launcher:memory() with serve.lua's
  /// memoryOut, a spelling that is not UTF-8 left out.
  public func memory() -> [String: [String]] {
    var out: [String: [String]] = [:]
    for (q, e) in store {
      guard let s = String(validatingUTF8Bytes: q[...]) else { continue }
      let order = Self.order(e, value: value)
      if !order.isEmpty { out[s] = order }
    }
    return out
  }
}
