// The shadow of step 1.3e of docs/PLAN-STANDALONE.md, written once for every source, as
// docs/DESIGN-APP.md says. The Lua list stays the one a person uses, rule 9 of the plan, and each
// answer it settles on is handed here by host/bridge as `~/.olm/run/<tool>shadow.json`, its query
// and its rows' keys in the order the shared search ranked them, followed by
// olm://shadow?tool=<tool>&id=N. This answers the same query through the source on a source of its
// own, so a list a person may have open is never touched, ranks it with the same search the stage
// ranks with, and appends one line per comparison to `~/.olm/log/shadow-<tool>.jsonl`. Nothing is
// shown.
//
// A query the source cannot answer like for like yet is logged as skipped, with the reason the
// composition root's skip answers, each naming the step that builds it.
//
// A list the app answers through the bridge, the launcher since step 2.3, is told what the Lua side
// settled on over the bridge's socket instead, `settled`, and its rows are named by what `named`
// answers, the launcher's memory keys, so a row the Lua side cannot name is left out on both sides.

import Foundation
import OlmKit

@MainActor
public final class Shadow {
  public let tool: String
  private let source: any ListSource
  private let searcher: Searcher
  private let skip: (String) -> String?
  private let requestURL: URL
  private let logURL: URL
  private let named: (@Sendable ([Row]) async -> [String])?
  private var told = 0
  // How many differing keys a line names on each side, so a line stays readable.
  private static let named = 5

  /// named answers the keys of the rows the app ranked that the Lua side names too, every row's key
  /// when nil, the launcher's leaving out a row with no memory key.
  public init(tool: String, source: any ListSource, searcher: Searcher, run: URL, log: URL,
              skip: @escaping (String) -> String?, named: (@Sendable ([Row]) async -> [String])? = nil) {
    self.named = named
    self.tool = tool
    self.source = source
    self.searcher = searcher
    self.skip = skip
    requestURL = run.appendingPathComponent("\(tool)shadow.json")
    logURL = log.appendingPathComponent("shadow-\(tool).jsonl")
  }

  struct Request {
    var id: Int
    var query: String
    var status: String?
    var keys: [String]
    var claimed = false
  }

  func read() -> Request? {
    guard let data = try? Data(contentsOf: requestURL),
      let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let id = (doc["id"] as? NSNumber)?.intValue,
      let query = doc["query"] as? String
    else { return nil }
    // An empty list reaches here as a JSON object, since Lua cannot tell an empty array from one.
    let keys = (doc["keys"] as? [Any])?.compactMap { $0 as? String } ?? []
    return Request(id: id, query: query, status: doc["status"] as? String, keys: keys)
  }

  /// Compares the request the URL names. A request written since, a newer id, is compared in its
  /// place, since the bridge rewrites one file and the newer answer is the one worth having.
  public func run(id: Int) {
    guard let request = read(), request.id >= id else { return }
    answer(request)
  }

  /// Compares what the Lua side settled on, told over the bridge's socket rather than by a file,
  /// step 2.3, the launcher's.
  public func settled(query: String, keys: [String], status: String?, claimed: Bool) {
    told += 1
    answer(Request(id: told, query: query, status: status, keys: keys, claimed: claimed))
  }

  private func answer(_ request: Request) {
    if let why = skip(request.query) {
      append(["at": Self.now(), "id": request.id, "query": request.query, "skipped": why])
      return
    }
    let source = source, searcher = searcher, named = named
    Task {
      let level = await source.open(query: request.query)
      guard let answer = try? await source.rows(Query(text: request.query, generation: request.id)) else { return }
      let ranked = await searcher.rank(answer, query: request.query, level: level)
      let status = answer.status ?? (ranked.rows.isEmpty ? answer.emptyStatus : nil)
      // A pinned row or one made from the query is the list's own, the `..` row of a browse among
      // them, and the Lua side leaves them out of what it sends too.
      let kept = ranked.rows.filter { !$0.pinned && !$0.fromQuery }
      let keys = await named?(kept) ?? kept.map(\.key)
      self.compare(request, keys, status: status)
    }
  }

  private func compare(_ request: Request, _ app: [String], status: String?) {
    let lua = request.keys
    var line: [String: Any] = [
      "at": Self.now(), "id": request.id, "query": request.query,
      "same": lua == app, "lua": lua.count, "app": app.count,
    ]
    if let s = request.status { line["luaStatus"] = s }
    if request.claimed { line["claimed"] = true }
    if let status { line["appStatus"] = status }
    if lua != app {
      let shared = min(lua.count, app.count)
      line["firstDiff"] = ((0..<shared).first { lua[$0] != app[$0] } ?? shared) + 1
      let luaSet = Set(lua), appSet = Set(app)
      line["onlyLua"] = Array(lua.filter { !appSet.contains($0) }.prefix(Self.named))
      line["onlyApp"] = Array(app.filter { !luaSet.contains($0) }.prefix(Self.named))
      line["luaTop"] = Array(lua.prefix(Self.named))
      line["appTop"] = Array(app.prefix(Self.named))
    }
    append(line)
  }

  private static func now() -> String { ISO8601DateFormatter().string(from: Date()) }

  private func append(_ line: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
    data.append(0x0A)
    try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let handle = try? FileHandle(forWritingTo: logURL) {
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
    } else {
      try? data.write(to: logURL)
    }
  }
}
