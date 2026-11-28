// Convert, the port of plugins/convert, step 6.10b of docs/PLAN-STANDALONE.md. A query is a
// conversion only when it has a digit and names a target after its last `to` or `->`, the Lua gate,
// so an ordinary search never runs anything. The tool is qalc with the plugin's three flags, run off
// the main thread with a time limit, and an answer in mixed units is asked again with a minus on the
// target and kept only when that gives one clean value. Every answer, and every failure, is kept for
// the session, so a query runs once. plugins/convert/AGENTS.md has why each rule is what it is.

import Foundation

public actor Convert {
  public enum Answer: Sendable, Equatable {
    case value(String)
    case miss
  }

  /// The flags every run carries: terse output, an unknown word a failure, no rate download.
  static let flags = ["-t", "-set", "limimpl on", "-set", "upxrates 0"]
  static let operators = [" to ", "->"]
  static let cacheMax = 200
  /// Seconds a run may take before it is stopped and read as no answer.
  static let limit: TimeInterval = 5

  public nonisolated let tool: String?
  private var cache: [String: Answer] = [:]

  /// tool, qalc's path, nil where it is not installed, which leaves conversion out.
  public init(tool: String?) { self.tool = tool }

  /// qalc where Hammerspoon's resolver finds Homebrew's tools.
  public static func find() -> String? {
    for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
      let path = dir + "/qalc"
      if FileManager.default.isExecutableFile(atPath: path) { return path }
    }
    return nil
  }

  static func isSpace(_ c: Character) -> Bool { c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\u{0B}" || c == "\u{0C}" }

  static func trim(_ s: String) -> String {
    var s = Substring(s)
    while let f = s.first, isSpace(f) { s.removeFirst() }
    while let l = s.last, isSpace(l) { s.removeLast() }
    return String(s)
  }

  static func asciiLower(_ s: String) -> String {
    String(decoding: s.utf8.map { ($0 >= 65 && $0 <= 90) ? $0 + 32 : $0 }, as: UTF8.self)
  }

  /// The expression and the target, split at the last operator, or nil when the query is not one.
  public static func parts(_ query: String) -> (expression: String, target: String)? {
    let q = trim(query)
    guard q.utf8.contains(where: { $0 >= 48 && $0 <= 57 }) else { return nil }
    let low = Array(asciiLower(q).utf8), bytes = Array(q.utf8)
    var at: Int?, stop = 0
    for op in operators.map({ Array($0.utf8) }) where low.count >= op.count {
      for i in 0...(low.count - op.count) where Array(low[i..<(i + op.count)]) == op {
        if at == nil || i > at! {
          at = i
          stop = i + op.count
        }
      }
    }
    guard let at else { return nil }
    let expression = trim(String(decoding: bytes[0..<at], as: UTF8.self))
    let target = trim(String(decoding: bytes[stop...], as: UTF8.self))
    guard !expression.isEmpty, !target.isEmpty else { return nil }
    return (expression, target)
  }

  /// The answer kept for a query, nil when it has not been run.
  public func cached(_ query: String) -> Answer? { cache[Self.trim(query)] }

  /// Runs a conversion, once per query, and keeps what it answered.
  public func convert(_ query: String) async -> Answer {
    let q = Self.trim(query)
    if let kept = cache[q] { return kept }
    guard let tool, let (expression, target) = Self.parts(q) else { return .miss }
    // The minus form is run beside the plain one rather than after it, so a mixed unit answer costs
    // one run's time, and is used only where the Lua plugin would use its retry.
    let minus = !target.hasPrefix("+") && !target.hasPrefix("-")
    async let plain = Self.exec(tool, expression + " to " + target)
    async let retried: String? = minus ? Self.exec(tool, expression + " to -" + target) : nil
    var answer: Answer = .miss
    if let text = await plain {
      answer = .value(text)
      if !Self.single(text), let retry = await retried, Self.single(retry) { answer = .value(retry) }
    }
    _ = await retried
    if cache.count >= Self.cacheMax { cache = [:] }
    cache[q] = answer
    return answer
  }

  /// One clean value, not a sum of units and not an unevaluated expression.
  static func single(_ text: String) -> Bool { !text.contains(" + ") && !text.contains("(") }

  /// qalc's answer to one expression, nil when it failed, said nothing or said error.
  static func exec(_ tool: String, _ expression: String) async -> String? {
    await withCheckedContinuation { (done: CheckedContinuation<String?, Never>) in
      let p = Process()
      p.executableURL = URL(fileURLWithPath: tool)
      p.arguments = flags + [expression]
      let out = Pipe()
      p.standardOutput = out
      p.standardError = FileHandle.nullDevice
      p.standardInput = FileHandle.nullDevice
      let once = Once(done)
      let finish: @Sendable (String?) -> Void = { once.resume($0) }
      p.terminationHandler = { proc in
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let text = trim(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\u{2212}", with: "-"))
        if proc.terminationStatus != 0 || text.isEmpty || text.lowercased().contains("error") { return finish(nil) }
        finish(text)
      }
      do { try p.run() } catch { return finish(nil) }
      DispatchQueue.global().asyncAfter(deadline: .now() + limit) {
        if p.isRunning { p.terminate() }
        finish(nil)
      }
    }
  }
}

/// A continuation resumed by whichever comes first, the run's end or the time limit.
private final class Once: @unchecked Sendable {
  private let lock = NSLock()
  private var done: CheckedContinuation<String?, Never>?
  init(_ done: CheckedContinuation<String?, Never>) { self.done = done }
  func resume(_ value: String?) {
    lock.lock()
    let d = done
    done = nil
    lock.unlock()
    d?.resume(returning: value)
  }
}
