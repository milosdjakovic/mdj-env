// The app's end of the bridge checked with no Hammerspoon, step 2.3 of docs/PLAN-STANDALONE.md. It
// starts the app's listener on a socket of its own, connects as Hammerspoon would and answers it as
// host/bridge/serve.lua does, from canned answers in the shapes test/fixtures/bridge/launcher.json
// records, and checks what the app makes of them: the folder and socket modes, hello before
// anything, the launcher's open and its memory, rows patched by their changes, the bonus the memory
// gives, a memory notification moving it, a request it does not serve refused, the shadow comparing
// a settled answer and logging it, and a lost connection closing the level.
//
// test/olmbridge.sh builds and runs it. Exit 0 when every check passed.

import Foundation
import OlmBridge
import OlmCore
import OlmKit

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

// Waits up to two seconds for cond.
func until(_ cond: () async -> Bool) async {
  for _ in 0..<100 {
    if await cond() { return }
    try? await Task.sleep(nanoseconds: 20_000_000)
  }
}

let bridge = Bridge(path: path, announce: false, log: { if ProcessInfo.processInfo.environment["OLM_BRIDGE_LOG"] != nil { print("  bridge: \($0)") } })
let launcher = BridgedLauncher(bridge: bridge)
await bridge.attach(launcher: launcher, settled: { told.add($0) })
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
await bridge.stop()
ok(!FileManager.default.fileExists(atPath: path), "stopping removes the socket")

print("olm-bridge-check, \(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
