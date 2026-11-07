// A check of the app's file index, step 1.3c of docs/PLAN-STANDALONE.md, run by test/olmindex.sh.
// It builds a small index of a folder it makes with the helper the app bundles, then asks it the
// way the app will, and checks the answers, that an ask never answers on the queue it was made
// from before that queue is free, and that a newer ask supersedes an older one. It shows nothing
// and touches nothing outside its own temporary folder.
//
//   olm-index-check HELPER

import Foundation
import OlmSearch

var failures = 0
func check(_ ok: Bool, _ what: String) {
  print((ok ? "ok   " : "FAIL ") + what)
  if !ok { failures += 1 }
}

guard CommandLine.arguments.count == 2 else { print("usage: olm-index-check HELPER"); exit(64) }
let helper = CommandLine.arguments[1]
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("olm-index-check-\(getpid())")
defer { try? fm.removeItem(at: root) }
let tree = root.appendingPathComponent("tree")
for path in ["notes/report.md", "notes/report-old.md", "src/app.js", "src/node_modules/dep.js",
             ".config/secret.md", "Reports.app/Contents/x.md"] {
  let url = tree.appendingPathComponent(path)
  try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  fm.createFile(atPath: url.path, contents: Data("x".utf8))
}
let index = root.appendingPathComponent("file-index.txt").path

let build = Process()
build.executableURL = URL(fileURLWithPath: helper)
build.arguments = ["build", index, "node_modules", tree.path]
build.standardOutput = FileHandle.nullDevice
try? build.run()
build.waitUntilExit()
check(build.terminationStatus == 0, "the helper builds an index of the folder")

let files = FileIndex(helper: helper, index: index)
let types = ["md": ["md"], "js": ["js"]]

// Runs one ask to its answer, keeping the main queue turning as the app's run loop would.
func answer(_ raw: String, cap: Int = 50) -> [IndexRow]? {
  var got: [IndexRow]?? = .none
  var answeredInline = true
  files.ask(FileQueryGrammar.parse(raw, types: types), cap: cap) { got = .some($0) }
  answeredInline = got != nil
  let deadline = Date().addingTimeInterval(5)
  while got == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
  check(!answeredInline, "\"\(raw)\" answers later, never while it is being asked")
  return got ?? nil
}

let names = { (rows: [IndexRow]?) in (rows ?? []).map(\.name).sorted() }
check(names(answer("report")) == ["Reports.app", "report-old.md", "report.md"],
  "a word finds every name holding it, in any case")
check(names(answer(".md report")) == ["report-old.md", "report.md"], "a type keeps its own extension")
check(names(answer("dep")).isEmpty, "a pruned folder is not in the index")
check(names(answer("secret")).isEmpty, "a hidden path is left out unless asked")
check(names(answer(". secret")) == ["secret.md"], "and found when asked")
check(names(answer("Reports")) == ["Reports.app"], "a bundle is listed and not entered")
let kinds = Dictionary(uniqueKeysWithValues: (answer("report") ?? []).map { ($0.name, $0) })
check(kinds["Reports.app"]?.isDir == true && kinds["report.md"]?.isDir == false
  && kinds.values.allSatisfy { $0.mtime > 0 }, "a row carries its date and kind")
check(names(answer("")).contains("app.js"), "an empty query is the recent list")

// A newer ask supersedes an older one, whose answer never arrives.
var first = 0, second = 0
files.ask(FileQueryGrammar.parse("report", types: types), cap: 50) { _ in first += 1 }
files.ask(FileQueryGrammar.parse("app", types: types), cap: 50) { _ in second += 1 }
let deadline = Date().addingTimeInterval(5)
while second == 0, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
RunLoop.main.run(until: Date().addingTimeInterval(0.2))
check(first == 0 && second == 1, "a newer ask supersedes the one before it")

check(files.arguments(for: FileQueryGrammar.parse(". ", types: types), cap: 5) == nil,
  "a lone dot with nothing typed asks nothing, as the Lua side")
// The engine over the same index, step 1.3d.
var settings = FileSearchSettings()
settings.types = types
settings.minChars = 3
let engine = FileSearchEngine(index: files, settings: settings)
func engineAnswer(_ raw: String) -> FileSearchAnswer? {
  var got: FileSearchAnswer?
  engine.query(raw) { got = $0 }
  let deadline = Date().addingTimeInterval(5)
  while got == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
  return got
}
let first3 = engineAnswer("rep")
check((first3?.rows ?? []).map(\.name).sorted() == ["Reports.app", "report-old.md", "report.md"],
  "the engine answers a search from the index")
let asked = engine.asks
let grown = engineAnswer("repo")
check(engine.asks == asked, "a grown text over the same files asks the index nothing")
check(grown?.rows.first?.name.lowercased().hasPrefix("report") == true, "and is ranked again")
check(engineAnswer("report.md")?.rows.first?.name == "report.md", "the name that matches best leads")
_ = engineAnswer("app")
check(engine.asks == asked + 1, "an edited text asks again")
let short = engineAnswer("ap")
check((short?.rows ?? []).contains { $0.name == "app.js" }, "a text below minChars ranks the recent list")
check(engineAnswer("x/ foo")?.status != nil, "a scoped query says it is not answered yet")
check(engineAnswer("zzzz")?.status == "No matches", "no match says so")

print(failures == 0 ? "olm-index-check, every check passed" : "olm-index-check, \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
