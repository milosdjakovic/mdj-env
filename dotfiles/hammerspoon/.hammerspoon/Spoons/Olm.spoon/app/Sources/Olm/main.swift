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
// An http or https link, Olm being the default browser, is handed on by Links.swift.

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
  // The window manager in shadow, step 6.3b, docs/DESIGN-APP-WINDOWS.md: each META window key read
  // here before Hammerspoon runs it, and compared with what Hammerspoon read and planned.
  private let windowShadow = WindowShadow(log: olm.appendingPathComponent("log"))
  // The window manager run here once windowsInApp is on, step 6.3b, its refusals in the same log.
  private lazy var windowRun = WindowRun(shadow: windowShadow)
  /// The window manager's settings as Olm's settings share holds them, by each setting's key.
  /// The numbers by each setting's key, and the named sizes by the action each is, read again only
  /// when the share's file changed, since a held key asks on every repeat.
  nonisolated static func windowSettings() -> WindowSettings? {
    let stamp = (try? FileManager.default.attributesOfItem(atPath: SettingsShare.path.path))?[.modificationDate] as? Date
    if let cached = WindowSettingsCache.shared.get(stamp) { return cached }
    guard let share = SettingsShare.read() else { return nil }
    var values: [String: Double] = [:]
    var sized: Setting?
    let prefix = "windowmanager."
    for setting in share.sections.flatMap(\.settings) where setting.id.hasPrefix(prefix) {
      if let n = setting.value.number { values[String(setting.id.dropFirst(prefix.count))] = n }
      if setting.kind == .sizes { sized = setting }
    }
    guard !values.isEmpty else { return nil }
    var settings = WindowSettings(values: values)
    for action in sized?.windowActions ?? [] {
      guard let id = action.size, let z = sized?.value.sizes?.first(where: { $0.id == id }) else { continue }
      settings.sizes[action.action] = WindowNamedSize(width: z.width, height: z.height, percent: z.percent,
        anchor: z.anchor, display: z.display)
    }
    WindowSettingsCache.shared.set(stamp, settings)
    return settings
  }
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
  // The external plugins the app runs, docs/DESIGN-APP-PLUGINS.md, Browser Switcher the first.
  private let plugins: PluginHost
  // The Olm Settings window, its changes sent over the bridge, S.3 of docs/DESIGN-APP-SETTINGS.md.
  private lazy var settingsWindow = SettingsWindow(share: { ExternalPlugins.merged(SettingsShare.read()) },
    service: Self.settingsService(bridge), permissions: Self.permissions(), installer: plugins.installer)

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
      // What a plugin asks for, a browser's profiles, which macOS keeps in each browser's Application
      // Support folder from any program without it. Olm uses it for nothing of its own. Read by
      // opening a file only that access opens, since macOS has no question for it, so the button
      // only takes the person to the list.
      Permission(id: "fullDiskAccess", title: "Full Disk Access",
        detail: "Reading what macOS keeps private, for the plugins that ask",
        symbol: "externaldrive",
        settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        pluginsOnly: true,
        // Any of a few files only Full Disk Access opens, since which ones macOS guards moves between
        // versions, the user's TCC database alone answering not allowed with access given on 27.
        check: {
          let probes = [
            "Library/Safari/Bookmarks.plist",
            "Library/Application Support/com.apple.TCC/TCC.db",
            "Library/Application Support/Google/Chrome/Local State",
            "Library/Containers/com.apple.Safari/Data/Library/Safari/Bookmarks.plist",
          ].map { home.appendingPathComponent($0).path } + ["/Library/Application Support/com.apple.TCC/TCC.db"]
          for path in probes {
            if let handle = FileHandle(forReadingAtPath: path) { try? handle.close(); return true }
          }
          return false
        }),
      // Olm as the Mac's default browser, so the links clicked anywhere reach it and the plugin
      // receiving links. Changed in Desktop & Dock or by the Default Browser setting.
      Permission(id: "defaultBrowser", title: "Default Browser",
        detail: "Receiving the links you click",
        symbol: "globe",
        settingsURL: "x-apple.systempreferences:com.apple.Desktop-Settings.extension",
        ownUse: "Opening a link in Safari when no plugin takes it",
        check: {
          guard let probe = URL(string: "https://example.com"),
            let app = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return false }
          return Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier
        }),
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
  /// Set once the keys are first taken, the keys taken again with the keymap read afresh, so an app's
  /// key, mode or place changed in Olm Settings is live before the window has drawn the change.
  nonisolated(unsafe) static var retakeKeys: (@Sendable () -> Void)?

  static func settingsService(_ bridge: Bridge) -> SettingsService {
    SettingsService(change: { id, value, reset in
      // A plugin the app runs keeps its settings in the app's own store, never Hammerspoon's.
      if id.hasPrefix(ExternalPlugins.prefix) {
        let why = ExternalPlugins.change(id, value, reset: reset)
        return SettingAnswer(ok: why == nil, why: why, share: ExternalPlugins.merged(SettingsShare.read()))
      }
      do {
        let answer = try await bridge.request("setting", .object(["id": .string(id), "value": JSON(value.any),
          "reset": .bool(reset)]))
        guard case .object(let o) = answer else { return SettingAnswer(ok: false, why: "was answered oddly", share: nil) }
        let share = o["share"].flatMap { try? JSONSerialization.data(withJSONObject: $0.any) }.flatMap(SettingsShare.parse)
        let ok = o["ok"] == .bool(true)
        if ok, id == AppCatalog.settingId || id == AppCatalog.modeId { retakeKeys?() }
        return SettingAnswer(ok: ok, why: o["why"]?.string, share: share.flatMap { ExternalPlugins.merged($0) })
      } catch {
        return SettingAnswer(ok: false, why: "was not changed, Hammerspoon did not answer (\(error))", share: nil)
      }
    }, done: {
      _ = try? await bridge.request("settingsDone", .object([:]))
    }, importValues: { data in
      guard let values = JSON.decode(data),
        let answer = try? await bridge.request("settingsImport", .object(["values": values])),
        case .object(let o) = answer else { return (["values"], nil) }
      let refused = (o["refused"]?.array ?? []).compactMap { r -> String? in
        guard let id = r["id"].string else { return nil }
        return id + (r["why"].string.map { " " + $0 } ?? "")
      }
      let share = o["share"].flatMap { try? JSONSerialization.data(withJSONObject: $0.any) }.flatMap(SettingsShare.parse)
      return (refused, share.flatMap { ExternalPlugins.merged($0) })
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
    let plugins = PluginHost(bridge: bridge)
    self.plugins = plugins
    let inUse = NativeLauncher(inner: typedLauncher, fallback: shownLauncher, run: context.run,
      externals: { PluginHost.launcherRows() }, external: { id in await plugins.source(id) })
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
    // The browsers and their profiles for Browser Switcher, found once at launch and again before
    // each link and whenever its page is shown.
    DispatchQueue.global(qos: .utility).async { Browsers.refresh() }
    // The external plugins, each built when its sources moved and loaded, off the main thread.
    plugins.start()
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
    applySharedMotion()
    if !appsAllowed { AppFocus.ask() }
    grants.tell("accessibility", appsAllowed)
    Task {
      await bridgeForApps.onAppRun { params in
        guard let press = AppPress(params) else { return }
        // While the app keeps the catalog, its table says what a press does, not Lua's toggler.
        if AppsHeld.shared.keeps {
          appFocus.run(AppsHeld.shared.press(press.id, bundle: press.bundle))
        } else {
          appFocus.run(press)
        }
      }
      // A leader's cheat sheet Hammerspoon laid out, drawn here, step 5.2, docs/DESIGN-APP-KEYS.md.
      let sheets = self.sheets
      await bridgeForApps.onSheet { params in
        let box = UncheckedSendable(params)
        Task { @MainActor in sheets.take(box.value) }
      }
      // The keys the app claims, step 5.3. Asked each time a session opens and each time Hammerspoon
      // says its leaders started, the keymap read afresh, and every claim dropped as the session goes.
      let windowShadow = self.windowShadow
      let windowRun = self.windowRun
      let owner = KeyOwner(words: KeyOwner.Words(
        release: { names in
          let answer = try? await bridgeForApps.request("releaseKeys", .object(["leaders": .array(names.map { .string($0) })]))
          var lists: [String: [KeyOwner.ListCombo]] = [:]
          for (name, combos) in answer?["lists"].object ?? [:] {
            lists[name] = (combos.array ?? []).compactMap { c in
              guard let code = c["code"].number else { return nil }
              return KeyOwner.ListCombo(code: Int(code), mods: Set((c["mods"].array ?? []).compactMap { $0.string.flatMap(Mod.init(rawValue:)) }))
            }
          }
          return KeyOwner.Released(leaders: answer?["released"].array?.compactMap(\.string) ?? [], lists: lists)
        },
        reclaim: { names in
          _ = try? await bridgeForApps.request("reclaimKeys", .object(["leaders": .array(names.map { .string($0) })]))
        },
        run: { id, depth in
          // An app's key the app keeps, step 6.2b, run here with the table's mode and place,
          // Hammerspoon told only so Hyper's sheet goes down. Without Accessibility it goes to
          // Hammerspoon's own action for the app where its catalog has one.
          if id.hasPrefix(AppCatalog.prefix) {
            let bundle = String(id.dropFirst(AppCatalog.prefix.count))
            if AppFocus.allowed {
              appFocus.run(AppsHeld.shared.press(id, bundle: bundle))
              let leader = AppsHeld.shared.leader(bundle).map { JSON.string($0) } ?? .null
              await bridgeForApps.notify("keyRan", .object(["id": .string(id), "leader": leader]))
            } else if let lua = AppsHeld.shared.luaAction(bundle) {
              _ = try? await bridgeForApps.request("runKey", .object(["id": .string(lua), "depth": .number(0)]))
            } else {
              NSLog("Olm apps: %@'s key was pressed without Accessibility, so nothing ran", bundle)
            }
            return
          }
          // A window key the app runs itself once the switch is on and it may act, Hammerspoon told
          // only so META's sheet goes down. Any other row, or the switch off, goes to Hammerspoon.
          if let action = WindowShadow.action(id), WindowsSwitch.on, AppFocus.allowed,
            let settings = Self.windowSettings(), WindowRun.runs(action, settings) {
            await windowRun.run(action, depth: depth, settings: settings)
            await bridgeForApps.notify("keyRan", .object(["id": .string(id)]))
            return
          }
          // A window action is read before Hammerspoon moves the window, and its report compared.
          let action = AppFocus.allowed ? WindowShadow.action(id) : nil
          let before = action == nil ? nil : await WindowRead.snapshot()
          let answer = try? await bridgeForApps.request("runKey", .object(["id": .string(id), "depth": .number(Double(depth))]))
          if let action, let before {
            windowShadow.compare(action: action, depth: depth, app: before, settings: Self.windowSettings(),
              lua: answer?["window"].any)
          }
        },
        list: { leader, code, mods, depth in
          let answer = try? await bridgeForApps.request("listKey", .object(["leader": .string(leader),
            "code": .number(Double(code)), "mods": .array(mods.map(\.rawValue).sorted().map { .string($0) }),
            "depth": .number(Double(depth))]))
          return KeyOwner.ListAnswer(ran: answer?["ran"].bool ?? false, repeats: answer?["repeats"].bool ?? false)
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
        KeyRecording.hold = { [weak owner] on in owner?.hold(on) }
      }
      let keymapURL = context.run.appendingPathComponent("keymap.json")
      let service = Self.settingsService(bridgeForApps)
      let takeKeys: @Sendable () -> Void = {
        Task { @MainActor in
          guard let keymap = try? Keymap.read(keymapURL) else { return }
          WindowsSwitch.on = keymap.windowsInApp
          guard keymap.appCatalog else {
            AppsHeld.shared.set(on: false, share: nil)
            return await owner.take(keymap)
          }
          var share = SettingsShare.read()
          // Seeded once from what Hammerspoon binds and styles, so the flip loses no key and no popup.
          if !FileManager.default.fileExists(atPath: AppCatalog.seededMark.path), let read = share,
            let data = try? Data(contentsOf: keymapURL) {
            let seeded = AppCatalog.seed(AppCatalog.table(read), keys: AppCatalog.luaKeys(data), catalog: AppCatalog.catalog(read))
            let answer = seeded.map { next in Task { await service.change(AppCatalog.settingId, .apps(next), false) } }
            if let got = await answer?.value, !got.ok {
              NSLog("Olm apps: the catalog was not seeded, %@", got.why ?? "refused")
            } else {
              if let got = await answer?.value, let now = got.share { share = now }
              try? Data().write(to: AppCatalog.seededMark)
              NSLog("Olm apps: the catalog is seeded from Hammerspoon's")
            }
          }
          AppsHeld.shared.set(on: true, share: share)
          let own = AppCatalog.keyed(AppCatalog.table(share))
          for bundle in own.clashes { NSLog("Olm apps: %@'s key is another app's, so it is left out", bundle) }
          let rows = own.apps.map { a -> KeyRow in
            let mods = Set(a.key.mods.compactMap(Mod.init(rawValue:)))
            return KeyRow(id: a.id, leader: a.key.leader, key: a.key.key, keyCode: a.key.code, mods: mods.isEmpty ? nil : mods)
          }
          let made = keymap.replacing(AppCatalog.luaPrefix, with: rows)
          for row in made.clashes { NSLog("Olm apps: %@'s key is held by another action, so it is left out", row.id) }
          await owner.take(made.keymap)
          // The keys claimed, told to Hammerspoon so its Hyper sheet and the launcher's app rows say
          // what a press does, in place of the toggler's own rows.
          let claimed = made.keymap.rows.filter { $0.id.hasPrefix(AppCatalog.prefix) }
          AppsHeld.shared.leaders(claimed.map { (String($0.id.dropFirst(AppCatalog.prefix.count)), $0.leader) })
          let list: [JSON] = claimed.map { row in
            .object(["bundle": .string(String(row.id.dropFirst(AppCatalog.prefix.count))),
              "leader": row.leader.map { .string($0) } ?? .null, "key": .string(row.key),
              "mods": .array((row.mods ?? []).map(\.rawValue).sorted().map { .string($0) })])
          }
          await bridgeForApps.notify("appsChanged", .object(["apps": .array(list),
            "replaces": .string(String(AppCatalog.luaPrefix.dropLast()))]))
        }
      }
      Self.retakeKeys = takeKeys
      await bridgeForApps.onOpen(takeKeys)
      await bridgeForApps.onKeysReady(takeKeys)
      await bridgeForApps.onClose { Task { @MainActor in owner.drop() } }
      await bridgeForApps.onOpen {
        Task { await bridgeForApps.notify("appsReady", .object(["ready": .bool(AppFocus.allowed)])) }
      }
      // The motion every surface shares, read again as Hammerspoon connects, since a load may have
      // moved it, Look.applyMotion.
      await bridgeForApps.onOpen { Task { @MainActor in applySharedMotion() } }
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
    // A plugin's list is told up by its own name too, and Hammerspoon's bridge, which serves no such
    // list, answers for it with a list context of its own, so the shared list keys reach it.
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
      if Links.isWeb(url) {
        // A plugin the app runs takes it when one may, else Hammerspoon's, else Safari.
        if !plugins.takeLink(url, sender: Links.sender(), stage: stage) { Links.route(url, bridge: bridge) }
        continue
      }
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
      } else if let host = url.host, ExternalPlugins.plugin(host) != nil {
        // A plugin the app runs, its list opened as its launcher row opens it.
        let plugins = plugins, stage = stage, query = item("query") ?? "", screen = item("screen")
        Task { @MainActor in
          guard let source = await plugins.source(host) else { return }
          stage.open(source, query: query, screen: screen)
        }
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

/// Whether the app runs the window manager's keys, the keymap's windowsInApp, set each time the keys
/// are taken.
enum WindowsSwitch {
  nonisolated(unsafe) static var on = false
}

/// The app catalog as the keys were last taken, step 6.2b, docs/DESIGN-APP-APPS.md: whether the app
/// keeps it, the table and the mode an app with none of its own takes, read by every press.
final class AppsHeld: @unchecked Sendable {
  static let shared = AppsHeld()
  private let lock = NSLock()
  private var on = false
  private var table: [String: AppOverride] = [:]
  private var global = "cycle"
  private var catalog: [CatalogApp] = []

  func set(on: Bool, share: SettingsShare?) {
    lock.lock(); defer { lock.unlock() }
    self.on = on
    table = AppCatalog.table(share)
    global = AppCatalog.globalMode(share)
    catalog = AppCatalog.catalog(share)
  }

  var keeps: Bool { lock.lock(); defer { lock.unlock() }; return on }

  /// What a press on an app runs from the table, as AppFocus takes it.
  func press(_ id: String, bundle: String) -> AppPress {
    lock.lock(); defer { lock.unlock() }
    let p = AppCatalog.press(bundle, table: table, global: global)
    return AppPress(id: id, bundle: bundle, hides: p.hides, placement: p.place, lua: nil)
  }

  private var leaderOf: [String: String] = [:]

  /// The leader each app's claimed key sits on, for keyRan.
  func leaders(_ pairs: [(String, String?)]) {
    lock.lock(); defer { lock.unlock() }
    leaderOf = [:]
    for (bundle, leader) in pairs { if let leader { leaderOf[bundle] = leader } }
  }

  func leader(_ bundle: String) -> String? {
    lock.lock(); defer { lock.unlock() }
    return leaderOf[bundle]
  }

  /// Hammerspoon's action for an app, where its catalog has one, for a press the app cannot run.
  func luaAction(_ bundle: String) -> String? {
    lock.lock(); defer { lock.unlock() }
    return catalog.first { $0.bundle == bundle }.map { AppCatalog.luaPrefix + $0.name }
  }
}

/// The window settings last read and the share's stamp they were read at.
final class WindowSettingsCache: @unchecked Sendable {
  static let shared = WindowSettingsCache()
  private let lock = NSLock()
  private var stamp: Date?
  private var settings: WindowSettings?

  func get(_ now: Date?) -> WindowSettings? {
    lock.lock(); defer { lock.unlock() }
    guard let now, now == stamp else { return nil }
    return settings
  }

  func set(_ now: Date?, _ value: WindowSettings) {
    lock.lock(); defer { lock.unlock() }
    stamp = now
    settings = value
  }
}
