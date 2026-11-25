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
  nonisolated static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".olm/plugins")
  /// OlmPluginKit's source, bundled with the app, compiled into every plugin.
  nonisolated static let kit = Bundle.main.resourceURL?.appendingPathComponent("OlmPluginKit.swift")

  let runner: PluginRunner
  /// Olm's own plugins as the signed app carries them, what a folder is compared with.
  nonisolated static let bundled = Bundle.main.resourceURL?.appendingPathComponent("Plugins")
  private nonisolated let records = PluginRecords()

  /// One reading of ~/.olm/plugins, what may run, ours first so a plugin installed later never takes an
  /// ability's turn from one of ours, and what is held.
  private struct Scan: Sendable {
    struct Folder: Sendable {
      let url: URL
      let manifest: PluginManifest
      let declared: PluginDeclarations
      let print: String
    }
    var through: [Folder] = []
    var held: [ExternalPlugins.Held] = []
  }

  /// What is loaded, by id, with the files it was built from.
  private var loaded: [String: String] = [:]
  /// What did not build, the files it was tried with and why, so it is tried again once they change.
  private var failed: [String: (print: String, why: String)] = [:]
  /// What the install page shows, by the offer's id, inPlace for a folder already in ~/.olm/plugins.
  private var offered: [String: (staged: PluginInstall.Staged, inPlace: Bool)] = [:]
  /// Readings and installs run one after another.
  private var last: Task<Void, Never>?
  private var watcher: PluginWatcher?

  init(bridge: Bridge) {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    runner = PluginRunner(appVersion: version, serve: { id, method, params in
      await PluginHost.serve(id, method, params, bridge: bridge)
    })
    // Read here as well as in start, so a link that launched Olm finds the plugin it goes to.
    publish(Self.scan(records))
    Self.migrate()
  }

  /// Builds and loads what may run, off the main thread, and from then on follows the folder.
  func start() {
    try? FileManager.default.removeItem(at: Self.aside)
    try? FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
    watcher = PluginWatcher(Self.root) { [weak self] in
      Task { @MainActor in await self?.rescan() }
    }
    Task { @MainActor in
      await Task.detached(priority: .utility) { Self.migrateTitles() }.value
      await rescan()
    }
  }

  // MARK: The folder

  /// Where a dropped plugin is copied until it is allowed, kept from every plugin with ~/.olm.
  private static let aside = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".olm/cache/plugin-install")

  private nonisolated static func scan(_ records: PluginRecords) -> Scan {
    let fm = FileManager.default
    let found = ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
      .filter { fm.fileExists(atPath: $0.appendingPathComponent("olm-plugin.json").path) }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    records.forget(except: Set(found.map(\.lastPathComponent)))
    var out = Scan(), others: [Scan.Folder] = []
    for folder in found {
      let name = folder.lastPathComponent
      let (verdict, manifest) = PluginGate.verdict(folder: folder, bundled: bundled, records: records)
      if verdict.runs, let manifest, var declared = PluginDeclarations.read(folder: folder),
        let print = try? PluginGate.fingerprint(folder) {
        declared.ours = verdict == .ours
        let f = Scan.Folder(url: folder, manifest: manifest, declared: declared, print: print)
        if verdict == .ours { out.through.append(f) } else { others.append(f) }
        continue
      }
      let more = records.allowed(name) != nil
      var why = verdict.why ?? "its files are changing"
      var review = false
      if case .waiting = verdict {
        review = true
        why = more ? "Asks for more than you allowed, so Olm does not run it" : "Not allowed yet, so Olm neither builds nor runs it"
      }
      if case .refused(let refused) = verdict { why = "Not taken, " + refused }
      out.held.append(.init(id: name, title: manifest?.title ?? name, why: why, review: review))
    }
    out.through += others
    return out
  }

  private func publish(_ scan: Scan) {
    let through = scan.through.filter { failed[$0.manifest.id]?.print != $0.print }
    let declared = through.map(\.declared)
    let held = scan.held + scan.through.filter { failed[$0.manifest.id]?.print == $0.print }.map {
      .init(id: $0.manifest.id, title: $0.manifest.title, why: "Did not build, so it does not run", review: true)
    }
    guard declared != ExternalPlugins.declared || held != ExternalPlugins.held else { return }
    for h in held where !ExternalPlugins.held.contains(h) { NSLog("Olm plugins: %@ is held, %@", h.id, h.why) }
    for p in ExternalPlugins.declared { ExternalBars.docs[p.id] = nil }
    for p in declared { ExternalBars.docs[p.id] = Self.bars(p) }
    ExternalPlugins.declared = declared
    ExternalPlugins.held = held
    NotificationCenter.default.post(name: ExternalPlugins.changed, object: nil)
  }

  private func alone<T: Sendable>(_ body: @escaping @MainActor () async -> T) async -> T {
    let before = last
    let task = Task { @MainActor in
      await before?.value
      return await body()
    }
    last = Task { _ = await task.value }
    return await task.value
  }

  func rescan() async { await alone { await self.follow() } }

  /// Reads the folder, lets go of what left, changed or asks for more, then builds and loads the rest.
  private func follow() async {
    let records = self.records, kit = Self.kit
    let scan = await Task.detached(priority: .utility) { Self.scan(records) }.value
    let prints = Dictionary(scan.through.map { ($0.manifest.id, $0.print) }, uniquingKeysWith: { a, _ in a })
    for (id, print) in loaded where prints[id] != print {
      await runner.unload(id)
      loaded[id] = nil
    }
    publish(scan)
    for f in scan.through where loaded[f.manifest.id] == nil && failed[f.manifest.id]?.print != f.print {
      let why: String? = await Task.detached(priority: .utility) {
        do {
          if try PluginGate.prepare(folder: f.url, manifest: f.manifest, kit: kit, records: records) {
            NSLog("Olm plugins: built %@", f.manifest.id)
          }
          // The very files read above, so what is loaded is what was let through.
          guard try PluginGate.fingerprint(f.url) == f.print else { return "its files changed while it was built" }
          return nil
        } catch {
          let line = "\(Date()) the build failed, \(error)\n"
          try? line.write(to: f.url.appendingPathComponent("log"), atomically: true, encoding: .utf8)
          return "\(error)"
        }
      }.value
      if let why {
        NSLog("Olm plugins: %@ did not build, %@", f.manifest.id, why)
        failed[f.manifest.id] = (f.print, why)
      } else if (try? await runner.load(folder: f.url)) != nil {
        failed[f.manifest.id] = nil
        loaded[f.manifest.id] = f.print
      }
    }
    publish(scan)
  }

  // MARK: Installing

  /// What Olm Settings asks, docs/DESIGN-APP-PLUGINS.md The install page.
  var installer: PluginInstaller {
    PluginInstaller(review: { [weak self] in await self?.review($0) ?? .init() },
      take: { [weak self] in await self?.take($0) ?? .init() },
      allow: { [weak self] offer in
        guard let self else { return .init() }
        return await self.alone { await self.allow(offer) }
      },
      leave: { [weak self] in self?.leave($0) },
      remove: { [weak self] id, data in
        guard let self else { return nil }
        return await self.alone { await self.remove(id, data: data) }
      })
  }

  private func offer(_ staged: PluginInstall.Staged, inPlace: Bool, from: String?) -> PluginOffer {
    let id = staged.manifest.id, token = UUID().uuidString
    offered[token] = (staged, inPlace)
    let old = inPlace ? nil : try? PluginManifest.read(folder: Self.root.appendingPathComponent(id)).version
    return PluginOffer(id: token, manifest: staged.manifest, declared: PluginDeclarations.read(folder: staged.folder),
      from: from, replaces: old, given: records.allowed(id),
      failed: inPlace && failed[id]?.print == staged.print ? failed[id]?.why : nil,
      data: PluginInstall.type(Self.root.appendingPathComponent(id + "/data")) == .typeDirectory)
  }

  private func review(_ name: String) async -> PluginInstaller.Answer {
    let folder = Self.root.appendingPathComponent(name)
    let read = await Task.detached {
      Result { try PluginInstall.inPlace(folder) }
    }.value
    switch read {
    case .success(let staged) where staged.manifest.id == name: return .init(offer: offer(staged, inPlace: true, from: nil))
    case .success: return .init(why: "\(name) is named differently from its id.")
    case .failure(let error): return .init(why: "\(name) cannot be read, \(error).")
    }
  }

  private func take(_ item: URL) async -> PluginInstaller.Answer {
    let item = item.standardizedFileURL
    if item.deletingLastPathComponent().path == Self.root.standardizedFileURL.path, item.pathExtension.isEmpty {
      if ExternalPlugins.plugin(item.lastPathComponent) != nil { return .init(why: "\(item.lastPathComponent) is installed already.") }
      return await review(item.lastPathComponent)
    }
    let dir = Self.aside.appendingPathComponent(UUID().uuidString)
    let read = await Task.detached { Result { try PluginInstall.stage(item, into: dir) } }.value
    let name = item.lastPathComponent
    switch read {
    case .failure(let error):
      try? FileManager.default.removeItem(at: dir)
      return .init(why: "\(name) was not taken, it \(error).".replacingOccurrences(of: "it it ", with: "it "))
    case .success(let staged):
      let id = staged.manifest.id
      let refused: String?
      if let own = Self.bundled?.appendingPathComponent(id), FileManager.default.fileExists(atPath: own.path) {
        refused = "\(name) was not taken, \(id) is the id of one of Olm's own plugins."
      } else if loaded[id] == staged.print {
        refused = "\(staged.manifest.title) is installed already, the same files."
      } else {
        refused = nil
      }
      if let refused {
        try? FileManager.default.removeItem(at: dir)
        return .init(why: refused)
      }
      return .init(offer: offer(staged, inPlace: false, from: name))
    }
  }

  private func allow(_ offer: PluginOffer) async -> PluginInstaller.Answer {
    guard let (staged, inPlace) = offered.removeValue(forKey: offer.id) else {
      return .init(why: "Olm lost what this page showed, open it again.")
    }
    let id = staged.manifest.id, root = Self.root
    if inPlace {
      let now = await Task.detached { try? PluginGate.fingerprint(staged.folder) }.value
      guard now == staged.print else {
        let next = await review(id)
        return .init(offer: next.offer, why: next.why ?? "Its files changed while this page was open, so it is shown again.")
      }
    } else {
      await runner.unload(id)
      loaded[id] = nil
      let put = await Task.detached { Result { try PluginInstall.put(staged, in: root) } }.value
      try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent())
      if case .failure(let error) = put {
        await follow()
        return .init(why: "\(staged.manifest.title) could not be put in place, \(error.localizedDescription)")
      }
    }
    if records.allowed(id) == nil { ExternalPlugins.turnOn(id) }
    records.allow(id, PluginGate.asks(staged.manifest))
    failed[id] = nil
    await follow()
    if loaded[id] == staged.print { return .init() }
    let next = await review(id)
    return .init(offer: next.offer, why: next.why ?? "\(staged.manifest.title) did not build.")
  }

  private func remove(_ id: String, data: Bool) async -> String? {
    let held = ExternalPlugins.held.contains { $0.id == id }
    guard held || ExternalPlugins.plugin(id)?.ours == false else { return "\(id) is not a plugin to uninstall." }
    await runner.unload(id)
    loaded[id] = nil
    failed[id] = nil
    let root = Self.root, aside = Self.aside
    let done = await Task.detached { Result { try PluginInstall.remove(id, from: root, data: data, aside: aside) } }.value
    if case .success = done, data { ExternalPlugins.forget(id) }
    await follow()
    if case .failure(let error) = done { return "\(id) was not uninstalled, \(error.localizedDescription)" }
    return nil
  }

  private func leave(_ offer: PluginOffer) {
    guard let (staged, inPlace) = offered.removeValue(forKey: offer.id), !inPlace else { return }
    try? FileManager.default.removeItem(at: staged.folder.deletingLastPathComponent())
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
    guard ExternalPlugins.isOn(id), ExternalPlugins.plugin(id) != nil else { return .failure(.init(-32001, "it is switched off")) }
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

/// Follows ~/.olm/plugins, told a second after a manifest or a source moved there, never for what a
/// plugin writes in its own data and tmp, its program or its log.
final class PluginWatcher: @unchecked Sendable {
  private var stream: FSEventStreamRef?
  private let root: String
  private let changed: @Sendable () -> Void

  init(_ root: URL, changed: @escaping @Sendable () -> Void) {
    self.root = Sandbox.resolved(root.path)
    self.changed = changed
    var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil,
      release: nil, copyDescription: nil)
    let heard: FSEventStreamCallback = { _, info, _, paths, _, _ in
      guard let info, let paths = unsafeBitCast(paths, to: CFArray.self) as? [String] else { return }
      let me = Unmanaged<PluginWatcher>.fromOpaque(info).takeUnretainedValue()
      if paths.contains(where: me.matters) { me.changed() }
    }
    let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
    stream = FSEventStreamCreate(nil, heard, &context, [self.root] as CFArray,
      FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1, FSEventStreamCreateFlags(flags))
    if let stream {
      FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "olm.plugins.watch", qos: .utility))
      FSEventStreamStart(stream)
    }
  }

  private func matters(_ path: String) -> Bool {
    guard path.hasPrefix(root) else { return true }
    let parts = path.dropFirst(root.count).split(separator: "/")
    return parts.count < 2 || !["data", "tmp", "bin", "log"].contains(String(parts[1]))
  }

  deinit {
    guard let stream else { return }
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
  }
}
