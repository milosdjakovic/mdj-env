// File search's folder search, step 1.4e of docs/PLAN-STANDALONE.md, the counterpart of
// plugins/filesearch/sources/walk.lua and of the engine's scope resolution and up query,
// docs/DESIGN-APP-FOLDER-SEARCH.md. A browse runs /bin/ls and a search runs fd with the very
// arguments walk.lua builds, so both lists find the same files, and every row goes to the shared
// search to rank, as on the Lua side.

import Foundation

public enum FolderScope {
  public static func isDir(_ path: String) -> Bool {
    var folder: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &folder) && folder.boolValue
  }

  /// util.expandHome, a leading tilde alone or before a slash.
  public static func expandHome(_ path: String, home: String) -> String {
    if path == "~" { return home }
    if path.hasPrefix("~/") { return home + "/" + path.dropFirst(2) }
    return path
  }

  private static func trimSlashes(_ s: String) -> String {
    var t = Substring(s)
    while t.hasSuffix("/") { t = t.dropLast() }
    return String(t)
  }

  /// engine:_resolveScope, a scope token to a real folder or nil. An absolute or tilde path is
  /// taken literally, then the first segment is looked up in the folder aliases with the rest
  /// beneath it, then the whole token is tried under home.
  public static func resolve(_ token: String, roots: [String: String], home: String,
                             isDir: (String) -> Bool = FolderScope.isDir) -> String? {
    var t = trimSlashes(token)
    if t.isEmpty { return "/" }
    t = expandHome(t, home: home)
    if t.hasPrefix("/") { return isDir(t) ? t : nil }
    let parts = t.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    if let first = parts.first, !first.isEmpty {
      // Lua's lower folds A to Z alone.
      let key = String(first.map { $0.isASCII ? Character($0.lowercased()) : $0 })
      if let mapped = roots[key] {
        var base = home
        if !mapped.isEmpty {
          base = expandHome(mapped, home: home)
          if !base.hasPrefix("/") { base = home + "/" + base }
        }
        let rest = parts.count > 1 ? String(parts[1]) : ""
        let full = rest.isEmpty ? base : base + "/" + rest
        if isDir(full) { return full }
      }
    }
    let literal = home + "/" + t
    return isDir(literal) ? literal : nil
  }

  /// engine:upQuery, the query browsing the folder above a scope, home written as a tilde, or nil
  /// with no scope, at the root, or for a scope that names nothing.
  public static func upQuery(_ token: String?, roots: [String: String], home: String,
                             isDir: (String) -> Bool = FolderScope.isDir) -> String? {
    guard let token, let here = resolve(token, roots: roots, home: home, isDir: isDir), here != "/" else { return nil }
    guard let slash = here.lastIndex(of: "/") else { return nil }
    var parent = String(here[..<slash])
    if parent.isEmpty { return "/" }
    if !home.isEmpty, parent.hasPrefix(home) { parent = "~" + parent.dropFirst(home.count) }
    return parent + "/"
  }
}

/// Why a walk has no rows, each worded as the Lua list words its status row.
public enum WalkError: Error, Equatable {
  case timedOut
  case failed
}

public struct FolderWalk: Sendable {
  public var fd: String?
  public var prune: [String]
  public var insideFrom: Int?
  public var timeoutSeconds: Double

  public init(fd: String?, prune: [String], insideFrom: Int?, timeoutSeconds: Double) {
    self.fd = fd
    self.prune = prune
    self.insideFrom = insideFrom
    self.timeoutSeconds = timeoutSeconds
  }

  /// walk.lua's browse, one level newest first. ls marks a folder with a trailing slash under -p,
  /// lists dotfiles under -A without the two dot entries, and sorts by date under -t.
  public static func browseArguments(_ dir: String) -> [String] { ["-1", "-A", "-p", "-t", dir] }

  /// walk.lua's startPattern, a short word at a word start in the name, after anything that is no
  /// letter or digit or at a camel hump, as the shared search reads one.
  public static func startPattern(_ w: String) -> String {
    func esc(_ t: Substring) -> String {
      var out = ""
      for c in t.unicodeScalars {
        // Lua's %p, ASCII punctuation.
        if c.isASCII, CharacterSet.punctuationCharacters.union(.symbols).contains(c) { out += "\\" }
        out.unicodeScalars.append(c)
      }
      return out
    }
    let s = Substring(w)
    var pattern = "(?:^|[^\\p{L}\\p{N}])(?i:" + esc(s) + ")"
    if let first = s.unicodeScalars.first, first.isASCII, CharacterSet.letters.contains(first) {
      let rest = s.dropFirst()
      pattern += "|\\p{Ll}" + String(first).uppercased() + (rest.isEmpty ? "" : "(?i:" + esc(rest) + ")")
    }
    return pattern
  }

  /// walk.lua's search arguments, the first word as fd's pattern and every other word left to the
  /// shared search.
  public func searchArguments(_ q: FileQuery, dir: String, cap: Int) -> [String] {
    var args: [String] = []
    if q.hidden { args.append("--hidden") }
    if q.ignored {
      args.append("--no-ignore")
    } else {
      for name in prune { args += ["--exclude", name] }
    }
    for e in q.exts ?? [] { args += ["--extension", e] }
    args.append("--follow")
    args += ["--max-results", String(cap)]
    let first = q.words.first ?? ""
    if !first.isEmpty, let inside = insideFrom, first.utf8.count < inside {
      let lowered = String(first.map { $0.isASCII ? Character($0.lowercased()) : $0 })
      args += ["--case-sensitive", Self.startPattern(lowered)]
    } else {
      args += ["--ignore-case", "--fixed-strings", first]
    }
    args.append(dir)
    return args
  }

  /// The rows of a line of output, a trailing slash marking a folder.
  static func rows(_ text: String, under dir: String?) -> [IndexRow] {
    var out: [IndexRow] = []
    let base = dir.map { d -> String in
      var t = Substring(d)
      while t.hasSuffix("/") { t = t.dropLast() }
      return String(t)
    }
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
      let isDir = line.hasSuffix("/")
      let name = isDir ? String(line.dropLast()) : String(line)
      if name.isEmpty { continue }
      out.append(IndexRow(path: base.map { $0 + "/" + name } ?? name, mtime: 0, isDir: isDir, hidden: false))
    }
    return out
  }

  /// One level of a folder, newest first.
  public func browse(_ dir: String, cap: Int) async throws -> [IndexRow] {
    let text = try await run("/bin/ls", Self.browseArguments(dir))
    return Array(Self.rows(text, under: dir).prefix(cap))
  }

  /// A search beneath a folder. Throws WalkError.failed without fd.
  public func search(_ q: FileQuery, dir: String, cap: Int) async throws -> [IndexRow] {
    guard let fd else { throw WalkError.failed }
    let text = try await run(fd, searchArguments(q, dir: dir, cap: cap))
    return Self.rows(text, under: nil)
  }

  private static let queue = DispatchQueue(label: "olm.folderwalk", qos: .userInitiated, attributes: .concurrent)

  private func run(_ tool: String, _ args: [String]) async throws -> String {
    try Task.checkCancellation()
    let run = Run(tool: tool, args: args)
    let seconds = timeoutSeconds
    let text = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (done: CheckedContinuation<String, Error>) in
        Self.queue.async { done.resume(with: run.start()) }
        Self.queue.asyncAfter(deadline: .now() + max(0.1, seconds)) { run.timeOut() }
      }
    } onCancel: {
      run.cancel()
    }
    try Task.checkCancellation()
    return text
  }

  // One run of a tool, which a cancel or the time running out ends whether it has started or not.
  private final class Run: @unchecked Sendable {
    let process = Process()
    private let lock = NSLock()
    private var cancelled = false
    private var timedOut = false

    init(tool: String, args: [String]) {
      process.executableURL = URL(fileURLWithPath: tool)
      process.arguments = args
    }

    func cancel() {
      lock.withLock {
        cancelled = true
        if process.isRunning { process.terminate() }
      }
    }

    func timeOut() {
      lock.withLock {
        guard process.isRunning else { return }
        timedOut = true
        process.terminate()
      }
    }

    func start() -> Result<String, Error> {
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      let started: Bool = lock.withLock {
        if cancelled { return false }
        return (try? process.run()) != nil
      }
      if !started { return .failure(lock.withLock { cancelled } ? CancellationError() : WalkError.failed) }
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      let (wasCancelled, wasTimedOut) = lock.withLock { (cancelled, timedOut) }
      if wasCancelled { return .failure(CancellationError()) }
      if wasTimedOut { return .failure(WalkError.timedOut) }
      guard process.terminationStatus == 0 else { return .failure(WalkError.failed) }
      return .success(String(decoding: data, as: UTF8.self))
    }
  }
}
