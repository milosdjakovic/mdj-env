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
// olm://apps-plan?bundles=A,B&hides=0 writes what a press on each app would do, changing nothing.
// olm://settings shows the Olm Settings window, docs/DESIGN-APP-SETTINGS.md, drawn from the share
// Hammerspoon writes at every load.
// An olm:// URL never runs anything, and one this app does not know is logged and dropped.

import AppKit
import FileSearchPlugin
import OlmApps
import OlmBridge
import OlmKeys
import OlmLauncher
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

/// A value handed to the main thread that Swift cannot see is safe to send, JSON from the bridge
/// that nothing else holds.
struct UncheckedSendable<T>: @unchecked Sendable {
  let value: T
  init(_ value: T) { self.value = value }
}

/// What macOS lets the app do, written for the setup's grants-probe, which can only ask the app,
/// ~/.olm/state/app/grants.json. Each grant is told by whoever checks it, on its own thread.
final class Grants: @unchecked Sendable {
  private let lock = NSLock()
  private var said: [String: Bool] = [:]
  private let url: URL
  init(_ url: URL) { self.url = url }

  func tell(_ name: String, _ allowed: Bool) {
    lock.lock()
    defer { lock.unlock() }
    said[name] = allowed
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let data = try? JSONSerialization.data(withJSONObject: said, options: [.sortedKeys]) {
      try? (data + Data("\n".utf8)).write(to: url, options: .atomic)
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let searcher = Searcher()
  private lazy var stage = Stage(searcher: searcher)
  private let sources: [String: any ListSource]
  private let shadows: [String: Shadow]
  // The catalog's shadow, reached by the tee over the launcher in use, step 6.1.
  @MainActor enum CatalogCompare { static var shadow: Shadow? }
  // The keys in shadow and the tap it hears through, step 5.1, held for the app's life.
  private var keyShadow: KeyShadow?
  private var keyTap: KeyTap?
  // Bringing an app forward, step 6.2, docs/DESIGN-APP-APPS.md, and whether it may, checked every ten
  // seconds and told to Hammerspoon on a change.
  private let appFocus = AppFocus(shadow: AppShadow(log: olm.appendingPathComponent("log")),
    log: { NSLog("Olm apps: %@", $0) })
  private var appsAllowed = AppFocus.allowed
  private var appsTimer: Timer?
  // The leaders whose modifier combinations the app claims, step 5.3, docs/DESIGN-APP-KEYS.md.
  private var keyOwner: KeyOwner?
  // The leaders' cheat sheets, step 5.2, drawn from what Hammerspoon laid out.
  private let sheets = SheetHost()
  private let bridge = Bridge(path: context.run.appendingPathComponent("bridge.sock").path)
  private let bridgedLauncher: BridgedLauncher
  private let shownLauncher: BridgedLauncher
  private let typedLauncher: BridgedLauncher
  private let launcherShadow: Shadow
  // The Olm Settings window, its changes sent over the bridge, S.3 of docs/DESIGN-APP-SETTINGS.md.
  private lazy var settingsWindow = SettingsWindow(service: Self.settingsService(bridge),
    permissions: Self.permissions())

  /// Every permission the app uses, for the Permissions page of Olm Settings: Accessibility for
  /// bringing an app forward, Input Monitoring for hearing the keys, and the three folders file
  /// search reads. A folder is probed only once file search has asked about it, since probing one
  /// never answered raises macOS's prompt, and the probe opens it without listing it.
  static func permissions() -> [Permission] {
    let access = FolderAccess(home: home, store: context.store)
    let folders = access.folders.map { folder in
      Permission(id: "folder." + folder.name, title: "\(folder.name) Folder",
        detail: "File search finding files in \(folder.name)", symbol: "folder",
        settingsURL: FolderAccess.settingsURL,
        check: {
          guard access.load().asked else { return false }
          guard let dir = opendir(folder.path) else { return false }
          closedir(dir)
          return true
        },
        ask: { DispatchQueue.global(qos: .userInitiated).async { _ = FolderAccess.readable(folder) } })
    }
    return [
      Permission(id: "accessibility", title: "Accessibility",
        detail: "Bringing an app forward, cycling its windows, hiding and placing it",
        symbol: "macwindow.on.rectangle",
        settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        check: { AppFocus.allowed }, ask: { AppFocus.ask() }),
      Permission(id: "inputMonitoring", title: "Input Monitoring",
        detail: "Hearing the keyboard, the leader keys",
        symbol: "keyboard",
        settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
        check: { KeyTap.allowed }, ask: { KeyTap.ask() }),
    ] + folders
  }

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
    // The shadow's launcher, Hammerspoon's whole list, which the launcher in use is compared with,
    // step 6.1, docs/DESIGN-APP-LAUNCHER.md.
    let launcher = BridgedLauncher(bridge: bridge)
    // File Search's row and its typed word push the app's own file search over the launcher, step
    // 3.3e, the same source its own key opens.
    let natives: [String: any ListSource] = [fileSearch.manifest.name: fileSearch]
    let shownLauncher = BridgedLauncher(bridge: bridge, shown: true, natives: natives)
    self.shownLauncher = shownLauncher
    // The launcher a person opens since step 6.1, its catalog built in the app and only the typed rows
    // asked of Hammerspoon, or the whole list asked as before while the launcherCatalog switch is off.
    let typedLauncher = BridgedLauncher(bridge: bridge, shown: true, typed: true, natives: natives)
    self.typedLauncher = typedLauncher
    let inUse = NativeLauncher(inner: typedLauncher, fallback: shownLauncher, run: context.run)
    // Passed through a tee, so each answer it settles on once typing pauses is compared with what
    // Hammerspoon's whole list would have been. A list a typed word handed over is left out.
    let compared = ShadowTee(inUse) { [searcher] query, answer, level in
      guard answer.handOver == nil else { return }
      let ranked = await searcher.rank(answer, query: query, level: level)
      let kept = ranked.rows.filter { !$0.pinned && !$0.fromQuery }
      let keys = await inUse.remembered(kept)
      let claimed = await inUse.claimed
      await MainActor.run { CatalogCompare.shadow?.settled(query: query, keys: keys, status: answer.status, claimed: claimed) }
    }
    sources = [fileSearch.manifest.name: fileSearch, shownLauncher.manifest.name: compared]
    // The shadow answers on a source of its own, so a list a person has open is never touched.
    let shadowed = FileSearchSource(context: context)
    shadows = [shadowed.manifest.name: Shadow(tool: shadowed.manifest.name, source: shadowed,
      searcher: searcher, run: context.run, log: olm.appendingPathComponent("log"),
      skip: { FileSearchSource.shadowSkip($0, settings: .read(from: context.run)) })]
    bridgedLauncher = launcher
    launcherShadow = Shadow(tool: launcher.manifest.name, source: launcher, searcher: searcher,
      run: context.run, log: olm.appendingPathComponent("log"), skip: { _ in nil },
      named: { await launcher.remembered($0) }, toldAs: "app", answeredAs: "lua")
    Self.CatalogCompare.shadow = launcherShadow
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
    // The keys in shadow, step 5.1, docs/DESIGN-APP-KEYS.md. The app hears every press, resolves it
    // against the keymap Hammerspoon compiled and pairs it with what Hammerspoon ran. A list of the
    // app's own being up leaves its presses to it. Input Monitoring is asked for once, by macOS's own
    // prompt, and the tap keeps trying until it is given.
    let keyShadow = KeyShadow(run: context.run, log: olm.appendingPathComponent("log"))
    self.keyShadow = keyShadow
    keyShadow.start()
    if !KeyTap.allowed { KeyTap.ask() }
    // Whether macOS lets the app hear the keyboard, written for the setup's grants-probe, which can
    // only ask the app, ~/.olm/state/app/grants.json.
    let grants = Grants(olm.appendingPathComponent("state/app/grants.json"))
    let keyTap = KeyTap(handle: { keyShadow.heard($0) }, log: { NSLog("Olm keys: %@", $0) }, report: { allowed in
      grants.tell("inputMonitoring", allowed)
    })
    self.keyTap = keyTap
    keyTap.start()
    Task { await bridge.onKeyFired { keyShadow.fired($0) } }
    // A press on an app Hammerspoon hands over, step 6.2, run on the app's own queue, and whether it
    // may, said once each session opens and again on a change. Accessibility is asked for once, by
    // macOS's own prompt, and until it is given Hammerspoon runs every press as before.
    let appFocus = appFocus
    let bridgeForApps = bridge
    // The motion every surface shares, before any of them shows, Look.applyMotion.
    Look.applyMotion()
    if !appsAllowed { AppFocus.ask() }
    grants.tell("accessibility", appsAllowed)
    Task {
      await bridgeForApps.onAppRun { params in
        if let press = AppPress(params) { appFocus.run(press) }
      }
      // A leader's cheat sheet Hammerspoon laid out, drawn here, step 5.2, docs/DESIGN-APP-KEYS.md.
      let sheets = self.sheets
      await bridgeForApps.onSheet { params in
        let box = UncheckedSendable(params)
        Task { @MainActor in sheets.take(box.value) }
      }
      // The keys the app claims, step 5.3. Asked each time a session opens and each time Hammerspoon
      // says its leaders started, the keymap read afresh, and every claim dropped as the session goes.
      let owner = KeyOwner(words: KeyOwner.Words(
        release: { names in
          let answer = try? await bridgeForApps.request("releaseKeys", .object(["leaders": .array(names.map { .string($0) })]))
          return answer?["released"].array?.compactMap(\.string) ?? []
        },
        reclaim: { names in
          _ = try? await bridgeForApps.request("reclaimKeys", .object(["leaders": .array(names.map { .string($0) })]))
        },
        run: { id, depth in
          _ = try? await bridgeForApps.request("runKey", .object(["id": .string(id), "depth": .number(Double(depth))]))
        }),
        gate: { name in
          guard name == "multipleDisplays" else { return true }
          var count: UInt32 = 0
          CGGetActiveDisplayList(0, nil, &count)
          return count > 1
        },
        log: { NSLog("Olm keys: %@", $0) })
      // What the app holds, ~/.olm/run/keys-owned.json, each leader with its combinations' count, so a
      // look from outside the app reads it rather than guessing.
      let ownedURL = context.run.appendingPathComponent("keys-owned.json")
      await MainActor.run {
        owner.onChange = { held in
          let doc: [String: Any] = ["held": held, "updated": ISO8601DateFormatter().string(from: Date())]
          if let data = try? JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys]) {
            try? data.write(to: ownedURL, options: .atomic)
          }
        }
        self.keyOwner = owner
      }
      let keymapURL = context.run.appendingPathComponent("keymap.json")
      let takeKeys: @Sendable () -> Void = {
        Task { @MainActor in
          guard let keymap = try? Keymap.read(keymapURL) else { return }
          await owner.take(keymap)
        }
      }
      await bridgeForApps.onOpen(takeKeys)
      await bridgeForApps.onKeysReady(takeKeys)
      await bridgeForApps.onClose { Task { @MainActor in owner.drop() } }
      await bridgeForApps.onOpen {
        Task { await bridgeForApps.notify("appsReady", .object(["ready": .bool(AppFocus.allowed)])) }
      }
      // The motion every surface shares, read again as Hammerspoon connects, since a load may have
      // moved it, Look.applyMotion.
      await bridgeForApps.onOpen { Task { @MainActor in Look.applyMotion() } }
    }
    appsTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        let now = AppFocus.allowed
        guard now != self.appsAllowed else { return }
        self.appsAllowed = now
        grants.tell("accessibility", now)
        NSLog("Olm apps: Accessibility is %@", now ? "allowed" : "not allowed")
        Task { await bridgeForApps.notify("appsReady", .object(["ready": .bool(now)])) }
      }
    }
    stage.onShowing = { tool, up in
      keyShadow.list(up: up)
      DistributedNotificationCenter.default().postNotificationName(Notification.Name("local.olm.Olm.state"),
        object: "\(tool):\(up ? "up" : "down")", userInfo: nil, deliverImmediately: true)
    }
    DistributedNotificationCenter.default().addObserver(self, selector: #selector(verbNote(_:)),
      name: Notification.Name("local.olm.Olm.verb"), object: nil, suspensionBehavior: .deliverImmediately)
    DistributedNotificationCenter.default().addObserver(self, selector: #selector(askNote(_:)),
      name: Notification.Name("local.olm.Olm.ask"), object: nil, suspensionBehavior: .deliverImmediately)
    // The bridge, step 2.3. Each answer the Lua launcher settles on comes as the shadow notification.
    let bridge = bridge, launcher = bridgedLauncher, shown = shownLauncher, typed = typedLauncher
    stage.onTextBudget = { budget in Task { await bridge.setTextBudget(budget) } }
    // Command and comma in any list, docs/DESIGN-APP-SETTINGS.md S.4. Handed to LaunchServices as
    // olm://settings, the way Hammerspoon's row opens it, rather than shown here, since the panel never
    // makes the app active and an app may only ask to come forward, which the app in front declines,
    // so a window shown here opened behind it. Found on 2026-11-20 when Command and comma in the
    // launcher closed it and showed nothing.
    stage.onOpenSettings = {
      guard let url = URL(string: "olm://settings") else { return }
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      NSWorkspace.shared.open(url, configuration: configuration)
    }
    // The settings window built ahead, hidden, so its first open is quick and does not flicker.
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.settingsWindow.prepare() }
    Task {
      // What the Lua launcher settles on is no longer compared, since from step 6.1 the shadow
      // compares the launcher in use with Hammerspoon's whole list, through the tee above.
      await bridge.attach(launcher: launcher, shown: shown, also: [typed], settled: { _ in })
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
      } else if url.host == "apps-plan" {
        // What a press on each app named would do now, written to ~/.olm/run/apps-plan.json and
        // changing nothing, so the live check compares it with lib/appfocus.lua's plan, step 6.2.
        let bundles = (item("bundles") ?? "").split(separator: ",").map(String.init)
        let hides = item("hides") == "1", appFocus = appFocus
        let out = context.run.appendingPathComponent("apps-plan.json")
        DispatchQueue.global().async {
          var doc: [String: Any] = ["allowed": AppFocus.allowed]
          doc["plans"] = appFocus.plans(bundles, hides: hides).mapValues { p -> [String: Any] in
            var o: [String: Any] = ["outcome": p.outcome.rawValue]
            if let w = p.window { o["window"] = Int(w) }
            return o
          }
          if let data = try? JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys]) {
            try? data.write(to: out, options: .atomic)
          }
        }
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
