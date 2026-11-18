// A hosted tool's list as Hammerspoon serves it over the bridge, step 3.3 of docs/PLAN-STANDALONE.md,
// docs/DESIGN-APP-HOSTED.md. The launcher's choose answering push names a level the Lua side opened
// for a tool's presentation, Keep Awake first, and the stage shows this source over the launcher in
// the same window. Its rows, Return and Backspace are the presentation's own, answered by
// host/bridge/serve.lua, and a redraw the tool asks for from outside any request reaches it as the
// effects notification, which the bridge routes here by the level's id.
//
// What both bridged sources share lives here too, the rows each answer patches, docs/PROTOCOL-BRIDGE.md
// Rows, the icon a wire spec names, the level an open or a push carries and the effects a choose
// answers, so the launcher and a hosted list cannot read the same wire two ways.

import Foundation
import OlmKit

/// The rows a bridged level holds, kept by key and patched by each answer's changes.
struct RowStore {
  var rows: [String: Row] = [:]
  var memoryKeys: Set<String> = []
  var order: [String] = []
  var revision: String?
  var names: [String: [String]] = [:]
  var refs: [String: String] = [:]
  var iconSpecs: [String: JSON] = [:]
  /// A row's own picture by its key, a file the Lua side wrote, docs/PROTOCOL-BRIDGE.md Picture.
  var pictures: [String: String] = [:]

  /// What one level held, gone with it. The names a connection sent are kept.
  mutating func clear() {
    rows = [:]
    memoryKeys = []
    order = []
    revision = nil
    refs = [:]
    iconSpecs = [:]
    pictures = [:]
  }

  /// One rows answer, its whole list or its changes, applied whatever its age, since the next
  /// request names the revision it leaves.
  mutating func apply(_ answer: JSON) {
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
  private mutating func take(_ wire: JSON) -> String? {
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
    pictures[key] = wire["picture"]["path"].string
    if wire["memoryKey"].string != nil { memoryKeys.insert(key) } else { memoryKeys.remove(key) }
    return key
  }

  /// Every owner the rows' icons name.
  var owners: Set<String> {
    Set(iconSpecs.values.compactMap { $0["owner"].string })
  }

  /// The icon a row's wire spec names, docs/PROTOCOL-BRIDGE.md Icon, an owner's resolved from its
  /// table, sf preferred over emoji as lib/icons prefers them. A mark is drawn blank, no row
  /// carrying one yet. A row's own picture is drawn instead of any icon, the protocol's Picture.
  func icon(_ key: String, owners: [String: [String: Icon]]) -> Icon? {
    if let path = pictures[key] { return .picture(path) }
    guard let spec = iconSpecs[key] else { return nil }
    if let id = spec["app"].string { return .app(id) }
    if let name = spec["sf"].string { return .symbol(name) }
    if let glyph = spec["emoji"].string { return .emoji(glyph) }
    if let path = spec["file"].string { return .file(path) }
    if let owner = spec["owner"].string, let key = spec["key"].string { return owners[owner]?[key] }
    return nil
  }
}

/// What a choose or a back answers, as the stage applies it.
struct WireEffects {
  var effects: [Effect] = []
  /// The run Return left waits for hidden, said before the level's close.
  var afterHidden = false
  /// The levels the push effects carry, by their id, for pushed to make a source of.
  var pushes: [String: JSON] = [:]

  init(_ list: [JSON], log: (String) -> Void) {
    for effect in list {
      if !effect["hide"].isNull {
        effects.append(.hide)
      } else if effect["after"].string == "hidden" {
        afterHidden = true
      } else if !effect["requery"].isNull {
        effects.append(.requery)
      } else if !effect["push"].isNull, let id = effect["push"]["level"]["id"].string {
        pushes[id] = effect["push"]["level"]
        effects.append(.push(id))
      } else if !effect["rows"].isNull {
        effects.append(.rows(hold: effect["rows"]["hold"].bool ?? false))
      } else if !effect["pop"].isNull {
        effects.append(.pop)
      } else if !effect["setQuery"].isNull {
        effects.append(.setQuery(effect["setQuery"]["query"].string ?? ""))
      } else if !effect["setPlaceholder"].isNull {
        effects.append(.setPlaceholder(effect["setPlaceholder"]["text"].string ?? ""))
      } else if let name = effect["native"]["name"].string {
        // A tool the app serves itself, its own source pushed over the launcher, step 3.3e.
        effects.append(.push(Self.native + name))
      } else if !effect["unserved"].isNull {
        log("\(effect["unserved"]["name"].string ?? "a row") becomes a list the app does not host yet")
      } else {
        log("an effect the app does not apply yet, \(effect.encoded().flatMap { String(data: $0, encoding: .utf8) } ?? "?")")
      }
    }
  }

  /// The token a native push carries, before the source's name, which no level id begins with.
  static let native = "native:"

  /// The level an open or a push carries, docs/PROTOCOL-BRIDGE.md Opening a list.
  static func level(_ l: JSON, defaultRowLimit: Int?) -> Level {
    let rowLimit: Int?
    switch l["rowLimit"] {
    case .number(let n): rowLimit = n >= 1 ? Int(n) : nil
    case .string("none"): rowLimit = nil
    default: rowLimit = defaultRowLimit
    }
    return Level(placeholder: l["placeholder"].string ?? "", ranking: l["ranking"].string == "source" ? .source : .app,
      rowLimit: rowLimit, fit: l["fit"].bool ?? false)
  }
}

public actor BridgedLevel: ListSource {
  public nonisolated let manifest: Manifest
  /// Every list verb the stage does not run itself is the tool's, run in Lua on the app's row.
  public nonisolated var runsEveryVerb: Bool { true }
  /// The level's id on the Lua side, which the effects notification names.
  public nonisolated let id: String

  private let bridge: Bridge
  private let level: Level
  private let defaultRowLimit: Int?
  private var store = RowStore()
  private var q = 0
  private var closed = false
  private var pushes: [String: JSON] = [:]
  private let log: @Sendable (String) -> Void

  /// A level a push effect carries, its name the tool's, which the bar and the info pane are read by.
  init(bridge: Bridge, wire: JSON, defaultRowLimit: Int?, log: @escaping @Sendable (String) -> Void) {
    self.bridge = bridge
    self.id = wire["id"].string ?? ""
    let name = (wire["name"].string ?? "").lowercased()
    // The actions its list's actions pane runs, step 3.3b, by the ids the push names.
    let actions = (wire["actions"].array ?? []).compactMap(\.string).map { Action(id: $0, title: $0) }
    // A pane the tool draws in Lua and sends as paneDrawn, step 3.3d.
    let pane = wire["previewPane"].bool == true ? PreviewPane(emptyText: "", drawn: true) : nil
    self.manifest = Manifest(name: name, title: name, actions: actions, previewPane: pane)
    self.level = WireEffects.level(wire, defaultRowLimit: defaultRowLimit)
    self.defaultRowLimit = defaultRowLimit
    self.log = log
  }

  /// Opened on the Lua side by the push already, so the level it carried is all there is to say.
  public func open(query: String) async -> Level { level }

  public func rows(_ query: Query) async throws -> RowsAnswer {
    guard !closed else { throw BridgeError.gone }
    q += 1
    var params: [String: JSON] = ["level": .string(id), "q": .number(Double(q)), "query": .string(query.text)]
    if let revision = store.revision { params["have"] = .string(revision) }
    let mine = q
    let answer = try await bridge.request("rows", .object(params))
    store.apply(answer)
    guard mine == q else { throw BridgeError.answered(BridgeError.stale, "superseded") }
    let owners = await bridge.icons(store.owners)
    let rows = store.order.compactMap { key -> Row? in
      guard var row = store.rows[key] else { return nil }
      row.icon = store.icon(key, owners: owners)
      return row
    }
    return RowsAnswer(rows: rows, rankText: answer["rankText"].string)
  }

  public func choose(_ pick: Pick) async -> [Effect] {
    guard !closed, let ref = store.refs[pick.key] else { return [] }
    let answer: JSON
    do {
      answer = try await bridge.request("choose", .object(["level": .string(id), "q": .number(Double(q)),
        "h": .number(Double(pick.highlight)), "ref": .string(ref), "row": .number(Double(pick.row)),
        "query": .string(pick.query), "mods": .array([])]))
    } catch {
      log("choose did not answer, \(error)")
      return []
    }
    let wire = WireEffects(answer["effects"].array ?? [], log: log)
    pushes.merge(wire.pushes) { $1 }
    return wire.effects
  }

  public func run(_ action: String, on pick: Pick) async -> [Effect] {
    await run(action, on: pick, choice: nil)
  }

  // An action of the actions pane on a row, step 3.3b, with the choice its level offered.
  public func run(_ action: String, on pick: Pick, choice: String?) async -> [Effect] {
    guard !closed, let ref = store.refs[pick.key] else { return [] }
    var params: [String: JSON] = ["level": .string(id), "q": .number(Double(q)), "h": .number(Double(pick.highlight)),
      "ref": .string(ref), "row": .number(Double(pick.row)), "query": .string(pick.query), "action": .string(action)]
    if let choice { params["choice"] = .string(choice) }
    let answer: JSON
    do {
      answer = try await bridge.request("run", .object(params))
    } catch {
      log("run did not answer, \(error)")
      return []
    }
    let wire = WireEffects(answer["effects"].array ?? [], log: log)
    pushes.merge(wire.pushes) { $1 }
    return wire.effects
  }

  // The actions that apply to the row and what each is called over it, as the Lua pane lists them.
  public func actions(on pick: Pick) async -> [String: String]? {
    guard !closed, let ref = store.refs[pick.key],
      let answer = try? await bridge.request("actions", .object(["level": .string(id), "h": .number(Double(pick.highlight)),
        "ref": .string(ref)])) else { return nil }
    var out: [String: String] = [:]
    for a in answer["actions"].array ?? [] {
      if let action = a["action"].string { out[action] = a["title"].string ?? action }
    }
    return out
  }

  // The level an action with choices or a confirm opens, its icons resolved as a row's are.
  public func choices(_ action: String, on pick: Pick) async -> [Choice] {
    guard !closed, let ref = store.refs[pick.key],
      let answer = try? await bridge.request("choices", .object(["level": .string(id), "h": .number(Double(pick.highlight)),
        "ref": .string(ref), "action": .string(action)])) else { return [] }
    let list = answer["choices"].array ?? []
    var specs = RowStore()
    let owners = await bridge.icons(Set(list.compactMap { $0["icon"]["owner"].string }))
    return list.compactMap { c -> Choice? in
      guard let ref = c["choice"].string else { return nil }
      specs.iconSpecs[ref] = c["icon"].isNull ? nil : c["icon"]
      return Choice(ref: ref, title: RowStore.text(c["title"]) ?? "", subtitle: RowStore.text(c["subtitle"]) ?? "",
        icon: specs.icon(ref, owners: owners), current: c["current"].bool ?? false,
        enabled: c["enabled"].bool ?? true, cancel: c["cancel"].bool ?? false, on: c["on"].bool)
    }
  }

  public func pushed(_ token: String) async -> (any ListSource)? {
    guard let wire = pushes.removeValue(forKey: token) else { return nil }
    let child = BridgedLevel(bridge: bridge, wire: wire, defaultRowLimit: defaultRowLimit, log: log)
    await bridge.hold(child)
    return child
  }

  public func back() async -> Bool {
    guard !closed, let answer = try? await bridge.request("back", .object(["level": .string(id)])) else { return false }
    return answer["handled"].bool ?? false
  }

  // Where the stage placed the list and its pane, step 3.3d, the protocol's positioned.
  public func positioned(frame: ScreenRect?, pane: ScreenRect?) async {
    guard !closed else { return }
    func rect(_ r: ScreenRect?) -> JSON {
      guard let r else { return .null }
      return .object(["x": .number(r.x), "y": .number(r.y), "w": .number(r.w), "h": .number(r.h)])
    }
    await bridge.notify("positioned", .object(["level": .string(id), "frame": rect(frame), "paneFrame": rect(pane)]))
  }

  // The row the highlight rests on, step 3.3d, the protocol's highlight, which the Lua side tells
  // the presentation's onHighlight and names in every pane it draws after.
  public func highlighted(_ pick: Pick?) async {
    guard !closed else { return }
    var params: [String: JSON] = ["showing": .bool(true), "level": .string(id), "q": .number(Double(q)),
      "h": .number(Double(pick?.highlight ?? 0)), "row": .number(Double(pick?.row ?? 0)),
      "query": .string(pick?.query ?? "")]
    if let pick, let ref = store.refs[pick.key] { params["ref"] = .string(ref) } else { params["ref"] = .null }
    await bridge.notify("highlight", .object(params))
  }

  /// The stage closed this list, popped back or hidden, so its level goes on the Lua side.
  public func close() async {
    guard !closed else { return }
    closed = true
    await bridge.release(id)
    _ = try? await bridge.request("close", .object(["level": .string(id)]))
  }
}
