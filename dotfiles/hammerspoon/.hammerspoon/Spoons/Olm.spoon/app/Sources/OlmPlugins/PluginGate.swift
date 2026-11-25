// What stands between a folder in ~/.olm/plugins and it being built or run,
// docs/DESIGN-APP-PLUGINS.md Nothing runs before Allow. A plugin is let through when the person
// allowed everything it asks for, or when it is one of Olm's own, the same files as the copy inside
// the signed app. The program it runs is always one Olm built from the sources it has now, never one
// that came with the folder.

import CryptoKit
import Foundation

public enum PluginGate {
  public enum Verdict: Sendable, Equatable {
    /// Olm's own, the same as the copy in the app.
    case ours
    /// Everything it asks for was allowed.
    case allowed
    /// Kept from building and running, what it asks for that was never allowed, all of it when new.
    case waiting([String])
    /// Not a folder Olm takes, why.
    case refused(String)

    public var runs: Bool { self == .ours || self == .allowed }

    /// Why it is held, for its row in Olm Settings, nil for one that runs.
    public var why: String? {
      switch self {
      case .ours, .allowed: return nil
      case .waiting: return "not allowed yet, so Olm neither builds nor runs it"
      case .refused(let why): return why
      }
    }
  }

  public struct Refused: Error, CustomStringConvertible {
    public let description: String
  }

  /// What a person allows, a line each, stable so a later manifest is compared with it. Abilities are
  /// not here, they are allowed with the plugin and switched off in Olm Settings.
  public static func asks(_ m: PluginManifest) -> Set<String> {
    var out = Set(m.needs.map { "need:\($0)" })
    out.formUnion(m.permissions.programs.map { "program:\($0)" })
    out.formUnion(m.permissions.files.map { "\($0.write ? "write" : "read"):\($0.path)" })
    if m.permissions.network != .none { out.insert("network:\(m.permissions.network.rawValue)") }
    for s in m.permissions.services {
      switch s {
      case .mach(let n): out.insert("mach:\(n)")
      case .socket(let p): out.insert("socket:\(p)")
      case .iokit(let c): out.insert("iokit:\(c)")
      }
    }
    if m.background { out.insert("background") }
    return out
  }

  public static func verdict(folder: URL, bundled: URL?, records: PluginRecords) -> (Verdict, PluginManifest?) {
    let manifest: PluginManifest
    let print: String
    do {
      print = try fingerprint(folder)
      manifest = try PluginManifest.read(folder: folder)
    } catch { return (.refused("\(error)"), nil) }
    guard manifest.id == folder.lastPathComponent else {
      return (.refused("its folder is named \(folder.lastPathComponent) and its id is \(manifest.id), which must be the same"), nil)
    }
    if let own = bundled?.appendingPathComponent(manifest.id), let theirs = try? fingerprint(own), theirs == print {
      return (.ours, manifest)
    }
    let asks = asks(manifest)
    guard let given = records.allowed(manifest.id) else { return (.waiting(asks.sorted()), manifest) }
    let new = asks.subtracting(given)
    return (new.isEmpty ? .allowed : .waiting(new.sorted()), manifest)
  }

  /// A hash of the manifest and the sources. A symlink is refused anywhere but in data and tmp, since
  /// the sandbox follows one standing in for a place the plugin may write and the build writes through
  /// one standing in for the program.
  public static func fingerprint(_ folder: URL) throws -> String {
    let fm = FileManager.default
    var hash = SHA256()
    var files: [(String, URL)] = []
    var seen = 0
    func walk(_ dir: URL, _ prefix: String) throws {
      for name in try fm.contentsOfDirectory(atPath: dir.path).sorted() {
        let url = dir.appendingPathComponent(name), path = prefix + name
        let type = try fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
        seen += 1
        guard seen <= 5000 else { throw Refused(description: "it holds more than 5000 files") }
        if type == .typeSymbolicLink { throw Refused(description: "it holds a link, \(path), which Olm does not follow") }
        if type == .typeDirectory {
          if prefix.isEmpty, name == "data" || name == "tmp" { continue }
          try walk(url, path + "/")
        } else if path == "olm-plugin.json" || path.hasPrefix("Sources/") {
          files.append((path, url))
        }
      }
    }
    if try fm.attributesOfItem(atPath: folder.path)[.type] as? FileAttributeType == .typeSymbolicLink {
      throw Refused(description: "its folder is a link, which Olm does not follow")
    }
    try walk(folder, "")
    var bytes = 0
    for (path, url) in files where url.lastPathComponent != ".DS_Store" {
      let data = try Data(contentsOf: url)
      bytes += data.count
      guard bytes <= 32 * 1024 * 1024 else { throw Refused(description: "its sources are over 32 MB") }
      hash.update(data: Data("\(path)\u{0}\(data.count)\u{0}".utf8))
      hash.update(data: data)
    }
    return hex(hash.finalize())
  }

  static func hash(_ file: URL) -> String? {
    guard let data = try? Data(contentsOf: file) else { return nil }
    return hex(SHA256.hash(data: data))
  }

  private static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

  /// The plugin's program, built unless the one there is the very one Olm built from these sources and
  /// this kit. Whether it was built.
  @discardableResult
  public static func prepare(folder: URL, manifest: PluginManifest, kit: URL?, records: PluginRecords) throws -> Bool {
    let program = folder.appendingPathComponent("bin").appendingPathComponent(manifest.id)
    func source() throws -> String { try fingerprint(folder) + (kit.flatMap(hash) ?? "") }
    let before = try source()
    if let built = records.built(manifest.id), built.source == before, built.program == hash(program) { return false }
    try? FileManager.default.removeItem(at: program)
    try PluginBuild.build(folder: folder, manifest: manifest, kit: kit)
    guard try source() == before, let made = hash(program) else {
      try? FileManager.default.removeItem(at: program)
      throw Refused(description: "its files changed while it was built")
    }
    records.setBuilt(manifest.id, .init(source: before, program: made))
    return true
  }
}

/// What the person allowed each plugin and what Olm built for it, ~/.olm/state/plugin-records.json. A
/// file of its own and never a setting, so no import, export or plugin's setting reaches it, and the
/// sandbox keeps every plugin out of ~/.olm. Unreadable, it holds nothing and every plugin but Olm's
/// own waits.
public final class PluginRecords: @unchecked Sendable {
  public struct Built: Codable, Sendable, Equatable {
    public var source: String
    public var program: String
  }

  private struct Doc: Codable {
    var version = 1
    var allowed: [String: [String]] = [:]
    var built: [String: Built] = [:]
  }

  public static let path = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".olm/state/plugin-records.json")
  private let url: URL
  private let lock = NSLock()

  public init(url: URL = PluginRecords.path) { self.url = url }

  public func allowed(_ id: String) -> Set<String>? { read().allowed[id].map(Set.init) }
  public func built(_ id: String) -> Built? { read().built[id] }
  /// The person's yes to everything asked, nil takes it back.
  public func allow(_ id: String, _ asks: Set<String>?) { change { $0.allowed[id] = asks?.sorted() } }
  public func setBuilt(_ id: String, _ built: Built) { change { $0.built[id] = built } }

  private func load() -> Doc {
    guard let data = try? Data(contentsOf: url) else { return Doc() }
    return (try? JSONDecoder().decode(Doc.self, from: data)) ?? Doc()
  }

  private func read() -> Doc {
    lock.lock(); defer { lock.unlock() }
    return load()
  }

  private func change(_ fn: (inout Doc) -> Void) {
    lock.lock(); defer { lock.unlock() }
    var doc = load()
    fn(&doc)
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let data = try? e.encode(doc) { try? data.write(to: url, options: .atomic) }
  }
}
