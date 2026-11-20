// Olm.app's composition root, docs/DESIGN-APP.md, and the only file that names a concrete plugin.
// It builds the stage, constructs every source, registers it under its manifest's name and answers
// olm:// URLs, docs/PROTOCOL-BRIDGE.md, by asking the stage to open a list. Nothing else lives here.
//
// It runs as an accessory, so it has no Dock icon and no menu bar, and keeps one instance.
// olm://ping?nonce=N answers a test, Ping.swift. olm://<name>?screen=MODE&query=TEXT opens the
// source registered under that name with TEXT in its input field, on the screen MODE names.
// olm://shadow?tool=<name>&id=N compares the Lua list's answer with the app's, OlmCore's Shadow, and
// the distributed notification local.olm.Olm.shadow, object "<name>:<N>", asks the same, which is
// how host/bridge asks it.
// The bridge's socket, ~/.olm/run/bridge.sock, is listened on from launch, step 2.3, and the launcher
// Hammerspoon serves over it is shadowed, each answer the Lua launcher settles on ranked again here
// and every difference logged to ~/.olm/log/shadow-launcher.jsonl. olm://launcher shows the app's own
// launcher, a second bridged launcher with a level for each show, opened by the trial key of step
// 3.2, docs/DESIGN-APP-LAUNCHER.md, while Hyper and Space still opens the Lua one.
// olm://settings shows the Olm Settings window, docs/DESIGN-APP-SETTINGS.md, drawn from the share
// Hammerspoon writes at every load.
// An olm:// URL never runs anything, and one this app does not know is logged and dropped.

import AppKit
import FileSearchPlugin
import OlmBridge
import OlmCore
import OlmKit
import OlmSettings

let home = FileManager.default.homeDirectoryForCurrentUser
let olm = home.appendingPathComponent(".olm")
let context = PluginContext(
  run: olm.appendingPathComponent("run"),
  cache: olm.appendingPathComponent("cache"),
  resources: Bundle.main.resourceURL ?? URL(fileURLWithPath: "."),
  store: olm.appendingPathComponent("state/filesearch"))

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let searcher = Searcher()
  private lazy var stage = Stage(searcher: searcher)
  private let sources: [String: any ListSource]
  private let shadows: [String: Shadow]
  private let bridge = Bridge(path: context.run.appendingPathComponent("bridge.sock").path)
  private let bridgedLauncher: BridgedLauncher
  private let shownLauncher: BridgedLauncher
  private let launcherShadow: Shadow
  // The Olm Settings window, its changes sent over the bridge, S.3 of docs/DESIGN-APP-SETTINGS.md.
  private lazy var settingsWindow = SettingsWindow(service: Self.settingsService(bridge))

  // The tools the serves share names, none where it is missing or names none.
  static func served(in run: URL) -> [String] {
    guard let data = try? Data(contentsOf: run.appendingPathComponent("serves.json")),
      let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
    return doc["tools"] as? [String] ?? []
  }

  /// The window's two words over the bridge, a change answered with the share as Hammerspoon now
  /// holds it, and done once the window closes.
  static func settingsService(_ bridge: Bridge) -> SettingsService {
    SettingsService(change: { id, value, reset in
      do {
        let answer = try await bridge.request("setting", .object(["id": .string(id), "value": JSON(value.any),
          "reset": .bool(reset)]))
        guard case .object(let o) = answer else { return SettingAnswer(ok: false, why: "was answered oddly", share: nil) }
        let share = o["share"].flatMap { try? JSONSerialization.data(withJSONObject: $0.any) }.flatMap(SettingsShare.parse)
        return SettingAnswer(ok: o["ok"] == .bool(true), why: o["why"]?.string, share: share)
      } catch {
        return SettingAnswer(ok: false, why: "was not changed, Hammerspoon did not answer (\(error))", share: nil)
      }
    }, done: {
      _ = try? await bridge.request("settingsDone", .object([:]))
    })
  }

  override init() {
    // OLM_DEMO_DOWNLOAD=0.6 stands Download still at that fraction, to look at the meter.
    let demo = ProcessInfo.processInfo.environment["OLM_DEMO_DOWNLOAD"].flatMap(Double.init)
    let fileSearch = FileSearchSource(context: context, asksAccess: true,
      frecency: FileSearchSource.frecency(context), cloud: demo.map { CloudFiles.demo(fraction: $0) } ?? .system,
      build: FileSearchSource.indexBuild(context))
    let launcher = BridgedLauncher(bridge: bridge)
    // File Search's row and its typed word push the app's own file search over the launcher, step
    // 3.3e, the same source its own key opens.
    let shownLauncher = BridgedLauncher(bridge: bridge, shown: true, natives: [fileSearch.manifest.name: fileSearch])
    self.shownLauncher = shownLauncher
    sources = [fileSearch.manifest.name: fileSearch, shownLauncher.manifest.name: shownLauncher]
    // The shadow answers on a source of its own, so a list a person has open is never touched.
    let shadowed = FileSearchSource(context: context)
    shadows = [shadowed.manifest.name: Shadow(tool: shadowed.manifest.name, source: shadowed,
      searcher: searcher, run: context.run, log: olm.appendingPathComponent("log"),
      skip: { FileSearchSource.shadowSkip($0, settings: .read(from: context.run)) })]
    bridgedLauncher = launcher
    launcherShadow = Shadow(tool: launcher.manifest.name, source: launcher, searcher: searcher,
      run: context.run, log: olm.appendingPathComponent("log"), skip: { _ in nil },
      named: { await launcher.remembered($0) })
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // LaunchServices keeps one instance for a bundle it opens, LSMultipleInstancesProhibited in
    // Info.plist. A second copy started some other way, the executable run by hand, leaves at once.
    let me = NSRunningApplication.current
    let others = NSRunningApplication.runningApplications(
      withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.olm.Olm"
    ).filter { $0.processIdentifier != me.processIdentifier }
    if !others.isEmpty {
      NSLog("Olm: another instance is running, pid %d, leaving", others[0].processIdentifier)
      NSApp.terminate(nil)
      return
    }
    // Each answer the Lua list settles on is told by a distributed notification whose object is
    // "<tool>:<id>", host/bridge's _tell, rather than olm://shadow, since running open while the
    // Lua list was up left it with no rows, found in the 1.3f trial on 2026-11-08.
    DistributedNotificationCenter.default().addObserver(self, selector: #selector(shadowNote(_:)),
      name: Notification.Name("local.olm.Olm.shadow"), object: nil, suspensionBehavior: .deliverImmediately)
    // A served key tells the running app its olm:// URL the same way, host/bridge's serves, some
    // fifty milliseconds sooner than open, measured in the 1.4a trial on 2026-11-08.
    DistributedNotificationCenter.default().addObserver(self, selector: #selector(openNote(_:)),
      name: Notification.Name("local.olm.Olm.open"), object: nil, suspensionBehavior: .deliverImmediately)
    // The tools Hammerspoon hands the app, host/bridge's serves share, kept warm while hidden.
    let sources = self.sources
    stage.keepWarm { Self.served(in: context.run).compactMap { sources[$0] } }
    // A served tool's own list pushed over the launcher takes its keys with it, step 3.4.
    stage.servesKeys = { Self.served(in: context.run).contains($0.lowercased()) }
    // List keys, step 1.4f, docs/DESIGN-APP-LIST-KEYS.md. The stage says up and down, a list verb
    // Hammerspoon's leaders heard comes back as "<tool>:<verb>", and an ask answers the state.
    stage.onShowing = { tool, up in
      DistributedNotificationCenter.default().postNotificationName(Notification.Name("local.olm.Olm.state"),
        object: "\(tool):\(up ? "up" : "down")", userInfo: nil, deliverImmediately: true)
    }
    DistributedNotificationCenter.default().addObserver(self, selector: #selector(verbNote(_:)),
      name: Notification.Name("local.olm.Olm.verb"), object: nil, suspensionBehavior: .deliverImmediately)
    DistributedNotificationCenter.default().addObserver(self, selector: #selector(askNote(_:)),
      name: Notification.Name("local.olm.Olm.ask"), object: nil, suspensionBehavior: .deliverImmediately)
    // The bridge, step 2.3. Each answer the Lua launcher settles on comes as the shadow notification.
    let bridge = bridge, launcher = bridgedLauncher, shadow = launcherShadow, shown = shownLauncher
    stage.onTextBudget = { budget in Task { await bridge.setTextBudget(budget) } }
    // Command and comma in any list, docs/DESIGN-APP-SETTINGS.md S.4.
    stage.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
    Task {
      await bridge.attach(launcher: launcher, shown: shown, settled: { s in
        guard s.tool == launcher.manifest.name else { return }
        Task { @MainActor in shadow.settled(query: s.query, keys: s.keys, status: s.status, claimed: s.claimed) }
      })
      // A hosted list's redraw asked by its tool, a timed session ending, step 3.3, where it is up.
      let stage = self.stage
      await bridge.onRedraw { list, hold in Task { @MainActor in stage.redraw(list, hold: hold) } }
      await bridge.onEffects { list, effects in Task { @MainActor in stage.applyEffects(list, effects) } }
      // What a hosted list's pane drew in Lua, step 3.3d, drawn where it is up.
      await bridge.onPaneDrawn { list, drawing in Task { @MainActor in stage.drawn(list, drawing) } }
      if let why = await bridge.start() { NSLog("Olm: the bridge's socket is not listening, %@", why) }
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    let bridge = bridge
    let done = DispatchSemaphore(value: 0)
    Task.detached { await bridge.stop(); done.signal() }
    _ = done.wait(timeout: .now() + 0.5)
  }

  @objc private func verbNote(_ note: Notification) {
    guard let object = note.object as? String else { return }
    let parts = object.split(separator: ":")
    guard parts.count == 2 else { return }
    stage.verb(String(parts[0]), String(parts[1]))
  }

  @objc private func askNote(_ note: Notification) { stage.tellState() }

  @objc private func openNote(_ note: Notification) {
    guard let object = note.object as? String, let url = URL(string: object) else { return }
    application(NSApp, open: [url])
  }

  @objc private func shadowNote(_ note: Notification) {
    guard let object = note.object as? String else { return }
    let parts = object.split(separator: ":")
    guard parts.count == 2, let shadow = shadows[String(parts[0])], let id = Int(parts[1]) else { return }
    shadow.run(id: id)
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      guard url.scheme == "olm" else { continue }
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      func item(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
      if let nonce = Ping.nonce(url) {
        Ping.answer(nonce, in: context.run)
      } else if url.host == "shadow", let tool = item("tool"), let shadow = shadows[tool],
        let id = item("id").flatMap({ Int($0) }) {
        shadow.run(id: id)
      } else if url.host == "settings" {
        settingsWindow.show()
      } else if url.host == "tool", let name = item("name") {
        // A tool's own key, step 3.8, its hosted list asked of the Lua side first and then opened.
        let launcher = shownLauncher, stage = stage
        let query = item("query") ?? "", screen = item("screen")
        // Its cycle key, step 3.9, the list shown bare, a press heard before it is up counted.
        let cycle = item("cycle") == "1"
        if cycle { stage.expectCycle(name) }
        Task { @MainActor in
          guard let level = await launcher.openTool(name, query: query, cycle: cycle) else { return }
          stage.open(level, query: query, screen: screen, cycle: cycle ? (level.cycleIdle ?? 0.8) : nil)
        }
      } else if let host = url.host, let source = sources[host] {
        stage.open(source, query: item("query") ?? "", screen: item("screen"))
      } else {
        NSLog("Olm: an olm URL this app does not know, %@", url.absoluteString)
      }
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
