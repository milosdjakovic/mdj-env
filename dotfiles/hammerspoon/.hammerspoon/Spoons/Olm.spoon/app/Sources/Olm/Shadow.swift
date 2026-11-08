// The shadow of step 1.3e of docs/PLAN-STANDALONE.md. The Lua file search stays the one a person
// uses, rule 9 of the plan, and each answer it settles on is handed here by host/bridge as
// `~/.olm/run/filesearchshadow.json`, its query and its rows' paths in the order the shared search
// ranked them, followed by olm://shadow?tool=filesearch&id=N. This answers the same query with the
// app's own engine, on an engine of its own so the list a person may have open is never touched,
// and appends one line per comparison to `~/.olm/log/shadow-filesearch.jsonl`. Nothing is shown.
//
// Two shapes are not compared yet, each named by the step that builds it. A folder search is 1.4e,
// and the recent list, an empty or short query, is ordered by frecency on the Lua side, 1.4d. Both
// sides leave frecency's bonus out of a search, so a search compares the index, the grammar, the
// narrowing and the ranking, and nothing the history decides.

import Foundation
import OlmSearch

final class FileSearchShadow {
  private static let home = FileManager.default.homeDirectoryForCurrentUser.path
  static let requestPath = home + "/.olm/run/filesearchshadow.json"
  static let logPath = home + "/.olm/log/shadow-filesearch.jsonl"

  private let engine: FileSearchEngine
  // How many differing paths a line names on each side, so a line stays readable.
  private static let named = 5

  init(index: FileIndex) {
    engine = FileSearchEngine(index: index, settings: FileSearchSettings())
  }

  struct Request {
    var id: Int
    var query: String
    var status: String?
    var keys: [String]
  }

  static func read() -> Request? {
    guard let data = FileManager.default.contents(atPath: requestPath),
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
  func run(id: Int, settings: FileSearchSettings) {
    guard let request = Self.read(), request.id >= id else { return }
    let q = FileQueryGrammar.parse(request.query, types: settings.types)
    if q.scope != nil { return log(request, skipped: "a folder search, step 1.4e") }
    if q.kind != .search || q.text.utf8.count < settings.minChars {
      return log(request, skipped: "the recent list, ordered by frecency on the Lua side, step 1.4d")
    }
    engine.settings = settings
    engine.reset()
    engine.query(request.query) { [weak self] answer in
      self?.compare(request, answer.rows.map(\.path), status: answer.status)
    }
  }

  private func compare(_ request: Request, _ app: [String], status: String?) {
    let lua = request.keys
    var line: [String: Any] = [
      "at": ISO8601DateFormatter().string(from: Date()),
      "id": request.id, "query": request.query,
      "same": lua == app, "lua": lua.count, "app": app.count,
    ]
    if let s = request.status { line["luaStatus"] = s }
    if let status { line["appStatus"] = status }
    if lua != app {
      let first = (0..<min(lua.count, app.count)).first(where: { lua[$0] != app[$0] }) ?? min(lua.count, app.count)
      line["firstDiff"] = first + 1
      let luaSet = Set(lua), appSet = Set(app)
      line["onlyLua"] = Array(lua.filter { !appSet.contains($0) }.prefix(Self.named))
      line["onlyApp"] = Array(app.filter { !luaSet.contains($0) }.prefix(Self.named))
      line["luaTop"] = Array(lua.prefix(Self.named))
      line["appTop"] = Array(app.prefix(Self.named))
    }
    append(line)
  }

  private func log(_ request: Request, skipped why: String) {
    append(["at": ISO8601DateFormatter().string(from: Date()), "id": request.id,
      "query": request.query, "skipped": why])
  }

  private func append(_ line: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
    data.append(0x0A)
    let url = URL(fileURLWithPath: Self.logPath)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let handle = try? FileHandle(forWritingTo: url) {
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
    } else {
      try? data.write(to: url)
    }
  }
}
