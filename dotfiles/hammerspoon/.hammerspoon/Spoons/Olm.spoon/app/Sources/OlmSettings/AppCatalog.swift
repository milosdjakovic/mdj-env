// The app catalog kept by the app, step 6.2b of docs/PLAN-STANDALONE.md, docs/DESIGN-APP-APPS.md.
// One table, apptoggler.apps in Olm's store, by bundle id: each application's mode, its place and its
// key. It is the catalog, so there is no second list of apps. Seeded once from what Hammerspoon binds
// and styles, so the flip loses no key and no popup. Pure, so olm-apps-check reads it with no window.

import Foundation
import OlmApps

public enum AppCatalog {
  public static let settingId = "apptoggler.apps"
  public static let modeId = "apptoggler.mode"
  /// The id a key the app keeps runs by, app: and the bundle id.
  public static let prefix = "app:"
  /// Hammerspoon's actions for its catalog, which the app's keys stand in for while it keeps it.
  public static let luaPrefix = "apptoggler."

  /// The table the share holds now.
  public static func table(_ share: SettingsShare?) -> [String: AppOverride] {
    setting(share)?.value.apps ?? [:]
  }

  /// What Hammerspoon's app toggler knows of each application, its action names and styles.
  public static func catalog(_ share: SettingsShare?) -> [CatalogApp] { setting(share)?.catalog ?? [] }

  /// The mode an app with none of its own takes, cycle or hides.
  public static func globalMode(_ share: SettingsShare?) -> String {
    share?.sections.flatMap(\.settings).first { $0.id == modeId }?.value.text ?? "cycle"
  }

  static func setting(_ share: SettingsShare?) -> Setting? {
    share?.sections.flatMap(\.settings).first { $0.id == settingId }
  }

  /// One application with a key.
  public struct Keyed: Equatable, Sendable {
    public let bundle: String
    public let key: AppKey
    public var id: String { AppCatalog.prefix + bundle }
  }

  /// Every application with a key, in bundle order, and the bundles left out because an application
  /// before it holds that combination.
  public static func keyed(_ table: [String: AppOverride]) -> (apps: [Keyed], clashes: [String]) {
    var seen = Set<String>()
    var apps: [Keyed] = []
    var clashes: [String] = []
    for bundle in table.keys.sorted() {
      guard let key = table[bundle]?.key else { continue }
      if seen.insert(key.slot).inserted { apps.append(Keyed(bundle: bundle, key: key)) } else { clashes.append(bundle) }
    }
    return (apps, clashes)
  }

  /// What a press on an application runs, whether it hides when in front, and its place as the app's
  /// Placement reads it, nil where it asks for none.
  public static func press(_ bundle: String, table: [String: AppOverride], global: String) -> (hides: Bool, place: Placement?) {
    let own = table[bundle]
    let hides = (own?.mode ?? global) == "hides"
    guard let place = own?.place, !place.isDefault else { return (hides, nil) }
    return (hides, Placement(place.any))
  }

  /// A key Hammerspoon binds on one of its catalog's actions, read from keymap.json for the seed.
  public struct LuaKey: Equatable, Sendable {
    public let id: String
    public let leader: String?
    public let key: String
    public let code: Int
    public let mods: [String]
    public init(id: String, leader: String?, key: String, code: Int, mods: [String]) {
      self.id = id
      self.leader = leader
      self.key = key
      self.code = code
      self.mods = mods
    }
  }

  /// The table with what Hammerspoon has laid in where the table has nothing of its own: each catalog
  /// action's key, the first one it binds, and each styled application's mode and place, the popup
  /// style of a terminal. A key whose combination the table already gives another application is left
  /// out. nil when nothing changes.
  public static func seed(_ table: [String: AppOverride], keys: [LuaKey], catalog: [CatalogApp]) -> [String: AppOverride]? {
    var next = table
    var held = Set(table.values.compactMap { $0.key?.slot })
    var byAction: [String: CatalogApp] = [:]
    for app in catalog { byAction[luaPrefix + app.name] = byAction[luaPrefix + app.name] ?? app }
    var keyed = Set<String>()
    for k in keys {
      guard let app = byAction[k.id], keyed.insert(app.bundle).inserted else { continue }
      var own = next[app.bundle] ?? AppOverride()
      guard own.key == nil else { continue }
      let key = AppKey(leader: k.leader, key: k.key, code: k.code, mods: k.mods)
      guard held.insert(key.slot).inserted else { continue }
      own.key = key
      next[app.bundle] = own
    }
    for app in catalog {
      var own = next[app.bundle] ?? AppOverride()
      var changed = false
      if own.mode == nil, let hides = app.hides {
        own.mode = hides ? "hides" : "cycle"
        changed = true
      }
      if own.place == nil, let place = app.placement {
        own.place = place
        changed = true
      }
      if changed { next[app.bundle] = own }
    }
    return next == table ? nil : next
  }

  /// The keys of Hammerspoon's catalog actions in keymap.json, in the order it binds them.
  public static func luaKeys(_ keymap: Data) -> [LuaKey] {
    guard let doc = (try? JSONSerialization.jsonObject(with: keymap)) as? [String: Any] else { return [] }
    return (doc["rows"] as? [[String: Any]] ?? []).compactMap { r in
      guard let id = r["id"] as? String, id.hasPrefix(luaPrefix), let key = r["key"] as? String,
        let code = (r["keyCode"] as? NSNumber)?.intValue else { return nil }
      return LuaKey(id: id, leader: r["leader"] as? String, key: key, code: code, mods: r["mods"] as? [String] ?? [])
    }
  }

  /// Whether the table was seeded on this Mac, a file beside Olm's store, so a key taken off on the
  /// page is never laid in again.
  public static let seededMark = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".olm/state/apps-seeded")
}
