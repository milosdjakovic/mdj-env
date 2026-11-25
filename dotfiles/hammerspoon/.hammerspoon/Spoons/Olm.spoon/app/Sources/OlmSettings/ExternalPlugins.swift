// The settings of the plugins Olm.app runs itself, docs/DESIGN-APP-PLUGINS.md, kept by the app in a
// store of its own, ~/.olm/state/plugins.json, since Hammerspoon writes ~/.olm/state/settings.json
// and one file has one writer, decided by Milos on 2026-11-24. Each plugin's olm-plugin.json says
// what it shows in Olm Settings, its switch, its settings and its abilities, and the window draws
// them on its page in Plugins beside the plugins Hammerspoon shares, through the same parts.
//
// Olm's list of abilities is lib/abilities.lua's, the same names and permissions, for a plugin
// Hammerspoon loads, and Abilities below for one the app runs. The two are kept alike by hand
// until Hammerspoon is gone.

import Foundation

/// Olm's list of abilities, each with the permission it rides on, lib/abilities.lua's LIST.
public enum Abilities {
  public struct Entry: Sendable {
    public let title: String
    public let does: String
    public let permission: String
    public let subject: Bool
  }

  public static let permissions: [String: (title: String, olm: Bool)] = [
    "accessibility": ("Accessibility", false), "inputMonitoring": ("Input Monitoring", false),
    "screenRecording": ("Screen Recording", false), "fullDiskAccess": ("Full Disk Access", false),
    "automation": ("Automation", false), "defaultBrowser": ("Default Browser", false),
    "pasteboard": ("Clipboard", true),
  ]

  public static let list: [String: Entry] = [
    "browserProfiles": Entry(title: "Browser Profiles", does: "lists the browsers and their profiles", permission: "fullDiskAccess", subject: false),
    "moveWindows": Entry(title: "Move Windows", does: "moves or sizes another app's window", permission: "accessibility", subject: false),
    "hearKeys": Entry(title: "Hear Keys", does: "passes key presses on", permission: "inputMonitoring", subject: false),
    "captureScreen": Entry(title: "Capture the Screen", does: "takes a picture of the screen", permission: "screenRecording", subject: false),
    "controlApp": Entry(title: "Control", does: "sends that app commands", permission: "automation", subject: true),
    "readFiles": Entry(title: "Read Files", does: "reads files under a declared path", permission: "fullDiskAccess", subject: true),
    "readClipboard": Entry(title: "Read the Clipboard", does: "reads the pasteboard", permission: "pasteboard", subject: false),
    "receiveLinks": Entry(title: "Receive Links", does: "hands it each link while Olm is the default browser", permission: "defaultBrowser", subject: false),
  ]

  /// An ability's entry and its subject, or why it is refused.
  public static func describe(_ use: String) -> (entry: Entry, subject: String?)? {
    let parts = use.split(separator: ":", maxSplits: 1).map(String.init)
    guard let stem = parts.first, let entry = list[stem] else { return nil }
    let subject = parts.count == 2 ? parts[1] : nil
    guard entry.subject == (subject != nil) else { return nil }
    return (entry, subject)
  }
}

/// What a plugin the app runs declares for Olm Settings and the list it shows, read from its
/// olm-plugin.json.
public struct PluginDeclarations: Sendable, Equatable {
  public struct Ability: Sendable, Equatable {
    public var use: String
    public var why: String
    public var breaks: String?
  }

  public struct SettingDecl: Sendable, Equatable {
    public var key: String
    public var kind: String
    public var title: String
    public var detail: String?
    public var scheme: String?
    public var source: String?
    public var fixed: [String]
    public var keywords: [String]
  }

  public struct Verb: Sendable, Equatable {
    public var action: String
    public var title: String
    public var icon: String?
  }

  public var id: String
  public var title: String
  public var description: String
  public var icon: String
  public var abilities: [Ability] = []
  public var settings: [SettingDecl] = []
  /// Return's word and icon, the secondary on Command and Return, and the actions pane's others.
  public var primary: Verb = Verb(action: "insertSelected", title: "Open", icon: nil)
  public var secondary: Verb?
  public var extra: [Verb] = []
  /// The launcher row's detail and its words, nil for no row.
  public var rowDetail: String?
  public var rowKeywords: [String] = []

  public init(id: String, title: String, description: String = "", icon: String = "puzzlepiece.extension") {
    self.id = id
    self.title = title
    self.description = description
    self.icon = icon
  }

  public static func read(folder: URL) -> PluginDeclarations? {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent("olm-plugin.json")),
      let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
    return parse(o)
  }

  public static func parse(_ o: [String: Any]) -> PluginDeclarations? {
    guard let id = o["id"] as? String, let title = o["title"] as? String else { return nil }
    var d = PluginDeclarations(id: id, title: title, description: o["description"] as? String ?? "",
      icon: o["icon"] as? String ?? "puzzlepiece.extension")
    for a in o["abilities"] as? [[String: Any]] ?? [] {
      guard let use = a["use"] as? String, let why = a["why"] as? String else { continue }
      d.abilities.append(Ability(use: use, why: why, breaks: a["breaks"] as? String))
    }
    for s in o["settings"] as? [[String: Any]] ?? [] {
      guard let key = s["key"] as? String, let kind = s["kind"] as? String, let title = s["title"] as? String else { continue }
      d.settings.append(SettingDecl(key: key, kind: kind, title: title, detail: s["detail"] as? String,
        scheme: s["scheme"] as? String, source: s["source"] as? String, fixed: s["fixed"] as? [String] ?? [],
        keywords: s["keywords"] as? [String] ?? []))
    }
    func verb(_ v: Any?, action: String? = nil) -> Verb? {
      guard let v = v as? [String: Any], let title = v["title"] as? String,
        let action = action ?? v["action"] as? String else { return nil }
      return Verb(action: action, title: title, icon: v["icon"] as? String)
    }
    let surface = o["surface"] as? [String: Any] ?? [:]
    if let p = verb(surface["primary"], action: "insertSelected") { d.primary = p }
    d.secondary = verb(surface["secondary"])
    d.extra = (surface["extra"] as? [Any] ?? []).compactMap { verb($0) }
    if let row = o["row"] as? [String: Any] {
      d.rowDetail = row["detail"] as? String ?? ""
      d.rowKeywords = row["keywords"] as? [String] ?? []
    }
    return d
  }

  /// Every action the list runs beyond Return, the secondary first.
  public var verbs: [Verb] { (secondary.map { [$0] } ?? []) + extra }
}

/// The app's own store for its plugins, ~/.olm/state/plugins.json, { version, values }, read and
/// written whole under a lock, since the window and a link's route both read it.
public final class PluginStore: @unchecked Sendable {
  public static let path = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".olm/state/plugins.json")
  private let url: URL
  private let lock = NSLock()

  public init(url: URL = PluginStore.path) { self.url = url }

  public func values() -> [String: Any] {
    lock.lock(); defer { lock.unlock() }
    return read()
  }

  public func value(_ key: String) -> Any? { values()[key] }

  public func set(_ key: String, _ value: Any?) {
    lock.lock(); defer { lock.unlock() }
    var all = read()
    all[key] = value
    write(all)
  }

  /// Every value replaced, an import.
  public func replace(_ values: [String: Any]) {
    lock.lock(); defer { lock.unlock() }
    write(values)
  }

  private func read() -> [String: Any] {
    guard let data = try? Data(contentsOf: url),
      let doc = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
    return doc["values"] as? [String: Any] ?? [:]
  }

  private func write(_ values: [String: Any]) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let doc: [String: Any] = ["version": 1, "values": values]
    if let data = try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys]) {
      try? data.write(to: url, options: .atomic)
    }
  }
}

/// The plugins the app runs, their rows in Olm Settings and what each is allowed now. Set once at
/// launch by the composition root.
public enum ExternalPlugins {
  nonisolated(unsafe) public static var declared: [PluginDeclarations] = []
  /// A folder Olm neither builds nor runs, why, shown as a locked row in Plugins.
  public struct Held: Sendable, Equatable {
    public let id: String
    public let title: String
    public let why: String
    public init(id: String, title: String, why: String) {
      self.id = id
      self.title = title
      self.why = why
    }
  }
  nonisolated(unsafe) public static var held: [Held] = []
  public static let store = PluginStore()
  /// The prefix every row of an app run plugin carries, which the window's change sends here
  /// rather than to Hammerspoon.
  public static let prefix = "ext."

  public static func plugin(_ id: String) -> PluginDeclarations? { declared.first { $0.id == id } }

  static func list(_ key: String) -> [String] { store.value(key) as? [String] ?? [] }

  /// Whether the plugin is switched on in Olm Settings.
  public static func isOn(_ id: String) -> Bool { !list("plugins.off").contains(id) }

  /// Whether Olm does use for the plugin now, declared, on Olm's list and not turned off.
  public static func allowed(_ id: String, _ use: String) -> Bool {
    guard let p = plugin(id), p.abilities.contains(where: { $0.use == use }), Abilities.describe(use) != nil
    else { return false }
    return !list("abilities.off").contains("\(id)/\(use)")
  }

  /// The plugin's own setting, as stored, nil for none.
  public static func value(_ id: String, _ key: String) -> Any? { store.value("\(id).\(key)") }

  /// The first plugin on, declaring use and allowed it, the one a link goes to.
  public static func first(allowed use: String) -> String? {
    declared.first { isOn($0.id) && allowed($0.id, use) }?.id
  }

  /// Every row the window draws for these plugins, in the Plugins section.
  public static func rows() -> [Setting] {
    var out: [Setting] = []
    let off = list("plugins.off"), abilitiesOff = list("abilities.off")
    for p in declared {
      var sw = Setting(id: prefix + p.id, title: p.title, detail: p.description, kind: .switch,
        keywords: [p.id, "plugin", "enable", "disable"], applies: "live", choices: [], min: nil, max: nil,
        step: nil, unit: nil, locked: nil, defaultValue: .flag(true), value: .flag(!off.contains(p.id)))
      sw.plugin = p.id
      out.append(sw)
      for s in p.settings {
        let kind = Setting.Kind(rawValue: s.kind) ?? .other
        let stored = value(p.id, s.key)
        let current: SettingValue = kind == .picks ? .names(stored as? [String] ?? []) : SettingValue(stored)
        var row = Setting(id: "\(prefix)\(p.id).\(s.key)", title: s.title, detail: s.detail, kind: kind,
          keywords: s.keywords, applies: "live", choices: [], min: nil, max: nil, step: nil, unit: nil,
          locked: nil, defaultValue: kind == .picks ? .names([]) : .none, value: current)
        row.page = p.id
        row.scheme = s.scheme
        row.source = s.source
        row.fixed = s.fixed
        out.append(row)
      }
      for a in p.abilities {
        let about = Abilities.describe(a.use)
        let permission = about.map { Abilities.permissions[$0.entry.permission] } ?? nil
        let refused = about == nil ? "is not one of Olm's abilities, so it is refused until Olm adds it" : nil
        let title = about.map { $0.entry.title + ($0.subject.map { " " + $0 } ?? "") } ?? a.use
        var row = Setting(id: "\(prefix)ability.\(p.id).\(a.use)", title: title, detail: a.why, kind: .ability,
          keywords: [a.use, permission?.title ?? "permission", "permission", "ability"], applies: "live",
          choices: [], min: nil, max: nil, step: nil, unit: nil,
          locked: refused.map { "refused, " + $0 }, defaultValue: .flag(refused == nil),
          value: .flag(refused == nil && !abilitiesOff.contains("\(p.id)/\(a.use)")))
        row.page = p.id
        row.ability = Ability(use: a.use, owner: p.id, permission: about?.entry.permission ?? "",
          permissionTitle: permission?.title ?? "", olmGate: permission?.olm ?? false,
          does: about?.entry.does, breaks: a.breaks, refused: refused)
        out.append(row)
      }
    }
    for h in held {
      out.append(Setting(id: prefix + "held." + h.id, title: h.title, detail: nil, kind: .switch,
        keywords: [h.id, "plugin"], applies: "live", choices: [], min: nil, max: nil, step: nil, unit: nil,
        locked: h.why, defaultValue: .flag(false), value: .flag(false)))
    }
    return out
  }

  /// Hammerspoon's share with these plugins' rows added to Plugins, the share the window draws and
  /// the profile scan asks.
  public static func merged(_ share: SettingsShare?) -> SettingsShare? {
    let mine = rows()
    guard !mine.isEmpty else { return share }
    guard let share else {
      return SettingsShare(version: 1, sections: [SettingsSection(id: "plugins", title: "Plugins",
        symbol: "puzzlepiece.extension", settings: mine)])
    }
    var sections = share.sections
    if let i = sections.firstIndex(where: { $0.id == "plugins" }) {
      let s = sections[i]
      sections[i] = SettingsSection(id: s.id, title: s.title, symbol: s.symbol, settings: s.settings + mine)
    } else {
      sections.append(SettingsSection(id: "plugins", title: "Plugins", symbol: "puzzlepiece.extension", settings: mine))
    }
    return SettingsShare(version: share.version, sections: sections)
  }

  /// One row of these plugins changed in the window, value nil a reset. Answers why it was refused.
  public static func change(_ id: String, _ value: SettingValue, reset: Bool) -> String? {
    guard id.hasPrefix(prefix) else { return "is not a setting of a plugin Olm runs" }
    let rest = String(id.dropFirst(prefix.count))
    if rest.hasPrefix("ability.") {
      let parts = rest.dropFirst("ability.".count).split(separator: ".", maxSplits: 1).map(String.init)
      guard parts.count == 2, let p = plugin(parts[0]), p.abilities.contains(where: { $0.use == parts[1] }) else {
        return "is not an ability a plugin declared"
      }
      guard Abilities.describe(parts[1]) != nil else { return "is refused, it is not one of Olm's abilities" }
      let on = reset ? true : (value.flag ?? true)
      toggle("abilities.off", "\(parts[0])/\(parts[1])", off: !on)
      return nil
    }
    if let p = plugin(rest) {
      toggle("plugins.off", p.id, off: !(reset ? true : (value.flag ?? true)))
      return nil
    }
    let parts = rest.split(separator: ".", maxSplits: 1).map(String.init)
    guard parts.count == 2, let p = plugin(parts[0]), let decl = p.settings.first(where: { $0.key == parts[1] }) else {
      return "is not a setting of a plugin Olm runs"
    }
    if reset || value == .none {
      store.set(rest, nil)
      return nil
    }
    switch (decl.kind, value) {
    case ("picks", .names(let names)): store.set(rest, names.isEmpty ? nil : names)
    case (_, .text(let s)): store.set(rest, s)
    case (_, .flag(let b)): store.set(rest, b)
    case (_, .number(let n)): store.set(rest, n)
    default: return "was not a value \(decl.title) takes"
    }
    return nil
  }

  private static func toggle(_ key: String, _ name: String, off: Bool) {
    var names = list(key).filter { $0 != name }
    if off { names.append(name) }
    names.sort()
    store.set(key, names.isEmpty ? nil : names)
  }
}
