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
//
// Step 3.3, docs/DESIGN-APP-HOSTED.md. A row leading to a tool's list the config hosts answers push,
// and pushed makes the BridgedLevel the stage shows over this one. A rows answer's fit, a scope's
// claim whose tool's list fits its rows, crosses to the stage as the answer's own fit.
//
// Step 3.3e. A row or a typed word leading to a tool the app serves itself answers native, and
// pushed answers the app's own source for that name, as main.swift hands them in. A rows answer's
// handOver, a typed word handing the list over, crosses as the answer's own, and a hosted level it
// opened that the stage did not push is closed, by the next answer or the launcher's close.

import Foundation
import OlmKit
@preconcurrency import OlmSearch

public actor BridgedLauncher: ListSource {
  public nonisolated let manifest = Manifest(name: "launcher", title: "Launcher",
    statuses: [BridgedLauncher.notConnected: StatusLook(title: "Hammerspoon is not connected",
      detail: "Reload Hammerspoon if this stays", symbol: "exclamationmark.triangle")])

  /// What the launcher a person opens says with no session to ask, rather than an empty list that
  /// reads as broken, found on 2026-11-16 with the app listening on a socket file that was gone.
  public static let notConnected = "Hammerspoon is not connected"

  private let bridge: Bridge
  private var level: String?
  private var placeholder = ""
  private var levelRowLimit: Int?
  private var memory: [String: [String]] = [:]
  private var store = RowStore()
  private var q = 0
  private var defaultRowLimit: Int?
  // The levels the last choose's push effects carried, for pushed.
  private var pushes: [String: JSON] = [:]
  // The level whose run waits for hidden, said before that level's close.
  private var waitingHidden: String?
  // The app's own sources by name, a native push's, step 3.3e.
  private let natives: [String: any ListSource]
  // The hosted level the last hand over opened and the stage has not pushed, closed when no answer
  // names it any more.
  private var handedLevel: String?
  private let log: @Sendable (String) -> Void

  /// Whether this is the launcher a person opens, a level for each show, rather than the shadow's.
  public nonisolated let shown: Bool

  public init(bridge: Bridge, shown: Bool = false, natives: [String: any ListSource] = [:],
    log: @escaping @Sendable (String) -> Void = { NSLog("Olm launcher: %@", $0) }) {
    self.bridge = bridge
    self.shown = shown
    self.natives = natives
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
    store.clear()
    level = id
    let wire = WireEffects.level(l, defaultRowLimit: defaultRowLimit)
    placeholder = wire.placeholder
    levelRowLimit = wire.rowLimit
    memory = [:]
    remember(l["memory"].object ?? [:])
  }

  /// A tool's own key, step 3.8, docs/DESIGN-APP-HOSTED.md under 3.8. Its hosted list opened on the
  /// Lua side as the only level, the same level a launcher row pushes, nil when the Lua side does not
  /// host that tool or no session is up. Asked before the stage opens it, since the stage reads a
  /// list's manifest, its name, actions and pane, as it opens.
  public func openTool(_ name: String, query: String, cycle: Bool = false) async -> BridgedLevel? {
    do {
      var what: [String: JSON] = ["tool": .string(name)]
      if cycle { what["cycle"] = .bool(true) }
      let answer = try await bridge.request("open", .object(["what": .object(what),
        "query": .string(query)]))
      guard answer["level"]["id"].string != nil else { return nil }
      let level = BridgedLevel(bridge: bridge, wire: answer["level"], defaultRowLimit: defaultRowLimit, log: log)
      await bridge.hold(level)
      return level
    } catch {
      log("\(name)'s list did not open, \(error)")
      return nil
    }
  }

  /// The connection went, so the level and every row with it.
  func reset() {
    level = nil
    store = RowStore()
    memory = [:]
    pushes = [:]
    waitingHidden = nil
    handedLevel = nil
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
    // The launcher a person opens and found no session at its show asks again at each query, so a
    // connection made while it is up answers the next keystroke, and says why it is empty meanwhile.
    if shown, level == nil { try? await openLevel(query: query.text, fromURL: true) }
    if shown, level == nil { return RowsAnswer(rows: [], status: Self.notConnected) }
    guard let level else { throw BridgeError.gone }
    q += 1
    var params: [String: JSON] = ["level": .string(level), "q": .number(Double(q)), "query": .string(query.text)]
    if let revision = store.revision { params["have"] = .string(revision) }
    let mine = q
    let answer = try await bridge.request("rows", .object(params))
    guard self.level == level else { throw BridgeError.gone }
    // Applied whatever its age, since the next request names this revision, and dropped as an
    // answer when a newer q has gone out since, docs/PROTOCOL-BRIDGE.md Generations.
    store.apply(answer)
    // Read before the age check, so a level a superseded answer opened is still closed later.
    let handed = await handOver(answer["handOver"])
    guard mine == q else { throw BridgeError.answered(BridgeError.stale, "superseded") }
    let owners = shown ? await bridge.icons(store.owners) : [:]
    let bonus = QueryMemory.bonus(QueryMemory.order(in: memory, for: query.text))
    let out = store.order.compactMap { key -> Row? in
      guard var row = store.rows[key] else { return nil }
      row.bonus = store.memoryKeys.contains(key) ? bonus[key] ?? 0 : 0
      if shown { row.icon = store.icon(key, owners: owners) }
      return row
    }
    return RowsAnswer(rows: out, rankText: answer["rankText"].string, fit: answer["fit"].bool ?? false,
      handOver: handed)
  }

  // A rows answer's handOver as the stage pushes it, step 3.3e, a hosted level held for pushed and
  // the one an earlier answer opened closed when this one names another or none.
  private func handOver(_ h: JSON) async -> HandOver? {
    var token: String?
    if let name = h["native"]["name"].string {
      token = WireEffects.native + name
    } else if let id = h["push"]["level"]["id"].string {
      pushes[id] = h["push"]["level"]
      token = id
    }
    let opened = token.flatMap { pushes[$0] == nil ? nil : $0 }
    if let old = handedLevel, old != opened {
      pushes[old] = nil
      _ = try? await bridge.request("close", .object(["level": .string(old)]))
    }
    handedLevel = opened
    guard shown, let token else { return nil }
    return HandOver(token: token, prefix: h["prefix"].string ?? "", query: h["query"].string ?? "")
  }

  /// Of these rows, the keys of those with a memory key, in order, which the Lua shadow names its
  /// rows by, a row the launcher cannot remember, a calculator answer, left out on both sides.
  public func remembered(_ rows: [Row]) -> [String] {
    rows.map(\.key).filter { store.memoryKeys.contains($0) }
  }

  /// Return on a row, docs/PROTOCOL-BRIDGE.md Running anything. The answer's effects become the
  /// stage's, a hide applied first by the stage, after hidden kept until the stage closes the list,
  /// requery searching again, push showing a hosted tool's list over this one, step 3.3, and
  /// unserved, a row that becomes a list the app does not host yet, kept in place and said.
  public func choose(_ pick: Pick) async -> [Effect] {
    guard shown, let level, let ref = store.refs[pick.key] else { return [] }
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
    let wire = WireEffects(answer["effects"].array ?? [], log: log)
    if wire.afterHidden { waitingHidden = level }
    pushes = wire.pushes
    return wire.effects
  }

  public func run(_ action: String, on pick: Pick) async -> [Effect] { [] }

  /// The hosted list a push effect named, held by the bridge so a redraw reaches it, step 3.3.
  public func pushed(_ token: String) async -> (any ListSource)? {
    if token.hasPrefix(WireEffects.native) {
      let name = String(token.dropFirst(WireEffects.native.count))
      guard let source = natives[name] else {
        log("\(name) is a list of the app's own it holds no source for")
        return nil
      }
      return source
    }
    if token == handedLevel { handedLevel = nil }
    guard let wire = pushes.removeValue(forKey: token) else { return nil }
    let child = BridgedLevel(bridge: bridge, wire: wire, defaultRowLimit: defaultRowLimit, log: log)
    await bridge.hold(child)
    return child
  }

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
      store.clear()
      pushes = [:]
      if let handed = handedLevel {
        handedLevel = nil
        _ = try? await bridge.request("close", .object(["level": .string(handed)]))
      }
    }
    _ = try? await bridge.request("close", .object(["level": .string(id)]))
  }
}
