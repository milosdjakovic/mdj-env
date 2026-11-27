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
  private var said: [String] = []
  func log(_ line: String, _ from: PluginLog.From) { if from == .plugin { lock.lock(); said.append(line); lock.unlock() } else { log(line) } }
  func words() -> [String] { lock.lock(); defer { lock.unlock() }; return said }
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

/// Blocks heard on the log's thread, read by the check.
final class Heard: @unchecked Sendable {
  private let lock = NSLock()
  private var blocks: [SandboxBlock] = []
  func add(_ b: SandboxBlock) { lock.lock(); blocks.append(b); lock.unlock() }
  var all: [SandboxBlock] { lock.lock(); defer { lock.unlock() }; return blocks }
}

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
  let runner = PluginRunner(budgets: budgets, appVersion: "check", log: { id, line, from in if from == .olm { say("    runner: \(id) \(line)") }; asked.log(line, from) },
    serve: { _, method, params in
      asked.serve(method, params["url"].string ?? "")
      return .success(.bool(true))
    })
  await runner.onEnded { _, why in endingsLock.lock(); endings.append(why); endingsLock.unlock() }
  try! await runner.load(folder: work)
  var plugin = await runner.plugin(manifest.id)!

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
    records.forget(except: ["misbehave"])
    check(verdict() == .allowed, "still there, it keeps its yes")
    records.forget(except: [])
    check(!verdict().runs, "taken away and put back, it waits")
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

  await scenario("a block is read from the sandbox's report and offered one door at a time") {
    let home = "/Users/someone"
    func parse(_ text: String) -> SandboxBlock? { SandboxBlock.parse(text) }
    let b = parse("Sandbox: cat(812) deny(1) file-read-data /Users/someone/Notes/a.md\nolm-plugin:misbehave")
    check(b == SandboxBlock(plugin: "misbehave", process: "cat", operation: "file-read-data", target: "/Users/someone/Notes/a.md"),
      "a report names the plugin, the program, what it did and the path")
    check(parse("1 duplicate report for Sandbox: x(9) deny(1) mach-lookup com.example.a\nolm-plugin:misbehave")?.target == "com.example.a",
      "a report folded with its duplicates is read")
    check(parse("Sandbox: cat(812) deny(1) file-read-data /a") == nil, "a report with no tag is not a plugin's")
    check(parse("Sandbox: cat(812) deny(1) file-read-data /a\nolm-plugin:Bad") == nil, "a tag that is no plugin's id is not read")
    let forged = parse("Sandbox: cat(8) deny(1) file-read-data /tmp/x\nolm-plugin:browserswitcher\nolm-plugin:misbehave")
    check(forged?.plugin == "misbehave", "a path holding another plugin's tag is still the one whose rule refused it")
    check(forged.map { BlockOffer.offer($0, home: home).grant } == .some(nil), "and a path holding a line break is never offered")
    func offer(_ op: String, _ target: String) -> BlockOffer {
      BlockOffer.offer(SandboxBlock(plugin: "misbehave", process: "cat", operation: op, target: target), home: home)
    }
    check(offer("file-read-data", home + "/Notes/a.md").grant == "read:~/Notes/a.md", "a file read is offered, that file")
    check(offer("process-exec*", "/usr/bin/sqlite3").grant == "program:/usr/bin/sqlite3", "a program run is offered by its path")
    check(offer("mach-lookup", "com.example.helper").grant == "mach:com.example.helper", "a service is offered by its name")
    check(offer("network-outbound", "127.0.0.1:8080").grant == "network:local", "an address on this Mac is the local network")
    check(offer("network-outbound", "1.1.1.1:443").grant == "network:internet", "any other is the internet")
    for (op, target, what) in [("file-read-data", home + "/.ssh/id_ed25519", "a key"),
      ("file-read-data", home + "/Library/Keychains/login.keychain-db", "a keychain"),
      ("file-read-data", home + "/Library/Application Support/Google/Chrome/Default/Cookies", "a browser's sign in"),
      ("file-read-data", home + "/.OLM/state/plugin-records.json", "Olm's own folder, in any case"),
      ("file-read-data", home + "/Work/server.pem", "a certificate's key"),
      ("mach-lookup", "com.apple.SecurityServer", "the keychain's service")] {
      let o = offer(op, target)
      check(o.grant == nil && o.never == BlockOffer.secret, "\(what) is never offered")
    }
    for (target, what) in [(home + "/.zshrc", "a shell's start file"), (home + "/Library/LaunchAgents/x.plist", "a login agent"),
      (home + "/.config/git/config", "a tool's config")] {
      check(offer("file-write-create", target).never == BlockOffer.escape, "writing \(what) is never offered")
    }
    check(offer("mach-lookup", "com.apple.lsd.mapdb").never == BlockOffer.escape, "opening apps through Launch Services is never offered")
    check(offer("file-read-data", home).never == BlockOffer.wide, "the whole home folder is never offered from a block")
    check(offer("file-write-data", "/etc/hosts").grant == nil, "a write outside the home folder is never offered")
    check(offer("sysctl-read", "kern.x").grant == nil, "what has no door is only logged")
    var p = PluginManifest.Permissions(programs: ["cat"], files: [.init(path: "~/A", write: false)])
    p = p.adding(["read:~/B", "write:~/A", "program:/usr/bin/sqlite3", "mach:com.example.x", "network:local", "nonsense", "program:sqlite3"])
    check(p.files == [.init(path: "~/B", write: false), .init(path: "~/A", write: true)], "a read and a write join its files, a write over a read")
    check(p.programs == ["cat", "/usr/bin/sqlite3"] && p.services == [.mach("com.example.x")] && p.network == .local,
      "a program by its path, a service and the network join it, a line Olm does not read adds nothing")
    let dir = work.deletingLastPathComponent().appendingPathComponent("unblock")
    try? fm.removeItem(at: dir)
    try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let records = PluginRecords(url: dir.appendingPathComponent("records.json"))
    records.allow("misbehave", ["need:copy"])
    records.unblock("misbehave", "read:~/B")
    records.unblock("misbehave", "read:~/C")
    records.unblock("misbehave", "read:~/B", false)
    check(records.unblocked("misbehave") == ["read:~/C"], "a door is allowed after a block and taken back")
    let kept = PluginRecords.Block(grant: "read:~/B", text: "Reads ~/B", never: nil, process: "cat", last: Date(timeIntervalSince1970: 0))
    records.setBlocks("misbehave", [kept])
    check(PluginRecords(url: dir.appendingPathComponent("records.json")).blocks("misbehave") == [kept],
      "a block is kept with what was allowed, so its row is there after a relaunch")
    records.setBlocks("other", [kept])
    records.allow("misbehave", nil)
    check(records.unblocked("misbehave").isEmpty && records.blocks("misbehave").isEmpty,
      "uninstalled, what was allowed after a block and what was blocked go too")
    records.unblock("other", "read:~/C")
    records.forget(except: ["misbehave"])
    check(records.unblocked("other").isEmpty && records.blocks("other").isEmpty, "and a plugin no longer there loses both")
    try? fm.removeItem(at: dir)
  }

  await scenario("a refusal reaches Olm from macOS's log, tagged with the plugin, and an allowed door opens it") {
    let probe = NSHomeDirectory() + "/.olm-plugin-check-block"
    try? "x".write(toFile: probe, atomically: true, encoding: .utf8)
    defer { try? fm.removeItem(atPath: probe) }
    func box(_ extra: [String]) -> Sandbox {
      Sandbox(folder: work, data: work.appendingPathComponent("data"), temp: work.appendingPathComponent("tmp"),
        executable: work.appendingPathComponent("bin/misbehave"),
        permissions: PluginManifest.Permissions(programs: ["cat"]).adding(extra), id: "misbehave")
    }
    func cat(_ b: Sandbox) async -> Int32 {
      let rules = b.profile().rules
      return await Task.detached {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        p.arguments = ["-p", rules, "/bin/cat", probe]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return Int32(-1) }
        p.waitUntilExit()
        return p.terminationStatus
      }.value
    }
    let heard = Heard()
    let reports = SandboxReports { heard.add($0) }
    reports.start()
    try? await Task.sleep(for: .seconds(2))
    check(reports.running, "the log is followed")
    let refused = await cat(box([]))
    check(refused != 0, "a file it was not given is refused")
    var got: SandboxBlock?
    for _ in 0..<40 where got == nil {
      try? await Task.sleep(for: .milliseconds(250))
      got = heard.all.first { $0.plugin == "misbehave" && $0.target == probe }
    }
    reports.stop()
    check(got?.process == "cat" && got?.operation.hasPrefix("file-read") == true,
      "its refusal is heard within ten seconds, by the program it ran, for that path")
    let offered = got.map { BlockOffer.offer($0) }
    check(offered?.grant == "read:~/.olm-plugin-check-block" && offered?.never == nil, "and offered, that one file")
    let read = await cat(box([offered?.grant ?? ""]))
    check(read == 0, "allowed, the same file is read")
  }

  await scenario("the sandbox, a plugin cannot turn a place it writes into another") {
    let dir = work.deletingLastPathComponent().appendingPathComponent("places")
    try? fm.removeItem(at: dir)
    let data = dir.appendingPathComponent("data"), tmp = dir.appendingPathComponent("tmp")
    let given = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".olm-plugin-check-place")
    try? fm.removeItem(at: given)
    for d in [data, tmp, given] { try! fm.createDirectory(at: d, withIntermediateDirectories: true) }
    func box(_ files: [PluginManifest.FileGrant], _ programs: [String] = ["rmdir", "mv", "touch", "ln"]) -> Sandbox {
      Sandbox(folder: dir, data: data, temp: tmp, executable: dir.appendingPathComponent("bin/x"),
        permissions: .init(programs: programs, files: files))
    }
    func run(_ words: [String], _ b: Sandbox) -> Int32 {
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
      p.arguments = ["-p", b.profile().rules] + words
      p.standardOutput = FileHandle.nullDevice
      p.standardError = FileHandle.nullDevice
      do { try p.run() } catch { return -1 }
      p.waitUntilExit()
      return p.terminationStatus
    }
    let b = box([.init(path: given.path, write: true)])
    for d in [data, tmp, given] {
      check(run(["/usr/bin/touch", d.path + "/a"], b) == 0 && fm.fileExists(atPath: d.path + "/a"), "it writes inside \(d.lastPathComponent)")
      check(run(["/bin/mv", d.path, tmp.path + "/gone"], b) != 0 && fm.fileExists(atPath: d.path), "it cannot move \(d.lastPathComponent) away")
      try? fm.removeItem(at: d.appendingPathComponent("a"))
      check(run(["/bin/rmdir", d.path], b) != 0 && fm.fileExists(atPath: d.path), "or remove it")
    }
    try! fm.createSymbolicLink(at: given.appendingPathComponent("in"), withDestinationURL: fm.homeDirectoryForCurrentUser)
    let wide = box([.init(path: given.path, write: true), .init(path: given.path + "/in", write: true)]).profile().rules
    check(!wide.contains("(subpath \"\(NSHomeDirectory())\")"), "a grant through a link it can make grants nothing")
    try! fm.createSymbolicLink(at: data.appendingPathComponent("prog"), withDestinationURL: URL(fileURLWithPath: "/bin/ls"))
    check(box([], [data.path + "/prog"]).profile().programs.isEmpty, "a program it can put in place is not run")
    let file = given.appendingPathComponent("note")
    try! "x".write(to: file, atomically: true, encoding: .utf8)
    let one = box([.init(path: file.path, write: true)])
    check(run(["/bin/mv", file.path, tmp.path + "/gone"], one) != 0, "a single file it writes is not moved away")
    try? fm.removeItem(at: dir)
    try? fm.removeItem(at: given)
  }

  await scenario("install, a dropped plugin is copied aside and put in place whole") {
    let dir = work.deletingLastPathComponent().appendingPathComponent("install")
    try? fm.removeItem(at: dir)
    let drop = dir.appendingPathComponent("My Plugin"), root = dir.appendingPathComponent("root")
    try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
    try! fm.copyItem(at: source, to: drop)
    try! fm.createDirectory(at: drop.appendingPathComponent("bin"), withIntermediateDirectories: true)
    try! fm.copyItem(atPath: "/bin/echo", toPath: drop.path + "/bin/misbehave")
    try! fm.createSymbolicLink(at: drop.appendingPathComponent("data"), withDestinationURL: fm.homeDirectoryForCurrentUser)
    var n = 0
    func stage(_ item: URL) -> Result<PluginInstall.Staged, Error> {
      n += 1
      return Result { try PluginInstall.stage(item, into: dir.appendingPathComponent("aside\(n)")) }
    }
    func refused(_ item: URL, _ what: String) {
      if case .failure(let e) = stage(item) { check(true, "\(what) is refused, it \(e)") } else { check(false, "\(what) is refused") }
    }
    func shell(_ command: String) {
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/bin/sh")
      p.arguments = ["-c", command]
      p.currentDirectoryURL = dir
      p.standardError = FileHandle.nullDevice
      try! p.run()
      p.waitUntilExit()
    }
    guard case .success(let s) = stage(drop) else { check(false, "a folder is taken"); return }
    check(((try? fm.contentsOfDirectory(atPath: s.folder.path)) ?? []).sorted() == ["Sources", "olm-plugin.json"], "its manifest and sources are taken, nothing else of it")
    check(s.print == (try? PluginGate.fingerprint(source)), "and are the same files")
    try! PluginInstall.put(s, in: root)
    let dest = root.appendingPathComponent("misbehave")
    check(fm.fileExists(atPath: dest.path + "/olm-plugin.json"), "it is put under its id, whatever its folder was called")
    let records = PluginRecords(url: dir.appendingPathComponent("records.json"))
    check(!PluginGate.verdict(folder: dest, bundled: nil, records: records).0.runs, "put in place, it still waits")

    try! fm.createDirectory(at: dest.appendingPathComponent("data"), withIntermediateDirectories: true)
    try! "kept".write(to: dest.appendingPathComponent("data/note"), atomically: true, encoding: .utf8)
    try! "old".write(to: dest.appendingPathComponent("Sources/old.swift"), atomically: true, encoding: .utf8)
    shell("ditto -c -k --keepParent 'My Plugin' dropped.olmplugin")
    refused(dir.appendingPathComponent("records.txt"), "what is not there")
    if case .success(let z) = stage(dir.appendingPathComponent("dropped.olmplugin")) {
      check(z.print == s.print, "a .olmplugin holds the same plugin")
      try! PluginInstall.put(z, in: root)
      check((try? String(contentsOf: dest.appendingPathComponent("data/note"), encoding: .utf8)) == "kept", "an update keeps its data")
      check(!fm.fileExists(atPath: dest.path + "/Sources/old.swift"), "and none of the old sources")
    } else { check(false, "a .olmplugin is taken") }

    // These two go to the Trash, as the real one does, and are taken out of it again.
    if let gone = try? PluginInstall.remove("misbehave", from: root, data: false, aside: dir.appendingPathComponent("going")) { try? fm.removeItem(at: gone) }
    check(((try? fm.contentsOfDirectory(atPath: dest.path)) ?? []) == ["data"], "uninstalled, its data alone stays")
    check(fm.fileExists(atPath: dest.path + "/data/note"), "with what it held")
    if let gone = try? PluginInstall.remove("misbehave", from: root, data: true, aside: dir.appendingPathComponent("going")) { try? fm.removeItem(at: gone) }
    check(!fm.fileExists(atPath: dest.path), "uninstalled with its data, nothing stays")

    shell("rm -f 'My Plugin/data'; ln -s /etc/hosts 'My Plugin/Sources/more.swift'")
    refused(drop, "a link among the sources")
    shell("rm -f 'My Plugin/Sources/more.swift'; mkfifo 'My Plugin/Sources/pipe.swift'")
    refused(drop, "a pipe among the sources")
    shell("cp -Rp 'My Plugin' misbehave")
    if case .refused = PluginGate.verdict(folder: dir.appendingPathComponent("misbehave"), bundled: nil, records: records).0 { check(true, "a pipe in a folder put in place is refused and not waited on") } else { check(false, "a pipe is refused") }
    shell("rm -f 'My Plugin/Sources/pipe.swift'; ln -s 'My Plugin' linked")
    refused(dir.appendingPathComponent("linked"), "a link to a plugin")
    refused(dir.appendingPathComponent("root"), "a folder with no manifest")
    shell("mkfile 33m 'My Plugin/Sources/big.swift'")
    refused(drop, "over 32 MB of sources")
    shell("ditto -c -k --keepParent 'My Plugin' big.olmplugin")
    refused(dir.appendingPathComponent("big.olmplugin"), "an archive that unpacks to over 32 MB")
    // An archive whose link points out and whose next file goes through it, and one that climbs.
    let out = NSHomeDirectory() + "/.olm/cache/plugin-check/install/escaped"
    try! fm.createDirectory(atPath: out, withIntermediateDirectories: true)
    try! """
    import zipfile, stat
    z = zipfile.ZipFile('evil.olmplugin', 'w')
    i = zipfile.ZipInfo('p/l'); i.create_system = 3; i.external_attr = (stat.S_IFLNK | 0o755) << 16
    z.writestr(i, '\(out)')
    z.writestr('p/l/through', 'x')
    z.writestr('../../escaped/climbed', 'x')
    z.writestr('p/olm-plugin.json', '{}')
    z.close()
    """.write(to: dir.appendingPathComponent("evil.py"), atomically: true, encoding: .utf8)
    shell("/usr/bin/python3 evil.py")
    check(fm.fileExists(atPath: dir.path + "/evil.olmplugin"), "the escaping archive was made")
    refused(dir.appendingPathComponent("evil.olmplugin"), "an archive that writes outside itself")
    check(((try? fm.contentsOfDirectory(atPath: out)) ?? []).isEmpty, "and nothing of it is outside")
    func manifest(_ json: String) -> Bool {
      try! json.write(to: dir.appendingPathComponent("olm-plugin.json"), atomically: true, encoding: .utf8)
      return (try? PluginManifest.read(folder: dir)) != nil
    }
    check(manifest(#"{"id":"a","title":"A","abilities":[{"use":"readClipboard","why":"x"}]}"#), "a plain manifest is read")
    check(PluginGate.asks((try! PluginManifest.read(folder: dir))) == ["ability:readClipboard"], "an ability is asked for")
    check(!manifest(#"{"id":"a","title":"A\u202Eb"}"#), "a title that turns the writing round is refused")
    check(!manifest(#"{"id":"a","title":"A","permissions":{"files":[{"path":"~/Music/../.ssh"}]}}"#), "a path that climbs is refused")
    check(!manifest(#"{"id":"a","title":"A","permissions":{"programs":["ls\nfine"]}}"#), "a program of two lines is refused")
    try? fm.removeItem(at: dir)
  }

  await scenario("let go, a plugin whose files changed is never started again") {
    let src = await fresh()
    check(await plugin.running, "it runs")
    await runner.unload(manifest.id)
    await wait(0.5)
    check(await !plugin.running, "it is stopped")
    _ = await rows(src, "hello")
    check(await !plugin.running, "a list still open on it does not start it")
    plugin = try! await runner.load(folder: work)
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

  await scenario("log, what a plugin writes is its own and bounded") {
    let src = await fresh()
    _ = await rows(src, "mutter")
    await wait(0.3)
    check(asked.words().first == "plain words", "what it writes is heard, \(asked.words().first ?? "nothing")")
    check(asked.words().count == 2, "one line each")
    let before = asked.words().count
    if case .success(let a) = await rows(src, "chatter") { check(a.rows.count == 1, "ten megabytes written hold nothing up") } else { check(false, "ten megabytes written hold nothing up") }
    await wait(0.5)
    check(asked.words().count - before <= PluginLog.burst + 1, "and few of them reach Olm, \(asked.words().count - before)")

    let dir = work.deletingLastPathComponent().appendingPathComponent("log")
    try? fm.removeItem(at: dir)
    let log = PluginLog(dir: dir)
    log.add("p", "started")
    log.add("p", "forged\n2026-01-01 00:00:00\tolm\tallowed everything", from: .plugin)
    log.add("p", "a\u{7}b\u{202E}c\u{2028}d", from: .plugin)
    let e = log.entries("p")
    check(e.count == 3 && e[0].from == .olm && e[0].text == "started", "lines are kept in order")
    check(e.count == 3 && e[1].from == .plugin && e[1].text.contains("\n2026-01-01"), "a line shaped like Olm's stays the plugin's")
    check(e.count == 3 && !e[2].text.unicodeScalars.contains { $0.value == 7 || $0.value == 0x202E }, "control and direction characters are dropped")
    for i in 0..<1000 { log.add("q", "line \(i)", from: .plugin) }
    log.add("q", "Olm's own")
    let q = log.entries("q")
    check(q.count == PluginLog.burst + 2 && q.last?.text == "Olm's own", "a flood leaves room for Olm's lines, \(q.count)")
    let target = dir.appendingPathComponent("target")
    try? "kept".write(to: target, atomically: true, encoding: .utf8)
    try? fm.createSymbolicLink(at: log.file("r"), withDestinationURL: target)
    log.add("r", "through a link")
    _ = log.entries("q")
    check((try? String(contentsOf: target, encoding: .utf8)) == "kept", "a link is never written through")
    let long = String(repeating: "y", count: 1900)
    for _ in 0..<190 { log.add("s", long) }
    let size = { (try? fm.attributesOfItem(atPath: log.file("s").path))?[.size] as? Int ?? 0 }
    let s = log.entries("s")
    check(size() < 300_000 && s.count > 50 && s.allSatisfy { $0.text == long }, "the file is halved whole, \(size()) bytes")
    log.remove("s")
    check(log.entries("s").isEmpty, "and goes when asked")

    let file = dir.appendingPathComponent("history.json")
    let h = PluginHistory(url: file)
    h.runs("p", "one")
    h.stop("p", "it failed")
    h.use("p", "readFiles", at: Date(timeIntervalSince1970: 1_000_000))
    let again = PluginHistory(url: file)
    check(again.stopped("p") == "it failed", "switched off is remembered over a restart")
    check(again.used("p", "readFiles") == Date(timeIntervalSince1970: 1_000_000), "and so is a last use")
    again.runs("p", "one")
    check(again.stopped("p") != nil, "the same files stay off")
    again.runs("p", "two")
    check(again.stopped("p") == nil, "files that moved get a new chance")
    again.stop("p", "it failed")
    again.start("p")
    check(PluginHistory(url: file).stopped("p") == nil, "turned on, it is on")
    again.forget("p")
    check(again.used("p", "readFiles") == nil, "forgotten with its data")
    try? fm.removeItem(at: dir)
  }

  await scenario("three failures in ten minutes switch it off") {
    await runner.switchOn(manifest.id)
    let told = Asked()
    await runner.onOff { id, why in told.serve(id, why) }
    for _ in 0..<3 {
      clearEndings()
      let src = await runner.source(manifest.id)!
      _ = await src.open(query: "")
      _ = await rows(src, "crash")
      _ = await waitEnded(2)
    }
    let off = await runner.offReason(manifest.id)
    check(told.all().served.count == 1, "whoever hosts it is told once")
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
