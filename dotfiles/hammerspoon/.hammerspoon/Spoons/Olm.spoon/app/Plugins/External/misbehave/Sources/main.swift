// A plugin that misbehaves on purpose, step 4.1 of docs/PLAN-STANDALONE.md, for olm-plugin-check to
// prove the runner holds Olm untouched whatever a plugin does. What it does is chosen by the text
// typed into its list, one word:
//
//   slow     answers its rows after a second, inside the limit
//   polite   takes ten seconds but stops when the runner cancels it
//   hang     takes thirty seconds and ignores the cancel
//   spin     keeps the processor busy in the request and ignores the cancel
//   burn     answers, then keeps the processor busy in the background
//   leak     answers, then takes memory until it is stopped
//   crash    aborts
//   flood    answers with a message past the 8 MiB limit
//   probe    tries what its sandbox allows and refuses, a row each
//
// Anything else answers three rows at once. It speaks the bridge protocol by hand, since the plugin
// kit is step 4.2.

import Foundation

let out = FileHandle.standardOutput
let outLock = NSLock()
var programs: [String: String] = [:]
let cancelled = NSMutableSet()
let work = DispatchQueue(label: "misbehave.work")

func send(_ object: [String: Any]) {
  guard let body = try? JSONSerialization.data(withJSONObject: object) else { return }
  outLock.lock()
  out.write(Data("\(body.count)\n".utf8) + body)
  outLock.unlock()
}

func answer(_ id: Any, _ result: Any) { send(["jsonrpc": "2.0", "id": id, "result": result]) }
func fail(_ id: Any, _ code: Int, _ message: String) {
  send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

func row(_ key: String, _ title: String, _ subtitle: String = "") -> [String: Any] {
  ["key": key, "ref": "m.\(key)", "title": title, "subtitle": subtitle]
}

func rows(_ list: [[String: Any]]) -> [String: Any] { ["rows": list, "revision": UUID().uuidString] }

func run(_ path: String?, _ args: [String]) -> String {
  guard let path else { return "not declared" }
  let p = Process()
  p.executableURL = URL(fileURLWithPath: path)
  p.arguments = args
  let pipe = Pipe()
  p.standardOutput = pipe
  p.standardError = pipe
  do { try p.run() } catch { return "refused, \(error.localizedDescription)" }
  p.waitUntilExit()
  let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  return "exit \(p.terminationStatus) \(text.split(separator: "\n").first ?? "")"
}

func probe() -> [[String: Any]] {
  let home = NSHomeDirectory()
  var list: [[String: Any]] = []
  list.append(row("caffeinate", "caffeinate", run(programs["caffeinate"], ["-i", "-t", "1"])))
  list.append(row("mullvad", "mullvad status", run(programs["mullvad"], ["status"])))
  list.append(row("ls", "ls, not declared", run("/bin/ls", ["/"])))
  let secret = (try? String(contentsOfFile: home + "/.zshrc", encoding: .utf8)).map { "READ \($0.count) characters" } ?? "refused"
  list.append(row("zshrc", "read ~/.zshrc, not declared", secret))
  let docs = (try? FileManager.default.contentsOfDirectory(atPath: home + "/Documents")).map { "LISTED \($0.count)" } ?? "refused"
  list.append(row("documents", "list ~/Documents, not declared", docs))
  let data = ProcessInfo.processInfo.environment["OLM_PLUGIN_DATA"] ?? "/nonexistent"
  let wrote = (try? "probe".write(toFile: data + "/probe.txt", atomically: false, encoding: .utf8)) != nil
  list.append(row("data", "write its own data folder", wrote ? "written" : "refused"))
  let sem = DispatchSemaphore(value: 0)
  var net = "no answer in 5 s"
  let task = URLSession(configuration: .ephemeral).dataTask(with: URL(string: "https://example.com")!) { _, r, e in
    net = e == nil ? "REACHED \((r as? HTTPURLResponse)?.statusCode ?? 0)" : "refused, \(e!.localizedDescription)"
    sem.signal()
  }
  task.resume()
  _ = sem.wait(timeout: .now() + 5)
  list.append(row("internet", "the internet", net))
  return list
}

// A loop the optimiser keeps, since an empty one is deleted and answers at once.
@_optimize(none) func spin() -> Never {
  var x = 0
  while true { x += 1 }
}

func handleRows(_ id: Any, _ query: String) {
  switch query.trimmingCharacters(in: .whitespaces) {
  case "slow":
    Thread.sleep(forTimeInterval: 1)
    answer(id, rows([row("slow", "Answered after a second")]))
  case "polite":
    for _ in 0..<200 {
      if cancelled.contains("\(id)") { fail(id, -32800, "cancelled"); return }
      Thread.sleep(forTimeInterval: 0.05)
    }
    answer(id, rows([row("polite", "Answered after ten seconds")]))
  case "hang":
    Thread.sleep(forTimeInterval: 30)
    answer(id, rows([row("hang", "Answered after thirty seconds")]))
  case "spin":
    spin()
  case "burn":
    answer(id, rows([row("burn", "Burning the processor in the background")]))
    Thread.detachNewThread { spin() }
  case "leak":
    answer(id, rows([row("leak", "Taking memory in the background")]))
    Thread.detachNewThread {
      var hoard: [UnsafeMutableRawPointer] = []
      while true {
        let n = 64 * 1024 * 1024
        let p = malloc(n)!
        memset(p, 1, n)
        hoard.append(p)
        Thread.sleep(forTimeInterval: 0.05)
      }
    }
  case "crash":
    abort()
  case "flood":
    answer(id, rows([row("flood", String(repeating: "x", count: 9 * 1024 * 1024))]))
  case "probe":
    answer(id, rows(probe()))
  default:
    answer(id, rows((1...3).map { row("r\($0)", "Row \($0)", query) }))
  }
}

func handle(_ message: [String: Any]) {
  let method = message["method"] as? String ?? ""
  let params = message["params"] as? [String: Any] ?? [:]
  guard let id = message["id"] else {
    if method == "$/cancelRequest", let which = params["id"] { cancelled.add("\(which)") }
    return
  }
  switch method {
  case "hello":
    let plugin = params["plugin"] as? [String: Any] ?? [:]
    programs = plugin["programs"] as? [String: String] ?? [:]
    answer(id, ["protocol": 1])
  case "open":
    answer(id, ["level": ["id": "m1", "placeholder": "Misbehave", "ranking": "source"]])
  case "rows":
    let query = params["query"] as? String ?? ""
    work.async { handleRows(id, query) }
  case "choose":
    answer(id, ["effects": [["hide": [:]]]])
  case "close":
    answer(id, true)
  default:
    fail(id, -32601, "no method \(method)")
  }
}

// Reads frames from stdin until it closes, which is the app asking it to go.
var buffer = Data()
let input = FileHandle.standardInput
while true {
  let chunk = input.availableData
  if chunk.isEmpty { exit(0) }
  buffer.append(chunk)
  while let nl = buffer.firstIndex(of: 0x0A) {
    guard let n = Int(String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)) else { exit(2) }
    let start = buffer.index(after: nl)
    guard buffer.distance(from: start, to: buffer.endIndex) >= n else { break }
    let body = buffer[start..<buffer.index(start, offsetBy: n)]
    buffer = Data(buffer[buffer.index(start, offsetBy: n)...])
    if let message = try? JSONSerialization.jsonObject(with: body) as? [String: Any] { handle(message) }
  }
}
