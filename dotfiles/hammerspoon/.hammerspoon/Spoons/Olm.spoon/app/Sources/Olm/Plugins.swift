// The external plugins Olm.app runs, docs/DESIGN-APP-PLUGINS.md, each a folder under ~/.olm/plugins
// with its olm-plugin.json, built from its Swift sources with OlmPluginKit beside them and run
// sandboxed by the runner. This host finds them, builds the stale ones, loads them, answers what a
// plugin asks of Olm, opens a plugin's list with what it is opened with, and gives its list the
// bottom bar and the launcher row a Lua plugin gets from Hammerspoon's shares.
//
// What a plugin asks of Olm is short, docs/DESIGN-APP-PLUGINS.md What a plugin may ask: open a link in
// a browser Olm found, write the clipboard, say a line. A plugin holds no permission of macOS's, so
// each is something Olm does for it, and what Olm does with a permission it holds is an ability the
// plugin declared and the person allows, ExternalPlugins.allowed.

import AppKit
import OlmBridge
import OlmCore
import OlmKit
import OlmPlugins
import OlmSettings

@MainActor
final class PluginHost {
  static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".olm/plugins")
  /// OlmPluginKit's source, bundled with the app, compiled into every plugin.
  static let kit = Bundle.main.resourceURL?.appendingPathComponent("OlmPluginKit.swift")

  let runner: PluginRunner
  /// Olm's own plugins as the signed app carries them, what a folder is compared with.
  static let bundled = Bundle.main.resourceURL?.appendingPathComponent("Plugins")
  private let records = PluginRecords()
  /// The folders let through by PluginGate, the only ones built, loaded and read from here on.
  private let folders: [(url: URL, manifest: PluginManifest)]

  init(bridge: Bridge) {
    let fm = FileManager.default
    var through: [(url: URL, manifest: PluginManifest)] = []
    var held: [ExternalPlugins.Held] = []
    let found = ((try? fm.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: nil)) ?? [])
      .filter { fm.fileExists(atPath: $0.appendingPathComponent("olm-plugin.json").path) }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    for folder in found {
      let (verdict, manifest) = PluginGate.verdict(folder: folder, bundled: Self.bundled, records: records)
      if verdict.runs, let manifest {
        through.append((folder, manifest))
        continue
      }
      NSLog("Olm plugins: %@ is held, %@", folder.lastPathComponent, verdict.why ?? "")
      held.append(.init(id: folder.lastPathComponent, title: manifest?.title ?? folder.lastPathComponent,
        why: verdict.why ?? ""))
    }
    folders = through
    ExternalPlugins.held = held
    ExternalPlugins.declared = through.compactMap { PluginDeclarations.read(folder: $0.url) }
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    runner = PluginRunner(appVersion: version, serve: { id, method, params in
      await PluginHost.serve(id, method, params, bridge: bridge)
    })
    for p in ExternalPlugins.declared { ExternalBars.docs[p.id] = Self.bars(p) }
    Self.migrate()
  }

  /// Builds every plugin let through whose program is not the one Olm built from its sources, then
  /// loads it, off the main thread. A plugin that does not build is said in its log and left unloaded.
  func start() {
    let folders = self.folders, runner = self.runner, kit = Self.kit, records = self.records
    Task.detached(priority: .utility) {
      Self.migrateTitles()
      for (folder, manifest) in folders {
        do {
          if try PluginGate.prepare(folder: folder, manifest: manifest, kit: kit, records: records) {
            NSLog("Olm plugins: built %@", manifest.id)
          }
        } catch {
          let line = "\(Date()) the build failed, \(error)\n"
          try? line.write(to: folder.appendingPathComponent("log"), atomically: true, encoding: .utf8)
          NSLog("Olm plugins: %@ did not build, %@", manifest.id, "\(error)")
          continue
        }
        _ = try? await runner.load(folder: folder)
      }
    }
  }

  // MARK: Opening a list

  /// The list of a plugin, opened with its settings, the browsers when it may have them, and what
  /// else the caller hands, a link. nil for a plugin switched off or not loaded.
  func source(_ id: String, with extra: [String: JSON] = [:]) async -> ExternalSource? {
    guard ExternalPlugins.isOn(id), let p = ExternalPlugins.plugin(id) else { return nil }
    var context = extra
    var settings: [String: JSON] = [:]
    for s in p.settings { settings[s.key] = JSON(ExternalPlugins.value(id, s.key)) }
    context["settings"] = .object(settings)
    // The browsers Olm finds, with their profiles only while the plugin has Browser Profiles on.
    if p.abilities.contains(where: { $0.use == "browserProfiles" }) {
      let scan = Browsers.scan(profiles: ExternalPlugins.allowed(id, "browserProfiles"))
      context["browsers"] = .array(scan.targets.map { t in
        .object(["title": .string(t.title), "browser": .string(t.browser), "bundle": .string(t.bundle),
          "id": .string(t.id)])
      })
    }
    let actions = p.verbs.enumerated().map { i, v in
      Action(id: v.action, title: v.title, chord: i == 0 && p.secondary != nil ? ["cmd", "return"] : [])
    }
    return await runner.source(id, context: .object(context), actions: actions)
  }

  /// Whether a plugin on and allowed Receive Links takes this link, its list opened on the stage.
  func takeLink(_ url: URL, sender: NSRunningApplication?, stage: Stage) -> Bool {
    guard let id = ExternalPlugins.first(allowed: "receiveLinks") else { return false }
    var link: [String: JSON] = ["url": .string(url.absoluteString)]
    if let bundle = sender?.bundleIdentifier { link["sourceBundle"] = .string(bundle) }
    if let name = sender?.localizedName { link["sourceName"] = .string(name) }
    Task { @MainActor in
      guard let source = await self.source(id, with: ["link": .object(link)]) else {
        Links.fallback(url)
        return
      }
      stage.open(source, query: "")
    }
    return true
  }

  /// The launcher's row of each plugin on that declares one.
  nonisolated static func launcherRows() -> [Row] {
    ExternalPlugins.declared.filter { $0.rowDetail != nil && ExternalPlugins.isOn($0.id) }.map { p in
      Row(key: "plugin:" + p.id, title: p.title, subtitle: "Plugin · " + (p.rowDetail ?? ""), icon: .symbol(p.icon),
        filterText: p.title, keywords: p.rowKeywords + ["Plugin"])
    }
  }

  // MARK: What a plugin asks of Olm

  nonisolated static func serve(_ id: String, _ method: String, _ params: JSON, bridge: Bridge) async
    -> Result<JSON, RunningPlugin.Refusal> {
    guard ExternalPlugins.isOn(id) else { return .failure(.init(-32001, "it is switched off")) }
    switch method {
    case "open":
      switch PluginRequests.link(params) {
      case .failure(let refusal):
        return .failure(refusal)
      case .success(let link):
        return await MainActor.run { open(link, for: id) }
      }
    case "copy":
      guard let text = params["text"].string else { return .failure(.init(-32602, "copy needs text")) }
      await MainActor.run {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
      }
      return .success(.bool(true))
    case "notify":
      guard let text = params["text"].string else { return .failure(.init(-32602, "notify needs text")) }
      _ = try? await bridge.request("notify", .object(["text": .string(text)]))
      return .success(.bool(true))
    default:
      return .failure(.init(-32601, "Olm does nothing called \(method) for a plugin"))
    }
  }

  /// Opens a link in the browser or profile the plugin named by Olm's id for it, looked up in a scan
  /// of Olm's own, so the program and its arguments are never the plugin's. A profile is in the scan
  /// only while the plugin has Browser Profiles on, and its browser's own program is started with it,
  /// which hands the link to the copy already running. With no browser named the link goes to Safari,
  /// since the default browser is Olm.
  @MainActor static func open(_ link: PluginRequests.Link, for id: String) -> Result<JSON, RunningPlugin.Refusal> {
    guard let browser = link.browser else {
      Links.fallback(link.url)
      return .success(.bool(true))
    }
    let scan = Browsers.scan(profiles: ExternalPlugins.allowed(id, "browserProfiles"))
    guard let target = scan.targets.first(where: { $0.id == browser }) else {
      return .failure(.init(-32001, "\(browser) is not a browser or profile it may open"))
    }
    let app = URL(fileURLWithPath: target.path)
    if !target.args.isEmpty, let program = Bundle(url: app)?.executableURL {
      let p = Process()
      p.executableURL = program
      p.arguments = target.args + [link.url.absoluteString]
      if (try? p.run()) != nil {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
          NSRunningApplication.runningApplications(withBundleIdentifier: target.bundle).first?.activate()
        }
        return .success(.bool(true))
      }
      NSLog("Olm plugins: %@ could not be started with its profile, opened plainly", app.path)
    }
    NSWorkspace.shared.open([link.url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    return .success(.bool(true))
  }

  // MARK: The bar

  /// The bottom bar, the actions pane's rows and the field keys of a plugin's list, laid out as
  /// Hammerspoon lays a tool's out, the leader legend and the keys every list shares taken from the
  /// launcher's share, and the plugin's own Return, secondary and actions from its manifest.
  static func bars(_ p: PluginDeclarations) -> [String: Any] {
    let run = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".olm/run")
    func doc(_ name: String) -> [String: Any]? {
      guard let data = try? Data(contentsOf: run.appendingPathComponent(name)) else { return nil }
      return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    let launcher = doc("launcherkeys.json") ?? [:]
    // The actions pane's chord as the person's keymap has it, read off any list that carries one.
    var actionsChord: Any = [[["glyph": "\u{2726}", "symbol": "sparkle"], ["glyph": "O"]]] // kbd-exempt, the bar share's own shape for a plugin Hammerspoon writes no share for, until the keys move to the app
    let names = (try? FileManager.default.contentsOfDirectory(atPath: run.path)) ?? []
    search: for name in names where name.hasSuffix("keys.json") {
      for item in ((doc(name)?["bar"] as? [String: Any])?["right"] as? [[String: Any]]) ?? []
      where item["action"] as? String == "openActionsPane" {
        actionsChord = item["chord"] ?? actionsChord
        break search
      }
    }
    let enter: [[String: Any]] = [["glyph": "\u{21A9}", "symbol": "return"]] // kbd-exempt, the bar share's own shape for a plugin Hammerspoon writes no share for, until the keys move to the app
    let cmdEnter: [[String: Any]] = [["glyph": "\u{2318}"], ["glyph": "\u{21A9}", "symbol": "return"]] // kbd-exempt, the bar share's own shape for a plugin Hammerspoon writes no share for, until the keys move to the app
    var right: [[String: Any]] = [["label": p.primary.title, "chord": [enter], "action": "insertSelected", "fit": true]]
    if let s = p.secondary { right.append(["label": s.title, "chord": [cmdEnter], "action": s.action, "fit": true]) }
    if !p.verbs.isEmpty { right.append(["label": "Actions", "chord": actionsChord, "action": "openActionsPane", "fit": false]) }
    var bar = launcher["bar"] as? [String: Any] ?? [:]
    bar["right"] = right
    var actions: [[String: Any]] = [["action": "insertSelected", "title": p.primary.title, "chord": [enter],
      "symbol": p.primary.icon ?? "play", "choices": false, "confirm": false, "tint": false]]
    for (i, v) in p.verbs.enumerated() {
      actions.append(["action": v.action, "title": v.title, "chord": i == 0 && p.secondary != nil ? [cmdEnter] : [],
        "symbol": v.icon ?? "circle", "choices": false, "confirm": false, "tint": false])
    }
    var fieldKeys = launcher["fieldKeys"] as? [[String: Any]] ?? []
    if let s = p.secondary {
      fieldKeys.append(["verb": s.action, "code": 36, "mods": ["cmd"]])
      fieldKeys.append(["verb": s.action, "code": 76, "mods": ["cmd"]])
    }
    var out: [String: Any] = ["bar": bar, "actions": actions, "fieldKeys": fieldKeys]
    if let panel = launcher["panelBar"] { out["panelBar"] = panel }
    return out
  }

  // MARK: Moving over

  /// The favourites saved for the Lua Browser Switcher, taken over once by the plugin that replaced
  /// it, so its first open shows what the old one did.
  static func migrate() {
    let key = "browserswitcher.favourites"
    guard ExternalPlugins.plugin("browserswitcher") != nil, ExternalPlugins.store.value(key) == nil else { return }
    let old = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".olm/state/settings.json")
    guard let data = try? Data(contentsOf: old),
      let doc = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let saved = (doc["values"] as? [String: Any])?["browserSwitcher.favourites"] as? [String], !saved.isEmpty
    else { return }
    ExternalPlugins.store.set(key, saved)
  }

  /// Favourites saved by the titles used until 2026-11-25, Google Chrome (Work), taken over by the id
  /// of what they named, each kept as it is while it names nothing found now.
  nonisolated static func migrateTitles() {
    let key = "browserswitcher.favourites"
    guard let saved = ExternalPlugins.store.value(key) as? [String] else { return }
    let targets = Browsers.scan(profiles: ExternalPlugins.allowed("browserswitcher", "browserProfiles")).targets
    let ids = Set(targets.map(\.id))
    let moved = saved.map { name in
      ids.contains(name) ? name : targets.first { $0.oldTitle == name }?.id ?? name
    }
    if moved != saved { ExternalPlugins.store.set(key, moved) }
  }
}
