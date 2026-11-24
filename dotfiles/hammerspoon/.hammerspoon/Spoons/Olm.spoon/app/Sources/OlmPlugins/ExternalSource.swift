// An external plugin's list as the stage sees it, the third conformance of ListSource beside a
// native plugin and the bridge, docs/DESIGN-APP.md, so the stage cannot tell them apart. Opening it
// asks the plugin for a level over its pipes, and from there it is the bridge's own hosted level
// speaking the same protocol to a different peer, so a plugin's rows, effects and actions read
// exactly as Hammerspoon's do.

import Foundation
import OlmBridge
import OlmKit

public actor ExternalSource: ListSource {
  public nonisolated let manifest: Manifest
  public nonisolated var runsEveryVerb: Bool { true }

  private let plugin: RunningPlugin
  private let runner: PluginRunner
  private var level: BridgedLevel?
  /// Why the list could not be served, said as its status in place of rows.
  private var trouble: String?
  /// What the list is opened with, a link for a plugin receiving links, handed to the plugin's open.
  private let context: JSON

  /// actions, the actions pane's and the secondary's, which the stage runs through this source.
  init(plugin: RunningPlugin, runner: PluginRunner, context: JSON = .null, actions: [Action] = []) {
    self.plugin = plugin
    self.runner = runner
    self.context = context
    manifest = Manifest(name: plugin.manifest.id, title: plugin.manifest.title, actions: actions,
      statusFallback: StatusLook(title: plugin.manifest.title, symbol: "exclamationmark.triangle"))
  }

  public func open(query: String) async -> Level {
    let title = plugin.manifest.title
    if let off = await runner.offReason(plugin.manifest.id) {
      trouble = "\(title) is switched off, \(off)"
      return Level(placeholder: title)
    }
    do {
      let answer = try await plugin.request("open", .object(["what": .object(["tool": .string(plugin.manifest.id),
        "context": context]), "query": .string(query)]))
      let opened = BridgedLevel(bridge: plugin, wire: answer["level"], defaultRowLimit: 50,
        log: { NSLog("Olm plugin: %@", $0) })
      await plugin.hold(opened)
      level = opened
      trouble = nil
      return await opened.open(query: query)
    } catch {
      trouble = "\(title) did not open, \(error)"
      return Level(placeholder: title)
    }
  }

  public func rows(_ query: Query) async throws -> RowsAnswer {
    guard let level else { return RowsAnswer(rows: [], status: trouble ?? "\(plugin.manifest.title) is not open") }
    do {
      return try await level.rows(query)
    } catch PluginError.timedOut(let method, let s) {
      // A slow answer keeps the rows already shown, the stage's own rule for a source that throws.
      throw PluginError.timedOut(method, s)
    } catch let error as PluginError {
      self.level = nil
      trouble = "\(plugin.manifest.title) \(error)"
      return RowsAnswer(rows: [], status: trouble)
    }
  }

  public func choose(_ pick: Pick) async -> [Effect] { await level?.choose(pick) ?? [] }
  public func run(_ action: String, on pick: Pick) async -> [Effect] { await level?.run(action, on: pick) ?? [] }
  public func run(_ action: String, on pick: Pick, choice: String?) async -> [Effect] {
    await level?.run(action, on: pick, choice: choice) ?? []
  }
  public func actions(on pick: Pick) async -> [String: String]? { await level?.actions(on: pick) }
  public func choices(_ action: String, on pick: Pick) async -> [Choice] { await level?.choices(action, on: pick) ?? [] }
  public func pushed(_ token: String) async -> (any ListSource)? { await level?.pushed(token) }
  public func back() async -> Bool { await level?.back() ?? false }
  public func highlighted(_ pick: Pick?) async { await level?.highlighted(pick) }

  public func close() async {
    await level?.close()
    level = nil
  }
}
