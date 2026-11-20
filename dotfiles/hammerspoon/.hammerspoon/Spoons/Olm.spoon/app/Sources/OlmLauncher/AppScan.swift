// The applications the launcher lists, found as host/launcher/init.lua finds them, step 6.1 of
// docs/PLAN-STANDALONE.md, docs/DESIGN-APP-LAUNCHER.md. The same three folders, four levels deep,
// an .app a leaf and never descended into, a name starting with a dot skipped, and the first bundle
// found for an id kept. A running application the scan missed is listed when it has a place in the
// Dock, a regular activation policy, which is the Lua side's kind 1, so background helpers stay out.

import AppKit
import Foundation

public struct ScannedApp: Sendable, Equatable {
  public var bundleID: String
  public var name: String
  public var running: Bool

  public init(bundleID: String, name: String, running: Bool) {
    self.bundleID = bundleID
    self.name = name
    self.running = running
  }
}

public enum AppScan {
  public static let maxDepth = 4

  public static var folders: [String] {
    ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
  }

  /// Every application bundle in the folders, by bundle id, in the order found.
  public static func installed(in folders: [String] = folders) -> [(bundleID: String, name: String)] {
    var seen = Set<String>()
    var out: [(String, String)] = []
    let fm = FileManager.default
    func walk(_ dir: String, _ depth: Int) {
      guard depth <= maxDepth, let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
      for entry in entries.sorted() where !entry.hasPrefix(".") {
        let path = dir + "/" + entry
        if entry.hasSuffix(".app") {
          guard let bundle = Bundle(path: path), let id = bundle.bundleIdentifier, seen.insert(id).inserted else { continue }
          out.append((id, name(bundle, path, entry)))
        } else {
          var isDir: ObjCBool = false
          if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue { walk(path, depth + 1) }
        }
      }
    }
    for folder in folders { walk(folder, 1) }
    return out
  }

  // The bundle's own name, its CFBundleName, as the Lua side's nameForBundleID answers it, Chrome and
  // Code rather than the Google Chrome and Visual Studio Code Finder shows, found by comparing the two
  // catalogs on 2026-11-20. The file's name without the extension where the bundle names none.
  static func name(_ bundle: Bundle, _ path: String, _ entry: String) -> String {
    if let n = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !n.isEmpty { return n }
    return String(entry.dropLast(4))
  }

  /// The installed applications marked running, with any running one the scan missed that has a
  /// place in the Dock, running first and then by name, as the Lua side orders them.
  public static func listed(installed: [(bundleID: String, name: String)],
                            running: [(bundleID: String, name: String?, regular: Bool)]) -> [ScannedApp] {
    var apps = installed.map { ScannedApp(bundleID: $0.bundleID, name: $0.name, running: false) }
    var index: [String: Int] = [:]
    for (i, a) in apps.enumerated() { index[a.bundleID] = i }
    for r in running {
      if let i = index[r.bundleID] {
        apps[i].running = true
      } else if r.regular {
        index[r.bundleID] = apps.count
        apps.append(ScannedApp(bundleID: r.bundleID, name: r.name ?? r.bundleID, running: true))
      }
    }
    return apps.enumerated().sorted { x, y in
      if x.element.running != y.element.running { return x.element.running }
      let a = x.element.name.lowercased(), b = y.element.name.lowercased()
      return a != b ? a < b : x.offset < y.offset
    }.map(\.element)
  }

  /// What is running now, by bundle id.
  public static func running() -> [(bundleID: String, name: String?, regular: Bool)] {
    NSWorkspace.shared.runningApplications.compactMap { app in
      guard let id = app.bundleIdentifier else { return nil }
      return (id, app.localizedName, app.activationPolicy == .regular)
    }
  }
}
