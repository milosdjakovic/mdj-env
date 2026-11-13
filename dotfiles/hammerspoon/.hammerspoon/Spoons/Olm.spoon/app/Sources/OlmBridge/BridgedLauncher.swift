// The launcher as Hammerspoon serves it over the bridge, the bridged source of docs/DESIGN-APP.md,
// step 2.3 of docs/PLAN-STANDALONE.md. It opens the launcher's level once a session starts, keeps
// the rows each answer sends by key and patches them by its changes, docs/PROTOCOL-BRIDGE.md Rows,
// and holds the memory the open sent and each memory notification moves.
//
// In the launcher the memory is the bonus. Each row's bonus is worked out from the memory as
// _memoryBonus does, by the longest remembered prefix of the query, and the bonus the Lua row
// carries is not read, so the searcher that ranks every list ranks this one unchanged.
//
// Two of these run, step 3.2, docs/DESIGN-APP-LAUNCHER.md. The shadow's opens one level when a
// session starts and keeps it, and chooses nothing. The shown one, the launcher a person opens on
// the trial key, opens a level for each show, fromURL, and closes it when the stage closes the
// list, chooses a row over the bridge, says hidden before that close when a run waits for it, and
// draws the icons the rows name. Two, so the shadow's requests never move the shown level's
// revision or its q, as file search keeps its shadow on a source of its own.

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
  private var refs: [String: String] = [:]
  private var iconSpecs: [String: JSON] = [:]
  private var ownerIcons: [String: [String: Icon]] = [:]
  private var defaultRowLimit: Int?
  // The level whose run waits for hidden, said before that level's close.
  private var waitingHidden: String?
  private let log: @Sendable (String) -> Void

  /// Whether this is the launcher a person opens, a level for each show, rather than the shadow's.
  public nonisolated let shown: Bool

  public init(bridge: Bridge, shown: Bool = false,
    log: @escaping @Sendable (String) -> Void = { NSLog("Olm launcher: %@", $0) }) {
    self.bridge = bridge
    self.shown = shown
    self.log = log
  }

  /// A session started, its hello answering the row limit a list naming none takes. The shadow's
  /// opens its level now, and the shown one at its next show.
  func connected(rowLimit: Int?) async throws {
    reset()
    defaultRowLimit = rowLimit
    if shown { return }
    try await openLevel(query: "", fromURL: false)
  }

  private func openLevel(query: String, fromURL: Bool) async throws {
    var what: [String: JSON] = ["what": .object(["launcher": .bool(true)]), "query": .string(query)]
    if fromURL { what["fromURL"] = .bool(true) }
    let answer = try await bridge.request("open", .object(what))
    let l = answer["level"]
    guard let id = l["id"].string else { throw BridgeError.malformed("open answered no level") }
    clearRows()
    level = id
    placeholder = l["placeholder"].string ?? ""
    switch l["rowLimit"] {
    case .number(let n): levelRowLimit = n >= 1 ? Int(n) : nil
    case .string("none"): levelRowLimit = nil
    default: levelRowLimit = defaultRowLimit
    }
    memory = [:]
    remember(l["memory"].object ?? [:])
  }

  /// The connection went, so the level and every row with it.
  func reset() {
    level = nil
    clearRows()
    names = [:]
    memory = [:]
    ownerIcons = [:]
    waitingHidden = nil
  }

  // What one level held, gone with it.
  private func clearRows() {
    rows = [:]
    memoryKeys = []
    order = []
    revision = nil
    refs = [:]
    iconSpecs = [:]
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
    if shown {
      // A show over a show still up, the trial key pressed again, closes the level before.
      if let old = level { await closeLevel(old) }
      do {
        try await openLevel(query: query, fromURL: true)
      } catch {
        log("the launcher did not open, \(error)")
      }
    }
    return Level(placeholder: placeholder, ranking: .app, rowLimit: levelRowLimit)
  }

  public func rows(_ query: Query) async throws -> RowsAnswer {
    guard let level else { throw BridgeError.gone }
    q += 1
    var params: [String: JSON] = ["level": .string(level), "q": .number(Double(q)), "query": .string(query.text)]
    if let revision { params["have"] = .string(revision) }
    let mine = q
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
    // Applied whatever its age, since the next request names this revision, and dropped as an
    // answer when a newer q has gone out since, docs/PROTOCOL-BRIDGE.md Generations.
    guard mine == q else { throw BridgeError.answered(BridgeError.stale, "superseded") }
    if shown { await askIcons() }
    let bonus = QueryMemory.bonus(QueryMemory.order(in: memory, for: query.text))
    let out = order.compactMap { key -> Row? in
      guard var row = rows[key] else { return nil }
      row.bonus = memoryKeys.contains(key) ? bonus[key] ?? 0 : 0
      if shown { row.icon = icon(iconSpecs[key]) }
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
    if let ref = wire["ref"].string { refs[key] = ref }
    iconSpecs[key] = wire["icon"].isNull ? nil : wire["icon"]
    if wire["memoryKey"].string != nil { memoryKeys.insert(key) } else { memoryKeys.remove(key) }
    return key
  }

  // The icon a wire spec names, docs/PROTOCOL-BRIDGE.md Icon, an owner's resolved from its table,
  // sf preferred over emoji as lib/icons prefers them. A mark is drawn blank, no launcher row
  // carrying one yet.
  private func icon(_ spec: JSON?) -> Icon? {
    guard let spec else { return nil }
    if let id = spec["app"].string { return .app(id) }
    if let name = spec["sf"].string { return .symbol(name) }
    if let glyph = spec["emoji"].string { return .emoji(glyph) }
    if let path = spec["file"].string { return .file(path) }
    if let owner = spec["owner"].string, let key = spec["key"].string { return ownerIcons[owner]?[key] }
    return nil
  }

  // Every owner the rows name whose table this connection has not asked for yet, asked once.
  private func askIcons() async {
    var owners = Set<String>()
    for spec in iconSpecs.values {
      if let owner = spec["owner"].string, ownerIcons[owner] == nil { owners.insert(owner) }
    }
    for owner in owners.sorted() {
      var table: [String: Icon] = [:]
      if let answer = try? await bridge.request("icons", .object(["owner": .string(owner)])) {
        for (key, spec) in answer["icons"].object ?? [:] {
          if let name = spec["sf"].string { table[key] = .symbol(name) } else if let glyph = spec["emoji"].string { table[key] = .emoji(glyph) }
        }
      } else {
        log("no icons for \(owner)")
      }
      ownerIcons[owner] = table
    }
  }

  /// Return on a row, docs/PROTOCOL-BRIDGE.md Running anything. The answer's effects become the
  /// stage's, a hide applied first by the stage, after hidden kept until the stage closes the list,
  /// requery searching again, and unserved, a row that becomes another list, kept in place and said.
  public func choose(_ pick: Pick) async -> [Effect] {
    guard shown, let level, let ref = refs[pick.key] else { return [] }
    let began = Date()
    let answer: JSON
    do {
      answer = try await bridge.request("choose", .object(["level": .string(level), "q": .number(Double(q)),
        "h": .number(Double(pick.highlight)), "ref": .string(ref), "row": .number(Double(pick.row)),
        "query": .string(pick.query), "mods": .array([])]))
    } catch {
      log("choose did not answer, \(error)")
      return []
    }
    let took = Date().timeIntervalSince(began) * 1000
    if took > 250 { log(String(format: "choose took %.0f ms", took)) }
    var out: [Effect] = []
    for effect in answer["effects"].array ?? [] {
      if !effect["hide"].isNull {
        out.append(.hide)
      } else if effect["after"].string == "hidden" {
        waitingHidden = level
      } else if !effect["requery"].isNull {
        out.append(.requery)
      } else if !effect["unserved"].isNull {
        log("\(effect["unserved"]["name"].string ?? "a row") becomes another list, which waits for 3.3")
      } else {
        log("an effect this launcher does not apply yet, \(effect.encoded().flatMap { String(data: $0, encoding: .utf8) } ?? "?")")
      }
    }
    return out
  }

  public func run(_ action: String, on pick: Pick) async -> [Effect] { [] }

  /// The stage closed the list. The shown launcher says hidden first when a run waits for it, the
  /// window being ordered out by then, and closes its level.
  public func close() async {
    guard shown, let level else { return }
    await closeLevel(level)
  }

  private func closeLevel(_ id: String) async {
    if waitingHidden == id {
      waitingHidden = nil
      await bridge.notify("hidden", .object(["level": .string(id)]))
    }
    if level == id {
      level = nil
      clearRows()
    }
    _ = try? await bridge.request("close", .object(["level": .string(id)]))
  }
}
