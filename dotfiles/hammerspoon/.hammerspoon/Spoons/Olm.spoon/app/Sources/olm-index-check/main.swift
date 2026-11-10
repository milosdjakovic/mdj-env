// A check of the app's file index, step 1.3c of docs/PLAN-STANDALONE.md, run by test/olmindex.sh.
// It builds a small index of a folder it makes with the helper the app bundles, then asks it the
// way the app does, and checks the answers, that a cancelled ask ends its helper and throws, then
// the file search source over it and the stage's ranking, docs/DESIGN-APP.md. It shows nothing and
// touches nothing outside its own temporary folder.
//
//   olm-index-check HELPER

import AppKit
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
             ".config/secret.md", "Reports.app/Contents/x.md", "bills/invoice-march.pdf",
             "school/vežbe.md"] {
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
let types = ["md": ["md"], "js": ["js"], "app": ["app"]]

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
check(!names(await ask("")).contains("Reports.app"), "and leaves folders out")
check(names(await ask(".app")) == ["Reports.app"], "a bare type lists a bundle of that type, step 1.4h")
check(names(await ask(".md")) == ["report-old.md", "report.md", "vežbe.md"], "and a plain type still only files")
// The helper keeps a name exactly when the shared search would, so a word one typo away finds
// it on a fresh search, and a shorter word's answer holds nothing a longer one would miss.
check(names(await ask("invioce")) == ["invoice-march.pdf"], "a word one typo away finds the name")
check(names(await ask("inv")) == names(await ask("invioce")), "and a shorter word's answer holds it too")
let plain = names(await ask("vezbe")), accented = names(await ask("vežbe"))
check(plain == ["vežbe.md"] && accented == ["vežbe.md"], "an accent is folded either way")

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

// What macOS answers in the folder permission checks below.
final class AccessAnswers: @unchecked Sendable {
  private let lock = NSLock()
  private var _refused: Set<String> = []
  private var _reset: [String] = []
  private var _resets = true
  var refused: Set<String> {
    get { lock.withLock { _refused } }
    set { lock.withLock { _refused = newValue } }
  }
  // The folders whose answer was reset, and whether a reset works.
  var reset: [String] {
    get { lock.withLock { _reset } }
    set { lock.withLock { _reset = newValue } }
  }
  var resets: Bool {
    get { lock.withLock { _resets } }
    set { lock.withLock { _resets = newValue } }
  }
}

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
// A grown text asks again, since a longer word can match a name a shorter one did not.
let grown = await answer("repo")
check(await source.asks == asked + 1, "a grown text over the same files asks the index again")
check(grown?.rows.first?.title.lowercased().hasPrefix("report") == true, "and is ranked")
check(await answer("report.md")?.rows.first?.title == "report.md", "the name that matches best leads")
_ = await answer("app")
check(await source.asks == asked + 3, "an edited text asks again")
let short = await answer("ap")
check((short?.rows ?? []).contains { $0.title == "app.js" }, "a text below minChars ranks the recent list")
check(await answer("x/ foo")?.status != nil, "a scoped query says it is not answered yet")
check(await answer("zzzz")?.status == "No matches", "no match says so")
check(await source.choose(Pick(key: "/a/b.md", query: "b")) == [.hide, .openFile("/a/b.md")],
  "Return hides and opens the file")
check(await source.run("reveal", on: Pick(key: "/a/b.md", query: "b")) == [.hide, .revealFile("/a/b.md")],
  "reveal hides and shows it in Finder")
check(await source.run("peekPreview", on: Pick(key: "/a/b.md", query: "b")) == [.quickLook("/a/b.md")],
  "Quick Look shows the file and keeps the list up")
check(await source.run("peekPreview", on: Pick(key: FileSearchSource.askKey, query: "")) == [],
  "Quick Look has nothing for a status row")
check(source.manifest.actions.contains { $0.id == "peekPreview" && $0.title == "Quick Look" },
  "Quick Look is an action by the Lua list's verb name")
check(await source.run("copyFile", on: Pick(key: "/a/b.md", query: "b")) == [.hide, .copyFile("/a/b.md")],
  "Copy File hides and puts the file itself on the clipboard")
check(await source.run("copyFile", on: Pick(key: FileSearchSource.askKey, query: "")) == [],
  "Copy File has nothing for a status row")
check(source.manifest.actions.contains { $0.id == "copyFile" && $0.title == "Copy File" },
  "Copy File is an action by the Lua list's verb name")
check(await source.label("copyFile", on: Pick(key: "/", query: "")) == "Copy Folder",
  "over a folder Copy File reads Copy Folder")
check(await source.label("copyFile", on: Pick(key: "/etc/hosts", query: "")) == nil,
  "and over a file keeps its own word")
check(await source.label("copyPath", on: Pick(key: "/", query: "")) == nil,
  "and every other verb keeps its own word")
check(FileSearchSource.shadowSkip("report", settings: settings) == nil
  && FileSearchSource.shadowSkip("re", settings: settings) != nil
  && FileSearchSource.shadowSkip("~/x/ foo", settings: settings) != nil
  && FileSearchSource.shadowSkip("~/x/", settings: settings) == nil,
  "the shadow compares a search and a browse and skips the recent list and a search beneath a folder")

// Folder search, step 1.4e. The resolution and the up query over a stood in filesystem first.
let fakeHome = "/Users/p"
let fakeDirs: Set<String> = ["/Users/p", "/Users/p/Downloads", "/Users/p/Downloads/inv", "/Applications", "/Users/p/dev",
  "/tmp"]
let fakeDir = { (p: String) in fakeDirs.contains(p) }
let fakeRoots = ["dl": "Downloads", "apps": "/Applications", "home": "", "t": "~/Downloads"]
func resolved(_ t: String) -> String? { FolderScope.resolve(t, roots: fakeRoots, home: fakeHome, isDir: fakeDir) }
check(resolved("dl/") == "/Users/p/Downloads" && resolved("DL/inv/") == "/Users/p/Downloads/inv",
  "an alias resolves, in any case, with a path beneath it")
check(resolved("apps/") == "/Applications" && resolved("t/") == "/Users/p/Downloads" && resolved("home/") == "/Users/p",
  "an alias may be absolute, written with a tilde, or home itself")
check(resolved("~/dev/") == "/Users/p/dev" && resolved("/tmp/") == "/tmp" && resolved("dev/") == "/Users/p/dev",
  "a tilde, an absolute path and a path under home resolve literally")
check(resolved("nope/") == nil && resolved("/nope/") == nil, "a folder that is not there resolves to nothing")
check(resolved("/") == "/", "the root is the root")
func upped(_ t: String?) -> String? { FolderScope.upQuery(t, roots: fakeRoots, home: fakeHome, isDir: fakeDir) }
check(upped("dl/inv/") == "~/Downloads/" && upped("apps/") == "/" && upped("/") == nil && upped(nil) == nil
  && upped("nope/") == nil, "the up query is the parent, home as a tilde, nothing above the root")

// The walker's arguments, walk.lua's search.
let walk = FolderWalk(fd: "/x/fd", prune: ["node_modules"], insideFrom: 3, timeoutSeconds: 5)
let walkArgs = walk.searchArguments(FileQueryGrammar.parse(". .md dl/ report notes", types: types), dir: "/d", cap: 9)
check(walkArgs == ["--hidden", "--exclude", "node_modules", "--extension", "md", "--follow", "--max-results", "9",
  "--ignore-case", "--fixed-strings", "report", "/d"], "a search hands fd the first word, its types and the prune list")
check(walk.searchArguments(FileQueryGrammar.parse("! dl/ x", types: types), dir: "/d", cap: 9).contains("--no-ignore"),
  "the bang walks what the prune list and gitignore drop")
check(walk.searchArguments(FileQueryGrammar.parse("dl/ Re", types: types), dir: "/d", cap: 9).suffix(3)
  == ["--case-sensitive", "(?:^|[^\\p{L}\\p{N}])(?i:re)|\\p{Ll}R(?i:e)", "/d"],
  "a word shorter than the inside length is asked at a word start")
check(FolderWalk.startPattern("a.") == "(?:^|[^\\p{L}\\p{N}])(?i:a\\.)|\\p{Ll}A(?i:\\.)", "punctuation is escaped")

// A browse and its rows, over the check's own folder.
var folderSettings = settings
folderSettings.roots = ["t": tree.path]
folderSettings.walker = nil
try? fm.createDirectory(at: tree.appendingPathComponent("empty"), withIntermediateDirectories: true)
let folderSource = FileSearchSource(context: context, index: files, settings: folderSettings)
await folderSource.open(settings: folderSettings)
func folderAnswer(_ raw: String) async -> (rows: [Row], status: String?)? {
  generation += 1
  guard let a = try? await folderSource.rows(Query(text: raw, generation: generation)) else { return nil }
  let ranked = await searcher.rank(a, query: raw, level: level)
  return (ranked.rows, a.status ?? (ranked.rows.isEmpty ? a.emptyStatus : nil))
}
let browsed = await folderAnswer("t/")
check(browsed?.rows.first?.title == ".." && browsed?.rows.first?.pinned == true
  && browsed?.rows.first?.key == tree.deletingLastPathComponent().path
  && browsed?.rows.first?.subtitle.hasPrefix("up to ") == true, "a browse leads with the .. row for the parent")
check(Set((browsed?.rows ?? []).dropFirst().map(\.title)) == ["notes", "src", ".config", "Reports.app", "bills",
  "school", "empty"], "and lists one level, dotfiles and folders among it")
let empty = await folderAnswer("t/empty/")
check(empty?.rows.map(\.title) == ["..", "Empty folder"] && empty?.rows.last?.key == FileSearchSource.statusKey,
  "an empty folder says so under the .. row")
check(await folderAnswer("nope-\(getpid())/")?.status == "No such folder", "a folder that is not there says so")
check(await folderAnswer("t/ report")?.status == "Nothing can answer that", "a search beneath a folder without fd says so")
check(await folderSource.choose(Pick(key: FileSearchSource.statusKey, query: "t/empty/")) == [],
  "the status row does nothing")

// The `..` row, Into Folder and Up a Level, and the two gates.
let parentQuery = tree.deletingLastPathComponent().path + "/"
check(await folderSource.choose(Pick(key: tree.deletingLastPathComponent().path, query: "t/")) == [.setQuery(parentQuery)],
  "Return on the .. row goes up a level in place")
let notes = tree.appendingPathComponent("notes").path
check(await folderSource.run("browseInto", on: Pick(key: notes, query: "t/")) == [.setQuery(notes + "/")],
  "Into Folder writes the folder as a scope")
check(await folderSource.run("browseInto", on: Pick(key: notes + "/report.md", query: "t/")) == [],
  "and does nothing over a file")
check(await folderSource.run("browseUp", on: Pick(key: notes, query: "t/notes/")) == [.setQuery(tree.path + "/")],
  "Up a Level writes the folder above")
check(await folderSource.run("browseUp", on: Pick(key: notes, query: "report")) == [], "and does nothing unscoped")
let folderYes = await folderSource.applies("isFolder", on: Pick(key: notes, query: ""))
let folderNo = await folderSource.applies("isFolder", on: Pick(key: notes + "/report.md", query: ""))
check(folderYes && !folderNo, "isFolder answers from the row")
let browsingYes = await folderSource.applies("isBrowsing", on: Pick(key: notes, query: "t/ x"))
let browsingNo = await folderSource.applies("isBrowsing", on: Pick(key: notes, query: "x"))
check(browsingYes && !browsingNo, "isBrowsing answers from the query")
check(await folderSource.run("copyFile", on: Pick(key: tree.deletingLastPathComponent().path, query: "t/")) == [],
  "Copy File does nothing on the .. row")
check(source.manifest.actions.contains { $0.id == "browseInto" && $0.title == "Into Folder" }
  && source.manifest.actions.contains { $0.id == "browseUp" && $0.title == "Up a Level" },
  "Into Folder and Up a Level are actions by the Lua list's verb names")

// The folder permissions, step 1.4j, with macOS's answer and the reset stood in for, so no prompt
// is raised and no answer is reset.
let accessRoot = root.appendingPathComponent("access")
let deny = AccessAnswers()
let access = FolderAccess(home: accessRoot, store: accessRoot,
  readable: { !deny.refused.contains($0.name) }, reset: { deny.reset.append($0.name); return deny.resets })
deny.refused = ["Documents"]
let gated = FileSearchSource(context: context, index: files, settings: settings, access: access)
_ = await gated.open(query: "")
let before = try? await gated.rows(Query(text: "rep", generation: 1))
check(before?.rows.map(\.key) == [FileSearchSource.askKey] && before?.rows.first?.pinned == true,
  "before the folders are answered the list is the one row that asks, whatever is typed")
check(before?.rows.first?.icon == .symbol("checkmark.circle"), "and it wears what choosing it does")
check(await gated.preview(Pick(key: FileSearchSource.askKey, query: ""))?.name == "Folder Access",
  "and its preview says why")
check(await gated.run("reveal", on: Pick(key: FileSearchSource.askKey, query: "")) == [],
  "and it reveals nothing")
check(await gated.choose(Pick(key: FileSearchSource.askKey, query: "")) == [.reopen],
  "choosing it asks and opens the list again")
check(access.load() == FolderAccess.State(asked: true, refused: ["Documents"]), "the answers are kept")
let after = try? await gated.rows(Query(text: "rep", generation: 2))
check(after?.rows.first?.key == FileSearchSource.refusedKey && (after?.rows.count ?? 0) > 1
  && after?.rows.first?.title == "Ask Again for Documents",
  "the list searches, led by the row that asks again for what was refused")
_ = await gated.open(query: "")
check((try? await gated.rows(Query(text: "rep", generation: 3)))?.rows.first?.key == FileSearchSource.refusedKey,
  "and it stays on every open while the folder is refused")
let inside = accessRoot.appendingPathComponent("Documents/a.pdf").path
check(await gated.preview(Pick(key: inside, query: ""))?.body?.facts == "Documents not allowed",
  "a file in a refused folder says so in the pane")
deny.resets = false
check(await gated.choose(Pick(key: FileSearchSource.refusedKey, query: "")) == [.hide, .openURL(FolderAccess.settingsURL)],
  "a reset that fails leaves System Settings as the way")
deny.resets = true
deny.refused = []
deny.reset = []
check(await gated.choose(Pick(key: FileSearchSource.refusedKey, query: "")) == [.reopen] && deny.reset == ["Documents"],
  "asking again resets that folder's answer alone and asks it")
let allowed = try? await gated.rows(Query(text: "rep", generation: 4))
check(access.load().refused.isEmpty && allowed?.rows.contains { $0.key.hasPrefix("olm:") } == false,
  "and once allowed the row is gone")
deny.refused = ["Desktop"]
_ = await gated.open(query: "")
check(access.load().refused.isEmpty, "an allowed folder is never tried again at an open")
check(FolderAccess.spoken(["Desktop", "Documents", "Downloads"]) == "Desktop, Documents and Downloads"
  && FolderAccess.spoken(["Documents"]) == "Documents", "the folders are said as a person reads them")
let ungated = try? await source.rows(Query(text: "rep", generation: 5))
check(ungated?.rows.contains { $0.key.hasPrefix("olm:") } == false, "a source that does not ask never gates")

// The preview's read, step 1.4a, which is the helper's peek done in process, so the two must find
// the same thing. The helper's answer is parsed as plugins/filesearch/sources/index.lua's parsePeek
// reads it.
func helperPeek(_ path: String) -> Peek? {
  let out = root.appendingPathComponent("peek-\(UUID().uuidString)").path
  let p = Process()
  p.executableURL = URL(fileURLWithPath: helper)
  p.arguments = ["peek", path, out, "4096", String(Peek.scanCap), "100"]
  try? p.run()
  p.waitUntilExit()
  guard let data = fm.contents(atPath: out), let nl = data.firstIndex(of: 10) else { return nil }
  let first = String(decoding: data[..<nl], as: UTF8.self)
  let rest = data[(nl + 1)...]
  if first == "missing" { return Peek() }
  let f = first.split(separator: "\t")
  guard f.count == 4, let size = Int(f[1]), let m = Int(f[2]), let c = Int(f[3]) else { return nil }
  let attrs = Peek.Attrs(isDir: f[0] == "dir", size: size, modification: m, creation: c)
  guard attrs.isDir else { return Peek(attrs: attrs, blob: Data(rest)) }
  let lines = String(decoding: rest, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
  guard let head = lines.first?.split(separator: "\t"), head.count == 2, let scanned = Int(head[0]) else {
    return Peek(attrs: attrs)
  }
  let entries = lines.dropFirst().compactMap { line -> Peek.Entry? in
    let e = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
    guard e.count == 3, let at = Int(e[0]) else { return nil }
    return Peek.Entry(name: e[1] == "d" ? e[2] + "/" : String(e[2]), at: at)
  }
  return Peek(attrs: attrs, folder: Peek.Folder(scanned: scanned, truncated: head[1] == "1", entries: entries))
}
fm.createFile(atPath: tree.appendingPathComponent("notes/long.txt").path,
  contents: Data(String(repeating: "a line of text\n", count: 600).utf8))
for (path, what) in [("notes/long.txt", "a file's head"), ("notes", "a folder, newest first"),
                     ("gone.md", "a path that is gone")] {
  let full = tree.appendingPathComponent(path).path
  check(Peek.read(full, readCap: 4096, entries: 100) == helperPeek(full), "the preview reads \(what) as the helper does")
}
// The source knows a row is a folder from the rows it last answered, as the Lua row carries isDir.
_ = await answer("rep")
let previewed = await source.preview(Pick(key: kinds["report.md"]?.path ?? "", query: "rep"))
check(previewed?.name == "report.md" && previewed?.facts.first == Preview.Fact(label: "KIND", value: "MD")
  && previewed?.body == Preview.Body(label: "HEAD", lines: ["x"], wrap: true, budget: 400, slack: 20, total: 1,
    hasLines: false), "the source describes a file it listed")
let bundle = await source.preview(Pick(key: kinds["Reports.app"]?.path ?? "", query: "rep"))
check(bundle?.facts.first?.value == "Application" && bundle?.body?.label == "FOLDER"
  && bundle?.body?.lines == ["Contents/"], "and a bundle it listed as a folder")
check(source.manifest.previewPane?.emptyText == FileSearchSource.paneEmptyText, "its manifest has a preview pane")

// Pictures, step 1.4b. The chain, the name a render is kept under and the Quick Look invocation are
// thumbs.lua's, then a real raster drawn from itself, a real svg rendered by Quick Look into a cache
// folder of the check's own, and the core reading both at the size the Lua layout is handed.
// The name the Lua side gave one file on 2026-11-08, hs.hash.MD5 of path, size and time.
check(ThumbChain.cacheName(ThumbSpec(path: "/Users/milosdjakovic/Downloads/00 Paketi po timovima.pdf", ext: "pdf",
  size: 66547, modification: 1792910115)) == "c5d9e634b4dec9cfc63652623be03b4d.png", "and named as the Lua side names it")
check(ThumbChain.cacheName(ThumbSpec(path: "/x.pdf", ext: "pdf", size: nil, modification: nil))
  == ThumbChain.cacheName(ThumbSpec(path: "/x.pdf", ext: "pdf", size: nil, modification: nil)), "a gone file still has a name")
check(ThumbChain.quickLookArguments(edge: 600, scratch: "/s.d", path: "/f.pdf") == ["-t", "-s", "600", "-o", "/s.d", "/f.pdf"]
  && ThumbChain.qlmanage == "/usr/bin/qlmanage", "Quick Look is asked as the Lua side asks it")
let mb = 1024 * 1024
check(ThumbChain.generator(for: ThumbSpec(path: "/p.png", ext: "png", size: mb, modification: 0), nativeMaxBytes: mb) == .native
  && ThumbChain.generator(for: ThumbSpec(path: "/p.png", ext: "png", size: mb + 1, modification: 0), nativeMaxBytes: mb) == .quickLook
  && ThumbChain.generator(for: ThumbSpec(path: "/p.svg", ext: "svg", size: 10, modification: 0), nativeMaxBytes: mb) == .quickLook
  && ThumbChain.generator(for: ThumbSpec(path: "/p.txt", ext: "txt", size: 10, modification: 0), nativeMaxBytes: mb) == nil,
  "a raster over nativeMaxBytes goes to Quick Look, as nativeGen's accepts steps aside")
check(PreviewDescriber.pictureExtensions == ThumbChain.extensions && ThumbChain.extensions.count == 36,
  "the describer claims every type the chain covers")

let pictures = root.appendingPathComponent("pictures")
try? fm.createDirectory(at: pictures, withIntermediateDirectories: true)
let png = pictures.appendingPathComponent("wide.png")
if let ctx = CGContext(data: nil, width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: 0,
  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
  ctx.setFillColor(red: 0, green: 0.5, blue: 1, alpha: 1)
  ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
  if let cg = ctx.makeImage() { try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: png) }
}
let svg = pictures.appendingPathComponent("box.svg")
try? Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100"><rect width="200" height="100" fill="red"/></svg>"#.utf8).write(to: svg)
fm.createFile(atPath: pictures.appendingPathComponent("broken.png").path, contents: Data("not a png".utf8))

let pictureContext = PluginContext(run: root, cache: root.appendingPathComponent("cache"), resources: root)
var pictureSettings = settings
pictureSettings.preview.cacheDir = nil
let pictureSource = FileSearchSource(context: pictureContext, index: files, settings: pictureSettings)
let wide = await pictureSource.preview(Pick(key: png.path, query: ""))
check(wide?.body?.picture == Preview.Picture(path: png.path, upscale: false) && wide?.pending == false,
  "a small raster is its own picture at once")
let unreadable = await pictureSource.preview(Pick(key: pictures.appendingPathComponent("broken.png").path, query: ""))
check(unreadable?.body == Preview.Body(label: "PREVIEW", facts: "no preview") && unreadable?.pending == false,
  "a raster the system cannot read says no preview")
let first = await pictureSource.preview(Pick(key: svg.path, query: ""))
check(first?.body == Preview.Body(label: "PREVIEW", facts: "rendering") && first?.pending == true,
  "an svg says rendering while Quick Look draws it")
let landed = await pictureSource.previewLanded(Pick(key: svg.path, query: ""))
let rendered = landed?.body?.picture?.path ?? ""
check(rendered.hasPrefix(FileSearchSource.previewsDir(pictureContext).path) && rendered.hasSuffix(".png")
  && fm.fileExists(atPath: rendered) && landed?.pending == false, "and lands as its render in the app's own folder")
let again = await pictureSource.preview(Pick(key: svg.path, query: ""))
check(again?.body?.picture?.path == rendered && again?.pending == false, "a render made once is drawn at once")
check(!((try? fm.contentsOfDirectory(atPath: FileSearchSource.previewsDir(pictureContext).path)) ?? []).contains { $0.hasSuffix(".d") },
  "no scratch folder is left behind")
// A render the highlight moved on from is ended and is not remembered as a failure.
let pdfLike = pictures.appendingPathComponent("other.svg")
try? Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="40"><rect width="10" height="40"/></svg>"#.utf8).write(to: pdfLike)
_ = await pictureSource.preview(Pick(key: pdfLike.path, query: ""))
let waiting = Task { await pictureSource.previewLanded(Pick(key: pdfLike.path, query: "")) }
waiting.cancel()
check(await waiting.value == nil, "a wait the highlight moved on from answers nothing")

func pixels(_ img: PaneImage?) -> Int {
  var r = NSRect(origin: .zero, size: img?.image?.size ?? .zero)
  return img?.image?.cgImage(forProposedRect: &r, context: nil, hints: nil)?.width ?? 0
}
let decoded = PanePicture.load(Preview.Picture(path: png.path, upscale: false), width: 462, scale: 2)
check(decoded?.w == 320 && decoded?.h == 180 && decoded?.image?.size == NSSize(width: 320, height: 180)
  && pixels(decoded) == 320, "the core reads a raster at its own size")
let shrunk = PanePicture.load(Preview.Picture(path: rendered, upscale: false), width: 300, scale: 1)
check(shrunk?.w == 600 && pixels(shrunk) == 300,
  "and decodes a render only at the pixels it is drawn at")
check(PanePicture.load(Preview.Picture(path: pictures.appendingPathComponent("broken.png").path), width: 100, scale: 2) == nil,
  "and answers nothing for a file it cannot read")

print(failures == 0 ? "olm-index-check, every check passed" : "olm-index-check, \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
