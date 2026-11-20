// The settings share, `~/.olm/run/settings.json`, which Hammerspoon writes at every load from
// lib/settings.lua, docs/DESIGN-APP-SETTINGS.md. It holds every section of the Olm Settings window
// in order, and each setting's declaration, its default and its current value. The window draws
// whatever it lists, so a setting added later is one declaration in Lua and nothing here.
//
// Everything in this file is plain data and pure functions, so olm-bridge-check reads a share and
// searches it with no window.

import Foundation

/// One setting's value as the share writes it, a name, a number, on or off, or a list of names.
public enum SettingValue: Equatable, Sendable {
  case text(String)
  case number(Double)
  case flag(Bool)
  case names([String])
  case none

  init(_ any: Any?) {
    switch any {
    case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): self = .flag(n.boolValue)
    case let n as NSNumber: self = .number(n.doubleValue)
    case let s as String: self = .text(s)
    case let a as [Any]: self = .names(a.compactMap { $0 as? String })
    default: self = .none
    }
  }

  public var text: String? { if case .text(let s) = self { return s }; return nil }
  public var number: Double? { if case .number(let n) = self { return n }; return nil }
  public var flag: Bool? { if case .flag(let b) = self { return b }; return nil }
}

public struct SettingChoice: Equatable, Sendable, Identifiable {
  public let value: String
  public let title: String
  public var id: String { value }
}

public struct Setting: Equatable, Sendable, Identifiable {
  public enum Kind: String, Sendable { case choice, number, font, `switch`, other }

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
    return Setting(id: id, title: title, detail: r["detail"] as? String,
      kind: Setting.Kind(rawValue: r["kind"] as? String ?? "") ?? .other,
      keywords: r["keywords"] as? [String] ?? [], applies: r["applies"] as? String ?? "live",
      choices: choices, min: number("min"), max: number("max"), step: number("step"),
      unit: r["unit"] as? String, locked: r["locked"] as? String,
      defaultValue: SettingValue(r["default"]), value: SettingValue(r["value"]))
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
