// The launcher as Hammerspoon serves it over the bridge, the bridged source of docs/DESIGN-APP.md,
// step 2.3 of docs/PLAN-STANDALONE.md. It opens the launcher's level once a session starts, keeps
// the rows each answer sends by key and patches them by its changes, docs/PROTOCOL-BRIDGE.md Rows,
// and holds the memory the open sent and each memory notification moves.
//
// In the launcher the memory is the bonus. Each row's bonus is worked out from the memory as
// _memoryBonus does, by the longest remembered prefix of the query, and the bonus the Lua row
// carries is not read, so the searcher that ranks every list ranks this one unchanged. Read only in
// this step. Choosing a row answers nothing until 3.1 serves choose.

import Foundation
import OlmKit
@preconcurrency import OlmSearch

public actor BridgedLauncher: ListSource {
  public nonisolated let manifest = Manifest(name: "launcher", title: "Launcher")

  private let bridge: Bridge
  private var level: String?
  private var placeholder = ""
  private var levelRowLimit: Int?
  private var memory: [String: [String]] = [:]
  private var rows: [String: Row] = [:]
  private var memoryKeys: Set<String> = []
  private var order: [String] = []
  private var revision: String?
  private var names: [String: [String]] = [:]
  private var q = 0

  public init(bridge: Bridge) {
    self.bridge = bridge
  }

  /// A session started, its hello answering the row limit a list naming none takes.
  func connected(rowLimit: Int?) async throws {
    reset()
    let answer = try await bridge.request("open", .object(["what": .object(["launcher": .bool(true)]),
      "query": .string("")]))
    let l = answer["level"]
    guard let id = l["id"].string else { throw BridgeError.malformed("open answered no level") }
    level = id
    placeholder = l["placeholder"].string ?? ""
    switch l["rowLimit"] {
    case .number(let n): levelRowLimit = n >= 1 ? Int(n) : nil
    case .string("none"): levelRowLimit = nil
    default: levelRowLimit = rowLimit
    }
    memory = [:]
    remember(l["memory"].object ?? [:])
  }

  /// The connection went, so the level and every row with it.
  func reset() {
    level = nil
    rows = [:]
    memoryKeys = []
    order = []
    revision = nil
    names = [:]
    memory = [:]
  }

  /// The memory notification, each query named taking its new order and an empty one forgotten.
  func remember(_ changes: [String: JSON]) {
    for (query, order) in changes {
      let keys = (order.array ?? []).compactMap(\.string)
      memory[query] = keys.isEmpty ? nil : keys
    }
  }

  /// The memory as it stands, for a check.
  public func memorySnapshot() -> [String: [String]] { memory }

  /// Whether a launcher level is open.
  public var isOpen: Bool { level != nil }

  public func open(query: String) async -> Level {
    Level(placeholder: placeholder, ranking: .app, rowLimit: levelRowLimit)
  }

  public func rows(_ query: Query) async throws -> RowsAnswer {
    guard let level else { throw BridgeError.gone }
    q += 1
    var params: [String: JSON] = ["level": .string(level), "q": .number(Double(q)), "query": .string(query.text)]
    if let revision { params["have"] = .string(revision) }
    let answer = try await bridge.request("rows", .object(params))
    guard self.level == level else { throw BridgeError.gone }
    for (id, list) in answer["names"].object ?? [:] {
      names[id] = (list.array ?? []).compactMap(\.string)
    }
    if let whole = answer["rows"].array {
      rows = [:]
      memoryKeys = []
      order = []
      for wire in whole { if let row = take(wire) { order.append(row) } }
    } else if let changes = answer["changes"].object {
      for wire in changes["upsert"]?.array ?? [] { _ = take(wire) }
      for key in changes["remove"]?.array ?? [] {
        guard let k = Self.key(key) else { continue }
        rows[k] = nil
        memoryKeys.remove(k)
      }
      if let o = changes["order"]?.array { order = o.compactMap(Self.key) }
    }
    revision = answer["revision"].string ?? revision
    let bonus = QueryMemory.bonus(QueryMemory.order(in: memory, for: query.text))
    let out = order.compactMap { key -> Row? in
      guard var row = rows[key] else { return nil }
      row.bonus = memoryKeys.contains(key) ? bonus[key] ?? 0 : 0
      return row
    }
    return RowsAnswer(rows: out, rankText: answer["rankText"].string)
  }

  /// Of these rows, the keys of those with a memory key, in order, which the Lua shadow names its
  /// rows by, a row the launcher cannot remember, a calculator answer, left out on both sides.
  public func remembered(_ rows: [Row]) -> [String] {
    rows.map(\.key).filter { memoryKeys.contains($0) }
  }

  static func key(_ v: JSON) -> String? {
    v.string ?? v.int.map(String.init)
  }

  // Text, a plain string or runs joined, docs/PROTOCOL-BRIDGE.md The row.
  static func text(_ v: JSON) -> String? {
    if let s = v.string { return s }
    guard let runs = v["runs"].array else { return nil }
    return runs.compactMap { $0["text"].string }.joined()
  }

  // One wire row into the row the stage ranks, kept by its key, its key answered.
  private func take(_ wire: JSON) -> String? {
    guard let key = Self.key(wire["key"]) else { return nil }
    var kw: [String] = []
    if let list = wire["keywords"].array { kw = list.compactMap(\.string) } else if let s = wire["keywords"].string { kw = [s] }
    let rowNames = wire["namesId"].string.flatMap { names[$0] }
    let row = Row(key: key, title: Self.text(wire["title"]) ?? "", subtitle: Self.text(wire["subtitle"]) ?? "",
      filterText: wire["filterText"].string, pinned: wire["pinned"].bool ?? false,
      fromQuery: wire["fromQuery"].bool ?? false, inert: wire["enabled"].bool == false, keywords: kw,
      names: rowNames, tier: wire["tier"].number ?? 0)
    rows[key] = row
    if wire["memoryKey"].string != nil { memoryKeys.insert(key) } else { memoryKeys.remove(key) }
    return key
  }

  public func choose(_ pick: Pick) async -> [Effect] { [] }
  public func run(_ action: String, on pick: Pick) async -> [Effect] { [] }
  public func close() async {}
}
