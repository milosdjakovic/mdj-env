// A plugin someone dropped on Olm Settings, docs/DESIGN-APP-PLUGINS.md The install page. It is copied
// aside first, its manifest and its sources and nothing else, so what the person reads on the page is
// what is put in ~/.olm/plugins once they allow it. Nothing here builds or runs any of it.

import Foundation

public enum PluginInstall {
  /// The most an archive may hold, and may be.
  static let most = 32 * 1024 * 1024
  static let seconds = 20.0

  public struct Staged: Sendable {
    public let folder: URL
    public let manifest: PluginManifest
    public let print: String
  }

  /// The plugin in a dropped folder, or in a dropped .olmplugin, a zip of one, copied into dir.
  public static func stage(_ item: URL, into dir: URL) throws -> Staged {
    let fm = FileManager.default
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    var from = item
    switch type(item) {
    case .typeDirectory?: break
    case .typeRegular? where item.pathExtension.lowercased() == "olmplugin":
      let out = dir.appendingPathComponent("unpacked")
      try unpack(item, into: out)
      from = try root(out)
    case .typeSymbolicLink?: throw PluginGate.Refused(description: "is a link, which Olm does not follow")
    default: throw PluginGate.Refused(description: "is neither a plugin folder nor a .olmplugin file")
    }
    guard type(from.appendingPathComponent("olm-plugin.json")) == .typeRegular else {
      throw PluginGate.Refused(description: "holds no olm-plugin.json, so it is not a plugin")
    }
    let folder = dir.appendingPathComponent("plugin")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    var left = (files: 5000, bytes: most)
    try copy(from.appendingPathComponent("olm-plugin.json"), folder.appendingPathComponent("olm-plugin.json"), &left)
    let sources = from.appendingPathComponent("Sources")
    guard type(sources) == .typeDirectory else { throw PluginGate.Refused(description: "holds no Sources folder") }
    try copy(sources, folder.appendingPathComponent("Sources"), &left)
    let manifest = try PluginManifest.read(folder: folder)
    return Staged(folder: folder, manifest: manifest, print: try PluginGate.fingerprint(folder))
  }

  /// A folder already in ~/.olm/plugins as it stands.
  public static func inPlace(_ folder: URL) throws -> Staged {
    Staged(folder: folder, manifest: try PluginManifest.read(folder: folder), print: try PluginGate.fingerprint(folder))
  }

  /// Puts a staged plugin in root, in place of the one by its id, whose data is kept. Everything else of
  /// the old one goes, and it is put back when the new one cannot be.
  public static func put(_ staged: Staged, in root: URL) throws {
    let fm = FileManager.default
    let dest = root.appendingPathComponent(staged.manifest.id)
    let aside = staged.folder.deletingLastPathComponent().appendingPathComponent("replaced")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    try? fm.removeItem(at: aside)
    let had = type(dest) != nil
    if had { try fm.moveItem(at: dest, to: aside) }
    do {
      if had, type(aside) == .typeDirectory, type(aside.appendingPathComponent("data")) == .typeDirectory {
        try fm.moveItem(at: aside.appendingPathComponent("data"), to: staged.folder.appendingPathComponent("data"))
      }
      try fm.moveItem(at: staged.folder, to: dest)
    } catch {
      if had {
        let data = staged.folder.appendingPathComponent("data")
        if type(data) != nil { try? fm.moveItem(at: data, to: aside.appendingPathComponent("data")) }
        try? fm.moveItem(at: aside, to: dest)
      }
      throw error
    }
    try? fm.removeItem(at: aside)
  }

  /// Takes a plugin out of root into the Trash, so it can be put back by hand. Its data folder stays
  /// where the next plugin by its id finds it, unless it goes too. Answers where it is in the Trash.
  @discardableResult
  public static func remove(_ id: String, from root: URL, data: Bool, aside: URL) throws -> URL? {
    let fm = FileManager.default
    let folder = root.appendingPathComponent(id)
    let kept = folder.appendingPathComponent("data")
    let keeps = !data && type(folder) == .typeDirectory && type(kept) == .typeDirectory
      && !((try? fm.contentsOfDirectory(atPath: kept.path)) ?? []).isEmpty
    guard keeps else {
      var trashed: NSURL?
      try fm.trashItem(at: folder, resultingItemURL: &trashed)
      return trashed as URL?
    }
    let out = aside.appendingPathComponent(UUID().uuidString)
    let going = out.appendingPathComponent(id)
    defer { try? fm.removeItem(at: out) }
    try fm.createDirectory(at: going, withIntermediateDirectories: true)
    let names = try fm.contentsOfDirectory(atPath: folder.path).filter { $0 != "data" }
    var moved: [String] = []
    do {
      for name in names {
        try fm.moveItem(at: folder.appendingPathComponent(name), to: going.appendingPathComponent(name))
        moved.append(name)
      }
      var trashed: NSURL?
      try fm.trashItem(at: going, resultingItemURL: &trashed)
      return trashed as URL?
    } catch {
      for name in moved { try? fm.moveItem(at: going.appendingPathComponent(name), to: folder.appendingPathComponent(name)) }
      throw error
    }
  }

  /// What is at a path itself, a link never followed.
  public static func type(_ url: URL) -> FileAttributeType? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
  }

  private static func copy(_ from: URL, _ to: URL, _ left: inout (files: Int, bytes: Int)) throws {
    let fm = FileManager.default
    left.files -= 1
    guard left.files >= 0 else { throw PluginGate.Refused(description: "holds more than 5000 files") }
    switch type(from) {
    case .typeDirectory?:
      try fm.createDirectory(at: to, withIntermediateDirectories: true)
      for name in try fm.contentsOfDirectory(atPath: from.path) where name != ".DS_Store" {
        try copy(from.appendingPathComponent(name), to.appendingPathComponent(name), &left)
      }
    case .typeRegular?:
      let size = ((try fm.attributesOfItem(atPath: from.path))[.size] as? NSNumber)?.intValue ?? 0
      left.bytes -= size
      guard left.bytes >= 0 else { throw PluginGate.Refused(description: "is over 32 MB") }
      try Data(contentsOf: from).write(to: to)
    default:
      throw PluginGate.Refused(description: "holds a link or a special file, \(from.lastPathComponent), which Olm does not take")
    }
  }

  /// The folder in an archive holding the manifest, its top or the one folder there.
  private static func root(_ out: URL) throws -> URL {
    if type(out.appendingPathComponent("olm-plugin.json")) != nil { return out }
    let inside = try FileManager.default.contentsOfDirectory(atPath: out.path)
      .filter { $0 != "__MACOSX" && !$0.hasPrefix(".") }
      .map { out.appendingPathComponent($0) }
    guard inside.count == 1, type(inside[0]) == .typeDirectory else {
      throw PluginGate.Refused(description: "holds no olm-plugin.json, so it is not a plugin")
    }
    return inside[0]
  }

  /// Unpacks an archive with ditto inside a sandbox that writes to out alone, since an archive may hold a
  /// link and then a file through it. It is stopped once it has written too much or taken too long.
  private static func unpack(_ archive: URL, into out: URL) throws {
    let fm = FileManager.default
    let size = ((try fm.attributesOfItem(atPath: archive.path))[.size] as? NSNumber)?.intValue ?? 0
    guard size <= most else { throw PluginGate.Refused(description: "is over 32 MB") }
    try fm.createDirectory(at: out, withIntermediateDirectories: true)
    let real = Sandbox.real(out.path)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
    p.arguments = ["-p", """
      (version 1)
      (allow default)
      (deny network*)
      (deny file-write*)
      (allow file-write* (subpath \(Sandbox.quote(real))) (literal "/dev/null"))
      """, "/usr/bin/ditto", "-x", "-k", archive.path, real]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try p.run()
    let until = Date().addingTimeInterval(seconds)
    var why: String?
    while p.isRunning {
      usleep(20_000)
      if written(out) > most { why = "holds over 32 MB" } else if Date() > until { why = "took too long to unpack" }
      if why != nil {
        kill(p.processIdentifier, SIGKILL)
        break
      }
    }
    p.waitUntilExit()
    if let why { throw PluginGate.Refused(description: why) }
    guard p.terminationStatus == 0 else { throw PluginGate.Refused(description: "could not be unpacked") }
  }

  private static func written(_ dir: URL) -> Int {
    var sum = 0, seen = 0
    let walk = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey])
    while let url = walk?.nextObject() as? URL {
      seen += 1
      sum += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      if sum > most || seen > 20_000 { return most + 1 }
    }
    return sum
  }
}
