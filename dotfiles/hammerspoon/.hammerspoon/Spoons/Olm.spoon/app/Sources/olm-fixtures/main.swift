// The Swift side of the shared fixtures, docs/PLAN-STANDALONE.md rule 4. It reads the same JSON
// files test/fixtures.lua reads and runs each kind the app has ported, so a part moves into the app
// only once its fixtures pass here too. A kind not ported yet is counted as skipped, never as
// passed. test/olmfixtures.sh builds and runs it.
//
//   olm-fixtures DIR    every fixture file under DIR, test/fixtures in the spoon

import Foundation
import OlmSearch

var failures = 0, passed = 0, skipped = 0

func fail(_ file: String, _ name: String, _ why: String) {
  failures += 1
  print("  FAIL  \(file), \(name), \(why)")
}

// A value as JSON writes it, for a message.
func show(_ v: Any?) -> String {
  guard let v, !(v is NSNull) else { return "null" }
  if let data = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed, .sortedKeys]),
    let s = String(data: data, encoding: .utf8) { return s }
  return "\(v)"
}

// Two JSON values alike, null and absent alike.
func same(_ a: Any?, _ b: Any?) -> Bool {
  let a = (a is NSNull) ? nil : a, b = (b is NSNull) ? nil : b
  switch (a, b) {
  case (nil, nil): return true
  case (nil, _), (_, nil): return false
  case let (x as [Any], y as [Any]):
    return x.count == y.count && zip(x, y).allSatisfy { same($0, $1) }
  case let (x as [String: Any], y as [String: Any]):
    let keys = Set(x.keys).union(y.keys)
    return keys.allSatisfy { same(x[$0], y[$0]) }
  case let (x as NSObject, y as NSObject): return x.isEqual(y)
  default: return false
  }
}

func types(_ doc: [String: Any]) -> [String: [String]] {
  (doc["types"] as? [String: [String]]) ?? [:]
}

// A parse as the fixtures name its fields.
func fields(_ q: FileQuery) -> [String: Any] {
  [
    "raw": q.raw, "hidden": q.hidden, "ignored": q.ignored, "typeTokens": q.typeTokens,
    "exts": q.exts as Any? ?? NSNull(), "scope": q.scope as Any? ?? NSNull(),
    "text": q.text, "words": q.words, "kind": q.kind.rawValue,
  ]
}

func runParse(_ file: String, _ doc: [String: Any]) {
  let t = types(doc)
  for case let c as [String: Any] in (doc["cases"] as? [Any]) ?? [] {
    let name = c["name"] as? String ?? "?"
    let got = fields(FileQueryGrammar.parse(c["raw"] as? String ?? "", types: t))
    var ok = true
    for (key, want) in (c["expect"] as? [String: Any]) ?? [:] where !same(got[key], want) {
      fail(file, name, "\(key) wanted \(show(want)), got \(show(got[key]))")
      ok = false
    }
    if ok { passed += 1 }
  }
}

func runNarrows(_ file: String, _ doc: [String: Any]) {
  let t = types(doc)
  for case let c as [String: Any] in (doc["cases"] as? [Any]) ?? [] {
    let name = c["name"] as? String ?? "?"
    let prev = FileQueryGrammar.parse(c["prev"] as? String ?? "", types: t)
    let next = FileQueryGrammar.parse(c["next"] as? String ?? "", types: t)
    var ok = true
    if let want = c["sameShape"] as? Bool, FileQueryGrammar.sameShape(prev, next) != want {
      fail(file, name, "sameShape wanted \(want)"); ok = false
    }
    if let want = c["narrows"] as? Bool, FileQueryGrammar.narrows(prev, next) != want {
      fail(file, name, "narrows wanted \(want)"); ok = false
    }
    if ok { passed += 1 }
  }
}

let runners: [String: (String, [String: Any]) -> Void] = [
  "filesearch.parse": runParse,
  "filesearch.narrows": runNarrows,
]

guard CommandLine.arguments.count == 2 else {
  print("usage: olm-fixtures DIR")
  exit(64)
}
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
  .compactMap { $0 as? URL } ?? [])
  .filter { $0.pathExtension == "json" }
  .sorted { $0.path < $1.path }
var skippedKinds = Set<String>()
for url in files {
  let file = String(url.path.dropFirst(root.path.count + 1))
  guard let data = try? Data(contentsOf: url),
    let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    fail(file, "the file", "is not a JSON object"); continue
  }
  let kind = doc["kind"] as? String ?? "?"
  if let run = runners[kind] {
    run(file, doc)
  } else {
    skipped += ((doc["cases"] as? [Any])?.count ?? 0)
    skippedKinds.insert(kind)
  }
}
print("olm-fixtures, \(passed) passed, \(failures) failed, \(skipped) not ported yet (\(skippedKinds.sorted().joined(separator: ", ")))")
exit(failures == 0 ? 0 : 1)
