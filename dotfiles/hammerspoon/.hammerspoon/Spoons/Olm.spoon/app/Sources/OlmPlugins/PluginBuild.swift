// Compiling a plugin's Swift sources into the program the runner starts, docs/DESIGN-APP-PLUGINS.md
// A plugin on disk. It uses the swiftc inside the command line tools, the toolchain the app's own
// build needs, and writes bin/<id> inside the plugin's folder. Swift is the one plugin language for
// now.

import Foundation

public enum PluginBuild {
  public static let tools = "/Library/Developer/CommandLineTools"

  public enum Failure: Error, CustomStringConvertible {
    case noTools
    case noSources(String)
    case compile(String)

    public var description: String {
      switch self {
      case .noTools: return "this Mac has no command line tools to build a plugin with"
      case .noSources(let dir): return "no Swift sources in \(dir)"
      case .compile(let errors): return "it did not compile:\n\(errors)"
      }
    }
  }

  /// Builds the plugin in a folder, its sources under Sources, into bin/<id>, answering the program.
  /// kit, OlmPluginKit's source, is compiled in beside them when given.
  @discardableResult
  public static func build(folder: URL, manifest: PluginManifest, kit: URL? = nil, optimize: Bool = true) throws -> URL {
    let swiftc = tools + "/usr/bin/swiftc"
    guard FileManager.default.isExecutableFile(atPath: swiftc) else { throw Failure.noTools }
    let sources = folder.appendingPathComponent("Sources")
    let files = (FileManager.default.enumerator(atPath: sources.path)?.compactMap { $0 as? String } ?? [])
      .filter { $0.hasSuffix(".swift") }.sorted().map { sources.appendingPathComponent($0).path }
    guard !files.isEmpty else { throw Failure.noSources(sources.path) }
    let compiled = files + (kit.map { [$0.path] } ?? [])
    let bin = folder.appendingPathComponent("bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let out = bin.appendingPathComponent(manifest.id)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: swiftc)
    p.arguments = ["-sdk", tools + "/SDKs/MacOSX.sdk"] + (optimize ? ["-O"] : []) + compiled + ["-o", out.path]
    var env = ProcessInfo.processInfo.environment
    env["DEVELOPER_DIR"] = tools
    p.environment = env
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    try p.run()
    let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    p.waitUntilExit()
    guard p.terminationStatus == 0 else {
      throw Failure.compile(text.split(separator: "\n").filter { $0.contains(": error:") || $0.hasPrefix("error:") }.prefix(20).joined(separator: "\n")
        .replacingOccurrences(of: folder.path + "/", with: ""))
    }
    return out
  }
}
