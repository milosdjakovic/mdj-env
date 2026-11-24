// The settings share, `~/.olm/run/settings.json`, which Hammerspoon writes at every load from
// lib/settings.lua, docs/DESIGN-APP-SETTINGS.md. It holds every section of the Olm Settings window
// in order, and each setting's declaration, its default and its current value. The window draws
// whatever it lists, so a setting added later is one declaration in Lua and nothing here.
//
// Everything in this file is plain data and pure functions, so olm-bridge-check reads a share and
// searches it with no window.

import Foundation

/// One application's own settings on the Applications page, its mode, where its window goes when its
/// key shows it, and the name and path of one added from outside the catalog.
public struct AppOverride: Equatable, Sendable {
  public var mode: String?
  public var name: String?
  public var path: String?
  public var place: AppPlace?
  /// Its key, once the app keeps the catalog, step 6.2b.
  public var key: AppKey?
  public init(mode: String? = nil, name: String? = nil, path: String? = nil, place: AppPlace? = nil,
    key: AppKey? = nil) {
    self.mode = mode
    self.name = name
    self.path = path
    self.place = place
    self.key = key
  }

  init(_ e: [String: Any]) {
    self.init(mode: e["mode"] as? String, name: e["name"] as? String, path: e["path"] as? String,
      place: (e["place"] as? [String: Any]).map(AppPlace.init), key: (e["key"] as? [String: Any]).flatMap(AppKey.init))
  }

  var any: [String: Any] {
    var o: [String: Any] = [:]
    if let mode { o["mode"] = mode }
    if let name { o["name"] = name }
    if let path { o["path"] = path }
    if let place { o["place"] = place.any }
    if let key { o["key"] = key.any }
    return o
  }

  /// Nothing of its own left, so the entry can leave the table, an added app keeping its name and path.
  var empty: Bool { mode == nil && place == nil && key == nil && path == nil }
}

/// An application's key, step 6.2b: the leader by the name a keymap row spells it, hyper, meta or
/// super, none for a plain combination, the key as the keymap names it, its key code and the
/// modifiers beyond the leader.
public struct AppKey: Equatable, Sendable {
  public var leader: String?
  public var key: String
  public var code: Int
  public var mods: [String]
  public init(leader: String?, key: String, code: Int, mods: [String] = []) {
    self.leader = leader
    self.key = key
    self.code = code
    self.mods = mods.sorted()
  }

  init?(_ e: [String: Any]) {
    guard let key = e["key"] as? String, !key.isEmpty, let code = (e["code"] as? NSNumber)?.intValue else { return nil }
    self.init(leader: e["leader"] as? String, key: key, code: code, mods: e["mods"] as? [String] ?? [])
  }

  var any: [String: Any] {
    var o: [String: Any] = ["key": key, "code": code, "mods": mods]
    if let leader { o["leader"] = leader }
    return o
  }

  /// The chord as the keymap spells it, hyper+C.
  public var chord: String { ((leader.map { [$0] } ?? []) + mods + [key]).joined(separator: "+") }

  /// One physical combination, so two keys on it are one.
  public var slot: String { "\(leader ?? "")|\(mods.joined(separator: ","))|\(code)" }
}

/// Where an application's window goes when its key shows it, set in its Customize sheet: the display,
/// where it was, the active one or the one under the pointer, centred or kept where it stands, its
/// size kept or set, in points or a percent of the display with a least and a most, and the padding it
/// keeps from the display's edges. The app's Placement reads the same table.
public struct AppPlace: Equatable, Sendable {
  public var display = "was"
  public var center = false
  public var sized = false
  public var percent = false
  public var width = 1200.0
  public var height = 800.0
  public var minWidth: Double?
  public var minHeight: Double?
  public var maxWidth: Double?
  public var maxHeight: Double?
  public var padX = 0.0
  public var padY = 0.0
  public init() {}

  init(_ o: [String: Any]) {
    display = o["display"] as? String ?? "was"
    center = o["center"] as? Bool ?? false
    if let s = o["size"] as? [String: Any] {
      sized = true
      percent = s["unit"] as? String == "percent"
      width = (s["width"] as? NSNumber)?.doubleValue ?? width
      height = (s["height"] as? NSNumber)?.doubleValue ?? height
      minWidth = (s["minWidth"] as? NSNumber)?.doubleValue
      minHeight = (s["minHeight"] as? NSNumber)?.doubleValue
      maxWidth = (s["maxWidth"] as? NSNumber)?.doubleValue
      maxHeight = (s["maxHeight"] as? NSNumber)?.doubleValue
    }
    if let p = o["padding"] as? [String: Any] {
      padX = (p["x"] as? NSNumber)?.doubleValue ?? 0
      padY = (p["y"] as? NSNumber)?.doubleValue ?? 0
    }
  }

  /// Where it was, kept and kept, which asks for nothing.
  public var isDefault: Bool { display == "was" && !center && !sized }

  public var any: [String: Any] {
    var o: [String: Any] = ["display": display, "center": center]
    if sized {
      var s: [String: Any] = ["width": width, "height": height, "unit": percent ? "percent" : "points"]
      if let minWidth { s["minWidth"] = minWidth }
      if let minHeight { s["minHeight"] = minHeight }
      if let maxWidth { s["maxWidth"] = maxWidth }
      if let maxHeight { s["maxHeight"] = maxHeight }
      o["size"] = s
    }
    if center || sized { o["padding"] = ["x": padX, "y": padY] }
    return o
  }
}

/// One setting's value as the share writes it, a name, a number, on or off, a list of names, or the
/// Applications page's table of applications by bundle id.
public enum SettingValue: Equatable, Sendable {
  case text(String)
  case number(Double)
  case flag(Bool)
  case names([String])
  case apps([String: AppOverride])
  /// Olm's own keys, an action id to its chord, nil for none.
  case keys([String: String?])
  /// The window manager's named sizes, in order.
  case sizes([WindowSize])
  case none

  init(_ any: Any?) {
    switch any {
    case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): self = .flag(n.boolValue)
    case let n as NSNumber: self = .number(n.doubleValue)
    case let s as String: self = .text(s)
    case let a as [Any]: self = .names(a.compactMap { $0 as? String })
    case let o as [String: Any] where !o.isEmpty && o.values.allSatisfy({ $0 is String || $0 is Bool }):
      var keys: [String: String?] = [:]
      for (action, chord) in o { keys[action] = chord as? String }
      self = .keys(keys)
    case let o as [String: Any]:
      var apps: [String: AppOverride] = [:]
      for (bundle, entry) in o {
        guard let e = entry as? [String: Any] else { continue }
        apps[bundle] = AppOverride(e)
      }
      self = .apps(apps)
    default: self = .none
    }
  }

  /// The value as JSONSerialization takes it, what a change sends over the bridge.
  public var any: Any {
    switch self {
    case .text(let s): return s
    case .number(let n): return n
    case .flag(let b): return b
    case .names(let a): return a
    case .apps(let o): return o.mapValues(\.any)
    case .keys(let o): return o.mapValues { $0 as Any? ?? false }
    case .sizes(let list): return list.map(\.any)
    case .none: return NSNull()
    }
  }

  public var text: String? { if case .text(let s) = self { return s }; return nil }
  public var number: Double? { if case .number(let n) = self { return n }; return nil }
  public var flag: Bool? { if case .flag(let b) = self { return b }; return nil }
  /// Olm's own keys, an empty table for the empty list a table with nothing in it is written as.
  public var keys: [String: String?]? {
    if case .keys(let o) = self { return o }
    if case .names(let a) = self, a.isEmpty { return [:] }
    return nil
  }

  /// The named sizes, none for anything else.
  public var sizes: [WindowSize]? {
    if case .sizes(let list) = self { return list }
    return nil
  }

  /// The applications table, an empty one for the empty list a table with nothing in it is written as.
  public var apps: [String: AppOverride]? {
    if case .apps(let o) = self { return o }
    if case .names(let a) = self, a.isEmpty { return [:] }
    return nil
  }
}

/// What the app toggler knows of one application, the Applications page's catalog. hides is what its
/// style and entry state, nil when neither does, and mode its own, nil when it follows.
public struct CatalogApp: Equatable, Sendable {
  public let name: String
  public let bundle: String
  public let style: String?
  public let hides: Bool?
  public let placed: Bool
  public let added: Bool
  public let path: String?
  /// The style's placement in the page's words, a centred window at its size, where the Customize
  /// sheet starts for an app with no place of its own.
  public var placement: AppPlace? = nil

  public init(name: String, bundle: String, style: String?, hides: Bool?, placed: Bool, added: Bool, path: String?,
    placement: AppPlace? = nil) {
    self.name = name
    self.bundle = bundle
    self.style = style
    self.hides = hides
    self.placed = placed
    self.added = added
    self.path = path
    self.placement = placement
  }
}

/// One named size of the window manager, plugins/windowmanager/plan.lua's named size: a name, a width
/// and a height in points or a percent of the screen, one of nine anchors and a display. Its id names
/// its action, small and recording shipped.
public struct WindowSize: Equatable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var width: Double
  public var height: Double
  public var percent: Bool
  public var anchor: String
  public var display: String

  public init(id: String, name: String, width: Double, height: Double, percent: Bool = false,
    anchor: String = "center", display: String = "current") {
    self.id = id
    self.name = name
    self.width = width
    self.height = height
    self.percent = percent
    self.anchor = anchor
    self.display = display
  }

  init?(json any: Any) {
    guard let o = any as? [String: Any], let id = o["id"] as? String, let name = o["name"] as? String,
      let w = o["width"] as? NSNumber, let h = o["height"] as? NSNumber else { return nil }
    self.init(id: id, name: name, width: w.doubleValue, height: h.doubleValue,
      percent: o["unit"] as? String == "percent", anchor: o["anchor"] as? String ?? "center",
      display: o["display"] as? String ?? "current")
  }

  static func list(_ any: Any?) -> [WindowSize] { (any as? [Any] ?? []).compactMap { WindowSize(json: $0) } }

  var any: [String: Any] {
    ["id": id, "name": name, "width": width, "height": height, "unit": percent ? "percent" : "points",
      "anchor": anchor, "display": display]
  }

  /// The two sizes that ship, which can be changed and not removed.
  public var shipped: Bool { id == "small" || id == "recording" }
}

/// One window action as the Window Management page lists it, the window manager's catalog: its name,
/// its title, the part of the page it belongs to and, for a named size, the size's id.
public struct WindowAction: Equatable, Sendable, Identifiable {
  public let action: String
  public let title: String
  public let group: String
  public let size: String?
  public var id: String { action }
}

public struct SettingChoice: Equatable, Sendable, Identifiable {
  public let value: String
  public let title: String
  public var id: String { value }
}

public struct Setting: Equatable, Sendable, Identifiable {
  public enum Kind: String, Sendable { case choice, number, font, `switch`, checkbox, text, apps, keys, sizes, other }

  public let id: String
  public let title: String
  public let detail: String?
  public let kind: Kind
  public let keywords: [String]
  /// "live" when a change applies at once, "reload" when it needs Hammerspoon to load again.
  public let applies: String
  public let choices: [SettingChoice]
  public let min: Double?
  public let max: Double?
  public let step: Double?
  public let unit: String?
  /// Why a person cannot change it here, set in a config file that wins over the window.
  public let locked: String?
  public let defaultValue: SettingValue
  public let value: SettingValue
  /// The app toggler's catalog, for the Applications page, empty for every other setting.
  public var catalog: [CatalogApp] = []
  /// The window manager's actions, for the Window Management page, empty for every other setting.
  public var windowActions: [WindowAction] = []
  /// The plugin whose own page draws this setting, nil for a setting on its section's page.
  public var page: String?
  /// The plugin a switch in Plugins turns on and off, which leads to that plugin's page.
  public var plugin: String?
  /// What an empty text field shows, and the most characters it takes.
  public var placeholder: String?
  public var maxLength: Int?
  /// A text's rows, a list of one entry per line drawn in a box under its title, nil for one line.
  public var lines: Int?

  public var needsReload: Bool { applies == "reload" }
  public var differs: Bool { defaultValue != .none && value != defaultValue }
}

public struct SettingsSection: Equatable, Sendable, Identifiable {
  public let id: String
  public let title: String
  public let symbol: String
  public let settings: [Setting]
}

public struct SettingsShare: Equatable, Sendable {
  public let version: Int
  public let sections: [SettingsSection]

  public static let path = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".olm/run/settings.json")

  /// The share at url, or nil when it is missing or is not one.
  public static func read(from url: URL = path) -> SettingsShare? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return parse(data)
  }

  /// A share from its JSON, nil when it is not one. A setting with no id or title is left out.
  public static func parse(_ data: Data) -> SettingsShare? {
    guard let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let sections = doc["sections"] as? [[String: Any]] else { return nil }
    let version = (doc["version"] as? NSNumber)?.intValue ?? 0
    return SettingsShare(version: version, sections: sections.compactMap { s in
      guard let id = s["id"] as? String, let title = s["title"] as? String else { return nil }
      let rows = (s["settings"] as? [[String: Any]] ?? []).compactMap(setting)
      return SettingsSection(id: id, title: title, symbol: s["symbol"] as? String ?? "gearshape", settings: rows)
    })
  }

  static func setting(_ r: [String: Any]) -> Setting? {
    guard let id = r["id"] as? String, let title = r["title"] as? String else { return nil }
    let choices = (r["choices"] as? [[String: Any]] ?? []).compactMap { c -> SettingChoice? in
      guard let value = c["value"] as? String else { return nil }
      return SettingChoice(value: value, title: c["title"] as? String ?? value)
    }
    func number(_ key: String) -> Double? { (r[key] as? NSNumber)?.doubleValue }
    let catalog = ((r["extra"] as? [Any]) ?? []).compactMap { any -> CatalogApp? in
      guard let e = any as? [String: Any], let name = e["name"] as? String, let bundle = e["bundle"] as? String
      else { return nil }
      let placement = (e["placement"] as? [String: Any]).map { p -> AppPlace in
        var place = AppPlace()
        place.center = true
        if let w = (p["width"] as? NSNumber)?.doubleValue, let h = (p["height"] as? NSNumber)?.doubleValue {
          place.sized = true
          place.width = w
          place.height = h
        }
        if let pad = p["padding"] as? [String: Any] {
          place.padX = (pad["x"] as? NSNumber)?.doubleValue ?? 0
          place.padY = (pad["y"] as? NSNumber)?.doubleValue ?? 0
        } else if let n = (p["padding"] as? NSNumber)?.doubleValue {
          place.padX = n
          place.padY = n
        }
        return place
      }
      return CatalogApp(name: name, bundle: bundle, style: e["style"] as? String, hides: e["hides"] as? Bool,
        placed: e["placed"] as? Bool ?? false, added: e["added"] as? Bool ?? false, path: e["path"] as? String,
        placement: placement)
    }
    let kind = Setting.Kind(rawValue: r["kind"] as? String ?? "") ?? .other
    // A list of sizes is read as sizes, since read by shape alone it is a list of names.
    func value(_ any: Any?) -> SettingValue {
      if kind == .sizes { return .sizes(WindowSize.list(any)) }
      // An applications table is read as one, since an entry holding only booleans and words looks
      // like a table of keys by shape alone.
      if kind == .apps, let o = any as? [String: Any] {
        var apps: [String: AppOverride] = [:]
        for (bundle, entry) in o { if let e = entry as? [String: Any] { apps[bundle] = AppOverride(e) } }
        return .apps(apps)
      }
      return SettingValue(any)
    }
    var made = Setting(id: id, title: title, detail: r["detail"] as? String,
      kind: kind,
      keywords: r["keywords"] as? [String] ?? [], applies: r["applies"] as? String ?? "live",
      choices: choices, min: number("min"), max: number("max"), step: number("step"),
      unit: r["unit"] as? String, locked: r["locked"] as? String,
      defaultValue: value(r["default"]), value: value(r["value"]))
    made.catalog = kind == .sizes ? [] : catalog
    made.page = r["page"] as? String
    made.plugin = r["plugin"] as? String
    made.placeholder = r["placeholder"] as? String
    made.maxLength = (r["maxLength"] as? NSNumber)?.intValue
    made.lines = (r["lines"] as? NSNumber)?.intValue
    if kind == .sizes {
      made.windowActions = ((r["extra"] as? [Any]) ?? []).compactMap { any -> WindowAction? in
        guard let e = any as? [String: Any], let action = e["action"] as? String, let title = e["title"] as? String
        else { return nil }
        return WindowAction(action: action, title: title, group: e["group"] as? String ?? "layout", size: e["size"] as? String)
      }
    }
    return made
  }

  /// The sections holding a setting every word of query finds, by its title, its detail, its
  /// keywords or its section's title, each with only those settings. An empty query is every one.
  public func matching(_ query: String) -> [SettingsSection] {
    let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    if words.isEmpty { return sections }
    return sections.compactMap { section in
      let found = section.settings.filter { setting in
        let hay = ([setting.title, setting.detail ?? "", section.title] + setting.keywords)
          .joined(separator: " ").lowercased()
        return words.allSatisfy { hay.contains($0) }
      }
      return found.isEmpty ? nil : SettingsSection(id: section.id, title: section.title,
        symbol: section.symbol, settings: found)
    }
  }
}

public enum SettingFormat {
  /// A number as the window shows it, with as many decimals as its step has and its unit short.
  public static func number(_ value: Double, step: Double?, unit: String?) -> String {
    var decimals = 0
    if let step, step > 0, step < 1 {
      var s = step
      while decimals < 4 && abs(s.rounded() - s) > 1e-9 { s *= 10; decimals += 1 }
    }
    let text = String(format: "%.\(decimals)f", value)
    switch unit {
    case "seconds": return text + " s"
    case "points": return text + " pt"
    case "pixels": return text + " px"
    case "times": return text + "×"
    case "rows": return text + " rows"
    case let u?: return text + " " + u
    case nil: return text
    }
  }

  /// A font name as a person reads it, the system's own fonts by what they are.
  public static func font(_ name: String) -> String {
    switch name {
    case ".AppleSystemUIFont": return "System"
    case ".AppleSystemUIFontMonospaced": return "System Monospaced"
    default: return name.hasPrefix(".") ? String(name.dropFirst()) : name
    }
  }
}

/// Hammerspoon's answer to one change, docs/DESIGN-APP-SETTINGS.md S.3: whether it was taken, why
/// not in words, and the share as it now stands.
public struct SettingAnswer: Sendable {
  public let ok: Bool
  public let why: String?
  public let share: SettingsShare?

  public init(ok: Bool, why: String?, share: SettingsShare?) {
    self.ok = ok
    self.why = why
    self.share = share
  }
}

/// How the window reaches Hammerspoon, handed in by the app so this module knows no bridge. change
/// sends one setting, a reset with no value, and done tells it the window closed, so a change that
/// waits for a reload is applied once.
public struct SettingsService: Sendable {
  public let change: @Sendable (_ id: String, _ value: SettingValue, _ reset: Bool) async -> SettingAnswer
  public let done: @Sendable () async -> Void
  /// An exported config taken whole, its values as JSON, every value checked as a change is, answered with the ids
  /// refused and why, and the share as it then stands.
  public let importValues: @Sendable (_ values: Data) async -> (refused: [String], share: SettingsShare?)

  public init(change: @escaping @Sendable (String, SettingValue, Bool) async -> SettingAnswer,
    done: @escaping @Sendable () async -> Void,
    importValues: @escaping @Sendable (Data) async -> (refused: [String], share: SettingsShare?) = { _ in (["values"], nil) }) {
    self.change = change
    self.done = done
    self.importValues = importValues
  }
}
