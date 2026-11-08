// File search's index, read by the app, step 1.3c of docs/PLAN-STANDALONE.md.
//
// The app asks the same helper the Lua side asks, plugins/filesearch/sources/fileindex.swift,
// compiled into the app's bundle by app/build.sh from that one source, so the two sides can never
// search differently. It reads the index the Lua side builds, ~/.olm/cache/filesearch/
// file-index.txt, and never builds one itself, so the index keeps one owner until the step that
// moves it. The arguments are the ones plugins/filesearch/sources/index.lua's argsFor builds.
//
// An ask runs the helper on a queue of its own, so the caller's actor is free while it runs, and a
// cancelled ask ends the helper's process and throws, which is how a newer query supersedes an
// older one, the stage cancelling the task the older one runs on.

import Foundation

public struct IndexRow: Equatable, Sendable {
  public var path: String
  public var mtime: Int
  public var isDir: Bool
  public var hidden: Bool
  public var name: String { (path as NSString).lastPathComponent }
}

/// Why an ask has no rows.
public enum IndexError: Error, Equatable {
  /// The helper failed or could not be started.
  case failed
}

// Every mutable field is behind the lock, so it is safe across threads.
public final class FileIndex: @unchecked Sendable {
  public let helper: String
  public let index: String
  private let lock = NSLock()
  private var _recentDays = 7
  private static let queue = DispatchQueue(label: "olm.fileindex", qos: .userInitiated, attributes: .concurrent)

  public var recentDays: Int {
    get { lock.withLock { _recentDays } }
    set { lock.withLock { _recentDays = newValue } }
  }

  public init(helper: String, index: String) {
    self.helper = helper
    self.index = index
  }

  /// The helper's arguments for a parse, or nil when there is nothing to ask, argsFor in index.lua.
  public func arguments(for q: FileQuery, cap: Int, now: Int = Int(Date().timeIntervalSince1970)) -> [String]? {
    let exts = (q.exts ?? []).flatMap { ["-e", $0] }
    if q.kind == .recent {
      if q.hidden { return nil }
      let since = exts.isEmpty ? now - recentDays * 86400 : 0
      return ["recent", index, String(cap), String(since)] + exts
    }
    if q.words.isEmpty { return nil }
    return ["search", index, String(cap)] + (q.hidden ? ["-h"] : []) + exts + q.words
  }

  /// One index line, `mtime TAB flags TAB path`, or nil for a line of another shape.
  public static func row(_ line: Substring) -> IndexRow? {
    let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count == 3, let mtime = Int(parts[0]), !parts[2].isEmpty else { return nil }
    return IndexRow(path: String(parts[2]), mtime: mtime,
      isDir: parts[1].contains("d"), hidden: parts[1].contains("h"))
  }

  /// The rows the index holds for a parse. Throws CancellationError when the task was cancelled,
  /// whose helper is ended, and IndexError.failed when the helper failed.
  public func ask(_ q: FileQuery, cap: Int) async throws -> [IndexRow] {
    guard let args = arguments(for: q, cap: cap) else { return [] }
    try Task.checkCancellation()
    let run = Run(helper: helper, args: args)
    let rows = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (done: CheckedContinuation<[IndexRow], Error>) in
        Self.queue.async { done.resume(with: run.start()) }
      }
    } onCancel: {
      run.cancel()
    }
    try Task.checkCancellation()
    return rows
  }

  // One run of the helper, which a cancel ends whether it has started or not.
  private final class Run: @unchecked Sendable {
    let process = Process()
    private let lock = NSLock()
    private var cancelled = false

    init(helper: String, args: [String]) {
      process.executableURL = URL(fileURLWithPath: helper)
      process.arguments = args
    }

    func cancel() {
      lock.withLock {
        cancelled = true
        if process.isRunning { process.terminate() }
      }
    }

    func start() -> Result<[IndexRow], Error> {
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      let started: Bool = lock.withLock {
        if cancelled { return false }
        return (try? process.run()) != nil
      }
      if !started { return .failure(lock.withLock { cancelled } ? CancellationError() : IndexError.failed) }
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      if lock.withLock({ cancelled }) { return .failure(CancellationError()) }
      guard process.terminationStatus == 0 else { return .failure(IndexError.failed) }
      let text = String(decoding: data, as: UTF8.self)
      return .success(text.split(separator: "\n").compactMap(FileIndex.row))
    }
  }
}
