// A check of the app's file index, step 1.3c of docs/PLAN-STANDALONE.md, run by test/olmindex.sh.
// It builds a small index of a folder it makes with the helper the app bundles, then asks it the
// way the app does, and checks the answers, that a cancelled ask ends its helper and throws, then
// the file search source over it and the stage's ranking, docs/DESIGN-APP.md. It shows nothing and
// touches nothing outside its own temporary folder.
//
//   olm-index-check HELPER

import Foundation
import FileSearchPlugin
import OlmCore
import OlmKit

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

func ask(_ raw: String, cap: Int = 50) async -> [IndexRow]? {
  try? await files.ask(FileQueryGrammar.parse(raw, types: types), cap: cap)
}

let names = { (rows: [IndexRow]?) in (rows ?? []).map(\.name).sorted() }
check(names(await ask("report")) == ["Reports.app", "report-old.md", "report.md"],
  "a word finds every name holding it, in any case")
check(names(await ask(".md report")) == ["report-old.md", "report.md"], "a type keeps its own extension")
check(names(await ask("dep")).isEmpty, "a pruned folder is not in the index")
check(names(await ask("secret")).isEmpty, "a hidden path is left out unless asked")
check(names(await ask(". secret")) == ["secret.md"], "and found when asked")
check(names(await ask("Reports")) == ["Reports.app"], "a bundle is listed and not entered")
let kinds = Dictionary(uniqueKeysWithValues: (await ask("report") ?? []).map { ($0.name, $0) })
check(kinds["Reports.app"]?.isDir == true && kinds["report.md"]?.isDir == false
  && kinds.values.allSatisfy { $0.mtime > 0 }, "a row carries its date and kind")
check(names(await ask("")).contains("app.js"), "an empty query is the recent list")

// A cancelled ask throws rather than answering, which is how a newer query supersedes it.
let cancelled = Task { try await files.ask(FileQueryGrammar.parse("report", types: types), cap: 50) }
cancelled.cancel()
let outcome = await cancelled.result
check({ if case .failure(let e) = outcome { return e is CancellationError } else { return false } }(),
  "a cancelled ask throws CancellationError")
let broken = FileIndex(helper: "/nonexistent/fileindex", index: index)
let failed = await Task { try await broken.ask(FileQueryGrammar.parse("report", types: types), cap: 50) }.result
check({ if case .failure(let e) = failed { return (e as? IndexError) == .failed } else { return false } }(),
  "a helper that cannot run says it failed")

check(files.arguments(for: FileQueryGrammar.parse(". ", types: types), cap: 5) == nil,
  "a lone dot with nothing typed asks nothing, as the Lua side")

// The source over the same index, and the stage's ranking, step 1.3g.
var settings = FileSearchSettings()
settings.types = types
settings.minChars = 3
let context = PluginContext(run: root, cache: root, resources: root)
let source = FileSearchSource(context: context, index: files, settings: settings)
await source.open(settings: settings)
let searcher = Searcher()
let level = Level(ranking: .app, rowLimit: settings.rowLimit)
var generation = 0
func answer(_ raw: String) async -> (rows: [Row], status: String?)? {
  generation += 1
  guard let a = try? await source.rows(Query(text: raw, generation: generation)) else { return nil }
  let ranked = await searcher.rank(a, query: raw, level: level)
  return (ranked.rows, a.status ?? (ranked.rows.isEmpty ? a.emptyStatus : nil))
}
let first3 = await answer("rep")
check((first3?.rows ?? []).map(\.title).sorted() == ["Reports.app", "report-old.md", "report.md"],
  "the source answers a search from the index")
check(first3?.rows.first?.icon == .file(first3?.rows.first?.key ?? ""), "a row's icon is its file's")
let asked = await source.asks
let grown = await answer("repo")
check(await source.asks == asked, "a grown text over the same files asks the index nothing")
check(grown?.rows.first?.title.lowercased().hasPrefix("report") == true, "and is ranked again")
check(await answer("report.md")?.rows.first?.title == "report.md", "the name that matches best leads")
_ = await answer("app")
check(await source.asks == asked + 1, "an edited text asks again")
let short = await answer("ap")
check((short?.rows ?? []).contains { $0.title == "app.js" }, "a text below minChars ranks the recent list")
check(await answer("x/ foo")?.status != nil, "a scoped query says it is not answered yet")
check(await answer("zzzz")?.status == "No matches", "no match says so")
check(await source.choose(Pick(key: "/a/b.md", query: "b")) == [.hide, .openFile("/a/b.md")],
  "Return hides and opens the file")
check(await source.run("reveal", on: Pick(key: "/a/b.md", query: "b")) == [.hide, .revealFile("/a/b.md")],
  "reveal hides and shows it in Finder")
check(FileSearchSource.shadowSkip("report", settings: settings) == nil
  && FileSearchSource.shadowSkip("re", settings: settings) != nil
  && FileSearchSource.shadowSkip("~/x/ foo", settings: settings) != nil,
  "the shadow compares a search and skips the recent list and a folder")

print(failures == 0 ? "olm-index-check, every check passed" : "olm-index-check, \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
