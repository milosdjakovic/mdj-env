// Step 4.1's check, docs/DESIGN-APP-PLUGINS.md Steps. It builds the misbehaving test plugin under
// Plugins/External/misbehave into a folder of its own, runs it through the real runner and the real
// ExternalSource, and for each thing the plugin does wrong checks what the runner did about it while
// timing the main thread, which is where the stage draws and hears typing. A main thread late by
// more than 8 ms at p99, or by two frames at worst, fails the check.
//
//   olm-plugin-check [--keep]    exits 0 when every case held, 1 otherwise

import Foundation
import OlmBridge
import OlmKit
import OlmPlugins

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let source = here.appendingPathComponent("../../Plugins/External/misbehave").standardizedFileURL
let work = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".olm/cache/plugin-check/misbehave")

// The main thread's lateness, a timer every 5 ms whose delay past its due time is recorded.
final class Lateness {
  private var samples: [Double] = []
  private var last = CFAbsoluteTimeGetCurrent()
  private let period = 0.005

  func start() {
    let t = Timer(timeInterval: period, repeats: true) { [unowned self] _ in
      let now = CFAbsoluteTimeGetCurrent()
      samples.append(max(0, now - last - period) * 1000)
      last = now
    }
    RunLoop.main.add(t, forMode: .common)
  }

  func reset() {
    samples = []
    last = CFAbsoluteTimeGetCurrent()
  }

  /// p50, p99 and the worst, in milliseconds.
  func read() -> (p50: Double, p99: Double, max: Double) {
    let s = samples.sorted()
    guard !s.isEmpty else { return (0, 0, 0) }
    return (s[s.count / 2], s[min(s.count - 1, s.count * 99 / 100)], s.last!)
  }
}

let lateness = Lateness()
nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var endings: [Ending] = []
let endingsLock = NSLock()

func say(_ s: String) { print(s); fflush(stdout) }

func check(_ ok: Bool, _ what: String) {
  say("  \(ok ? "ok  " : "FAIL") \(what)")
  if !ok { failures += 1 }
}

func lastEnding() -> Ending? {
  endingsLock.lock(); defer { endingsLock.unlock() }
  return endings.last
}

func clearEndings() {
  endingsLock.lock(); endings = []; endingsLock.unlock()
}

func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

/// Waits up to s seconds for the plugin to have ended.
func waitEnded(_ s: Double) async -> Ending? {
  let until = Date().addingTimeInterval(s)
  while Date() < until {
    if let e = lastEnding() { return e }
    await wait(0.05)
  }
  return nil
}

@MainActor
func mainThreadHeld(_ name: String) {
  let l = lateness.read()
  say(String(format: "  main thread late by p50 %.2f ms, p99 %.2f ms, worst %.2f ms", l.p50, l.p99, l.max))
  // Nothing of the runner's runs on the main thread, so what is left is the machine's own noise,
  // which the baseline shows: single delays of 9 to 18 ms in any case on 2026-11-20, p99 under 5.
  check(l.p99 < 8 && l.max < 33, "\(name): the main thread kept time, p99 under 8 ms and never two frames")
}

func rows(_ src: ExternalSource, _ text: String) async -> Result<RowsAnswer, Error> {
  do { return .success(try await src.rows(Query(text: text, generation: 1))) } catch { return .failure(error) }
}

/// What reached Olm and what the runner logged, for the requests' cases.
final class Asked: @unchecked Sendable {
  private let lock = NSLock()
  private var served: [String] = []
  private var lines: [String] = []
  func serve(_ method: String, _ what: String) { lock.lock(); served.append("\(method) \(what)"); lock.unlock() }
  func log(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
  func clear() { lock.lock(); served = []; lines = []; lock.unlock() }
  func all() -> (served: [String], refused: [String]) {
    lock.lock(); defer { lock.unlock() }
    return (served, lines.filter { $0.contains("was refused") })
  }
}

func link(_ params: [String: JSON]) -> PluginRequests.Link? {
  if case .success(let l) = PluginRequests.link(.object(params)) { return l }
  return nil
}

let only = ProcessInfo.processInfo.environment["OLM_CHECK_ONLY"]

func scenario(_ name: String, _ body: () async -> Void) async {
  if let only, !name.hasPrefix(only) { return }
  say("\n\(name)")
  clearEndings()
  await MainActor.run { lateness.reset() }
  await body()
  await MainActor.run { mainThreadHeld(name) }
}

func runAll() async {
  // The test plugin, copied and built where nothing in the checkout is written.
  let fm = FileManager.default
  try? fm.removeItem(at: work)
  try! fm.createDirectory(at: work.deletingLastPathComponent(), withIntermediateDirectories: true)
  try! fm.copyItem(at: source, to: work)
  let manifest = try! PluginManifest.read(folder: work)
  say("building \(manifest.id)")
  do { try PluginBuild.build(folder: work, manifest: manifest) } catch { say("\(error)"); exit(1) }

  var budgets = Budgets()
  budgets.idle = 3
  budgets.cpu = 3
  budgets.cpuWindow = 4
  budgets.act = 1
  let asked = Asked()
  let runner = PluginRunner(budgets: budgets, appVersion: "check", log: { say("    runner: \($0)"); asked.log($0) },
    serve: { _, method, params in
      asked.serve(method, params["url"].string ?? "")
      return .success(.bool(true))
    })
  await runner.onEnded { _, why in endingsLock.lock(); endings.append(why); endingsLock.unlock() }
  try! await runner.load(folder: work)
  let plugin = await runner.plugin(manifest.id)!

  func fresh() async -> ExternalSource {
    await runner.switchOn(manifest.id)
    let src = await runner.source(manifest.id)!
    _ = await src.open(query: "")
    return src
  }

  await scenario("baseline, no plugin running") {
    await wait(5)
  }

  await scenario("rows answered at once") {
    let src = await fresh()
    if case .success(let a) = await rows(src, "hello") { check(a.rows.count == 3, "three rows") } else { check(false, "three rows") }
  }

  await scenario("the sandbox, what it allows and refuses") {
    let src = await fresh()
    guard case .success(let a) = await rows(src, "probe") else { check(false, "the probe answered"); return }
    let by = Dictionary(uniqueKeysWithValues: a.rows.map { ($0.key, $0.subtitle) })
    for (k, v) in by.sorted(by: { $0.key < $1.key }) { say("    \(k): \(v)") }
    check(by["caffeinate"]?.hasPrefix("exit 0") == true, "caffeinate, declared, runs")
    if Sandbox.resolve("mullvad") != nil {
      check(by["mullvad"]?.hasPrefix("exit 0") == true, "mullvad, declared, runs and reaches its daemon")
    }
    check(by["ls"]?.hasPrefix("refused") == true, "a program it did not declare is refused")
    check(by["zshrc"] == "refused", "a file in the home folder is refused")
    check(by["documents"] == "refused", "Documents is refused")
    check(by["data"] == "written", "its own data folder is written")
    check(by["internet"]?.hasPrefix("refused") == true, "the internet is refused")
  }

  await scenario("gate, nothing is built or run before Allow") {
    let dir = work.deletingLastPathComponent().appendingPathComponent("gate")
    try? fm.removeItem(at: dir)
    let records = PluginRecords(url: dir.appendingPathComponent("records.json"))
    let folder = dir.appendingPathComponent("misbehave"), own = dir.appendingPathComponent("own")
    try! fm.createDirectory(at: own, withIntermediateDirectories: true)
    try! fm.copyItem(at: source, to: folder)
    func verdict() -> PluginGate.Verdict { PluginGate.verdict(folder: folder, bundled: own, records: records).0 }
    func rewrite(_ from: String, _ to: String) {
      let f = folder.appendingPathComponent("olm-plugin.json")
      let t = try! String(contentsOf: f, encoding: .utf8).replacingOccurrences(of: from, with: to)
      try! t.write(to: f, atomically: true, encoding: .utf8)
    }
    let asks = PluginGate.asks(manifest)
    check(verdict() == .waiting(asks.sorted()), "a new folder waits, with everything it asks for")
    try! fm.copyItem(at: source, to: own.appendingPathComponent("misbehave"))
    check(verdict() == .ours, "the same files as Olm's own run without asking")
    rewrite("0.1.0", "0.1.1")
    check(verdict() == .waiting(asks.sorted()), "Olm's own with one file changed waits")
    records.allow("misbehave", asks)
    check(verdict() == .allowed, "allowed, it runs")
    rewrite("\"caffeinate\",", "\"caffeinate\", \"tmux\",")
    check(verdict() == .waiting(["program:tmux"]), "asking for more waits, with only what is new")
    rewrite(", \"tmux\",", ",")
    check(verdict() == .allowed, "asking for no more runs")
    records.allow("misbehave", nil)
    check(!verdict().runs, "taken back, it waits")
    let moved = dir.appendingPathComponent("other")
    try! fm.copyItem(at: folder, to: moved)
    if case .refused = PluginGate.verdict(folder: moved, bundled: own, records: records).0 { check(true, "a folder whose name is not its id is refused") } else { check(false, "a folder whose name is not its id is refused") }
    for link in ["data", "log", "Sources/more.swift", "bin"] {
      let at = folder.appendingPathComponent(link)
      try! fm.createSymbolicLink(at: at, withDestinationURL: fm.homeDirectoryForCurrentUser)
      if case .refused = verdict() { check(true, "a link for \(link) is refused") } else { check(false, "a link for \(link) is refused") }
      try! fm.removeItem(at: at)
    }
    rewrite("\"misbehave\"", "\"plugins\"")
    check(!verdict().runs, "an id that is Olm's own word is refused")
    rewrite("\"plugins\"", "\"misbehave\"")
    try! "not json".write(to: dir.appendingPathComponent("records.json"), atomically: true, encoding: .utf8)
    check(!verdict().runs, "a broken record lets nothing through")

    let bin = folder.appendingPathComponent("bin/misbehave")
    try! fm.createDirectory(at: bin.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! fm.copyItem(atPath: "/bin/echo", toPath: bin.path)
    func prepare() -> Bool? { try? PluginGate.prepare(folder: folder, manifest: manifest, kit: nil, records: records) }
    check(prepare() == true, "a program that came with the folder is replaced by one built")
    check(prepare() == false, "the one built is kept")
    try! fm.removeItem(at: bin)
    try! fm.copyItem(atPath: "/bin/echo", toPath: bin.path)
    check(prepare() == true, "a program put in its place is built again")
    try? fm.removeItem(at: dir)
  }

  await scenario("the sandbox keeps Olm's own folder out of a granted home") {
    let box = Sandbox(folder: work, data: work.appendingPathComponent("data"), temp: work.appendingPathComponent("tmp"),
      executable: work.appendingPathComponent("bin/misbehave"),
      permissions: .init(programs: ["cat"], files: [.init(path: "~", write: true)]))
    let state = NSHomeDirectory() + "/.olm/state", secret = state + "/plugin-check-probe"
    try? fm.createDirectory(atPath: state, withIntermediateDirectories: true)
    try? "x".write(toFile: secret, atomically: true, encoding: .utf8)
    let home = NSHomeDirectory() + "/.olm-plugin-check-probe"
    try? "x".write(toFile: home, atomically: true, encoding: .utf8)
    func cat(_ path: String) -> Int32 {
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
      p.arguments = ["-p", box.profile().rules, "/bin/cat", path]
      p.standardOutput = FileHandle.nullDevice
      p.standardError = FileHandle.nullDevice
      do { try p.run() } catch { return -1 }
      p.waitUntilExit()
      return p.terminationStatus
    }
    check(cat(home) == 0, "a file of the home folder, granted, is read")
    check(cat(secret) != 0, "a file of ~/.olm/state is not")
    check(cat(work.appendingPathComponent("olm-plugin.json").path) == 0, "its own folder is")
    try? fm.removeItem(atPath: secret)
    try? fm.removeItem(atPath: home)
  }

  await scenario("requests, what a plugin may ask of Olm") {
    let web = JSON.string("https://example.com/a?b=c")
    check(link(["url": web])?.url.absoluteString == "https://example.com/a?b=c", "a web link is read")
    check(link(["url": web, "browser": .string("com.apple.Safari")])?.browser == "com.apple.Safari", "with a browser's id")
    for bad in ["file:///tmp/x.command", "/tmp/x", "olm://settings", "shortcuts://run", "javascript:1", "--args", "https:", ""] {
      check(link(["url": .string(bad)]) == nil, "\(bad.isEmpty ? "nothing" : bad) is refused")
    }
    check(link(["url": web, "app": .string("/Applications/Safari.app")]) == nil, "an application path is refused")
    check(link(["url": web, "args": .array([])]) == nil, "arguments are refused")
    check(link(["url": web, "browser": .number(1)]) == nil, "a browser that is no id is refused")

    let src = await fresh()
    asked.clear()
    _ = await rows(src, "beacon")
    await wait(0.3)
    check(asked.all().served.isEmpty && asked.all().refused.count == 1, "a link nobody chose is refused and logged")
    asked.clear()
    _ = await rows(src, "copy")
    await wait(0.3)
    check(asked.all().served.isEmpty && asked.all().refused.count == 1, "a request its manifest does not need is refused")
    asked.clear()
    guard case .success(let a) = await rows(src, "hello"), let first = a.rows.first else { check(false, "rows to choose"); return }
    _ = await src.choose(Pick(key: first.key, query: "hello", row: 1))
    await wait(0.3)
    check(asked.all().served == ["open https://example.com/first"], "one choice opens one link, \(asked.all().served)")
    check(asked.all().refused.count == 3, "the program, the file and the second link are refused")
    asked.clear()
    _ = await src.choose(Pick(key: first.key, query: "hello", row: 1))
    await wait(0.1)
    check(asked.all().served.count == 1, "the next choice opens its own")
  }

  await scenario("a choice goes stale") {
    let src = await fresh()
    guard case .success(let a) = await rows(src, "hello"), let first = a.rows.first else { check(false, "rows to choose"); return }
    asked.clear()
    _ = await src.choose(Pick(key: first.key, query: "late", row: 1))
    await wait(2)
    check(asked.all().served.isEmpty && asked.all().refused.count == 1, "a link long after the choice is refused")
  }

  await scenario("slow, a second, inside the limit") {
    let src = await fresh()
    let t = Date()
    if case .success(let a) = await rows(src, "slow") {
      check(a.rows.first?.key == "slow", String(format: "answered after %.2f s", Date().timeIntervalSince(t)))
    } else { check(false, "answered") }
    check(lastEnding() == nil, "not stopped")
  }

  await scenario("polite, ten seconds but stops when cancelled") {
    let src = await fresh()
    let t = Date()
    let r = await rows(src, "polite")
    if case .failure(let e) = r { check(e as? PluginError == .timedOut("rows", 2), String(format: "cancelled after %.2f s", Date().timeIntervalSince(t))) } else { check(false, "cancelled") }
    await wait(1.5)
    check(lastEnding() == nil, "not killed, since it stopped when asked")
    check(await plugin.running, "still running")
  }

  for (word, what) in [("hang", "thirty seconds, ignoring the cancel"), ("spin", "the processor held inside the request")] {
    await scenario("\(word), \(what)") {
      let src = await fresh()
      let t = Date()
      let r = await rows(src, word)
      if case .failure(let e) = r { check(e as? PluginError == .timedOut("rows", 2), String(format: "the list answered after %.2f s, its rows kept", Date().timeIntervalSince(t))) } else { check(false, "timed out") }
      let e = await waitEnded(2)
      if case .killed = e { check(true, String(format: "killed %.2f s after the request", Date().timeIntervalSince(t))) } else { check(false, "killed, got \(String(describing: e))") }
    }
  }

  await scenario("burn, the processor held in the background") {
    let src = await fresh()
    _ = await rows(src, "burn")
    let t = Date()
    let e = await waitEnded(8)
    if case .killed(let why) = e { check(why.contains("processor"), String(format: "killed for the processor after %.1f s, %@", Date().timeIntervalSince(t), why)) } else { check(false, "killed, got \(String(describing: e))") }
  }

  await scenario("leak, memory taken in the background") {
    let src = await fresh()
    _ = await rows(src, "leak")
    let t = Date()
    let e = await waitEnded(10)
    if case .killed(let why) = e { check(why.contains("MB"), String(format: "killed for memory after %.1f s, %@", Date().timeIntervalSince(t), why)) } else { check(false, "killed, got \(String(describing: e))") }
  }

  await scenario("crash, then started again on the next request") {
    let src = await fresh()
    _ = await rows(src, "crash")
    let e = await waitEnded(2)
    if case .crashed = e { check(true, "\(e!)") } else { check(false, "crashed, got \(String(describing: e))") }
    let again = await fresh()
    if case .success(let a) = await rows(again, "hello") { check(a.rows.count == 3, "started again and answered") } else { check(false, "started again") }
  }

  await scenario("flood, a message past 8 MiB") {
    let src = await fresh()
    _ = await rows(src, "flood")
    let e = await waitEnded(3)
    if case .broken = e { check(true, "\(e!)") } else { check(false, "stopped for breaking the protocol, got \(String(describing: e))") }
  }

  await scenario("idle, stopped once unused") {
    let src = await fresh()
    _ = await rows(src, "hello")
    await src.close()
    let e = await waitEnded(6)
    check(e == .idle, "stopped for idling, \(String(describing: e))")
    check(e?.failed == false, "not counted as a failure")
  }

  await scenario("three failures in ten minutes switch it off") {
    await runner.switchOn(manifest.id)
    for _ in 0..<3 {
      clearEndings()
      let src = await runner.source(manifest.id)!
      _ = await src.open(query: "")
      _ = await rows(src, "crash")
      _ = await waitEnded(2)
    }
    let off = await runner.offReason(manifest.id)
    check(off != nil, "switched off, \(off ?? "no")")
    let src = await runner.source(manifest.id)!
    _ = await src.open(query: "")
    if case .success(let a) = await rows(src, "hello") {
      check(a.rows.isEmpty && (a.status ?? "").contains("switched off"), "its list says so, \(a.status ?? "")")
    } else { check(false, "its list says so") }
    check(await plugin.running == false, "not started again")
  }

  await runner.stopAll()
  if !CommandLine.arguments.contains("--keep") { try? fm.removeItem(at: work) }
  say(failures == 0 ? "\nevery case held" : "\n\(failures) FAILED")
  exit(failures == 0 ? 0 : 1)
}

lateness.start()
// Detached, so the check's own work never runs on the main thread it times.
Task.detached { await runAll() }
RunLoop.main.run()
