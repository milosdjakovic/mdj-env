// The olm command, docs/DESIGN-APP-PLUGINS.md The olm command. It ships inside Olm.app, at
// Contents/Resources/bin/olm, and src/setup-olmapp.sh links it into ~/.local/bin. It works with the
// plugins in ~/.olm/plugins and with a plugin folder anywhere, by the same code Olm.app runs them with.
//
//   olm plugin list                     every plugin in ~/.olm/plugins and what it is doing
//   olm plugin log ID [-f] [-n N]       its log, the oldest first, followed with -f
//   olm plugin test FOLDER [-q TEXT]    builds it apart, runs its test.json or opens it and shows rows
//   olm plugin new ID [DIR]             a plugin folder that builds and passes its test
//   olm plugin dev FOLDER               puts it in ~/.olm/plugins and again on every change, with its log
//   olm plugin install PATH             shows its install page in Olm Settings
//   olm plugin remove ID                asks in Olm Settings whether to uninstall it
//
// Allowing and uninstalling stay a click in Olm Settings. The command only asks the window for its
// page, through a request file under ~/.olm/run/requests named by a random id, so a web page opening
// an olm:// link cannot ask the same.

import Foundation
import OlmBridge
import OlmCore
import OlmKit
import OlmPlugins

let fm = FileManager.default
let home = fm.homeDirectoryForCurrentUser
let root = home.appendingPathComponent(".olm/plugins")
let stateDir = home.appendingPathComponent(".olm/state")

func say(_ s: String = "") { print(s); fflush(stdout) }
func fail(_ s: String, _ code: Int32 = 1) -> Never {
  FileHandle.standardError.write(Data("olm: \(s)\n".utf8))
  exit(code)
}

let usage = """
  usage: olm plugin <command>

    list                     every plugin in ~/.olm/plugins and what it is doing
    log ID [-f] [-n N]       its log, the oldest first, -f to follow it, -n the last N lines
    test FOLDER [-q TEXT]    builds it apart and runs its test.json, or opens it and shows its rows
    new ID [DIR]             a plugin folder in DIR, the current folder by default
    dev FOLDER               puts it in ~/.olm/plugins and again on every change, showing its log
    install PATH             a folder or .olmplugin, shown on its install page in Olm Settings
    remove ID                asks in Olm Settings whether to uninstall it
  """

// MARK: Where Olm.app keeps what the command needs

/// Olm.app's Resources, beside bin, where the kit and Olm's own plugins are. OLM_RESOURCES names
/// another for a check.
let resources: URL = {
  if let given = ProcessInfo.processInfo.environment["OLM_RESOURCES"] { return URL(fileURLWithPath: given) }
  let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
  let beside = exe.deletingLastPathComponent().deletingLastPathComponent()
  if fm.fileExists(atPath: beside.appendingPathComponent("OlmPluginKit.swift").path) { return beside }
  return URL(fileURLWithPath: "/Applications/Olm.app/Contents/Resources")
}()
let kit = resources.appendingPathComponent("OlmPluginKit.swift")
let bundled = resources.appendingPathComponent("Plugins")

func isOurs(_ id: String) -> Bool { fm.fileExists(atPath: bundled.appendingPathComponent(id).path) }

func json(_ url: URL) -> [String: Any] {
  guard let data = try? Data(contentsOf: url) else { return [:] }
  return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}

/// A plugin's id as Olm takes one, so it never names a path.
func validID(_ id: String) -> Bool { id.range(of: "^[a-z][a-z0-9]{0,31}$", options: .regularExpression) != nil }

// MARK: Asking Olm Settings

/// Writes what the window is asked to show and opens it. Olm reads the file once and removes it.
func ask(_ what: [String: String]) {
  let dir = home.appendingPathComponent(".olm/run/requests")
  try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
  let id = UUID().uuidString.lowercased()
  guard let data = try? JSONSerialization.data(withJSONObject: what) else { fail("the request could not be written") }
  do { try data.write(to: dir.appendingPathComponent(id + ".json"), options: .atomic) } catch {
    fail("the request could not be written, \(error.localizedDescription)")
  }
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
  // In front, since the window asks the person something.
  p.arguments = ["olm://settings?request=\(id)"]
  do { try p.run(); p.waitUntilExit() } catch { fail("Olm.app could not be opened, \(error.localizedDescription)") }
}

// MARK: list

/// What each plugin is doing, from what Olm keeps on disk.
func list() {
  let records = PluginRecords()
  let off = Set(json(stateDir.appendingPathComponent("plugins.json"))["values"]
    .flatMap { ($0 as? [String: Any])?["plugins.off"] as? [String] } ?? [])
  let stopped = json(stateDir.appendingPathComponent("plugin-history.json"))["stopped"] as? [String: [String: Any]] ?? [:]
  let log = PluginLog()
  let names = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
  guard !names.isEmpty else { say("No plugins in \(root.path)."); return }
  var lines: [(String, String, String)] = [("ID", "VERSION", "STATE")]
  for name in names {
    let folder = root.appendingPathComponent(name)
    let (verdict, manifest) = PluginGate.verdict(folder: folder, bundled: bundled, records: records)
    let state: String
    switch verdict {
    case .refused(let why): state = "refused, \(why)"
    case .waiting(let asks): state = "waiting for Allow in Olm Settings, \(asks.count) thing\(asks.count == 1 ? "" : "s") to allow"
    case .ours, .allowed:
      let built = log.entries(name).last { $0.from == .olm && ($0.text.hasPrefix("built") || $0.text.hasPrefix("did not build")) }
      if let built, built.text.hasPrefix("did not build") { state = "did not build, olm plugin log \(name)" }
      else if let why = stopped[name]?["why"] as? String { state = "switched off by Olm, \(why)" }
      else if off.contains(name) { state = "off" }
      else { state = verdict == .ours ? "on, Olm's own" : "on" }
    }
    lines.append((name, manifest?.version ?? "?", state))
  }
  let w0 = lines.map(\.0.count).max()!, w1 = lines.map(\.1.count).max()!
  for (a, b, c) in lines { say(a.padding(toLength: w0 + 2, withPad: " ", startingAt: 0) + b.padding(toLength: w1 + 2, withPad: " ", startingAt: 0) + c) }
}

// MARK: log

func printEntry(_ e: PluginLog.Entry) {
  let mark = e.from == .plugin ? "plugin" : "olm   "
  let text = e.text.replacingOccurrences(of: "\n", with: "\n" + String(repeating: " ", count: e.at.count + 9))
  say("\(e.at)  \(mark) \(text)")
}

/// Prints what arrived after the lines already shown, which were `shown`. A log halved past its size
/// starts again from its new first line.
func tail(_ id: String, _ shown: inout [PluginLog.Entry], _ log: PluginLog) {
  let now = log.entries(id)
  var from = 0
  if let last = shown.last {
    if let i = now.lastIndex(where: { $0.at == last.at && $0.text == last.text }) { from = i + 1 }
  }
  for e in now[from...] { printEntry(e) }
  shown = now
}

func showLog(_ args: [String]) {
  var follow = false, count: Int?, id: String?
  var i = 0
  while i < args.count {
    switch args[i] {
    case "-f", "--follow": follow = true
    case "-n":
      i += 1
      guard i < args.count, let n = Int(args[i]), n > 0 else { fail("-n takes a number of lines") }
      count = n
    default:
      guard id == nil else { fail(usage, 64) }
      id = args[i]
    }
    i += 1
  }
  guard let id, validID(id) else { fail("log takes a plugin's id, olm plugin list names them", 64) }
  let log = PluginLog()
  var shown = log.entries(id)
  if shown.isEmpty, !follow { say("\(id) has written nothing yet."); return }
  for e in shown.suffix(count ?? shown.count) { printEntry(e) }
  guard follow else { return }
  while true {
    Thread.sleep(forTimeInterval: 0.5)
    tail(id, &shown, log)
  }
}

// MARK: test

/// What a test case says, test.json beside olm-plugin.json, a list of them:
///
///   { "name": "…", "query": "text", "context": { … }, "rows": ["first title", …], "has": ["a title"],
///     "count": 3, "choose": "a title", "effects": ["copyText(…)"], "asks": ["copy …"] }
///
/// rows are the first titles in order, has titles anywhere, effects and asks what choosing did, each
/// written as the command prints it. The rows are ranked by Olm's own search, the app's Searcher, as
/// the list shows them, unless the level keeps the plugin's order.
struct Case {
  var name: String
  var query: String
  var context: JSON
  var rows: [String]?
  var has: [String]?
  var count: Int?
  var choose: String?
  var effects: [String]?
  var asks: [String]?
}

func cases(_ folder: URL) -> [Case]? {
  let file = folder.appendingPathComponent("test.json")
  guard fm.fileExists(atPath: file.path) else { return nil }
  guard let data = try? Data(contentsOf: file), let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
    fail("test.json is not a list of cases")
  }
  return list.enumerated().map { i, o in
    let context = (try? JSONSerialization.data(withJSONObject: o["context"] ?? NSNull(), options: [.fragmentsAllowed]))
      .flatMap { JSON.decode($0) } ?? .null
    return Case(name: o["name"] as? String ?? "case \(i + 1)", query: o["query"] as? String ?? "", context: context,
      rows: o["rows"] as? [String], has: o["has"] as? [String], count: o["count"] as? Int,
      choose: o["choose"] as? String, effects: o["effects"] as? [String], asks: o["asks"] as? [String])
  }
}

/// What the plugin asked of Olm during a case, answered yes and never done.
final class Asks: @unchecked Sendable {
  private let lock = NSLock()
  private var list: [String] = []
  func add(_ s: String) { lock.lock(); list.append(s); lock.unlock() }
  func take() -> [String] { lock.lock(); defer { list = []; lock.unlock() }; return list }
}

func test(_ args: [String]) async -> Int32 {
  var queries: [String] = [], path: String?
  var i = 0
  while i < args.count {
    if args[i] == "-q" || args[i] == "--query" {
      i += 1
      guard i < args.count else { fail("-q takes the text typed") }
      queries.append(args[i])
    } else {
      guard path == nil else { fail(usage, 64) }
      path = args[i]
    }
    i += 1
  }
  guard let path else { fail("test takes a plugin folder", 64) }
  let source = URL(fileURLWithPath: path).standardizedFileURL
  let work = home.appendingPathComponent(".olm/cache/plugin-test/\(UUID().uuidString)")
  defer { try? fm.removeItem(at: work) }
  // The folder copied as Olm copies a dropped one, its manifest and Sources alone, links and pipes refused.
  let staged: PluginInstall.Staged
  do { staged = try PluginInstall.stage(source, into: work) } catch { fail("\(source.lastPathComponent) \(error)") }
  let manifest = staged.manifest
  say("building \(manifest.id) \(manifest.version)")
  do { try PluginBuild.build(folder: staged.folder, manifest: manifest, kit: fm.fileExists(atPath: kit.path) ? kit : nil, optimize: false) }
  catch { say("\(error)"); return 1 }

  let asks = Asks()
  let runner = PluginRunner(appVersion: "test", log: { _, line, from in
    say("    \(from == .plugin ? "plugin" : "olm") \(line)")
  }, serve: { _, method, params in
    let what = params["url"].string ?? params["text"].string
    asks.add(method + (what.map { " " + $0 } ?? ""))
    return .success(.bool(true))
  })
  do { try await runner.load(folder: staged.folder) } catch { say("\(error)"); return 1 }

  // Typed text asked for on the command line is run in place of test.json.
  let list = (queries.isEmpty ? cases(source) : nil) ?? (queries.isEmpty ? [""] : queries).map {
    Case(name: $0.isEmpty ? "opened" : "typed \($0)", query: $0, context: .null)
  }
  let searcher = Searcher()
  var failures = 0
  func check(_ ok: Bool, _ what: String) {
    say("  \(ok ? "ok  " : "FAIL") \(what)")
    if !ok { failures += 1 }
  }
  for c in list {
    say("\n\(c.name)")
    _ = asks.take()
    guard let src = await runner.source(manifest.id, context: c.context) else { check(false, "it opened"); continue }
    let level = await src.open(query: c.query)
    let answer: RowsAnswer
    do { answer = try await src.rows(Query(text: c.query, generation: 1)) } catch {
      check(false, "it answered rows, \(error)")
      await src.close()
      continue
    }
    if let status = answer.status { say("  status \(status)") }
    let ranked = await searcher.rank(answer, query: c.query, level: level)
    let shown = ranked.rows
    for (n, r) in shown.enumerated() {
      say("  \(n + 1). \(r.title)\(r.subtitle.isEmpty ? "" : "  ·  \(r.subtitle)")")
    }
    if ranked.more > 0 { say("  and \(ranked.more) more") }
    let titles = shown.map(\.title)
    if let want = c.rows { check(Array(titles.prefix(want.count)) == want, "rows start \(want)") }
    if let want = c.has { for t in want { check(titles.contains(t), "has \(t)") } }
    if let want = c.count { check(titles.count == want, "\(want) rows") }
    if let pick = c.choose {
      guard let (n, row) = shown.enumerated().first(where: { $0.element.title == pick }) else {
        check(false, "a row called \(pick) to choose")
        await src.close()
        continue
      }
      let effects = await src.choose(Pick(key: row.key, query: c.query, row: n + 1)).map { "\($0)" }
      let asked = asks.take()
      say("  chose \(pick)")
      for e in effects { say("    did \(e)") }
      for a in asked { say("    asked \(a)") }
      if let want = c.effects { check(effects == want, "did \(want)") }
      if let want = c.asks { check(asked == want, "asked \(want)") }
    }
    await src.close()
  }
  await runner.stopAll()
  say(failures == 0 ? "\nevery case held" : "\n\(failures) FAILED")
  return failures == 0 ? 0 : 1
}

// MARK: new

func new(_ args: [String]) {
  guard let id = args.first, args.count <= 2 else { fail("new takes an id, one lowercase word, and a folder", 64) }
  guard validID(id) else { fail("an id is one lowercase word of letters and digits, starting with a letter", 64) }
  guard !isOurs(id) else { fail("\(id) is the id of one of Olm's own plugins") }
  let dir = URL(fileURLWithPath: args.count == 2 ? args[1] : fm.currentDirectoryPath).appendingPathComponent(id)
  guard !fm.fileExists(atPath: dir.path) else { fail("\(dir.path) is there already") }
  let title = id.prefix(1).uppercased() + id.dropFirst()
  let manifest = """
    {
      "id": "\(id)",
      "title": "\(title)",
      "description": "Say what it is for in one line.",
      "version": "0.1.0",
      "protocol": 1,
      "run": { "swift": "Sources" },
      "icon": "puzzlepiece.extension",
      "row": { "detail": "say what it does in a few words" },
      "needs": ["copy", "notify"],
      "permissions": {}
    }

    """
  let main = """
    // \(title), an Olm plugin. Olm opens its list from olm://\(id) and its launcher row, asks for its rows
    // as the person types, and does what choosing a row answers. The plugin runs in a sandbox with its
    // own data folder, plugin.data, and asks Olm for what it cannot do itself, here copying a line.
    // `olm plugin test .` builds it and runs test.json, and `olm plugin dev .` runs it in Olm.

    import Foundation

    let plugin = OlmPlugin()
    let words = ["Alpha", "Bravo", "Charlie"]

    plugin.open = { _ in OlmLevel(placeholder: "\(title)") }

    // Every row, every time. Olm ranks them for what is typed with its shared search, so a plugin
    // never filters by the text unless that text is a value rather than a search.
    plugin.rows = { _ in
      words.map { OlmRow(key: $0, title: $0, subtitle: "Copies \\($0)") }
    }

    plugin.choose = { key, _ in
      plugin.copy(key)
      plugin.notify("Copied \\(key)")
      return [.hide]
    }

    plugin.start()

    """
  let tests = """
    [
      { "name": "opened, every row", "query": "", "rows": ["Alpha", "Bravo", "Charlie"] },
      { "name": "typed, Olm's search finds it", "query": "bra", "rows": ["Bravo"], "count": 1 },
      { "name": "chosen, copied and said", "query": "", "choose": "Alpha", "effects": ["hide"],
        "asks": ["copy Alpha", "notify Copied Alpha"] }
    ]

    """
  do {
    try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    try manifest.write(to: dir.appendingPathComponent("olm-plugin.json"), atomically: true, encoding: .utf8)
    try main.write(to: dir.appendingPathComponent("Sources/main.swift"), atomically: true, encoding: .utf8)
    try tests.write(to: dir.appendingPathComponent("test.json"), atomically: true, encoding: .utf8)
  } catch { fail("\(dir.path) could not be written, \(error.localizedDescription)") }
  say("""
    \(dir.path)
      olm-plugin.json    its id, title, what it asks of Olm and its sandbox's permissions
      Sources/main.swift its rows and what choosing one does
      test.json          what olm plugin test checks

    olm plugin test \(dir.path)
    olm plugin dev \(dir.path)
    """)
}

// MARK: dev

/// One thing a plugin asks for in a person's words, as its install page says it.
func askWords(_ ask: String) -> String {
  switch ask {
  case "need:copy": return "copy to the clipboard"
  case "need:notify": return "show a message"
  case "need:open": return "open links"
  case "background": return "run in the background"
  default:
    if ask.hasPrefix("ability:") { return "use the ability \(ask.dropFirst("ability:".count))" }
    let w = BlockOffer.words(ask)
    return w.prefix(1).lowercased() + w.dropFirst()
  }
}

/// Copies the manifest and the sources into ~/.olm/plugins, the data folder kept, as
/// src/setup-olmapp.sh does for ours.
func put(_ folder: URL, _ id: String) throws {
  let dest = root.appendingPathComponent(id)
  try fm.createDirectory(at: dest, withIntermediateDirectories: true)
  let next = dest.appendingPathComponent(".Sources.new")
  try? fm.removeItem(at: next)
  try fm.copyItem(at: folder.appendingPathComponent("Sources"), to: next)
  try? fm.removeItem(at: dest.appendingPathComponent("Sources"))
  try fm.moveItem(at: next, to: dest.appendingPathComponent("Sources"))
  let manifest = dest.appendingPathComponent("olm-plugin.json")
  try? fm.removeItem(at: manifest)
  try fm.copyItem(at: folder.appendingPathComponent("olm-plugin.json"), to: manifest)
}

func dev(_ args: [String]) -> Never {
  guard args.count == 1 else { fail("dev takes a plugin folder", 64) }
  let folder = URL(fileURLWithPath: args[0]).standardizedFileURL
  let manifest: PluginManifest
  do { manifest = try PluginManifest.read(folder: folder) } catch { fail("\(folder.path) \(error)") }
  let id = manifest.id
  guard !isOurs(id) else { fail("\(id) is one of Olm's own, src/setup-olmapp.sh puts it in place") }
  signal(SIGINT, SIG_IGN)
  let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
  interrupt.setEventHandler {
    say("\n\(id) stays in \(root.appendingPathComponent(id).path) as it was last put there.")
    exit(0)
  }
  interrupt.resume()

  let records = PluginRecords(), log = PluginLog()
  var shown = log.entries(id)
  var seen = ""
  var asked: [String] = []
  say("\(manifest.title), from \(folder.path), into \(root.appendingPathComponent(id).path). Control C stops watching.")
  let timer = DispatchSource.makeTimerSource(queue: .main)
  timer.schedule(deadline: .now(), repeating: 0.5)
  timer.setEventHandler {
    tail(id, &shown, log)
    guard let now = try? PluginGate.fingerprint(folder), now != seen else { return }
    do { try put(folder, id) } catch {
      say("not put in place, \(error.localizedDescription)")
      return
    }
    seen = now
    say("put in place, Olm builds it and starts it again on its next use")
    let placed = root.appendingPathComponent(id)
    if case .waiting(let asks) = PluginGate.verdict(folder: placed, bundled: bundled, records: records).0, asks != asked {
      asked = asks
      say("waiting for Allow in Olm Settings, it asks to \(asks.map(askWords).joined(separator: ", "))")
      ask(["do": "review", "id": id])
    }
  }
  timer.resume()
  dispatchMain()
}

// MARK: install, remove

func install(_ args: [String]) {
  guard args.count == 1 else { fail("install takes a plugin folder or a .olmplugin file", 64) }
  let item = URL(fileURLWithPath: args[0]).standardizedFileURL
  guard fm.fileExists(atPath: item.path) else { fail("\(item.path) is not there") }
  ask(["do": "install", "path": item.path])
  say("Olm Settings shows what \(item.lastPathComponent) asks for. It is installed once you click Allow there.")
}

func remove(_ args: [String]) {
  guard args.count == 1, validID(args[0]) else { fail("remove takes a plugin's id, olm plugin list names them", 64) }
  let id = args[0]
  guard !isOurs(id) else { fail("\(id) is one of Olm's own, switch it off in Olm Settings instead") }
  guard fm.fileExists(atPath: root.appendingPathComponent(id).path) else { fail("\(id) is not in \(root.path)") }
  ask(["do": "uninstall", "id": id])
  say("Olm Settings asks whether to uninstall \(id), and whether its data goes too.")
}

// MARK: The command

let args = Array(CommandLine.arguments.dropFirst())
guard args.first == "plugin", args.count >= 2 else {
  if args.first == "help" || args.first == "-h" || args.first == "--help" || args.isEmpty { say(usage); exit(0) }
  fail(usage, 64)
}
let rest = Array(args.dropFirst(2))
switch args[1] {
case "list": list()
case "log": showLog(rest)
case "new": new(rest)
case "dev": dev(rest)
case "install": install(rest)
case "remove": remove(rest)
case "test":
  Task { exit(await test(rest)) }
  dispatchMain()
default: fail(usage, 64)
}
