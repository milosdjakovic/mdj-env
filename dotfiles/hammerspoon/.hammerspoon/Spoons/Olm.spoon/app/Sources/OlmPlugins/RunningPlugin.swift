// One external plugin as its runner holds it, docs/DESIGN-APP-PLUGINS.md Never clogging Olm. It
// starts the plugin's process when a request first needs it, says hello, sends every request with a
// time limit, and kills a plugin that breaks a limit, its memory cap or its processor cap. It never
// waits on the main thread and never waits on the plugin beyond a limit, so whatever the plugin does
// the most it costs Olm is a list that shows its working state and then a line saying why.

import Darwin
import Foundation
import OlmBridge
import OlmKit

/// The limits every plugin is held to, docs/DESIGN-APP-PLUGINS.md, first guesses that step 4.1's
/// check measured against.
public struct Budgets: Sendable, Equatable {
  /// Seconds a request may take before it is cancelled, by method, and for any other.
  public var limits: [String: Double] = ["hello": 2, "choose": 5, "run": 5]
  public var limit: Double = 2
  /// Seconds after a cancel by which a plugin must have answered, or it is taken as stuck and killed.
  public var grace: Double = 1
  /// Seconds unused before a plugin that is not a watcher is stopped.
  public var idle: Double = 300
  /// Bytes of memory past which it is killed.
  public var memory: UInt64 = 512 * 1024 * 1024
  /// Processor seconds it may use within cpuWindow before it is taken as spinning and killed.
  public var cpu: Double = 9
  public var cpuWindow: Double = 10
  /// How often memory and processor are read.
  public var watch: Double = 1
  /// Seconds after a row is chosen or an action run in which the plugin may open one link.
  public var act: Double = 5

  public init() {}

  func limit(for method: String) -> Double { limits[method] ?? limit }
}

/// Why a plugin stopped, what its runner counts and says.
public enum Ending: Sendable, Equatable, CustomStringConvertible {
  case idle
  case asked
  case crashed(Int32)
  case killed(String)
  case broken(String)

  /// Whether it counts towards switching the plugin off.
  public var failed: Bool {
    switch self {
    case .idle, .asked: return false
    default: return true
    }
  }

  public var description: String {
    switch self {
    case .idle: return "stopped after going unused"
    case .asked: return "stopped"
    case .crashed(let status):
      let signal = status & 0x7f
      return signal != 0 ? "crashed with signal \(signal)" : "exited with status \((status >> 8) & 0xff)"
    case .killed(let why): return "killed, \(why)"
    case .broken(let why): return "stopped for breaking the protocol, \(why)"
    }
  }
}

public enum PluginError: Error, Equatable, CustomStringConvertible {
  /// It did not answer within its limit, which method and how long.
  case timedOut(String, Double)
  /// It stopped while the request waited.
  case gone(String)
  /// It could not be started.
  case unstartable(String)
  /// It is switched off.
  case off(String)

  public var description: String {
    switch self {
    case .timedOut(let method, let s): return "\(method) did not answer within \(s) s"
    case .gone(let why): return "it stopped, \(why)"
    case .unstartable(let why): return "it could not start, \(why)"
    case .off(let why): return "it is switched off, \(why)"
    }
  }
}

public actor RunningPlugin: LevelPeer {
  public nonisolated let manifest: PluginManifest
  public nonisolated let folder: URL
  private let budgets: Budgets
  private let appVersion: String
  private let ended: @Sendable (String, Ending) -> Void
  private let log: @Sendable (String) -> Void
  /// Answers what the plugin asks of Olm, by plugin id, method and params, a result or why not.
  private let serve: Serve

  private var process: PluginProcess?
  private var starting: Task<Void, Error>?
  private var generation = 0
  private var nextID = 0
  private var pending: [String: (method: String, done: CheckedContinuation<JSON, Error>)] = [:]
  // Requests past their limit, cancelled and waiting for the plugin to say so within the grace.
  private var overdue: Set<String> = []
  private var lastUsed = Date()
  // When the person last chose a row or ran an action, until the one link it allows is opened.
  private var acted: Date?
  private var cpuSamples: [(at: Date, cpu: Double)] = []
  private var stopping: Ending?
  private var levels: [String: BridgedLevel] = [:]

  /// The programs it declared as resolved on this machine, told to it in hello.
  public private(set) var programs: [String: String] = [:]
  /// The peak memory and processor time it was seen using since it started, for the check.
  public private(set) var peakFootprint: UInt64 = 0

  public typealias Serve = @Sendable (String, String, JSON) async -> Result<JSON, Refusal>

  /// Why Olm did not do what a plugin asked, its code and words.
  public struct Refusal: Error, Sendable {
    public let code: Int
    public let message: String
    public init(_ code: Int, _ message: String) {
      self.code = code
      self.message = message
    }
  }

  init(manifest: PluginManifest, folder: URL, budgets: Budgets, appVersion: String,
       ended: @escaping @Sendable (String, Ending) -> Void, log: @escaping @Sendable (String) -> Void,
       serve: @escaping Serve = { _, method, _ in .failure(Refusal(-32601, "no method \(method)")) }) {
    self.manifest = manifest
    self.folder = folder
    self.budgets = budgets
    self.appVersion = appVersion
    self.ended = ended
    self.log = log
    self.serve = serve
  }

  public var running: Bool { process != nil }
  public var pid: pid_t? { process?.pid }

  // The plugin's own places, docs/DESIGN-APP-PLUGINS.md What every plugin has without asking.
  nonisolated var data: URL { folder.appendingPathComponent("data") }
  nonisolated var temp: URL { folder.appendingPathComponent("tmp") }
  nonisolated var executable: URL { folder.appendingPathComponent("bin").appendingPathComponent(manifest.id) }
  public nonisolated var logFile: URL { folder.appendingPathComponent("log") }

  // MARK: Requests

  public func request(_ method: String, _ params: JSON) async throws -> JSON {
    try await ensureStarted()
    return try await send(method, params)
  }

  public func notify(_ method: String, _ params: JSON) async {
    guard let process else { return }
    lastUsed = Date()
    guard let body = JSON.object(["jsonrpc": .string("2.0"), "method": .string(method), "params": params]).encoded() else { return }
    process.send(body)
  }

  /// A plugin draws no icons of its own owners yet, so a row names its icon by symbol or emoji.
  package func icons(_ owners: Set<String>) async -> [String: [String: Icon]] { [:] }

  package func hold(_ level: BridgedLevel) async { levels[level.id] = level }
  package func release(_ id: String) async { levels[id] = nil }

  private func send(_ method: String, _ params: JSON) async throws -> JSON {
    guard let process else { throw PluginError.gone("it is not running") }
    nextID += 1
    let id = "p\(nextID)"
    guard let body = JSON.object(["jsonrpc": .string("2.0"), "id": .string(id), "method": .string(method),
      "params": params]).encoded() else { throw PluginError.unstartable("the request could not be encoded") }
    lastUsed = Date()
    if method == "choose" || method == "run" { acted = lastUsed }
    let limit = budgets.limit(for: method)
    let gen = generation
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(limit))
      await self?.expire(id, method: method, limit: limit, generation: gen)
    }
    return try await withCheckedThrowingContinuation { done in
      pending[id] = (method, done)
      process.send(body)
    }
  }

  // Past its limit: the waiting request fails at once, the plugin is told to stop working on it, and
  // a plugin that has not answered it by the end of the grace is stuck, so it is killed.
  private func expire(_ id: String, method: String, limit: Double, generation gen: Int) async {
    guard gen == generation, let p = pending.removeValue(forKey: id) else { return }
    p.done.resume(throwing: PluginError.timedOut(method, limit))
    overdue.insert(id)
    await notify("$/cancelRequest", .object(["id": .string(id)]))
    try? await Task.sleep(for: .seconds(budgets.grace))
    guard gen == generation, overdue.contains(id) else { return }
    kill(.killed("\(method) took over \(limit) s and it did not stop when asked"))
  }

  // MARK: Life

  private var retired = false

  /// Killed for good, its folder changed or taken away, so the manifest it holds is never run again.
  func retire() {
    retired = true
    kill(.asked)
  }

  private func ensureStarted() async throws {
    if retired { throw PluginError.off("its files changed, open it again") }
    if process != nil, starting == nil { return }
    if let starting { return try await starting.value }
    let task = Task { try await self.start() }
    starting = task
    defer { starting = nil }
    try await task.value
  }

  private func start() async throws {
    let fm = FileManager.default
    for dir in [data, temp] { try? fm.createDirectory(at: dir, withIntermediateDirectories: true) }
    guard fm.isExecutableFile(atPath: executable.path) else {
      throw PluginError.unstartable("it is not built, no \(executable.path)")
    }
    if retired { throw PluginError.off("its files changed, open it again") }
    let sandbox = Sandbox(folder: folder, data: data, temp: temp, executable: executable, permissions: manifest.permissions)
    let profile = sandbox.profile()
    for name in profile.missing { log("\(manifest.id) asks for \(name), which this Mac does not have") }
    programs = profile.programs
    var env = [
      "HOME": NSHomeDirectory(),
      "TMPDIR": temp.path + "/",
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
      "LANG": ProcessInfo.processInfo.environment["LANG"] ?? "en_US.UTF-8",
      "OLM_PLUGIN": manifest.id,
      "OLM_PLUGIN_DATA": data.path,
    ]
    env["USER"] = ProcessInfo.processInfo.environment["USER"]
    let p: PluginProcess
    do {
      p = try PluginProcess.spawn(executable: executable, rules: profile.rules, environment: env, log: logFile,
        qos: manifest.background ? QOS_CLASS_BACKGROUND : QOS_CLASS_UTILITY, label: manifest.id)
    } catch {
      throw PluginError.unstartable("\(error)")
    }
    generation += 1
    process = p
    stopping = nil
    overdue = []
    acted = nil
    cpuSamples = []
    peakFootprint = 0
    let gen = generation
    Task { [weak self] in
      for await event in p.events { await self?.take(event, generation: gen) }
    }
    Task { [weak self] in await self?.watch(generation: gen) }
    log("\(manifest.id) started, pid \(p.pid)")
    let hello: JSON
    do {
      hello = try await send("hello", .object([
        "protocol": .number(Double(Bridge.protocolVersion)), "app": .string(appVersion), "features": .array([]),
        "plugin": .object(["id": .string(manifest.id), "data": .string(data.path),
          "programs": .object(programs.mapValues { .string($0) })]),
      ]))
    } catch {
      kill(.killed("it did not say hello, \(error)"))
      throw PluginError.unstartable("it did not say hello, \(error)")
    }
    guard hello["protocol"].int == Bridge.protocolVersion else {
      kill(.broken("it speaks protocol \(hello["protocol"].int ?? 0), Olm \(Bridge.protocolVersion)"))
      throw PluginError.unstartable("it speaks another protocol")
    }
  }

  /// Stops it, asked to go by closing its input, killed if it has not within the grace.
  public func stop(_ why: Ending = .asked) async {
    guard let process else { return }
    stopping = why
    process.closeInput()
    let gen = generation
    try? await Task.sleep(for: .seconds(budgets.grace))
    if gen == generation, self.process != nil { process.kill() }
  }

  /// Kills it now, saying why.
  public func kill(_ why: Ending) {
    guard let process else { return }
    stopping = why
    log("\(manifest.id) \(why)")
    process.kill()
  }

  private func take(_ event: PluginProcess.Event, generation gen: Int) async {
    guard gen == generation else { return }
    switch event {
    case .message(let data):
      await receive(data)
    case .broken(let why):
      kill(.broken(why))
    case .exited(let status):
      let why = stopping ?? .crashed(status)
      process = nil
      generation += 1
      for (_, p) in pending { p.done.resume(throwing: PluginError.gone("\(why)")) }
      pending = [:]
      overdue = []
      levels = [:]
      if stopping == nil { log("\(manifest.id) \(why)") }
      ended(manifest.id, why)
    }
  }

  private func receive(_ data: Data) async {
    guard let message = JSON.decode(data), message["jsonrpc"].string == "2.0" else {
      kill(.broken("a message that is not JSON-RPC"))
      return
    }
    if let method = message["method"].string {
      if let id = message["id"].string ?? message["id"].int.map(String.init) {
        // What a plugin asks of Olm, answered off this actor so a slow answer holds nothing.
        if let refusal = refuses(method, message["params"]) {
          log("\(manifest.id) was refused \(method), \(refusal.message)")
          reply(id, error: (refusal.code, refusal.message))
          return
        }
        let serve = self.serve, plugin = manifest.id, params = message["params"]
        Task { [weak self] in
          let outcome = await serve(plugin, method, params)
          if case .failure(let refusal) = outcome { await self?.refused(method, refusal) }
          await self?.answer(id, outcome)
        }
      } else if method == "log" {
        log("\(manifest.id): \(message["params"]["text"].string ?? "")")
      }
      return
    }
    guard let id = message["id"].string else { return }
    overdue.remove(id)
    guard let p = pending.removeValue(forKey: id) else { return }
    lastUsed = Date()
    if !message["error"].isNull {
      p.done.resume(throwing: BridgeError.answered(message["error"]["code"].int ?? 0, message["error"]["message"].string ?? ""))
    } else {
      p.done.resume(returning: message["result"])
    }
  }

  // Why a request is refused before Olm looks at it: not in the manifest, or a link nobody chose. A
  // link can carry data out of a plugin with no network, so each act of the person's opens one at most.
  private func refuses(_ method: String, _ params: JSON) -> Refusal? {
    guard manifest.needs.contains(method) else { return Refusal(-32601, "its manifest does not need \(method)") }
    guard method == "open" else { return nil }
    if case .failure(let refusal) = PluginRequests.link(params) { return refusal }
    guard let at = acted, Date().timeIntervalSince(at) <= budgets.act else {
      return Refusal(-32001, "a link opens only just after a row is chosen or an action run, one for each")
    }
    acted = nil
    return nil
  }

  private func refused(_ method: String, _ refusal: Refusal) {
    log("\(manifest.id) was refused \(method), \(refusal.message)")
  }

  private func answer(_ id: String, _ outcome: Result<JSON, Refusal>) {
    switch outcome {
    case .success(let result):
      guard let process, let body = JSON.object(["jsonrpc": .string("2.0"), "id": .string(id), "result": result]).encoded()
      else { return }
      process.send(body)
    case .failure(let refusal):
      reply(id, error: (refusal.code, refusal.message))
    }
  }

  private func reply(_ id: String, error: (Int, String)) {
    guard let process, let body = JSON.object(["jsonrpc": .string("2.0"), "id": .string(id),
      "error": .object(["code": .number(Double(error.0)), "message": .string(error.1)])]).encoded() else { return }
    process.send(body)
  }

  // Memory and processor read every watch, and idling, while this generation runs.
  private func watch(generation gen: Int) async {
    while gen == generation, let process {
      try? await Task.sleep(for: .seconds(budgets.watch))
      guard gen == generation, self.process === process else { return }
      guard let use = process.usage() else { continue }
      peakFootprint = max(peakFootprint, use.footprint)
      if use.footprint > budgets.memory {
        kill(.killed("it used \(use.footprint / 1_048_576) MB, over the \(budgets.memory / 1_048_576) MB it may"))
        return
      }
      let now = Date()
      cpuSamples.append((now, use.cpu))
      // The share of a processor it used since the newest reading at least a window old. Dropping
      // readings at exactly the window's age once left none old enough to judge by, so a plugin
      // burning a whole core in the background was never killed, found by the check on 2026-11-20.
      cpuSamples.removeAll { now.timeIntervalSince($0.at) > budgets.cpuWindow + 3 * budgets.watch }
      if let base = cpuSamples.last(where: { now.timeIntervalSince($0.at) >= budgets.cpuWindow }) {
        let span = now.timeIntervalSince(base.at)
        let share = (use.cpu - base.cpu) / span
        if share > budgets.cpu / budgets.cpuWindow {
          kill(.killed("it kept the processor busy, \(Int(share * 100)) % of a core for \(Int(span)) s"))
          return
        }
      }
      if !manifest.background, pending.isEmpty, levels.isEmpty, now.timeIntervalSince(lastUsed) > budgets.idle {
        await stop(.idle)
        return
      }
    }
  }
}
