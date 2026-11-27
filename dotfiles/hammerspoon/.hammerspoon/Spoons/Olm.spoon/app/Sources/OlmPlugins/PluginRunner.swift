// Every external plugin Olm.app runs, docs/DESIGN-APP-PLUGINS.md. The runner is an actor inside the
// app rather than a process of its own, holding one RunningPlugin per plugin, and it keeps the one
// rule that spans a plugin's processes: three failures in ten minutes switch the plugin off until a
// person turns it on again, so a plugin that keeps crashing stops costing anything.

import Foundation
import OlmBridge
import OlmKit

public actor PluginRunner {
  public struct Status: Sendable, Equatable {
    public var running: Bool
    public var off: String?
    public var failures: Int
  }

  private let budgets: Budgets
  private let appVersion: String
  /// A plugin's id, a line and who wrote it.
  public typealias Log = @Sendable (String, String, PluginLog.From) -> Void
  private let log: Log
  private var plugins: [String: RunningPlugin] = [:]
  private var failures: [String: [Date]] = [:]
  private var off: [String: String] = [:]
  private var onOff: (@Sendable (String, String) -> Void)?
  private var onEnded: (@Sendable (String, Ending) -> Void)?
  private let serve: RunningPlugin.Serve
  private let grants: @Sendable (String) -> [String]
  private var live: Set<String> = []
  private var onRunning: (@Sendable (Bool) -> Void)?

  /// Failures within the window that switch a plugin off.
  public static let strikes = 3
  public static let strikeWindow: TimeInterval = 600

  /// serve answers what a plugin asks of Olm, every plugin's requests.
  public init(budgets: Budgets = Budgets(), appVersion: String = "0",
              log: @escaping Log = { id, text, _ in NSLog("Olm plugins: %@ %@", id, text) },
              serve: @escaping RunningPlugin.Serve = { _, method, _ in
                .failure(RunningPlugin.Refusal(-32601, "no method \(method)")) },
              grants: @escaping @Sendable (String) -> [String] = { _ in [] }) {
    self.grants = grants
    self.budgets = budgets
    self.appVersion = appVersion
    self.log = log
    self.serve = serve
  }

  /// Who hears a plugin switched off and why, before anything can start it again.
  public func onOff(_ fn: @escaping @Sendable (String, String) -> Void) { onOff = fn }

  /// Who hears whether any plugin's process is running, as the first starts and the last ends, what
  /// the sandbox's reports are followed for.
  public func onRunning(_ fn: @escaping @Sendable (Bool) -> Void) { onRunning = fn }

  /// Stops a plugin so its next use starts it under what it is allowed now.
  public func restart(_ id: String) async { await plugins[id]?.stop() }

  private func begun(_ id: String) {
    let was = !live.isEmpty
    live.insert(id)
    if !was { onRunning?(true) }
  }

  /// Who hears each ending, the check.
  public func onEnded(_ fn: @escaping @Sendable (String, Ending) -> Void) {
    onEnded = fn
  }

  /// The plugin in a folder, its manifest read, held but not started.
  @discardableResult
  public func load(folder: URL) throws -> RunningPlugin {
    let manifest = try PluginManifest.read(folder: folder)
    if let held = plugins[manifest.id] { return held }
    let plugin = RunningPlugin(manifest: manifest, folder: folder, budgets: budgets, appVersion: appVersion,
      ended: { [weak self] id, why in Task { await self?.ended(id, why) } }, log: log, serve: serve,
      grants: grants, begun: { [weak self] id in Task { await self?.begun(id) } })
    plugins[manifest.id] = plugin
    return plugin
  }

  /// Lets a plugin go, killed and never started again, a list still open on it answered with why.
  public func unload(_ id: String) async {
    guard let plugin = plugins.removeValue(forKey: id) else { return }
    switchOn(id)
    await plugin.retire()
  }

  public func plugin(_ id: String) -> RunningPlugin? { plugins[id] }

  /// The list a plugin answers, for the stage, nil for a plugin not loaded.
  public func source(_ id: String, context: JSON = .null, actions: [Action] = []) -> ExternalSource? {
    guard let plugin = plugins[id] else { return nil }
    return ExternalSource(plugin: plugin, runner: self, context: context, actions: actions)
  }

  /// Why the plugin is switched off, nil while it may run.
  public func offReason(_ id: String) -> String? { off[id] }

  /// Switches it on again, its failures forgotten, Olm Settings' switch.
  public func switchOn(_ id: String) {
    off[id] = nil
    failures[id] = nil
  }

  public func status(_ id: String) async -> Status? {
    guard let plugin = plugins[id] else { return nil }
    return Status(running: await plugin.running, off: off[id], failures: failures[id]?.count ?? 0)
  }

  /// Every plugin stopped, as the app quits.
  public func stopAll() async {
    for plugin in plugins.values { await plugin.stop() }
  }

  private func ended(_ id: String, _ why: Ending) {
    if live.remove(id) != nil, live.isEmpty { onRunning?(false) }
    if why.failed {
      let now = Date()
      var list = (failures[id] ?? []).filter { now.timeIntervalSince($0) < Self.strikeWindow }
      list.append(now)
      failures[id] = list
      if list.count >= Self.strikes, off[id] == nil {
        let reason = "it failed \(list.count) times in ten minutes, last \(why)"
        off[id] = reason
        log(id, "switched off, \(reason)", .olm)
        onOff?(id, reason)
      }
    }
    onEnded?(id, why)
  }
}
