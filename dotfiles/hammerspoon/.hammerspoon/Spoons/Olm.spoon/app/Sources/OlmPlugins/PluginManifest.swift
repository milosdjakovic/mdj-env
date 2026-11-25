// What an external plugin says about itself, olm-plugin.json at its folder's root,
// docs/DESIGN-APP-PLUGINS.md A plugin on disk. It is read without running anything, and its
// permissions are what the sandbox the runner writes for it allows, so what it declares is what it
// can do.

import Foundation

public struct PluginManifest: Sendable, Equatable {
  /// One lowercase word, the folder's name, olm://<id>.
  public var id: String
  public var title: String
  public var version: String
  /// The bridge protocol's major version it speaks.
  public var proto: Int
  /// Runs while nothing uses it, a watcher, at background quality and never stopped for idling.
  public var background: Bool
  public var permissions: Permissions
  /// What it asks of Olm, PluginRequests.known, anything else refused.
  public var needs: Set<String> = []
  /// What Olm does for it with a permission Olm holds, each ability's `use`.
  public var abilities: Set<String> = []

  public struct Permissions: Sendable, Equatable {
    /// Programs it runs, a bare name looked up on the plugin path or an absolute path.
    public var programs: [String] = []
    public var files: [FileGrant] = []
    public var network: Network = .none
    public var services: [Service] = []

    public init(programs: [String] = [], files: [FileGrant] = [], network: Network = .none, services: [Service] = []) {
      self.programs = programs
      self.files = files
      self.network = network
      self.services = services
    }
  }

  public struct FileGrant: Sendable, Equatable {
    /// A place, `~` for the home folder.
    public var path: String
    public var write: Bool

    public init(path: String, write: Bool) {
      self.path = path
      self.write = write
    }
  }

  public enum Network: String, Sendable, Equatable {
    case none, local, internet
  }

  /// One narrow door to a system service a program it runs needs, a Mach service by name, a Unix
  /// socket by path or an IOKit user client by class.
  public enum Service: Sendable, Equatable {
    case mach(String)
    case socket(String)
    case iokit(String)
  }

  public enum Failure: Error, Equatable, CustomStringConvertible {
    case unreadable(String)
    case field(String)

    public var description: String {
      switch self {
      case .unreadable(let why): return "olm-plugin.json could not be read, \(why)"
      case .field(let why): return "olm-plugin.json \(why)"
      }
    }
  }

  public init(id: String, title: String, version: String = "0", proto: Int = 1, background: Bool = false,
              permissions: Permissions = Permissions()) {
    self.id = id
    self.title = title
    self.version = version
    self.proto = proto
    self.background = background
    self.permissions = permissions
  }

  /// The manifest in a plugin's folder, refused whole when a field is wrong, so a plugin never runs on
  /// half a reading of what it asked for.
  public static func read(folder: URL) throws -> PluginManifest {
    let url = folder.appendingPathComponent("olm-plugin.json")
    guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable("no file at \(url.path)") }
    guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      throw Failure.unreadable("it is not a JSON object")
    }
    return try parse(o)
  }

  /// Words olm://, a setting's id and the app's store already use.
  static let reserved: Set<String> = ["abilities", "ability", "ext", "held", "olm", "plugins", "settings", "tool"]

  static func parse(_ o: [String: Any]) throws -> PluginManifest {
    guard let id = o["id"] as? String, id.range(of: "^[a-z][a-z0-9]*$", options: .regularExpression) != nil else {
      throw Failure.field("needs an id of lowercase letters and digits")
    }
    guard !reserved.contains(id) else { throw Failure.field("has the id \(id), which is Olm's own word") }
    guard let title = o["title"] as? String, !title.isEmpty else { throw Failure.field("needs a title") }
    try plain(title, "title", 60)
    try plain(o["version"] as? String ?? "", "version", 30)
    var m = PluginManifest(id: id, title: title, version: o["version"] as? String ?? "0",
      proto: o["protocol"] as? Int ?? 1, background: o["background"] as? Bool ?? false)
    if let needs = o["needs"] {
      guard let list = needs as? [String] else { throw Failure.field("needs is a list of names") }
      if let odd = list.first(where: { !PluginRequests.known.contains($0) }) {
        throw Failure.field("needs \(odd), which Olm does not do for a plugin")
      }
      m.needs = Set(list)
    }
    for a in o["abilities"] as? [[String: Any]] ?? [] {
      guard let use = a["use"] as? String else { throw Failure.field("an ability needs a use") }
      try plain(use, "ability", 200)
      m.abilities.insert(use)
    }
    guard let p = o["permissions"] as? [String: Any] else { return m }
    if let programs = p["programs"] {
      guard let list = programs as? [String] else { throw Failure.field("permissions.programs is a list of names") }
      for name in list { try plain(name, "program", 500) }
      m.permissions.programs = list
    }
    for f in p["files"] as? [[String: Any]] ?? [] {
      guard let path = f["path"] as? String else { throw Failure.field("a file grant needs a path") }
      try plain(path, "file path", 1000)
      // A path a person reads on the install page is the one granted, with no way back up in it.
      guard path == "~" || path.hasPrefix("~/") || path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
        throw Failure.field("a file grant's path starts with ~/ or / and has no ..")
      }
      let access = f["access"] as? String ?? "read"
      guard access == "read" || access == "write" else { throw Failure.field("a file grant's access is read or write") }
      m.permissions.files.append(FileGrant(path: path, write: access == "write"))
    }
    if let n = p["network"] as? String {
      guard let net = Network(rawValue: n) else { throw Failure.field("permissions.network is local or internet") }
      m.permissions.network = net
    }
    for s in p["services"] as? [[String: Any]] ?? [] {
      for word in s.values.compactMap({ $0 as? String }) { try plain(word, "service", 500) }
      if let name = s["mach"] as? String {
        m.permissions.services.append(.mach(name))
      } else if let path = s["socket"] as? String {
        m.permissions.services.append(.socket(path))
      } else if let cls = s["iokit"] as? String {
        m.permissions.services.append(.iokit(cls))
      } else {
        throw Failure.field("a service is mach, socket or iokit")
      }
    }
    return m
  }

  /// Refuses a text that could show as something else than it is on the install page, a line break, a
  /// control character or one that turns the writing round.
  static func plain(_ s: String, _ what: String, _ most: Int) throws {
    let odd = s.unicodeScalars.contains {
      [.control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .unassigned].contains($0.properties.generalCategory)
    }
    guard !odd, s.count <= most else { throw Failure.field("has a \(what) that is too long or holds characters that do not show") }
  }
}
