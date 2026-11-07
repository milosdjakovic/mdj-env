// The Swift side of the shared fixtures, docs/PLAN-STANDALONE.md rule 4. It reads the same JSON
// files test/fixtures.lua reads and runs each kind the app has ported, so a part moves into the app
// only once its fixtures pass here too. A kind not ported yet is counted as skipped, never as
// passed. test/olmfixtures.sh builds and runs it.
//
//   olm-fixtures DIR    every fixture file under DIR, test/fixtures in the spoon

import Foundation
import OlmLook
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

// A JSON boolean, which JSONSerialization hands over as an NSNumber like any number, so it is told
// apart by its Core Foundation type, the way Lua tells true from 1.
func isBool(_ v: Any?) -> Bool {
  guard let n = v as? NSNumber else { return false }
  return CFGetTypeID(n) == CFBooleanGetTypeID()
}

// A JSON number that is not a boolean, the only thing Lua's type(x) == "number" accepts.
func number(_ v: Any?) -> Double? {
  guard let n = v as? NSNumber, !isBool(n) else { return nil }
  return n.doubleValue
}

// A row as a fixture writes it, each field read the way rank.lua reads it, a field of the wrong
// type being absent. pinned and fromQuery count only when they are the boolean true.
func rankRow(_ d: [String: Any]) -> RankRow {
  var keywords: [String] = []
  if let k = d["keywords"] as? String { keywords = [k] }
  else if let list = d["keywords"] as? [Any] { keywords = list.compactMap { $0 as? String } }
  return RankRow(
    title: d["title"] as? String,
    subTitle: d["subTitle"] as? String,
    filterText: d["filterText"] as? String,
    keywords: keywords,
    names: (d["names"] as? [Any]).map { $0.compactMap { $0 as? String } },
    pinned: isBool(d["pinned"]) && (d["pinned"] as? Bool) == true,
    fromQuery: isBool(d["fromQuery"]) && (d["fromQuery"] as? Bool) == true,
    tier: number(d["tier"]) ?? 0,
    bonus: number(d["bonus"]) ?? 0
  )
}

// rank.order, a case's rows ranked for its query, the titles shown in order and, where the case
// names more, what the limit cut, null meaning nothing.
func runOrder(_ file: String, _ doc: [String: Any]) {
  for case let c as [String: Any] in (doc["cases"] as? [Any]) ?? [] {
    let name = c["name"] as? String ?? "?"
    let dicts = ((c["rows"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
    var limit: Int? = nil
    if let n = number(c["rowLimit"]), n >= 1, n.rounded(.towardZero) == n { limit = Int(n) }
    let got = Rank.apply(dicts.map(rankRow), query: c["query"] as? String ?? "", rowLimit: limit)
    let titles: [Any] = got.order.map { dicts[$0]["title"] ?? NSNull() }
    var ok = true
    if !same(titles, c["expect"]) {
      fail(file, name, "wanted \(show(c["expect"])), got \(show(titles))"); ok = false
    }
    if c.keys.contains("more") {
      let cut: Any = got.more.map { ["count": $0.count, "at": $0.at + 1] as [String: Any] } ?? NSNull()
      if !same(cut, c["more"]) {
        fail(file, name, "cut wanted \(show(c["more"])), got \(show(cut))"); ok = false
      }
    }
    if ok { passed += 1 }
  }
}

// rank.corpus, one list and many queries, each expecting the 1 based places of the rows shown.
// One matcher serves every query, as one list asks it on every keystroke.
func runCorpus(_ file: String, _ doc: [String: Any]) {
  let rows = ((doc["rows"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.map(rankRow)
  let fuzzy = Fuzzy()
  for case let c as [String: Any] in (doc["cases"] as? [Any]) ?? [] {
    let query = c["query"] as? String ?? ""
    let places = Rank.apply(rows, query: query, using: fuzzy).order.map { $0 + 1 }
    if same(places, c["expect"]) {
      passed += 1
    } else {
      fail(file, "query \(show(query))", "wanted \(show(c["expect"])), got \(show(places))")
    }
  }
}

// A rectangle as the fixtures write one, under only where it is set.
func rectFields(_ r: LayoutRect?) -> Any {
  guard let r else { return NSNull() }
  var out: [String: Any] = ["x": r.x, "y": r.y, "w": r.w, "h": r.h]
  if let under = r.under { out["under"] = under }
  return out
}

func rect(_ v: Any?) -> LayoutRect {
  let d = v as? [String: Any] ?? [:]
  func n(_ k: String) -> Double { (d[k] as? NSNumber)?.doubleValue ?? 0 }
  return LayoutRect(x: n("x"), y: n("y"), w: n("w"), h: n("h"))
}

func runGeometry(_ file: String, _ doc: [String: Any]) {
  let base = doc["layout"] as? [String: Any] ?? [:]
  for case let c as [String: Any] in (doc["cases"] as? [Any]) ?? [] {
    let name = c["name"] as? String ?? "?"
    var fields = base
    for (k, v) in c["layout"] as? [String: Any] ?? [:] { fields[k] = v }
    var width = PreviewPaneWidth.none
    if let n = c["previewPaneWidth"] as? NSNumber {
      width = CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? .list : .none) : .points(n.doubleValue)
    }
    let r = Geometry.resolve(screen: rect(c["screen"]), layout: ChooserLayout(fields), previewPaneWidth: width)
    let got: [String: Any] = [
      "canvas": rectFields(r.canvas), "field": rectFields(r.field), "list": rectFields(r.list),
      "previewPane": rectFields(r.previewPane), "bottomBar": rectFields(r.bottomBar),
      "rowCount": r.rowCount, "viewRows": r.viewRows,
    ]
    var ok = true
    for (key, want) in (c["expect"] as? [String: Any]) ?? [:] where !same(got[key], want) {
      fail(file, name, "\(key) wanted \(show(want)), got \(show(got[key]))")
      ok = false
    }
    if ok { passed += 1 }
  }
}

let runners: [String: (String, [String: Any]) -> Void] = [
  "filesearch.parse": runParse,
  "filesearch.narrows": runNarrows,
  "chooser.geometry": runGeometry,
  "rank.order": runOrder,
  "rank.corpus": runCorpus,
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
