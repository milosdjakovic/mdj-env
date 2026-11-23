// The app's end of the bridge checked with no Hammerspoon, step 2.3 of docs/PLAN-STANDALONE.md. It
// starts the app's listener on a socket of its own, connects as Hammerspoon would and answers it as
// host/bridge/serve.lua does, from canned answers in the shapes test/fixtures/bridge/launcher.json
// records, and checks what the app makes of them: the folder and socket modes, hello before
// anything, the launcher's open and its memory, rows patched by their changes, the bonus the memory
// gives, a memory notification moving it, a request it does not serve refused, the shadow comparing
// a settled answer and logging it, and a lost connection closing the level. Step 3.2 adds the
// launcher a person opens: metrics, a level for each show opened fromURL, its rows' icons, choose and
// what its effects become, hidden said before the level's close, and an older rows answer dropped.
// Step 3.3 adds a hosted tool's list: a claim's fit, a push made into a level of its own, its rows and
// icons, the effects notification reaching it and no other, its back and its close. Step 3.3b adds its
// actions pane, the actions the push names, which apply, a verb's choices and a run with a choice.
// Step 3.3c adds the pop and setQuery effects a hosted list's own code answers. A socket file removed
// while the app listens is made again, one another program binds is left to it, and the launcher a
// person opens with no session says so. Step 3.3d adds a pane drawn in Lua: the push saying so,
// positioned and highlight sent, and paneDrawn reaching its level and read into what the pane draws.
// Step 3.8 adds a tool's own key, its level opened by name and a tool not hosted opening nothing.
//
// test/olmbridge.sh builds and runs it. Exit 0 when every check passed.

import AppKit
import Foundation
import OlmBridge
import OlmCore
import OlmKit
import OlmSettings

var failures = 0, checks = 0
func ok(_ cond: Bool, _ what: String) {
  checks += 1
  if !cond { failures += 1; print("  FAIL  \(what)") }
}
func give(_ why: String) -> Never {
  print("olm-bridge-check: \(why)")
  exit(1)
}

let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("olm-bridge-check-\(getpid())")
let run = dir.appendingPathComponent("run")
let log = dir.appendingPathComponent("log")
let path = run.appendingPathComponent("bridge.sock").path
defer { try? FileManager.default.removeItem(at: dir) }

final class Told: @unchecked Sendable {
  private let lock = NSLock()
  private var list: [Settled] = []
  func add(_ s: Settled) { lock.lock(); list.append(s); lock.unlock() }
  var all: [Settled] { lock.lock(); defer { lock.unlock() }; return list }
}
let told = Told()

final class Redrawn: @unchecked Sendable {
  private let lock = NSLock()
  private var list: [(ObjectIdentifier, Bool)] = []
  func add(_ l: any ListSource, _ hold: Bool) { lock.lock(); list.append((ObjectIdentifier(l), hold)); lock.unlock() }
  var all: [(ObjectIdentifier, Bool)] { lock.lock(); defer { lock.unlock() }; return list }
}
let redrawn = Redrawn()

final class Applied: @unchecked Sendable {
  private let lock = NSLock()
  private var list: [(ObjectIdentifier, [Effect])] = []
  func add(_ l: any ListSource, _ e: [Effect]) { lock.lock(); list.append((ObjectIdentifier(l), e)); lock.unlock() }
  var all: [(ObjectIdentifier, [Effect])] { lock.lock(); defer { lock.unlock() }; return list }
}
let applied = Applied()

// Waits up to two seconds for cond.
func until(_ cond: () async -> Bool) async {
  for _ in 0..<100 {
    if await cond() { return }
    try? await Task.sleep(nanoseconds: 20_000_000)
  }
}

let bridge = Bridge(path: path, announce: false, log: { if ProcessInfo.processInfo.environment["OLM_BRIDGE_LOG"] != nil { print("  bridge: \($0)") } })
let launcher = BridgedLauncher(bridge: bridge)
// A list of the app's own, as main.swift hands File Search's in, step 3.3e.
actor NativeList: ListSource {
  nonisolated let manifest = Manifest(name: "filesearch", title: "File Search")
  func open(query: String) async -> Level { Level(placeholder: "Search files", ranking: .app, rowLimit: nil) }
  func rows(_ query: Query) async throws -> RowsAnswer { RowsAnswer(rows: []) }
  func choose(_ pick: Pick) async -> [Effect] { [] }
  func run(_ action: String, on pick: Pick) async -> [Effect] { [] }
  func close() async {}
}
let nativeList = NativeList()
final class Lines: @unchecked Sendable {
  private let lock = NSLock()
  private var list: [String] = []
  func add(_ s: String) { lock.lock(); list.append(s); lock.unlock() }
  var all: [String] { lock.lock(); defer { lock.unlock() }; return list }
}
let unknownNames = Lines()
let shown = BridgedLauncher(bridge: bridge, shown: true, natives: ["filesearch": nativeList], log: { unknownNames.add($0) })
await bridge.attach(launcher: launcher, shown: shown, settled: { told.add($0) })
await bridge.onRedraw { redrawn.add($0, $1) }
await bridge.onEffects { applied.add($0, $1) }
final class Drawn: @unchecked Sendable {
  private let lock = NSLock()
  private var list: [(ObjectIdentifier, DrawnPane)] = []
  func add(_ l: any ListSource, _ d: DrawnPane) { lock.lock(); list.append((ObjectIdentifier(l), d)); lock.unlock() }
  var all: [(ObjectIdentifier, DrawnPane)] { lock.lock(); defer { lock.unlock() }; return list }
}
let drawnPanes = Drawn()
await bridge.onPaneDrawn { drawnPanes.add($0, $1) }
if let why = await bridge.start() { give("the listener did not start, \(why)") }

func mode(_ p: String) -> Int {
  ((try? FileManager.default.attributesOfItem(atPath: p))?[.posixPermissions] as? NSNumber)?.intValue ?? -1
}
ok(mode(run.path) == 0o700, "the run folder is 0700")
ok(mode(path) == 0o600, "the socket is 0600")

// Hammerspoon's end, blocking, each read bounded.
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutableBytes(of: &addr.sun_path) { raw in
  let b = Array(path.utf8)
  raw.copyBytes(from: b)
  raw[b.count] = 0
}
let connected = withUnsafePointer(to: &addr) {
  $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
if connected != 0 { give("could not connect, errno \(errno)") }
var tv = timeval(tv_sec: 5, tv_usec: 0)
setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
var reader = Frame.Reader()
var waiting: [Data] = []
func next() -> [String: Any] {
  while waiting.isEmpty {
    var chunk = [UInt8](repeating: 0, count: 1 << 16)
    let n = read(fd, &chunk, chunk.count)
    if n <= 0 { give("the app said nothing within 5 s") }
    guard let got = try? reader.feed(Data(chunk[0..<n])) else { give("the app's framing is wrong") }
    waiting += got
  }
  guard let doc = try? JSONSerialization.jsonObject(with: waiting.removeFirst()) as? [String: Any] else {
    give("the app sent something that is not a JSON object")
  }
  return doc
}
func send(_ doc: [String: Any]) {
  let body = try! JSONSerialization.data(withJSONObject: doc)
  let m = Frame.encode(body)
  _ = m.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
}
func answer(_ request: [String: Any], _ result: Any) {
  send(["jsonrpc": "2.0", "id": request["id"]!, "result": result])
}
func request(_ method: String) -> [String: Any] {
  let m = next()
  ok(m["method"] as? String == method && m["id"] is String, "the app asks \(method), got \(m["method"] ?? "nothing")")
  return m
}

let hello = request("hello")
ok((hello["params"] as? [String: Any])?["protocol"] as? Int == 1, "hello names protocol 1")
answer(hello, ["protocol": 1, "olm": "check", "features": [String](),
  "limits": ["message": 8388608, "rowLimit": 50, "name": 65536]])
let open = request("open")
ok(((open["params"] as? [String: Any])?["what"] as? [String: Any])?["launcher"] as? Bool == true, "open asks for the launcher")
answer(open, ["level": ["id": "v1", "placeholder": "Search", "previewPane": false, "ranking": "app",
  "rowLimit": "default", "memory": ["ma": ["app:maps", "app:mail"], "sa": ["app:safari"]]]])

await until { await launcher.isOpen }
ok(await launcher.isOpen, "the launcher's level is open")
let level = await launcher.open(query: "")
ok(level.rowLimit == 50 && level.placeholder == "Search", "the level takes hello's row limit and the placeholder")
ok(await launcher.memorySnapshot()["ma"] == ["app:maps", "app:mail"], "the open's memory is held")

func row(_ key: String, _ title: String, memory: Bool = true) -> [String: Any] {
  var r: [String: Any] = ["ref": "v1.\(key)", "key": key, "title": title, "filterText": title, "bonus": 0.9]
  if memory { r["memoryKey"] = key }
  return r
}

// The first rows, every row as an upsert.
async let first = launcher.rows(Query(text: "ma", generation: 1))
let r1 = request("rows")
let p1 = r1["params"] as? [String: Any] ?? [:]
ok(p1["level"] as? String == "v1" && p1["query"] as? String == "ma" && p1["have"] == nil, "the first rows ask names the level and the query and has nothing")
answer(r1, ["q": p1["q"] ?? 0, "revision": "r1", "fromQuery": [String](), "exclusive": false,
  "changes": ["upsert": [row("app:mail", "Mail"), row("app:maps", "Maps"), row("k9", "Mammoth", memory: false)],
    "remove": [String](), "order": ["app:mail", "app:maps", "k9"]]])
let a1 = try await first
ok(a1.rows.map(\.key) == ["app:mail", "app:maps", "k9"], "the rows come in the supplier's order")
ok(a1.rows.map(\.bonus) == [0.5, 1, 0], "the bonus is the memory's, the leader one, never the Lua row's, none for a row with no memory key")
ok(a1.rows[0].filterText == "Mail", "a row's filterText crosses")
ok(await launcher.remembered(a1.rows) == ["app:mail", "app:maps"], "only rows with a memory key are named for the shadow")

// The next rows patch what is held.
async let second = launcher.rows(Query(text: "map", generation: 2))
let r2 = request("rows")
ok((r2["params"] as? [String: Any])?["have"] as? String == "r1", "the next ask says the revision it holds")
answer(r2, ["q": 2, "revision": "r2", "fromQuery": [String](), "exclusive": false,
  "changes": ["upsert": [row("app:maps", "Apple Maps")], "remove": ["k9"], "order": ["app:maps", "app:mail"]]])
let a2 = try await second
ok(a2.rows.map(\.title) == ["Apple Maps", "Mail"], "an upsert replaces a row, a remove drops one, the order follows")
ok(a2.rows.map(\.bonus) == [1, 0.5], "a longer query takes its longest remembered prefix's memory")

// The memory moves by notification, a forgotten query sent empty.
send(["jsonrpc": "2.0", "method": "memory", "params": ["memory": ["ma": ["app:mail"], "sa": [String: Any]()]]])
async let third = launcher.rows(Query(text: "Ma", generation: 3))
let r3 = request("rows")
answer(r3, ["q": 3, "revision": "r2", "fromQuery": [String](), "exclusive": false])
let a3 = try await third
let memory = await launcher.memorySnapshot()
ok(memory["ma"] == ["app:mail"] && memory["sa"] == nil, "a memory notification moves a query and forgets an empty one")
ok(a3.rows.map(\.key) == ["app:maps", "app:mail"] && a3.rows.map(\.bonus) == [0, 1],
  "an answer with no changes keeps the rows, and the bonus follows the new memory, a capital folded")

// A request the app does not serve is refused, and the session goes on.
send(["jsonrpc": "2.0", "id": "l1", "method": "ping", "params": [String: Any]()])
let refused = next()
ok(refused["id"] as? String == "l1" && (refused["error"] as? [String: Any])?["code"] as? Int == -32601, "a request of the Lua side's is answered -32601")

// The shadow notification is heard, and the shadow ranks and logs it.
send(["jsonrpc": "2.0", "method": "shadow", "params": ["tool": "launcher", "query": "ma", "claimed": false,
  "keys": ["app:mail", "app:maps"]]])
await until { !told.all.isEmpty }
ok(told.all.first == Settled(tool: "launcher", query: "ma", keys: ["app:mail", "app:maps"], status: nil, claimed: false),
  "the shadow notification is heard with its query and keys")
let shadow = await MainActor.run {
  Shadow(tool: "launcher", source: launcher, searcher: Searcher(), run: run, log: log, skip: { _ in nil },
    named: { await launcher.remembered($0) })
}
await MainActor.run { shadow.settled(query: "ma", keys: ["app:mail", "app:maps"], status: nil, claimed: false) }
// The shadow runs on the main actor, so Hammerspoon's blocking read waits off it.
let r4 = await Task.detached { request("rows") }.value
answer(r4, ["q": 4, "revision": "r3", "fromQuery": [String](), "exclusive": false,
  "changes": ["upsert": [row("k9", "Mammoth", memory: false)], "remove": [String](), "order": ["app:maps", "app:mail", "k9"]]])
let logFile = log.appendingPathComponent("shadow-launcher.jsonl")
await until { FileManager.default.fileExists(atPath: logFile.path) }
let line = (try? String(contentsOf: logFile, encoding: .utf8))?.split(separator: "\n").last.map(String.init) ?? ""
let doc = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] ?? [:]
ok(doc["same"] as? Bool == true && doc["app"] as? Int == 2, "the shadow ranks the memory's leader first, leaves the row with no memory key out and logs the same, \(line)")

// The launcher a person opens, step 3.2. metrics first, sent once the stage has measured a list.
await bridge.setTextBudget(612)
let metrics = next()
ok(metrics["method"] as? String == "metrics" && metrics["id"] == nil
  && (metrics["params"] as? [String: Any])?["textBudget"] as? Int == 612, "metrics is a notification with the text budget")

// A show opens a level of its own, fromURL, the shadow's level left open.
async let shownLevel = shown.open(query: "")
let o2 = request("open")
let op2 = o2["params"] as? [String: Any] ?? [:]
ok((op2["what"] as? [String: Any])?["launcher"] as? Bool == true && op2["fromURL"] as? Bool == true, "a show opens a launcher level fromURL")
answer(o2, ["level": ["id": "v2", "placeholder": "Search", "ranking": "app", "rowLimit": "default",
  "memory": ["ma": ["app:mail"]]]])
let l2 = await shownLevel
ok(l2.rowLimit == 50 && l2.placeholder == "Search", "the shown level takes hello's row limit")
ok(await launcher.isOpen, "the shadow's level stays open beside it")

// Its rows draw the icons they name, an owner's table asked once.
func shownRow(_ key: String, _ title: String, icon: [String: Any]) -> [String: Any] {
  ["ref": "v2.\(key)", "key": key, "title": title, "memoryKey": key, "icon": icon]
}
async let s1 = shown.rows(Query(text: "ma", generation: 1))
let rs1 = request("rows")
ok((rs1["params"] as? [String: Any])?["level"] as? String == "v2", "the shown launcher asks rows of its own level")
answer(rs1, ["q": (rs1["params"] as? [String: Any])?["q"] ?? 0, "revision": "r1", "fromQuery": [String](), "exclusive": false,
  "changes": ["upsert": [shownRow("app:mail", "Mail", icon: ["app": "com.apple.mail"]),
    shownRow("tool:clip", "Clipboard", icon: ["owner": "clipboard", "key": "pin"]),
    shownRow("tool:sym", "Lock", icon: ["sf": "lock"]), shownRow("tool:emo", "Pizza", icon: ["emoji": "🍕"]),
    ["ref": "v2.pic", "key": "clip:pic", "title": "cat.png", "memoryKey": "clip:pic", "picture": ["path": "/tmp/thumb.png"]]],
    "remove": [String](), "order": ["app:mail", "tool:clip", "tool:sym", "tool:emo", "clip:pic"]]])
let ic = await Task.detached { request("icons") }.value
ok((ic["params"] as? [String: Any])?["owner"] as? String == "clipboard", "an owner the rows name is asked for its icons")
answer(ic, ["icons": ["pin": ["sf": "pin.fill", "emoji": "📌"]]])
let sa1 = try await s1
ok(sa1.rows.map(\.icon) == [.app("com.apple.mail"), .symbol("pin.fill"), .symbol("lock"), .emoji("🍕"),
  .picture("/tmp/thumb.png")],
  "app, owner, sf and emoji icons resolve, an owner's sf preferred, and a row's own picture is its icon")
ok(sa1.rows.map(\.bonus) == [1, 0, 0, 0, 0], "the shown launcher's bonus is the memory its open sent")

// Return. hide becomes the stage's hide, after hidden waits for the close.
async let picked = shown.choose(Pick(key: "app:mail", query: "ma", row: 1, highlight: 3))
let c1 = request("choose")
let cp1 = c1["params"] as? [String: Any] ?? [:]
ok(cp1["level"] as? String == "v2" && cp1["ref"] as? String == "v2.app:mail" && cp1["row"] as? Int == 1
  && cp1["h"] as? Int == 3 && cp1["query"] as? String == "ma" && cp1["q"] is Int && cp1["mods"] is [Any],
  "choose names the level, the row's ref, its place, h, q and the query")
answer(c1, ["effects": [["hide": [String: Any]()], ["after": "hidden"]]])
ok(await picked == [.hide], "hide is the stage's hide and after hidden is kept")
async let closed: Void = shown.close()
let hidden = next()
ok(hidden["method"] as? String == "hidden" && hidden["id"] == nil
  && (hidden["params"] as? [String: Any])?["level"] as? String == "v2", "closing says hidden first when a run waits")
let cl = request("close")
ok((cl["params"] as? [String: Any])?["level"] as? String == "v2", "then closes the level")
answer(cl, true)
await closed

// The next show, its choose answering requery, unserved and nothing.
async let again = shown.open(query: "ma")
let o3 = request("open")
answer(o3, ["level": ["id": "v3", "placeholder": "Search", "ranking": "app", "rowLimit": "default", "memory": [String: Any]()]])
_ = await again
async let s3 = shown.rows(Query(text: "ma", generation: 1))
let rs3 = request("rows")
answer(rs3, ["q": (rs3["params"] as? [String: Any])?["q"] ?? 0, "revision": "r1", "fromQuery": [String](), "exclusive": false,
  "changes": ["upsert": [["ref": "v3.1", "key": "tool:vpn", "title": "VPN"]], "remove": [String](), "order": ["tool:vpn"]]])
_ = try await s3
for (effects, expect, what) in [([["requery": ["level": "v3", "q": 1]]], [Effect.requery], "requery searches again"),
  ([["unserved": ["name": "vpn"]]], [], "unserved keeps the row in place"), ([], [], "no effects do nothing")] {
  async let e = shown.choose(Pick(key: "tool:vpn", query: "ma"))
  let c = request("choose")
  ok((c["params"] as? [String: Any])?["ref"] as? String == "v3.1", "choose names the new level's ref")
  answer(c, ["effects": effects])
  ok(await e == expect, what)
}

// Two rows asks out at once, the older answer dropped.
async let older = shown.rows(Query(text: "m", generation: 2))
async let newer = shown.rows(Query(text: "ma", generation: 3))
for _ in 0..<2 {
  let r = request("rows")
  answer(r, ["q": (r["params"] as? [String: Any])?["q"] ?? 0, "revision": "r1", "fromQuery": [String](), "exclusive": false])
}
let results = [await (try? older) != nil, await (try? newer) != nil]
ok(results.filter { $0 }.count == 1, "of two rows asks out at once, only the newer answer lands")

// A close with no run waiting says no hidden.
async let closed2: Void = shown.close()
let cl2 = next()
ok(cl2["method"] as? String == "close", "with no run waiting the close is all, got \(cl2["method"] ?? "nothing")")
answer(cl2, true)
await closed2

// A hosted tool's list, step 3.3. A claim whose tool fits says so, and a push is a level of its own.
async let hostedLevel = shown.open(query: "")
let o4 = request("open")
answer(o4, ["level": ["id": "v4", "placeholder": "Search", "ranking": "app", "rowLimit": "default", "memory": [String: Any]()]])
_ = await hostedLevel
async let claim = shown.rows(Query(text: "k", generation: 1))
let rk = request("rows")
answer(rk, ["q": (rk["params"] as? [String: Any])?["q"] ?? 0, "revision": "r1", "fromQuery": [String](), "exclusive": true, "fit": true,
  "changes": ["upsert": [["ref": "v4.1", "key": "tool:caffeinate", "title": "Keep Awake"]], "remove": [String](), "order": ["tool:caffeinate"]]])
ok((try await claim).fit, "a claim whose tool's list fits crosses as the answer's fit")
async let unclaimed = shown.rows(Query(text: "", generation: 2))
let ru = request("rows")
answer(ru, ["q": (ru["params"] as? [String: Any])?["q"] ?? 0, "revision": "r1", "fromQuery": [String](), "exclusive": false])
ok(!(try await unclaimed).fit, "and an answer with none does not fit")
async let pushing = shown.choose(Pick(key: "tool:caffeinate", query: ""))
let cp = request("choose")
answer(cp, ["effects": [["push": ["parent": "v4", "level": ["id": "v5", "name": "caffeinate", "placeholder": "Time or duration",
  "previewPane": false, "ranking": "source", "rowLimit": "default", "fit": true, "actions": ["insertSelected", "setTerminal"]]]]]])
ok(await pushing == [.push("v5")], "a push effect names the level it carries")
guard let child = await shown.pushed("v5") as? BridgedLevel else { give("pushed made no level of the push") }
ok(await shown.pushed("v5") == nil, "and the same push makes it once")
ok(child.id == "v5" && child.manifest.name == "caffeinate", "the level is the tool's, by its name")
let childLevel = await child.open(query: "")
ok(childLevel.ranking == .source && childLevel.fit && childLevel.placeholder == "Time or duration" && childLevel.rowLimit == 50,
  "it opens with the push's placeholder, its own order, fit, and hello's row limit")
async let childRows = child.rows(Query(text: "", generation: 1))
let rc = request("rows")
ok((rc["params"] as? [String: Any])?["level"] as? String == "v5", "its rows are asked of its own level")
answer(rc, ["q": (rc["params"] as? [String: Any])?["q"] ?? 0, "revision": "r1", "fromQuery": [String](), "exclusive": false,
  "changes": ["upsert": [["ref": "v5.1", "key": "k1", "title": "Keep Awake Indefinitely", "icon": ["owner": "caffeinate", "key": "on"]]],
    "remove": [String](), "order": ["k1"]]])
let icc = await Task.detached { request("icons") }.value
ok((icc["params"] as? [String: Any])?["owner"] as? String == "caffeinate", "its owner's icons are asked")
answer(icc, ["icons": ["on": ["sf": "sun.max", "emoji": "☀️"]]])
let cr = try await childRows
ok(cr.rows.map(\.title) == ["Keep Awake Indefinitely"] && cr.rows.first?.icon == .symbol("sun.max"), "its rows draw their owner's icons")

// A tool's own key, step 3.8, its level asked of the Lua side by name and opened as one of its own,
// and a tool the Lua side does not host opening nothing.
async let toolOpen = shown.openTool("clipboard", query: "")
let ot = request("open")
ok(((ot["params"] as? [String: Any])?["what"] as? [String: Any])?["tool"] as? String == "clipboard",
  "a tool's own key asks open for that tool")
answer(ot, ["level": ["id": "v20", "name": "clipboard", "placeholder": "Clipboard History", "previewPane": true,
  "ranking": "app", "rowLimit": "default", "actions": ["copy"]]])
let tool = await toolOpen
ok(tool?.id == "v20" && tool?.manifest.name == "clipboard" && tool?.manifest.previewPane?.drawn == true,
  "its level is the tool's, by its name, with its pane")
async let refusedOpen = shown.openTool("nothing", query: "")
let orf = request("open")
send(["jsonrpc": "2.0", "id": orf["id"]!, "error": ["code": -32013, "message": "not hosted"]])
ok(await refusedOpen == nil, "a tool the Lua side does not host opens nothing")

// Its cycle key, step 3.9, asked open as a cycle, its level carrying the idle, and a key typed over it
// sent with the choose, the level saying hidden before it closes once the answer asks for it.
async let cycleOpen = shown.openTool("inputsources", query: "", cycle: true)
let co = request("open")
let coWhat = (co["params"] as? [String: Any])?["what"] as? [String: Any]
ok(coWhat?["tool"] as? String == "inputsources" && coWhat?["cycle"] as? Bool == true, "a cycle key asks open as a cycle")
answer(co, ["level": ["id": "v21", "name": "inputsources", "placeholder": "Input Sources", "previewPane": false,
  "ranking": "source", "rowLimit": "default", "fit": true, "cycle": ["idle": 0.8]]])
guard let cycleLevel = await cycleOpen else { give("the cycle's level did not open") }
ok(cycleLevel.cycleIdle == 0.8, "its level carries the idle")
ok(tool?.cycleIdle == nil, "and a tool's own key's level none")
async let cycleRows = cycleLevel.rows(Query(text: "", generation: 1))
let cr2 = request("rows")
answer(cr2, ["q": (cr2["params"] as? [String: Any])?["q"] ?? 0, "revision": "r1", "fromQuery": [String](),
  "exclusive": false, "changes": ["upsert": [["ref": "v21.1", "key": "k1", "title": "ABC"],
    ["ref": "v21.2", "key": "k2", "title": "Serbian"]], "remove": [String](), "order": ["k1", "k2"]]])
_ = try await cycleRows
async let typedChoose = cycleLevel.choose(Pick(key: "k2", query: "", row: 2, highlight: 3,
  retype: Retype(code: 0, mods: ["shift"])))
let tc = request("choose")
let tcRetype = (tc["params"] as? [String: Any])?["retype"] as? [String: Any]
ok(tcRetype?["code"] as? Int == 0 && tcRetype?["mods"] as? [String] == ["shift"], "a key typed over it goes with the choose")
answer(tc, ["effects": [["hide": [String: Any]()], ["after": "hidden"]]])
ok(await typedChoose == [.hide], "it closes the list")
async let cycleClosed: Void = cycleLevel.close()
let cycleHidden = next()
ok(cycleHidden["method"] as? String == "hidden" && cycleHidden["id"] == nil
  && (cycleHidden["params"] as? [String: Any])?["level"] as? String == "v21", "the level says hidden before it closes")
let cycleClose = request("close")
answer(cycleClose, true)
await cycleClosed

// The cycle's own rules on the app's stage, step 3.9, as the Lua stage keeps them. The first press
// lands one row down from the top, each further one more, wrapping, and presses owed before the rows
// landed are taken at once. The vertical arrows are the list's, Return and keypad Enter complete it,
// and every other key completes it and is typed again with its modifiers, fn left out.
ok(Stage.cycleRow(after: 1, from: 1, count: 3) == 2, "a cycle's first press lands on the row used before")
ok(Stage.cycleRow(after: 1, from: 3, count: 3) == 1, "a press on the last row wraps to the first")
ok(Stage.cycleRow(after: 4, from: 1, count: 3) == 2, "presses owed before the rows landed are taken together")
ok(Stage.cycleRow(after: 1, from: 1, count: 1) == 1, "a list of one stays on it")
ok(Stage.cycleRow(after: 1, from: 1, count: 0) == 0, "and an empty list has no row")
ok(Stage.cycleKeyKind(125) == .list && Stage.cycleKeyKind(126) == .list, "the vertical arrows are the list's own")
ok(Stage.cycleKeyKind(36) == .complete && Stage.cycleKeyKind(76) == .complete, "Return and keypad Enter complete it")
ok(Stage.cycleKeyKind(0) == .retype && Stage.cycleKeyKind(49) == .retype && Stage.cycleKeyKind(48) == .retype,
  "any other key completes it and is typed again")
ok(Stage.retypeMods([.maskShift, .maskCommand, .maskSecondaryFn]) == ["shift", "cmd"],
  "with the modifiers held, by their names, fn left out")

// The effects notification reaches the level it names and no other.
send(["jsonrpc": "2.0", "method": "effects", "params": ["level": "v9", "q": 1, "effects": [["rows": ["hold": true]]]]])
send(["jsonrpc": "2.0", "method": "effects", "params": ["level": "v5", "q": 1, "effects": [["rows": ["hold": true]]]]])
await until { !redrawn.all.isEmpty }
ok(redrawn.all.count == 1 && redrawn.all.first?.0 == ObjectIdentifier(child) && redrawn.all.first?.1 == true,
  "a redraw reaches the hosted level it names, holding the highlight, and an unknown level reaches nothing")
// A stage word a hosted list's code called outside any request, step 3.8, a placeholder and a query.
send(["jsonrpc": "2.0", "method": "effects", "params": ["level": "v5", "q": 1, "effects": [
  ["setPlaceholder": ["level": "v5", "text": "Duration or count"]], ["setQuery": ["level": "v5", "q": 1, "query": ""]]]]])
await until { !applied.all.isEmpty }
ok(applied.all.count == 1 && applied.all.first?.0 == ObjectIdentifier(child)
  && applied.all.first?.1 == [.setPlaceholder("Duration or count"), .setQuery("")],
  "a placeholder and a query from outside a request reach the level they name, and no redraw")
ok(redrawn.all.count == 1, "and are not taken for a redraw")

// Its actions pane, step 3.3b. The push names its actions, actions says which apply and what each is
// called, choices is the level a verb opens with its icons, and run carries the choice made there.
ok(child.manifest.actions.map(\.id) == ["insertSelected", "setTerminal"], "the push names the actions its pane runs")
async let applying = child.actions(on: Pick(key: "k1", query: "", highlight: 4))
let ac = request("actions")
let acp = ac["params"] as? [String: Any]
ok(acp?["level"] as? String == "v5" && acp?["ref"] as? String == "v5.1", "actions asks of the level and the row's ref")
answer(ac, ["h": 4, "actions": [["action": "insertSelected", "title": "Confirm"], ["action": "setTerminal", "title": "Terminal"]]])
ok(await applying == ["insertSelected": "Confirm", "setTerminal": "Terminal"], "and answers each action that applies with its title")
async let offered = child.choices("setTerminal", on: Pick(key: "k1", query: ""))
let ch = request("choices")
ok((ch["params"] as? [String: Any])?["action"] as? String == "setTerminal", "choices names the action")
answer(ch, ["h": 0, "choices": [
  ["choice": "c1", "title": "Ghostty", "subtitle": "Installed", "icon": ["owner": "actionspane", "key": "chosen"], "current": true],
  ["choice": "c2", "title": "WezTerm", "subtitle": "Not installed", "icon": ["sf": "circle"], "enabled": false],
  ["choice": "c3", "title": "Cancel", "cancel": true], ["choice": "c4", "title": "Chrome", "on": false]]])
let ich = await Task.detached { request("icons") }.value
ok((ich["params"] as? [String: Any])?["owner"] as? String == "actionspane", "a choice's owner's icons are asked")
answer(ich, ["icons": ["chosen": ["sf": "circle.inset.filled", "emoji": "🔘"]]])
let got = await offered
ok(got.count == 4 && got[3].on == false && got[0].on == nil && got[0] == Choice(ref: "c1", title: "Ghostty", subtitle: "Installed", icon: .symbol("circle.inset.filled"), current: true)
  && got[1].enabled == false && got[1].icon == .symbol("circle") && got[2].cancel,
  "the level's rows carry their titles, icons, the one in force, a disabled one, Cancel and a switch")
async let chose = child.run("setTerminal", on: Pick(key: "k1", query: "", row: 1, highlight: 4), choice: "c1")
let rn = request("run")
let rnp = rn["params"] as? [String: Any]
ok(rnp?["action"] as? String == "setTerminal" && rnp?["choice"] as? String == "c1" && rnp?["ref"] as? String == "v5.1",
  "run carries the action, the choice and the row")
answer(rn, ["effects": [["rows": ["hold": true]]]])
ok(await chose == [.rows(hold: true)], "and its effects are the stage's")
async let plain = child.run("setTerminal", on: Pick(key: "k1", query: ""))
let rp = request("run")
ok((rp["params"] as? [String: Any])?["choice"] == nil, "an action run plainly carries no choice")
answer(rp, ["effects": [[String: Any]]()])
_ = await plain

// Return closes the list, back is declined for the stage to pop, and close forgets it.
async let childPick = child.choose(Pick(key: "k1", query: ""))
let cc = request("choose")
ok((cc["params"] as? [String: Any])?["level"] as? String == "v5" && (cc["params"] as? [String: Any])?["ref"] as? String == "v5.1",
  "Return names the hosted level and its row's ref")
answer(cc, ["effects": [["hide": [String: Any]()]]])
ok(await childPick == [.hide], "and a hide is the stage's")
// Step 3.3c, a row that leaves its own level and one that writes the field.
async let leaving = child.choose(Pick(key: "k1", query: ""))
let lv = request("choose")
answer(lv, ["effects": [["pop": ["level": "v5"]], ["rows": ["hold": false]]]])
ok(await leaving == [.pop, .rows(hold: false)], "a pop is the stage's, the rows beside it kept in order")
async let writing = child.choose(Pick(key: "k1", query: ""))
let wq = request("choose")
answer(wq, ["effects": [["setQuery": ["level": "v5", "q": 3, "query": "tea"]]]])
ok(await writing == [.setQuery("tea")], "a setQuery carries its text")
async let declined = child.back()
let bk = request("back")
answer(bk, ["handled": false])
ok(await declined == false, "a back the list declines is the stage's to pop")
async let childClosed: Void = child.close()
let cx = request("close")
ok((cx["params"] as? [String: Any])?["level"] as? String == "v5", "closing the hosted list closes its level")
answer(cx, true)
await childClosed
send(["jsonrpc": "2.0", "method": "effects", "params": ["level": "v5", "q": 1, "effects": [["rows": ["hold": true]]]]])
// Step 3.3d, a hosted list whose preview pane is drawn in Lua. The push says it has one, the level
// is told where it stands and which row the highlight rests on, and what the pane drew reaches the
// level it names, read into what the pane view draws.
ok(child.manifest.previewPane == nil, "a push with no pane is a level with none")
async let panePush = shown.choose(Pick(key: "tool:caffeinate", query: ""))
let pp = request("choose")
answer(pp, ["effects": [["push": ["parent": "v4", "level": ["id": "v6", "name": "speedtest", "placeholder": "Measure",
  "previewPane": true, "ranking": "app", "rowLimit": "default", "actions": [String]()]]]]])
_ = await panePush
guard let paned = await shown.pushed("v6") as? BridgedLevel else { give("pushed made no level of the pane's push") }
ok(paned.manifest.previewPane?.drawn == true, "a push with a pane is a level whose pane is drawn in Lua")
await paned.positioned(frame: ScreenRect(x: 1, y: 2, w: 600, h: 400), pane: ScreenRect(x: 610, y: 2, w: 480, h: 400))
let pos = next()
let posp = pos["params"] as? [String: Any]
ok(pos["method"] as? String == "positioned" && pos["id"] == nil && posp?["level"] as? String == "v6"
  && (posp?["paneFrame"] as? [String: Any])?["w"] as? Double == 480 && (posp?["frame"] as? [String: Any])?["x"] as? Double == 1,
  "positioned is a notification naming the level, the list's rect and the pane's")
await paned.positioned(frame: ScreenRect(x: 1, y: 2, w: 600, h: 400), pane: nil)
ok((next()["params"] as? [String: Any])?["paneFrame"] is NSNull, "and a pane gone as null")
async let panedRows = paned.rows(Query(text: "", generation: 1))
let prq = request("rows")
answer(prq, ["q": (prq["params"] as? [String: Any])?["q"] ?? 0, "revision": "r1", "fromQuery": [String](), "exclusive": false,
  "changes": ["upsert": [["ref": "v6.1", "key": "a", "title": "Run"]], "remove": [String](), "order": ["a"]]])
_ = try await panedRows
await paned.highlighted(Pick(key: "a", query: "", row: 1, highlight: 7))
let hl = next()
let hlp = hl["params"] as? [String: Any]
ok(hl["method"] as? String == "highlight" && hlp?["level"] as? String == "v6" && hlp?["ref"] as? String == "v6.1"
  && hlp?["h"] as? Int == 7 && hlp?["row"] as? Int == 1, "highlight names the level, the row's ref, its place and h")
await paned.highlighted(nil)
ok((next()["params"] as? [String: Any])?["ref"] is NSNull, "and no row as a null ref")
let picture = dir.appendingPathComponent("arrow.png")
let png = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4,
  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!.representation(using: .png, properties: [:])!
try png.write(to: picture)
let elements: [[String: Any]] = [
  ["type": "rectangle", "action": "fill", "frame": ["x": 0, "y": 0, "w": "100%", "h": 4], "fillColor": ["red": 1, "green": 0, "blue": 0, "alpha": 1]],
  ["type": "segments", "action": "stroke", "strokeWidth": 2, "coordinates": [["x": 0, "y": 10], ["x": 5, "y": 2], ["x": 10, "y": 8]],
    "strokeColor": ["red": 0, "green": 0, "blue": 1, "alpha": 1]],
  ["type": "text", "text": ["string": "120 Mbps", "font": "Helvetica", "size": 14, "color": ["red": 0, "green": 0, "blue": 0, "alpha": 1],
    "alignment": "left", "lineBreak": "truncateTail", "lineHeight": 19], "frame": ["x": 0, "y": 20, "w": 200, "h": 19]],
  ["type": "image", "image": ["path": picture.path], "frame": ["x": 0, "y": 40, "w": 16, "h": 16]],
  ["type": "oval", "action": "fill"],
]
send(["jsonrpc": "2.0", "method": "paneDrawn", "params": ["level": "v9", "h": 7, "elements": elements, "contentHeight": 900]])
send(["jsonrpc": "2.0", "method": "paneDrawn", "params": ["level": "v6", "h": 7, "ref": "v6.1", "elements": elements,
  "contentHeight": 900, "keepScroll": true]])
await until { !drawnPanes.all.isEmpty }
let dp = drawnPanes.all
ok(dp.count == 1 && dp.first?.0 == ObjectIdentifier(paned) && dp.first?.1.highlight == 7 && dp.first?.1.height == 900
  && dp.first?.1.keepScroll == true, "what a pane drew reaches the level it names, with its h, height and scroll, and no other")
if let d = dp.first?.1 {
  let read = await PaneElements.kinds(d.elements, w: 480, h: 400)
  ok(read.kinds == ["fill:6", "stroke:3", "text:120 Mbps", "image:16x16"],
    "a rectangle, a curve, a Text and a Picture are read into what the pane draws, got \(read.kinds)")
  ok(read.unsupported == ["oval"], "and a kind it cannot draw is left out and named")
}

async let panedClosed: Void = paned.close()
let cx6 = request("close")
ok((cx6["params"] as? [String: Any])?["level"] as? String == "v6", "closing the list with a pane closes its level")
answer(cx6, true)
await panedClosed

// Step 3.3e. A row of a tool the app serves itself pushes the app's own source, a typed word's hand
// over crosses as the answer's own, and a hosted level a hand over opened that nobody pushed is closed.
async let nativeChoose = shown.choose(Pick(key: "tool:caffeinate", query: ""))
let cn = request("choose")
answer(cn, ["effects": [["native": ["name": "filesearch"]]]])
ok(await nativeChoose == [.push("native:filesearch")], "native becomes a push of a source of the app's own")
let nativePushed = await shown.pushed("native:filesearch")
ok(nativePushed != nil && nativePushed === nativeList, "pushed answers the source the app holds under that name")
ok(await shown.pushed("native:nothing") == nil, "an unknown name pushes nothing")
ok(unknownNames.all.contains { $0.contains("nothing") }, "and is logged")
func handRows(_ text: String, _ generation: Int, handOver: [String: Any]?) async throws -> RowsAnswer {
  async let got = shown.rows(Query(text: text, generation: generation))
  let r = request("rows")
  var doc: [String: Any] = ["q": (r["params"] as? [String: Any])?["q"] ?? 0, "revision": "r1", "fromQuery": [String](),
    "exclusive": handOver != nil]
  if let handOver { doc["handOver"] = handOver }
  answer(r, doc)
  return try await got
}
let typedNative = try await handRows("/ foo", 3, handOver: ["native": ["name": "filesearch"], "prefix": "/ ", "query": "foo"])
ok(typedNative.handOver == HandOver(token: "native:filesearch", prefix: "/ ", query: "foo"),
  "a hand over to a source of the app's own crosses with its word and the rest")
let speedLevel: [String: Any] = ["id": "v7", "name": "speedtest", "placeholder": "Measure", "previewPane": true,
  "ranking": "app", "rowLimit": "default", "actions": [String]()]
let typedHosted = try await handRows("st ", 4, handOver: ["push": ["parent": "v4", "level": speedLevel], "prefix": "st ", "query": ""])
ok(typedHosted.handOver == HandOver(token: "v7", prefix: "st ", query: ""), "a hand over to a hosted tool names the level it pushed")
async let movedOn = shown.rows(Query(text: "s", generation: 5))
let rmo = request("rows")
answer(rmo, ["q": (rmo["params"] as? [String: Any])?["q"] ?? 0, "revision": "r1", "fromQuery": [String](), "exclusive": false])
let cv7 = request("close")
ok((cv7["params"] as? [String: Any])?["level"] as? String == "v7", "a level a hand over opened and the stage never pushed is closed")
answer(cv7, true)
ok((try await movedOn).handOver == nil, "and an answer that hands nothing over carries none")
var speedLevel8 = speedLevel
speedLevel8["id"] = "v8"
_ = try await handRows("st ", 6, handOver: ["push": ["parent": "v4", "level": speedLevel8], "prefix": "st ", "query": ""])
let handedChild = await shown.pushed("v8") as? BridgedLevel
ok(handedChild?.manifest.name == "speedtest" && handedChild?.manifest.previewPane?.drawn == true,
  "the level a hand over names is pushed as a hosted level with its pane")
async let handedClosed: Void = handedChild!.close()
let cv8 = request("close")
ok((cv8["params"] as? [String: Any])?["level"] as? String == "v8", "and once pushed it is the stage's to close, not the launcher's")
answer(cv8, true)
await handedClosed

async let launcherClosed: Void = shown.close()
let cl4 = request("close")
ok((cl4["params"] as? [String: Any])?["level"] as? String == "v4", "then the launcher's own")
answer(cl4, true)
await launcherClosed
ok(redrawn.all.count == 1, "and a closed level is redrawn no more")

// Hammerspoon goes, and the level with it.
close(fd)
await until { !(await launcher.isOpen) }
ok(!(await launcher.isOpen), "a lost connection closes the level")
do {
  _ = try await launcher.rows(Query(text: "ma", generation: 5))
  ok(false, "rows with no connection throws")
} catch {
  ok(error as? BridgeError == .gone, "rows with no connection throws gone")
}
// The launcher a person opens, with no session, says so rather than showing nothing.
if let answer = try? await shown.rows(Query(text: "ma", generation: 6)) {
  ok(answer.status == BridgedLauncher.notConnected && answer.rows.isEmpty, "the shown launcher with no session says Hammerspoon is not connected")
  ok(shown.manifest.statusRow(BridgedLauncher.notConnected) != nil, "and draws it as a status row")
} else {
  ok(false, "the shown launcher with no session answers rather than throwing")
}

// The socket file removed while the app listens is made again, and a connection reaches it, step
// 3.3's finding of 2026-11-16, the stand-in check leaving the app on a file that was gone.
func inode(_ p: String) -> UInt64? {
  var st = stat()
  return stat(p, &st) == 0 ? UInt64(st.st_ino) : nil
}
func connects(_ p: String) -> Bool {
  let s = socket(AF_UNIX, SOCK_STREAM, 0)
  defer { close(s) }
  var a = sockaddr_un()
  a.sun_family = sa_family_t(AF_UNIX)
  withUnsafeMutableBytes(of: &a.sun_path) { raw in
    let b = Array(p.utf8)
    raw.copyBytes(from: b)
    raw[b.count] = 0
  }
  return withUnsafePointer(to: &a) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
  } == 0
}
unlink(path)
await until { FileManager.default.fileExists(atPath: path) }
ok(FileManager.default.fileExists(atPath: path), "a socket file removed is made again")
ok(mode(path) == 0o600, "at 0600")
ok(connects(path), "and a connection reaches the listener again")

// A program that removes the file to bind its own keeps it, and the app takes it back once it goes.
unlink(path)
let foreign = socket(AF_UNIX, SOCK_STREAM, 0)
var faddr = sockaddr_un()
faddr.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutableBytes(of: &faddr.sun_path) { raw in
  let b = Array(path.utf8)
  raw.copyBytes(from: b)
  raw[b.count] = 0
}
let fbound = withUnsafePointer(to: &faddr) {
  $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(foreign, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
ok(fbound == 0 && listen(foreign, 1) == 0, "another program binds the path the moment it is free")
let theirs = inode(path)
try? await Task.sleep(nanoseconds: UInt64((Listener.healDelay + 0.35) * 1_000_000_000))
ok(theirs != nil && inode(path) == theirs, "and the app leaves it theirs")
close(foreign)
unlink(path)
await until { inode(path) != nil && inode(path) != theirs }
ok(inode(path) != nil && inode(path) != theirs, "once theirs is gone the app binds again")
ok(connects(path), "and is reached")

await bridge.stop()
ok(!FileManager.default.fileExists(atPath: path), "stopping removes the socket")
try? await Task.sleep(nanoseconds: UInt64((Listener.healDelay + 0.2) * 1_000_000_000))
ok(!FileManager.default.fileExists(atPath: path), "and a stopped listener makes it no more")

// The Olm Settings share, docs/DESIGN-APP-SETTINGS.md step S.2, read as the window reads it.
do {
  let text = """
  {"version":1,"sections":[
   {"id":"general","title":"General","symbol":"gearshape","settings":[
    {"id":"chooser","title":"Chooser","kind":"choice","applies":"reload","keywords":["glass","canvas"],
     "choices":[{"value":"default","title":"Canvas"},{"value":"swift","title":"Glass"}],"default":"swift","value":"default"},
    {"id":"rowLimit","title":"Rows per list","kind":"number","applies":"live","keywords":["limit"],
     "min":10,"max":500,"step":10,"unit":"rows","default":50,"value":50},
    {"title":"no id"}]},
   {"id":"plugins","title":"Plugins","symbol":"puzzlepiece.extension","settings":[
    {"id":"plugin.vpn","title":"VPN","detail":"Connect and disconnect","kind":"switch","applies":"reload",
     "keywords":["vpn","plugin"],"default":true,"value":false,"locked":"set in config/plugins.lua"}]}]}
  """
  let share = SettingsShare.parse(Data(text.utf8))
  ok(share != nil, "settings: a share is read")
  ok(share?.version == 1, "settings: with its version")
  ok(share?.sections.map(\.id) == ["general", "plugins"], "settings: its sections in order")
  ok(share?.sections.first?.settings.count == 2, "settings: a setting with no id is left out")
  let chooser = share?.sections.first?.settings.first
  ok(chooser?.kind == .choice && chooser?.choices.map(\.title) == ["Canvas", "Glass"], "settings: a choice and its titles")
  ok(chooser?.value == .text("default") && chooser?.defaultValue == .text("swift"), "settings: its value and default")
  ok(chooser?.differs == true && chooser?.needsReload == true, "settings: it differs and needs a reload")
  let rows = share?.sections.first?.settings.last
  ok(rows?.kind == .number && rows?.value == .number(50) && rows?.max == 500, "settings: a number and its range")
  ok(rows?.differs == false, "settings: a number at its default does not differ")
  let vpn = share?.sections.last?.settings.first
  ok(vpn?.kind == .switch && vpn?.value == .flag(false) && vpn?.defaultValue == .flag(true), "settings: a switch is a flag, not a number")
  ok(vpn?.locked == "set in config/plugins.lua" && vpn?.detail == "Connect and disconnect", "settings: its lock and detail")
  ok(share?.matching("").count == 2, "settings: an empty search is every section")
  ok(share?.matching("glass").map(\.id) == ["general"], "settings: a keyword finds its section")
  ok(share?.matching("glass").first?.settings.map(\.id) == ["chooser"], "settings: with only what it found")
  ok(share?.matching("PLUGINS vpn").first?.settings.map(\.id) == ["plugin.vpn"], "settings: every word, any case, a section title among them")
  ok(share?.matching("connect").first?.settings.map(\.id) == ["plugin.vpn"], "settings: the detail is searched")
  ok(share?.matching("nothing at all").isEmpty == true, "settings: no match is no section")
  ok(SettingsShare.parse(Data("[]".utf8)) == nil, "settings: a share that is not one is nil")
  ok(SettingFormat.number(0.15, step: 0.01, unit: "seconds") == "0.15 s", "settings: seconds to the step's decimals")
  ok(SettingFormat.number(1, step: 0.5, unit: "points") == "1.0 pt", "settings: a half step has one decimal")
  ok(SettingFormat.number(50, step: 10, unit: "rows") == "50 rows", "settings: a whole step has none")
  ok(SettingFormat.number(0.98, step: 0.01, unit: "times") == "0.98×", "settings: times")
  ok(SettingFormat.font(".AppleSystemUIFont") == "System" && SettingFormat.font("Menlo") == "Menlo", "settings: a font's name")
  let live = SettingsShare.read(from: URL(fileURLWithPath: "/nonexistent/settings.json"))
  ok(live == nil, "settings: a missing share is nil")
}

do {
  // A whole number from the bridge reads as Double and Int both, since a Swift Int was refused by
  // every `as? Double` and dropped each cheat sheet the app was sent, 2026-11-23.
  let o = JSON.decode(Data(#"{"x":200,"r":12.5}"#.utf8))?.any as? [String: Any]
  ok(o?["x"] as? Double == 200 && o?["x"] as? Int == 200, "json: a whole number reads as Double and Int")
  ok(o?["r"] as? Double == 12.5 && o?["r"] as? Int == nil, "json: a fraction reads as Double only")
}

print("olm-bridge-check, \(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
