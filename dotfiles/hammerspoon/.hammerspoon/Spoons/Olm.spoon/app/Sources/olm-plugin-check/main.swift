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
  let runner = PluginRunner(budgets: budgets, appVersion: "check", log: { say("    runner: \($0)") })
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
