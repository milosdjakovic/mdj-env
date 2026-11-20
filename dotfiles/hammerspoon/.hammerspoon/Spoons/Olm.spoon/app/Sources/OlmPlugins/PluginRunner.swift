// Every external plugin Olm.app runs, docs/DESIGN-APP-PLUGINS.md. The runner is an actor inside the
// app rather than a process of its own, holding one RunningPlugin per plugin, and it keeps the one
// rule that spans a plugin's processes: three failures in ten minutes switch the plugin off until a
// person turns it on again, so a plugin that keeps crashing stops costing anything.

import Foundation
import OlmKit

public actor PluginRunner {
  public struct Status: Sendable, Equatable {
    public var running: Bool
    public var off: String?
    public var failures: Int
  }

  private let budgets: Budgets
  private let appVersion: String
  private let log: @Sendable (String) -> Void
  private var plugins: [String: RunningPlugin] = [:]
  private var failures: [String: [Date]] = [:]
  private var off: [String: String] = [:]
  private var onEnded: (@Sendable (String, Ending) -> Void)?

  /// Failures within the window that switch a plugin off.
  public static let strikes = 3
  public static let strikeWindow: TimeInterval = 600

  public init(budgets: Budgets = Budgets(), appVersion: String = "0",
              log: @escaping @Sendable (String) -> Void = { NSLog("Olm plugins: %@", $0) }) {
    self.budgets = budgets
    self.appVersion = appVersion
    self.log = log
  }

  /// Who hears each ending, the check today and Olm Settings at step 4.3.
  public func onEnded(_ fn: @escaping @Sendable (String, Ending) -> Void) {
    onEnded = fn
  }

  /// The plugin in a folder, its manifest read, held but not started.
  @discardableResult
  public func load(folder: URL) throws -> RunningPlugin {
    let manifest = try PluginManifest.read(folder: folder)
    if let held = plugins[manifest.id] { return held }
    let plugin = RunningPlugin(manifest: manifest, folder: folder, budgets: budgets, appVersion: appVersion,
      ended: { [weak self] id, why in Task { await self?.ended(id, why) } }, log: log)
    plugins[manifest.id] = plugin
    return plugin
  }

  public func plugin(_ id: String) -> RunningPlugin? { plugins[id] }

  /// The list a plugin answers, for the stage, nil for a plugin not loaded.
  public func source(_ id: String) -> ExternalSource? {
    guard let plugin = plugins[id] else { return nil }
    return ExternalSource(plugin: plugin, runner: self)
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
    if why.failed {
      let now = Date()
      var list = (failures[id] ?? []).filter { now.timeIntervalSince($0) < Self.strikeWindow }
      list.append(now)
      failures[id] = list
      if list.count >= Self.strikes, off[id] == nil {
        off[id] = "it failed \(list.count) times in ten minutes, last \(why)"
        log("\(id) is switched off, \(off[id]!)")
      }
    }
    onEnded?(id, why)
  }
}
