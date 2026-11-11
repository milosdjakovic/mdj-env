// The Swift side of the shared fixtures, docs/PLAN-STANDALONE.md rule 4. It reads the same JSON
// files test/fixtures.lua reads and runs each kind the app has ported, so a part moves into the app
// only once its fixtures pass here too. A kind not ported yet is counted as skipped, never as
// passed. test/olmfixtures.sh builds and runs it.
//
//   olm-fixtures DIR    every fixture file under DIR, test/fixtures in the spoon

import Foundation
import OlmCore
import OlmKit
import OlmLook
import OlmSearch
import FileSearchPlugin

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

// chooser.pane, a file search row and what the helper's peek found, described by the file search
// plugin and laid out by OlmCore's port of the Lua pane with the app's own measurer, against the
// elements the Lua pane drew, frames and the height within half a point. Every width Hammerspoon
// measured is measured again first, since a pane can only lay out alike when the two measure alike.
func runPane(_ file: String, _ doc: [String: Any]) {
  func num(_ v: Any?) -> Double? {
    guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    return n.doubleValue
  }
  let home = doc["home"] as? String ?? ""
  let now = Int(num(doc["now"]) ?? 0)
  let f = doc["frame"] as? [String: Any] ?? [:]
  let frame = PaneFrame(w: num(f["w"]) ?? 0, h: num(f["h"]) ?? 0, under: num(f["under"]) ?? 0)
  let limits = PreviewLimits(doc["limits"] as? [String: Any] ?? [:])
  let tokens = doc["tokens"] as? [String: Any] ?? [:]
  let measure = PaneMeasure()
  let emptyText = FileSearchSource.paneEmptyText
  if emptyText != doc["emptyText"] as? String {
    fail(file, "the empty text", "wanted \(show(doc["emptyText"])), the plugin says \(show(emptyText))")
  }

  // The widths first.
  var off = 0, measuredCount = 0
  for (key, raw) in (doc["measured"] as? [String: Any])?["sizes"] as? [String: Any] ?? [:] {
    let parts = key.split(separator: "|", maxSplits: 1)
    guard parts.count == 2, let size = Double(parts[1]) else { continue }
    for (str, w) in raw as? [String: Any] ?? [:] {
      measuredCount += 1
      let got = PaneMeasure.measure(str, font: String(parts[0]), size: size)
      if let w = num(w), abs(got - w) > 1e-9 {
        off += 1
        if off <= 5 { fail(file, "the measurer", "\(show(str)) in \(key) wanted \(w), got \(got)") }
      }
    }
  }
  if off == 0 { passed += 1 }

  func peek(_ v: Any?) -> Peek? {
    guard let v, !(v is NSNull) else { return nil }
    guard let seen = v as? [String: Any] else { return Peek() }
    var p = Peek()
    if let a = seen["attrs"] as? [String: Any] {
      p.attrs = Peek.Attrs(isDir: a["mode"] as? String == "directory", size: Int(num(a["size"]) ?? 0),
        modification: Int(num(a["modification"]) ?? 0), creation: Int(num(a["creation"]) ?? 0))
    }
    if let blob = seen["blob"] as? String { p.blob = Data(blob.utf8) }
    if let fo = seen["folder"] as? [String: Any] {
      let entries = (fo["entries"] as? [Any] ?? []).compactMap { e -> Peek.Entry? in
        guard let e = e as? [String: Any], let name = e["name"] as? String else { return nil }
        return Peek.Entry(name: name, at: Int(num(e["at"]) ?? 0))
      }
      p.folder = Peek.Folder(scanned: Int(num(fo["scanned"]) ?? 0), truncated: fo["truncated"] as? Bool ?? false,
        entries: entries)
    }
    return p
  }

  func rect(_ v: Any?) -> PaneRect? {
    guard let r = v as? [String: Any], let x = num(r["x"]), let y = num(r["y"]), let w = num(r["w"]), let h = num(r["h"])
    else { return nil }
    return PaneRect(x: x, y: y, w: w, h: h)
  }
  func near(_ a: PaneRect, _ b: PaneRect) -> Bool {
    abs(a.x - b.x) <= 0.5 && abs(a.y - b.y) <= 0.5 && abs(a.w - b.w) <= 0.5 && abs(a.h - b.h) <= 0.5
  }
  func describe(_ r: PaneRect) -> String { "{\(r.x), \(r.y), \(r.w), \(r.h)}" }

  // One element against the one the Lua drew, nil when they agree.
  func differs(_ want: [String: Any], _ got: PaneItem) -> String? {
    switch got {
    case .resetClip:
      return want["type"] as? String == "resetClip" ? nil : "wanted \(show(want["type"])), got resetClip"
    case .fill(let r, _, _):
      guard want["type"] as? String == "fill", let w = rect(want["frame"]) else { return "wanted \(show(want["type"])), got a fill" }
      return near(w, r) ? nil : "fill wanted \(describe(w)), got \(describe(r))"
    case .clip(let r, let radius):
      guard want["type"] as? String == "clip", let w = rect(want["frame"]) else { return "wanted \(show(want["type"])), got a clip" }
      if !near(w, r) { return "clip wanted \(describe(w)), got \(describe(r))" }
      if abs((num(want["radius"]) ?? 0) - radius) > 0.5 { return "clip radius wanted \(show(want["radius"])), got \(radius)" }
      return nil
    case .image(_, let r, let alpha):
      guard want["type"] as? String == "image", let w = rect(want["frame"]) else { return "wanted \(show(want["type"])), got an image" }
      if !near(w, r) { return "image wanted \(describe(w)), got \(describe(r))" }
      if abs((num(want["alpha"]) ?? 1) - alpha) > 1e-9 { return "image alpha wanted \(show(want["alpha"])), got \(alpha)" }
      // PaneHost draws every picture scaled proportionally at the top left, PaneReader's reading.
      if want["scaling"] as? String != "scaleProportionally" || want["alignment"] as? String != "topLeft" {
        return "image drawn \(show(want["scaling"])) \(show(want["alignment"])), the app draws scaleProportionally topLeft"
      }
      return nil
    case .text(let t):
      guard want["type"] as? String == "text", let w = rect(want["frame"]) else { return "wanted \(show(want["type"])), got a text" }
      if want["text"] as? String != t.string { return "text wanted \(show(want["text"])), got \(show(t.string))" }
      if !near(w, t.frame) { return "\(show(t.string)) frame wanted \(describe(w)), got \(describe(t.frame))" }
      if want["font"] as? String != t.font || num(want["size"]) != t.size {
        return "\(show(t.string)) font wanted \(show(want["font"])) \(show(want["size"])), got \(t.font) \(t.size)"
      }
      if want["align"] as? String != t.align || want["lineBreak"] as? String != t.lineBreak {
        return "\(show(t.string)) wanted \(show(want["align"])) \(show(want["lineBreak"])), got \(t.align) \(t.lineBreak)"
      }
      if num(want["lineHeight"]) != t.lineHeight || (want["tight"] as? Bool ?? false) != t.tight {
        return "\(show(t.string)) line height or tightening differs"
      }
      let c = want["color"] as? [String: Any] ?? [:]
      let wc = [num(c["red"]) ?? 0, num(c["green"]) ?? 0, num(c["blue"]) ?? 0, num(c["alpha"]) ?? 1]
      let gc = [t.color.red, t.color.green, t.color.blue, t.color.alpha]
      if zip(wc, gc).contains(where: { abs($0 - $1) > 1e-6 }) { return "\(show(t.string)) colour wanted \(wc), got \(gc)" }
      return nil
    }
  }

  for case let c as [String: Any] in (doc["cases"] as? [Any]) ?? [] {
    let name = c["name"] as? String ?? "?"
    let half = c["half"] as? String ?? "dark"
    guard let T = PaneTokens(tokens[half]) else {
      fail(file, name, "the fixture has no tokens for \(half)"); continue
    }
    let paint: PanePaint
    if let path = c["path"] as? String {
      // What the thumbnail chain answered, the picture's own size standing in for its file, and a
      // late answer being the preview the stage draws once previewLanded answers.
      let pic = c["picture"] as? [String: Any]
      var picture: PictureState? = nil
      var image: PaneImage? = nil
      if let pic {
        if pic["rendering"] as? Bool == true {
          picture = .rendering
        } else if let w = num(pic["w"]), let h = num(pic["h"]) {
          picture = .ready(path)
          image = PaneImage(path: path, w: w, h: h)
        }
      }
      let isDir = c["isDir"] as? Bool ?? false
      let seen = peek(c["seen"])
      if pic != nil, PreviewDescriber.thumbSpec(path: path, isDir: isDir, peek: seen) == nil {
        fail(file, name, "the plugin's thumbnail chain does not cover this type")
      }
      let preview = PreviewDescriber.describe(path: path, isDir: isDir, peek: seen,
        limits: limits, now: now, home: home, picture: picture)
      if preview.pending != (picture == .rendering) { fail(file, name, "the preview's pending is \(preview.pending)") }
      paint = PanePainter.paint(preview, frame: frame, tokens: T, measure: measure, image: image)
    } else {
      paint = PanePainter.empty(emptyText, frame: frame, tokens: T, measure: measure)
    }
    let expect = c["expect"] as? [String: Any] ?? [:]
    let want = expect["elements"] as? [[String: Any]] ?? []
    var problems: [String] = []
    if let h = num(expect["height"]), abs(h - paint.height) > 0.5 { problems.append("height wanted \(h), got \(paint.height)") }
    if want.count != paint.items.count { problems.append("wanted \(want.count) elements, got \(paint.items.count)") }
    for (i, (w, g)) in zip(want, paint.items).enumerated() {
      if let why = differs(w, g) { problems.append("element \(i + 1), \(why)") }
    }
    if problems.isEmpty { passed += 1 } else { fail(file, name, problems.prefix(4).joined(separator: "; ")) }
  }
}

let runners: [String: (String, [String: Any]) -> Void] = [
  "filesearch.parse": runParse,
  "filesearch.narrows": runNarrows,
  "chooser.geometry": runGeometry,
  "chooser.pane": runPane,
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
