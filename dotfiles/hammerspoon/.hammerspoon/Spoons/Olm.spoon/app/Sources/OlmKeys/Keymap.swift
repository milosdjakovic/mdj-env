// The keys as Hammerspoon compiled them, ~/.olm/run/keymap.json, written by lib/keyshare.lua on
// every load, docs/DESIGN-APP-KEYS.md. The keymap stays compiled in Lua until stage 8, so the app
// reads only its answer, the leaders in use and every global row in the order the binder binds them.

import Foundation

/// A real modifier, the four a binding compares on. fn and Caps Lock are never compared.
public enum Mod: String, Sendable, Hashable, CaseIterable {
  case shift, ctrl, alt, cmd
}

public struct KeyLeader: Sendable, Equatable {
  /// The name a row spells it with, hyper, meta.
  public var name: String
  /// Whether it listens on a held function key.
  public var held: Bool
  /// The function key it listens on when held, after the remap.
  public var keyCode: Int?
  /// The set of real modifiers it listens on, nil for a leader with none.
  public var mods: Set<Mod>?
  /// The global tier rule, lib/leader.lua's ranked.
  public var ranked: Bool

  public init(name: String, held: Bool, keyCode: Int?, mods: Set<Mod>?, ranked: Bool) {
    self.name = name
    self.held = held
    self.keyCode = keyCode
    self.mods = mods
    self.ranked = ranked
  }

  /// A held leader that also listens on modifiers, HYPER and META as they ship.
  public var composite: Bool { held && mods != nil }

  /// The name the plain leader is handed over by, the rows with no leader on their own modifiers.
  public static let plainName = "plain"
  /// The plain leader, an empty base set, never in the share's leaders.
  public static let plain = KeyLeader(name: plainName, held: false, keyCode: nil, mods: [], ranked: false)
  /// The name its rows spell, none.
  var rowName: String? { name == Self.plainName ? nil : name }
}

public struct KeyRow: Sendable, Equatable {
  /// The action, owner and action joined, apptoggler.Safari.
  public var id: String
  /// The leader it is bound on, nil for a plain combo.
  public var leader: String?
  public var key: String
  public var keyCode: Int
  /// The modifiers it binds on, nil for a catch all.
  public var mods: Set<Mod>?
  /// The predicate that gates it, answered at each press.
  public var gate: String?
  public var priority: Double
  public var repeats: Bool
  public var afterRelease: Bool

  public init(id: String, leader: String?, key: String, keyCode: Int, mods: Set<Mod>?, gate: String? = nil,
              priority: Double = 0, repeats: Bool = false, afterRelease: Bool = false) {
    self.id = id
    self.leader = leader
    self.key = key
    self.keyCode = keyCode
    self.mods = mods
    self.gate = gate
    self.priority = priority
    self.repeats = repeats
    self.afterRelease = afterRelease
  }
}

public struct Keymap: Sendable, Equatable {
  public static let version = 1

  public var leaders: [KeyLeader]
  /// In the order the binder bound them, which the first exact rule reads.
  public var rows: [KeyRow]
  /// The leaders whose modifier combinations the app claims, step 5.3, by the name a row spells each.
  public var appKeys: [String] = []
  /// The key codes the app claims without excluding macOS, so its own answer runs too, the Globe
  /// key where Olm Settings lets macOS's input source picker show beside Olm's cycle.
  public var systemKeys: Set<Int> = []

  public init(leaders: [KeyLeader], rows: [KeyRow]) {
    self.leaders = leaders
    self.rows = rows
  }

  public enum Failure: Error, Equatable {
    case unreadable
    case version(Int)
  }

  /// The share Hammerspoon wrote, a row with no keycode left out, since no key can press it.
  public static func parse(_ data: Data) throws -> Keymap {
    guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw Failure.unreadable }
    let v = o["version"] as? Int ?? 0
    guard v == version else { throw Failure.version(v) }
    func mods(_ any: Any?) -> Set<Mod>? {
      guard let list = any as? [String] else { return nil }
      return Set(list.compactMap(Mod.init(rawValue:)))
    }
    let leaders = (o["leaders"] as? [[String: Any]] ?? []).compactMap { l -> KeyLeader? in
      guard let name = l["name"] as? String else { return nil }
      return KeyLeader(name: name, held: l["held"] as? Bool ?? false, keyCode: l["keyCode"] as? Int,
        mods: mods(l["mods"]), ranked: l["ranked"] as? Bool ?? false)
    }
    let rows = (o["rows"] as? [[String: Any]] ?? []).compactMap { r -> KeyRow? in
      guard let id = r["id"] as? String, let code = r["keyCode"] as? Int else { return nil }
      return KeyRow(id: id, leader: r["leader"] as? String, key: r["key"] as? String ?? "", keyCode: code,
        mods: mods(r["mods"]), gate: r["gate"] as? String, priority: (r["priority"] as? NSNumber)?.doubleValue ?? 0,
        repeats: r["repeats"] as? Bool ?? false, afterRelease: r["afterRelease"] as? Bool ?? false)
    }
    var keymap = Keymap(leaders: leaders, rows: rows)
    keymap.appKeys = o["appKeys"] as? [String] ?? []
    keymap.systemKeys = Set((o["systemKeys"] as? [NSNumber] ?? []).map(\.intValue))
    return keymap
  }

  public static func read(_ url: URL) throws -> Keymap {
    guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable }
    return try parse(data)
  }
}
