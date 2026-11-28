// The launcher with its catalog built in the app, step 6.1 of docs/PLAN-STANDALONE.md,
// docs/DESIGN-APP-LAUNCHER.md. Typing asks Hammerspoon only for the rows made from what was typed,
// the calculator, convert and the scopes, through a bridged launcher whose level serves those alone,
// and the catalog is the app's: the applications it finds itself and every other row from the share
// Hammerspoon writes. A typed answer is waited for 50 ms at most. Later than that the catalog is
// shown at once and the typed rows are merged when they land, so typing never waits on Hammerspoon.
//
// Choosing still runs in Hammerspoon, a typed row by its ref and a catalog row by the item the share
// carried, since bringing an app's windows forward needs Accessibility, which is the app toggler's
// step. Hammerspoon keeps the recency and the memory and hands both back, the recency in the share
// and the memory as the bridged launcher has it.

import AppKit
import Foundation
import OlmBridge
import CoreGraphics
import OlmKit

public actor NativeLauncher: ListSource {
  public nonisolated let manifest: Manifest
  public nonisolated var runsEveryVerb: Bool { false }

  /// Milliseconds a typed answer is waited for before the catalog is shown without it.
  public static let typedBudget = 50

  private let inner: BridgedLauncher
  /// The whole list asked of Hammerspoon, what an open takes while the launcherCatalog switch is off,
  /// nil for the shadow's, which is always the app's.
  private let fallback: BridgedLauncher?
  // Decided at each open, so a list never changes path while it is up.
  private var native = true
  private let shareURL: URL
  /// nil waits for every typed answer, the shadow's, which compares whole lists.
  private let budget: Int?
  private let say: @Sendable (String) -> Void

  private var share: CatalogShare?
  private var shareStamp: Date?
  private var shareChecked = Date.distantPast
  private var installed: [(bundleID: String, name: String)] = []
  private var scanned = Date.distantPast
  private var built: Catalog.Built?
  private var ownerIcons: [String: [String: Icon]] = [:]
  private var waiting: (query: String, task: Task<(RowsAnswer, Bool)?, Never>)?
  private var unknownGates: Set<String> = []
  /// Whether the last answer was a claim, set when the app answered the typed rows itself.
  private var localClaimed: Bool?
  /// Convert, run by the app where qalc is installed, step 6.10b.
  private let convert = Convert(tool: Convert.find())
  /// The query whose conversion the next rowsLanded runs.
  private var converts: String?
  /// The rows of the plugins the app runs, and the list each opens, docs/DESIGN-APP-PLUGINS.md.
  private let externals: @Sendable () -> [Row]
  private let external: @Sendable (String) async -> (any ListSource)?
  static let externalPrefix = "plugin:"

  /// Seconds a scan of the applications is kept before an open scans again.
  static let scanAge: TimeInterval = 30

  public init(inner: BridgedLauncher, fallback: BridgedLauncher? = nil, run: URL,
              budget: Int? = NativeLauncher.typedBudget,
              say: @escaping @Sendable (String) -> Void = { NSLog("Olm launcher: %@", $0) },
              externals: @escaping @Sendable () -> [Row] = { [] },
              external: @escaping @Sendable (String) async -> (any ListSource)? = { _ in nil }) {
    self.externals = externals
    self.external = external
    self.inner = inner
    self.fallback = fallback
    self.manifest = inner.manifest
    shareURL = run.appendingPathComponent("launchercatalog.json")
    self.budget = budget
    self.say = say
  }

  // MARK: The catalog

  private func refresh(force: Bool = false) async {
    let now = Date()
    if force || now.timeIntervalSince(shareChecked) > 1 {
      shareChecked = now
      let stamp = (try? FileManager.default.attributesOfItem(atPath: shareURL.path))?[.modificationDate] as? Date
      if stamp != shareStamp || share == nil {
        shareStamp = stamp
        if let data = try? Data(contentsOf: shareURL), let parsed = CatalogShare.parse(data) {
          share = parsed
        } else if share == nil {
          say("no catalog share at \(shareURL.path) yet")
        }
      }
    }
    if force || now.timeIntervalSince(scanned) > Self.scanAge {
      scanned = now
      installed = AppScan.installed()
    }
    guard let share else {
      built = nil
      return
    }
    if inner.shown {
      // The calculator's icon too, which a row the app makes itself wears.
      let owners = Set(share.entries.compactMap { $0.icon["owner"].string } + (share.gate?.sources.sorted() ?? []))
      if !owners.isSubset(of: Set(ownerIcons.keys)) { ownerIcons = await inner.icons(owners) }
    }
    let icons = ownerIcons
    let apps = AppScan.listed(installed: installed, running: AppScan.running())
    for name in Set(share.entries.compactMap(\.when)) where gate(name) == nil && unknownGates.insert(name).inserted {
      say("a gate the app does not answer yet, \(name), so its rows are hidden as the Lua catalog hides them")
    }
    built = Catalog.build(share, apps: apps, gate: { [self] in gate($0) }, icon: { spec in
      if let id = spec["app"].string { return .app(id) }
      if let name = spec["sf"].string { return .symbol(name) }
      if let glyph = spec["emoji"].string { return .emoji(glyph) }
      if let owner = spec["owner"].string, let key = spec["key"].string { return icons[owner]?[key] }
      return nil
    })
  }

  // The gates the app answers itself, by the Lua predicate's name, nil for one it does not know.
  private nonisolated func gate(_ name: String) -> Bool? {
    switch name {
    case "multipleDisplays":
      var count: UInt32 = 0
      CGGetActiveDisplayList(0, nil, &count)
      return count > 1
    default: return nil
    }
  }

  // MARK: ListSource

  public func open(query: String) async -> Level {
    await refresh(force: true)
    native = fallback == nil || (share?.inApp ?? false)
    if !native, let fallback { return await fallback.open(query: query) }
    return await inner.open(query: query)
  }

  public func prepare() async -> RowsAnswer? {
    await refresh(force: true)
    guard fallback == nil || (share?.inApp ?? false) else { return nil }
    return built.map { RowsAnswer(rows: $0.rows + externals()) }
  }

  public func rows(_ query: Query) async throws -> RowsAnswer {
    if !native, let fallback { return try await fallback.rows(query) }
    await refresh()
    waiting?.task.cancel()
    waiting = nil
    guard let built else {
      // No share yet, a first load, so the list is Hammerspoon's whole, as before 6.1.
      return try await inner.rows(query)
    }
    let memory = await inner.memorySnapshot()
    let catalog = Catalog.withBonus(built, memory: memory, query: query.text) + externals()
    localClaimed = nil
    converts = nil
    if query.text.isEmpty { return RowsAnswer(rows: catalog) }
    // A query none of Hammerspoon's other sources can answer is the app's alone, the calculator's
    // and convert's.
    if let gate = localGate(), !gate.asks(query.text) {
      localClaimed = false
      let (typed, converting) = await typedHere(query.text)
      if converting { converts = query.text }
      return RowsAnswer(rows: typed + catalog, pending: converting)
    }
    let inner = self.inner
    let task = Task<(RowsAnswer, Bool)?, Never> {
      guard let answer = try? await inner.rows(query) else { return nil }
      return (answer, await inner.claimed)
    }
    if let budget {
      let outcome = await withTaskGroup(of: Outcome.self) { group in
        group.addTask { await task.value.map(Outcome.landed) ?? .failed }
        group.addTask {
          try? await Task.sleep(for: .milliseconds(budget))
          return .late
        }
        let first = await group.next() ?? .late
        group.cancelAll()
        return first
      }
      switch outcome {
      case .landed(let landed): return merge(landed, catalog)
      case .failed: return RowsAnswer(rows: catalog)
      case .late:
        waiting = (query.text, task)
        return RowsAnswer(rows: catalog, pending: true)
      }
    }
    guard let landed = await task.value else { return RowsAnswer(rows: catalog) }
    return merge(landed, catalog)
  }

  public func rowsLanded(_ query: Query) async throws -> RowsAnswer? {
    if !native, let fallback { return try await fallback.rowsLanded(query) }
    if converts == query.text {
      converts = nil
      return try await converted(query)
    }
    guard let w = waiting, w.query == query.text else { return nil }
    waiting = nil
    guard let landed = await w.task.value, let built else { return nil }
    let catalog = Catalog.withBonus(built, memory: await inner.memorySnapshot(), query: query.text) + externals()
    return merge(landed, catalog)
  }

  // MARK: The typed rows the app answers itself

  static let calcPrefix = "calc:"

  /// The gate with what the app answers itself taken out, convert where qalc is here, nil from a
  /// share that carries none.
  private func localGate() -> TypedGate? {
    guard var gate = share?.gate else { return nil }
    if convert.tool != nil { gate.sources.remove("convert") }
    return gate
  }

  /// The calculator's row and convert's, each where Hammerspoon wired it, as the Lua rows read, and
  /// whether a conversion is still running, its row then the Lua placeholder.
  private func typedHere(_ query: String) async -> ([Row], Bool) {
    let sources = share?.gate?.sources ?? []
    if sources.contains("arithmetic"), let value = Arithmetic.answer(query) {
      return ([Row(key: Self.calcPrefix + value, title: value, subtitle: "Copy the result",
        icon: ownerIcons["arithmetic"]?["arithmetic"], fromQuery: true)], false)
    }
    guard sources.contains("convert"), convert.tool != nil, Convert.parts(query) != nil else { return ([], false) }
    let icon = ownerIcons["convert"]?["convert"]
    switch await convert.cached(query) {
    case .value(let value)?:
      return ([Row(key: Self.calcPrefix + value, title: value, subtitle: "Copy the result", icon: icon, fromQuery: true)], false)
    case .miss?:
      return ([], false)
    case nil:
      return ([Row(key: "convert:pending", title: "Converting", icon: icon, fromQuery: true, inert: true)], true)
    }
  }

  /// The conversion's answer once typing has paused. The Lua plugin waits a quarter second, since
  /// each run there is a process the list waits on. Here a run is off the list's path and a newer
  /// keystroke cancels this wait, so a short pause only keeps a burst of keys from starting one run
  /// each.
  private func converted(_ query: Query) async throws -> RowsAnswer? {
    try await Task.sleep(for: .milliseconds(80))
    _ = await convert.convert(query.text)
    try Task.checkCancellation()
    return try await rows(query)
  }

  private enum Outcome: Sendable {
    case landed((RowsAnswer, Bool))
    case failed
    case late
  }

  // The typed rows lead, as rank.lua leads fromQuery rows, and a claim is the whole list.
  private func merge(_ landed: (RowsAnswer, Bool), _ catalog: [Row]) -> RowsAnswer {
    let (typed, claimed) = landed
    if claimed { return typed }
    return RowsAnswer(rows: typed.rows + catalog, rankText: typed.rankText)
  }

  /// The keys the Lua shadow names its rows by, every remembered row's, in order.
  public func remembered(_ rows: [Row]) async -> [String] {
    if !native, let fallback { return await fallback.remembered(rows) }
    let typed = Set(await inner.remembered(rows))
    let mine = built?.remembered ?? []
    return rows.map(\.key).filter { mine.contains($0) || typed.contains($0) }
  }

  /// Whether the last answer was a claim, the typed rows being the whole list.
  public var claimed: Bool {
    get async {
      if !native, let fallback { return await fallback.claimed }
      if let localClaimed { return localClaimed }
      return await inner.claimed
    }
  }

  public func choose(_ pick: Pick) async -> [Effect] {
    if !native, let fallback { return await fallback.choose(pick) }
    if pick.key.hasPrefix(Self.externalPrefix) { return [.push(pick.key)] }
    if pick.key.hasPrefix(Self.calcPrefix) {
      // As the Lua calc row's run, the result on the pasteboard once the list is gone.
      let value = String(pick.key.dropFirst(Self.calcPrefix.count))
      await MainActor.run {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
      }
      return [.hide]
    }
    if await inner.holds(pick.key) { return await inner.choose(pick) }
    guard let item = built?.items[pick.key] else { return [] }
    return await inner.chooseItem(item, query: pick.query)
  }

  public func run(_ action: String, on pick: Pick) async -> [Effect] { [] }

  public func pushed(_ token: String) async -> (any ListSource)? {
    if token.hasPrefix(Self.externalPrefix) { return await external(String(token.dropFirst(Self.externalPrefix.count))) }
    if !native, let fallback { return await fallback.pushed(token) }
    return await inner.pushed(token)
  }

  public func close() async {
    waiting?.task.cancel()
    waiting = nil
    if !native, let fallback { return await fallback.close() }
    await inner.close()
  }
}
