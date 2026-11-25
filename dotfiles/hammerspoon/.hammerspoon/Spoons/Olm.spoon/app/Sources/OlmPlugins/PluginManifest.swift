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

  static func parse(_ o: [String: Any]) throws -> PluginManifest {
    guard let id = o["id"] as? String, id.range(of: "^[a-z][a-z0-9]*$", options: .regularExpression) != nil else {
      throw Failure.field("needs an id of lowercase letters and digits")
    }
    guard let title = o["title"] as? String, !title.isEmpty else { throw Failure.field("needs a title") }
    var m = PluginManifest(id: id, title: title, version: o["version"] as? String ?? "0",
      proto: o["protocol"] as? Int ?? 1, background: o["background"] as? Bool ?? false)
    if let needs = o["needs"] {
      guard let list = needs as? [String] else { throw Failure.field("needs is a list of names") }
      if let odd = list.first(where: { !PluginRequests.known.contains($0) }) {
        throw Failure.field("needs \(odd), which Olm does not do for a plugin")
      }
      m.needs = Set(list)
    }
    guard let p = o["permissions"] as? [String: Any] else { return m }
    if let programs = p["programs"] {
      guard let list = programs as? [String] else { throw Failure.field("permissions.programs is a list of names") }
      m.permissions.programs = list
    }
    for f in p["files"] as? [[String: Any]] ?? [] {
      guard let path = f["path"] as? String else { throw Failure.field("a file grant needs a path") }
      let access = f["access"] as? String ?? "read"
      guard access == "read" || access == "write" else { throw Failure.field("a file grant's access is read or write") }
      m.permissions.files.append(FileGrant(path: path, write: access == "write"))
    }
    if let n = p["network"] as? String {
      guard let net = Network(rawValue: n) else { throw Failure.field("permissions.network is local or internet") }
      m.permissions.network = net
    }
    for s in p["services"] as? [[String: Any]] ?? [] {
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
}
