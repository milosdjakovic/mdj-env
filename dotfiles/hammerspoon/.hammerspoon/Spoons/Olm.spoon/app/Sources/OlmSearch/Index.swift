// File search's index, read by the app, step 1.3c of docs/PLAN-STANDALONE.md.
//
// The app asks the same helper the Lua side asks, plugins/filesearch/sources/fileindex.swift,
// compiled into the app's bundle by app/build.sh from that one source, so the two sides can never
// search differently. It reads the index the Lua side builds, ~/.olm/cache/filesearch/
// file-index.txt, and never builds one itself, so the index keeps one owner until the step that
// moves it. The arguments are the ones plugins/filesearch/sources/index.lua's argsFor builds.
//
// Every ask runs on a queue of its own and answers on the main queue, so typing never waits on a
// search. A new ask supersedes the one before it, whose process is ended and whose answer, if it
// is already on its way, is dropped by its generation.

import Foundation

public struct IndexRow: Equatable {
  public var path: String
  public var mtime: Int
  public var isDir: Bool
  public var hidden: Bool
  public var name: String { (path as NSString).lastPathComponent }
}

public final class FileIndex {
  public let helper: String
  public let index: String
  public var recentDays = 7

  private let queue = DispatchQueue(label: "olm.fileindex", qos: .userInitiated)
  private let lock = NSLock()
  private var generation = 0
  private var running: Process?

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

  /// Asks the index for a parse, answering on the main queue with the rows, or nil when the ask
  /// failed, unless a newer ask came first, in which case it never answers.
  public func ask(_ q: FileQuery, cap: Int, answer: @escaping ([IndexRow]?) -> Void) {
    lock.lock()
    generation += 1
    let mine = generation
    running?.terminate()
    running = nil
    lock.unlock()
    guard let args = arguments(for: q, cap: cap) else {
      DispatchQueue.main.async { answer([]) }
      return
    }
    queue.async { [weak self] in
      guard let self else { return }
      let rows = self.run(args, generation: mine)
      DispatchQueue.main.async {
        self.lock.lock()
        let current = self.generation == mine
        self.lock.unlock()
        if current { answer(rows) }
      }
    }
  }

  private func run(_ args: [String], generation mine: Int) -> [IndexRow]? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: helper)
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    lock.lock()
    if generation != mine { lock.unlock(); return nil }
    running = process
    lock.unlock()
    do { try process.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    lock.lock()
    if running === process { running = nil }
    lock.unlock()
    guard process.terminationStatus == 0 else { return nil }
    let text = String(decoding: data, as: UTF8.self)
    return text.split(separator: "\n").compactMap(Self.row)
  }
}
