// File search's index, built by the app, step 1.5 of docs/PLAN-STANDALONE.md,
// docs/PARITY-FILESEARCH.md. The list that serves owns the index, Milos's call on 2026-11-11, as
// 1.4d gave frecency one owner, so once the app serves file search an open rebuilds an index older
// than its limit in the background, as plugins/filesearch/sources/index.lua's warm does. It runs
// the same helper with the same arguments into the same file, `build`, the index path, the prune
// list joined by newlines and the roots, home and searchAlso. The helper writes a temporary file of
// its own and moves it into place, so a search reads the old index whole meanwhile, and a build the
// Lua side starts at the same moment, from the launcher's slash scope, never mixes with this one.
//
// Every mutable field is behind the lock, so it is safe across threads.

import Foundation

public final class IndexBuild: @unchecked Sendable {
  public let helper: String
  public let index: String
  /// How long a build may run before it is ended, index.lua's 60.
  public static let timeoutSeconds = 60.0
  private let lock = NSLock()
  private var running: Process?
  private var waiters: [CheckedContinuation<Bool, Never>] = []
  private static let queue = DispatchQueue(label: "olm.indexbuild", qos: .utility)

  public init(helper: String, index: String) {
    self.helper = helper
    self.index = index
  }

  /// Seconds since the index was written, nil when there is none.
  public func age(now: Date = Date()) -> Double? {
    guard let at = (try? FileManager.default.attributesOfItem(atPath: index))?[.modificationDate] as? Date
    else { return nil }
    return now.timeIntervalSince(at)
  }

  /// Whether a build is running.
  public var building: Bool { lock.withLock { running != nil } }

  /// What the list says while a build runs, index.lua's status, Building index with no index yet
  /// and Updating index over an old one, nil with none running.
  public var status: String? {
    guard building else { return nil }
    return age() == nil ? Self.buildingText : Self.updatingText
  }
  public static let buildingText = "Building index"
  public static let updatingText = "Updating index"

  /// The index's starting points, index.lua's roots, home and every searchAlso folder that exists,
  /// a relative one under home, each once.
  public static func roots(home: String, searchAlso: [String]) -> [String] {
    var list = [home]
    var seen: Set<String> = [home]
    for entry in searchAlso {
      var path = (entry as NSString).expandingTildeInPath
      while path.count > 1, path.hasSuffix("/") { path.removeLast() }
      if !path.isEmpty, !path.hasPrefix("/") { path = home + "/" + path }
      var dir: ObjCBool = false
      guard !path.isEmpty, !seen.contains(path),
        FileManager.default.fileExists(atPath: path, isDirectory: &dir), dir.boolValue else { continue }
      seen.insert(path)
      list.append(path)
    }
    return list
  }

  /// Starts a build in the background when the index is missing or older than maxAge seconds and
  /// none is running, index.lua's warm, and answers whether one is running after the call.
  @discardableResult
  public func warm(maxAge: Double, prune: [String], roots: [String]) -> Bool {
    if let age = age(), age <= maxAge { return building }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: helper)
    process.arguments = ["build", index, prune.joined(separator: "\n")] + roots
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let started: Bool = lock.withLock {
      if running != nil { return false }
      guard (try? process.run()) != nil else { return false }
      running = process
      return true
    }
    if started {
      Self.queue.asyncAfter(deadline: .now() + Self.timeoutSeconds) { [weak process] in
        if let process, process.isRunning { process.terminate() }
      }
      Self.queue.async { [self] in
        process.waitUntilExit()
        let built = process.terminationStatus == 0
        let waiting: [CheckedContinuation<Bool, Never>] = lock.withLock {
          running = nil
          defer { waiters = [] }
          return waiters
        }
        for waiter in waiting { waiter.resume(returning: built) }
      }
    }
    return building
  }

  /// Waits for the build running, true when it replaced the index, and false at once with none.
  /// A wait whose task was cancelled still ends when the build does, and its asker drops the answer.
  public func landed() async -> Bool {
    await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
      let parked: Bool = lock.withLock {
        guard running != nil else { return false }
        waiters.append(done)
        return true
      }
      if !parked { done.resume(returning: false) }
    }
  }
}
