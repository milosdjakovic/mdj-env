// The Applications page of Olm Settings, every application an app key can reach, what Olm does with
// each, and a mode of its own over its style's and the global one, docs/DESIGN-APP-SETTINGS.md
// Applications. The page draws the app toggler's setting `apptoggler.apps`, a table of applications by
// bundle id, and lays Hammerspoon's catalog over the list for the apps this Mac has, a temporary
// bridge kept in `HammerspoonCatalog` alone. The applications
// installed here are the page's own to find, read at the top of /Applications, /System/Applications
// and ~/Applications and never inside a folder there, so a suite's helpers and an app's bundled
// utilities stay out, and an app that runs with no Dock icon, an agent or a background helper, is
// left out too. One kept anywhere else is added with Add Application, a file picker.
//
// Each row is the app, then its Customize button, then its key at the far right. Customize opens a
// sheet holding the app's mode and where its window goes when its key shows it, the display, the
// position and the size. A row customized and a key that is set are drawn in the accent, a light tint
// and an outline, and the rest muted, so a scroll down the list catches what is set. A key is Olm's own setting `keys`, an action
// to its chord, laid over the keymap's, so it travels with Olm's config when it is exported. A change
// goes to Hammerspoon as every setting's does, the whole table at once, and applies on the reload the
// window's close runs.

import AppKit
import OlmApps
import SwiftUI
import UniformTypeIdentifiers

/// An application found installed, by its bundle id.
public struct InstalledApp: Equatable, Sendable, Identifiable {
  public let bundle: String
  public let name: String
  public let path: String
  public var id: String { bundle }
}

public enum AppScan {
  /// The folders read, each at its top level only.
  public static let folders: [URL] = [
    URL(fileURLWithPath: "/Applications"),
    URL(fileURLWithPath: "/System/Applications"),
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
  ]

  /// Every application at the top of the folders with a bundle id and a Dock icon, the first of two
  /// with one bundle id kept, sorted by name.
  public static func scan(_ folders: [URL] = folders) -> [InstalledApp] {
    var seen = Set<String>()
    var out: [InstalledApp] = []
    for folder in folders {
      let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles])) ?? []
      for url in items where url.pathExtension == "app" {
        guard let app = read(url), seen.insert(app.bundle).inserted else { continue }
        out.append(app)
      }
    }
    return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  /// One application bundle, nil for one with no bundle id or one that runs with no Dock icon.
  public static func read(_ url: URL) -> InstalledApp? {
    guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
    let info = bundle.infoDictionary ?? [:]
    func on(_ key: String) -> Bool {
      if let b = info[key] as? Bool { return b }
      if let s = info[key] as? String { return s == "1" || s.lowercased() == "yes" || s.lowercased() == "true" }
      return (info[key] as? NSNumber)?.boolValue ?? false
    }
    if on("LSUIElement") || on("LSBackgroundOnly") { return nil }
    let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
      ?? url.deletingPathExtension().lastPathComponent
    return InstalledApp(bundle: id, name: name, path: url.path)
  }
}

/// The page's own state, the applications found, their icons, the filter typed and the row
/// recording a key, held by the window's model since a view here can keep none of its own.
@MainActor
final class AppsPageModel: ObservableObject {
  @Published var installed: [InstalledApp] = []
  @Published var filter = ""
  @Published var scanned = false
  /// Each app action's key from the keymap Hammerspoon shares, by action id, hyper+C.
  @Published var keys: [String: String] = [:]
  /// Each application's icon at row size, drawn once off the main thread, by bundle id, so
  /// scrolling draws a bitmap and asks macOS for nothing.
  @Published var icons: [String: NSImage] = [:]
  /// The applications on this Mac, scanned or named elsewhere and found at their path, by bundle id.
  @Published var found = Set<String>()
  /// The action whose key is being recorded, and the monitor hearing the key.
  @Published var recording: String?
  /// The application whose Customize sheet is open, and what it holds until Done.
  @Published var customizing: AppCustomize?
  private var monitor: Any?

  /// The picture an application not installed here wears.
  static let generic: NSImage = {
    let icon = NSWorkspace.shared.icon(for: .applicationBundle)
    icon.size = NSSize(width: 28, height: 28)
    return icon
  }()

  /// Started as the window is prepared, with the catalog and the table from the share, so the list
  /// and every icon are ready before the page is first opened.
  func warm(_ share: SettingsShare?) {
    let apps = share?.sections.flatMap(\.settings).first { $0.kind == .apps }
    let also = (apps?.catalog.map { ($0.bundle, $0.path) } ?? [])
      + (apps?.value.apps ?? [:]).map { ($0.key, $0.value.path) }
    scan(also: also)
  }

  /// Bundles whose icon was already looked for, found or not, so a fill asks once.
  private var looked = Set<String>()

  /// Icons for applications that came after the scan, an added one or a catalog grown by a reload,
  /// drawn off the main thread.
  func fill(_ apps: [(bundle: String, path: String?)]) {
    let wanted = apps.filter { !looked.contains($0.bundle) }
    guard scanned, !wanted.isEmpty else { return }
    for app in wanted { looked.insert(app.bundle) }
    Task.detached(priority: .userInitiated) {
      var icons: [String: NSImage] = [:]
      for app in wanted {
        if let path = app.path ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundle)?.path,
          FileManager.default.fileExists(atPath: path), let icon = AppsPageModel.rowIcon(path) { icons[app.bundle] = icon }
      }
      let present = Set(icons.keys)
      await MainActor.run {
        self.icons.merge(icons) { a, _ in a }
        self.found.formUnion(present)
      }
    }
  }

  func scan(also: [(bundle: String, path: String?)]) {
    guard !scanned else { return }
    for app in also { looked.insert(app.bundle) }
    scanned = true
    Task.detached(priority: .userInitiated) {
      let found = AppScan.scan()
      let keys = AppsPageModel.readKeys()
      var paths: [String: String] = [:]
      for app in found { paths[app.bundle] = app.path }
      for extra in also {
        if let path = extra.path ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: extra.bundle)?.path,
          FileManager.default.fileExists(atPath: path) {
          paths[extra.bundle] = paths[extra.bundle] ?? path
        }
      }
      var icons: [String: NSImage] = [:]
      for (bundle, path) in paths { icons[bundle] = AppsPageModel.rowIcon(path) }
      await MainActor.run {
        for app in found { self.looked.insert(app.bundle) }
        self.installed = found
        self.keys = keys
        self.icons = icons
        self.found = Set(paths.keys)
      }
    }
  }

  /// An application's icon drawn once into a 56 point square bitmap, two pixels a point, so the row
  /// shows a small picture rather than the icon file's largest one scaled on every frame.
  nonisolated static func rowIcon(_ path: String) -> NSImage? {
    let icon = NSWorkspace.shared.icon(forFile: path)
    var rect = NSRect(x: 0, y: 0, width: 56, height: 56)
    guard let cg = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil),
      let ctx = CGContext(data: nil, width: 56, height: 56, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 56, height: 56))
    guard let out = ctx.makeImage() else { return nil }
    return NSImage(cgImage: out, size: NSSize(width: 28, height: 28))
  }

  /// The keys of the app actions, apptoggler.<name>, from ~/.olm/run/keymap.json, as chords, hyper+C.
  nonisolated static func readKeys() -> [String: String] {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".olm/run/keymap.json")
    guard let data = try? Data(contentsOf: url),
      let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    var out: [String: String] = [:]
    for row in doc["rows"] as? [[String: Any]] ?? [] {
      guard let id = row["id"] as? String, let key = row["key"] as? String, out[id] == nil else { continue }
      var parts: [String] = []
      if let leader = row["leader"] as? String { parts.append(leader) }
      parts += (row["mods"] as? [String] ?? [])
      parts.append(key)
      out[id] = parts.joined(separator: "+")
    }
    return out
  }

  /// Hears one key for action, Escape cancelling, Delete answering none, any other its name.
  func record(_ action: String, _ done: @escaping (String?, Bool) -> Void) {
    stop()
    recording = action
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return event }
      switch event.keyCode {
      case 53: self.stop()
      case 51, 117:
        self.stop()
        done(nil, true)
      default:
        guard let name = KeyName.of(event) else { return nil }
        self.stop()
        done(name, true)
      }
      return nil
    }
  }

  func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    recording = nil
  }
}

/// A key's name as the keymap spells it, a letter in capitals, a digit or a mark as typed, and the
/// few keys with names, hs.keycodes.map's.
public enum KeyName {
  static let named: [UInt16: String] = [
    49: "space", 36: "return", 48: "tab", 123: "left", 124: "right", 125: "down", 126: "up",
    122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8", 101: "f9",
    109: "f10", 103: "f11", 111: "f12",
  ]

  static func of(_ event: NSEvent) -> String? {
    if let name = named[event.keyCode] { return name }
    guard let c = event.charactersIgnoringModifiers?.first, !c.isWhitespace else { return nil }
    return c.isLetter ? String(c).uppercased() : String(c)
  }

  /// A chord in words, hyper+C as Hyper C.
  public static func words(_ chord: String) -> String {
    chord.split(separator: "+", omittingEmptySubsequences: false).enumerated().map { i, part in
      let p = String(part)
      if p.isEmpty { return "+" }
      return p.count == 1 ? p.uppercased() : p.capitalized
    }.joined(separator: " ")
  }
}

/// One application as the page lists it, what is installed, the catalog and the table together.
struct AppEntry: Identifiable {
  let bundle: String
  let name: String
  let path: String?
  let catalog: CatalogApp?
  let own: AppOverride?
  var id: String { bundle }
  /// Given a mode or a place of its own on this page.
  var customized: Bool { own?.mode != nil || own?.place != nil }
  /// In the catalog or added, so it has an action and a key.
  var configured: Bool { catalog != nil || own != nil }
  /// Added on this page from outside the catalog, so it can be removed here.
  var removable: Bool { (catalog == nil || catalog?.added == true) && own != nil }
  /// Its action, apptoggler.<name>, once the catalog knows it.
  var action: String? { catalog.map { "apptoggler." + $0.name } }
}

enum AppsPage {
  static let settingId = "apptoggler.apps"
  static let modeId = "apptoggler.mode"
  static let keysId = "keys"

  /// The applications setting of a section, when it is the Applications page's.
  static func setting(in section: SettingsSection) -> Setting? {
    section.settings.first { $0.kind == .apps }
  }
}

/// The widths of a row's columns, so the Customize button and the key line up from row to row. Each
/// column is as wide as its control, the row's spacing standing between them, and the name takes
/// every point they leave. The marks, the key's reset and the remove, close the row on the right.
enum AppColumns {
  /// The Customize button and the key control, one width so the two read as a pair.
  static let menu: CGFloat = 110
  static let recorder: CGFloat = 110
  /// A reset or a remove, kept in place when hidden so nothing moves.
  static let mark: CGFloat = 16
  /// The marks column, the key's reset and the remove.
  static let marks: CGFloat = mark * 2 + Space.related
}

struct AppsView: View {
  let setting: Setting
  @ObservedObject var model: SettingsModel
  @ObservedObject var page: AppsPageModel

  var body: some View {
    let all = entries
    ScrollView {
      VStack(alignment: .leading, spacing: Space.group) {
        header
        if let mode = modeSetting {
          SettingRow(setting: mode, model: model)
            .padding(.horizontal, Space.pad + 4).padding(.vertical, Space.pad)
            .glassCard(cornerRadius: 20)
        }
        HStack(spacing: Space.pad) {
          TextField("Filter applications", text: $page.filter)
            .textFieldStyle(.roundedBorder)
          Button {
            add()
          } label: {
            Label("Add Application…", systemImage: "plus")
          }
          .help("Add an application kept outside the Applications folders")
        }
        card("Applications", all)
        if !page.scanned || page.installed.isEmpty {
          ProgressView().frame(maxWidth: .infinity)
        }
      }
      .padding(Space.edge)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .ignoresSafeArea(.container, edges: .top)
    .onAppear {
      let apps = setting.catalog.map { ($0.bundle, $0.path) } + table.map { ($0.key, $0.value.path) }
      page.scan(also: apps)
      page.fill(apps)
    }
    .onDisappear { page.stop() }
    .sheet(isPresented: Binding(get: { page.customizing != nil }, set: { if !$0 { page.customizing = nil } })) {
      CustomizeSheet(page: page, global: global, save: save)
    }
  }

  private var header: some View {
    HStack(spacing: Space.pad + 4) {
      Image(systemName: "square.grid.2x2")
        // look-exempt, the section's picture in its glass circle, sized as System Settings does.
        .font(.system(size: 26, weight: .medium))
        .foregroundStyle(.tint)
        .frame(width: SectionPage.header, height: SectionPage.header)
        .glassCircle()
      VStack(alignment: .leading, spacing: Space.row) {
        Text("Applications").font(.largeTitle.weight(.semibold))
        Text(summary).font(.callout).foregroundStyle(.secondary)
      }
      Spacer(minLength: Space.group)
      if let note { Note(text: note.text, symbol: note.symbol) }
    }
    .frame(height: SectionPage.header)
  }

  private var summary: String {
    let n = table.values.filter { $0.mode != nil || $0.place != nil }.count
    return n == 1 ? "1 application customized" : "\(n) applications customized"
  }

  private var note: (text: String, symbol: String)? {
    if let refusal = model.refusal { return (refusal, "exclamationmark.triangle") }
    if model.reloadDue { return ("Applies when this window closes", "arrow.clockwise") }
    return nil
  }

  // A long list sits on a plain fill rather than glass, which redraws its blur under every row on
  // every scrolled frame.
  @ViewBuilder private func card(_ title: String, _ list: [AppEntry]) -> some View {
    if !list.isEmpty {
      VStack(alignment: .leading, spacing: Space.related) {
        HStack(spacing: Space.pad) {
          Text(title).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
          Text("Behaviour").font(.caption).foregroundStyle(.secondary)
            .frame(width: AppColumns.menu, alignment: .leading)
          Text("Shortcut").font(.caption).foregroundStyle(.secondary)
            .frame(width: AppColumns.recorder, alignment: .leading)
          Color.clear.frame(width: AppColumns.marks, height: 1)
        }
        .padding(.horizontal, Space.pad + 4)
        // Every row made at once, a few hundred at most, so none appears as it scrolls into view.
        VStack(spacing: 0) {
          ForEach(Array(list.enumerated()), id: \.element.id) { index, entry in
            if index > 0 { Divider().padding(.leading, Space.pad + 4) }
            AppRow(entry: entry, icon: page.icons[entry.bundle],
              chord: entry.action.flatMap(chord), recording: entry.action != nil && page.recording == entry.action,
              keyOwn: entry.action.map { keysTable[$0] != nil } ?? false, busy: !model.busy.isEmpty,
              customize: { customize(entry) }, reset: { resetCustom(entry) }, remove: { remove(entry) },
              record: { record(entry) }, resetKey: { resetKey(entry) })
              .padding(.horizontal, Space.pad + 4).padding(.vertical, Space.pad - 4)
          }
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.quaternary.opacity(0.5)))
      }
    }
  }

  // MARK: What is listed

  private var table: [String: AppOverride] { setting.value.apps ?? [:] }
  private var allSettings: [Setting] { model.share?.sections.flatMap(\.settings) ?? [] }
  private var modeSetting: Setting? { allSettings.first { $0.id == AppsPage.modeId } }
  private var keysSetting: Setting? { allSettings.first { $0.id == AppsPage.keysId } }
  private var keysTable: [String: String?] { keysSetting?.value.keys ?? [:] }
  private var global: String { modeSetting?.value.text ?? "cycle" }

  /// The chord an action has, the one set here first, nil for none.
  private func chord(_ action: String) -> String? {
    if let own = keysTable[action] { return own }
    return page.keys[action]
  }

  /// One list: every application the scan finds, every one added here, and each with what the app
  /// toggler in Hammerspoon does with it today laid over it, by `HammerspoonCatalog`.
  private var entries: [AppEntry] {
    var out: [AppEntry] = []
    var seen = Set<String>()
    let catalog = HammerspoonCatalog.byBundle(setting.catalog, found: page.found)
    for app in page.installed where seen.insert(app.bundle).inserted {
      out.append(AppEntry(bundle: app.bundle, name: app.name, path: app.path, catalog: catalog[app.bundle],
        own: table[app.bundle]))
    }
    // An application kept outside the scanned folders, added here, or saved with a mode of its own
    // and since gone, so the mode can still be reset.
    for (bundle, own) in table where seen.insert(bundle).inserted {
      out.append(AppEntry(bundle: bundle, name: own.name ?? catalog[bundle]?.name ?? bundle,
        path: own.path, catalog: catalog[bundle], own: own))
    }
    out += HammerspoonCatalog.outsideScan(setting.catalog, found: page.found, seen: &seen)
      .map { AppEntry(bundle: $0.bundle, name: $0.name, path: $0.path, catalog: $0, own: nil) }
    let words = page.filter.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    return out
      .filter { e in words.allSatisfy { (e.name + " " + e.bundle).lowercased().contains($0) } }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  // MARK: Changes, each table sent whole

  /// Opens the entry's Customize sheet, starting from its own mode and place, or for an app with no
  /// place of its own from what its style does today.
  private func customize(_ entry: AppEntry) {
    let own = entry.own
    let inherited = entry.catalog?.placement
    page.customizing = AppCustomize(bundle: entry.bundle, name: entry.name, mode: own?.mode ?? "default",
      place: own?.place ?? inherited ?? AppPlace(),
      fromStyle: own?.place == nil && inherited != nil ? entry.catalog?.style : nil,
      added: entry.catalog == nil || entry.catalog?.added == true, path: entry.path)
  }

  /// Writes the sheet's mode and place. Default and a place equal to what the app would do anyway are
  /// left off, and an app with nothing else of its own here is taken off the table, an added one
  /// keeping its name and path.
  private func save(_ c: AppCustomize) {
    var next = table
    var own = next[c.bundle] ?? AppOverride()
    own.mode = c.mode == "default" ? nil : c.mode
    let inherited = catalogPlacement(c.bundle)
    // A place is kept when it differs from what the app does with none of its own: the style's
    // placement where it has one, otherwise where it was, kept and kept.
    own.place = c.place == (inherited ?? AppPlace()) ? nil : c.place
    if c.added {
      own.name = own.name ?? c.name
      own.path = own.path ?? c.path
    }
    next[c.bundle] = own.mode == nil && own.place == nil && (!c.added || own.path == nil) ? nil : own
    page.customizing = nil
    model.change(setting, to: .apps(next))
  }

  private func resetCustom(_ entry: AppEntry) {
    var next = table
    guard var own = next[entry.bundle] else { return }
    own.mode = nil
    own.place = nil
    let added = entry.catalog == nil || entry.catalog?.added == true
    next[entry.bundle] = !added || own.path == nil ? nil : own
    model.change(setting, to: .apps(next))
  }

  private func catalogPlacement(_ bundle: String) -> AppPlace? {
    setting.catalog.first { $0.bundle == bundle }?.placement
  }

  private func remove(_ entry: AppEntry) {
    var next = table
    next[entry.bundle] = nil
    model.change(setting, to: .apps(next))
  }

  /// Records a key for the entry's action, refusing one another action holds, and Delete leaving it
  /// with none.
  private func record(_ entry: AppEntry) {
    guard let action = entry.action, let keys = keysSetting else {
      model.refusal = "\(entry.name) has a key once its mode is set and the window closed once."
      return
    }
    page.record(action) { name, _ in
      var next = keysTable
      if let name {
        let chord = "hyper+" + name
        if let holder = holder(of: chord, besides: action) {
          model.refusal = "\(KeyName.words(chord)) is \(holder)'s, clear it there first."
          return
        }
        next[action] = .some(chord)
      } else {
        next[action] = .some(nil)
      }
      model.change(keys, to: .keys(next))
    }
  }

  private func resetKey(_ entry: AppEntry) {
    guard let action = entry.action, let keys = keysSetting else { return }
    var next = keysTable
    next[action] = nil
    model.change(keys, to: .keys(next))
  }

  /// The action holding a chord now, the keys set here over the keymap's, besides one.
  private func holder(of chord: String, besides action: String) -> String? {
    let want = chord.lowercased()
    for (other, own) in keysTable where other != action && own?.lowercased() == want { return other }
    for (other, held) in page.keys where other != action && held.lowercased() == want && keysTable[other] == nil {
      return other
    }
    return nil
  }

  private func add() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.applicationBundle]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.message = "Choose an application for Olm's app keys"
    guard panel.runModal() == .OK, let url = panel.url,
      let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
    // Known to LaunchServices, so Olm can open it by its bundle id wherever it is kept.
    LSRegisterURL(url as CFURL, true)
    let info = bundle.infoDictionary ?? [:]
    let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
      ?? url.deletingPathExtension().lastPathComponent
    var next = table
    var own = next[id] ?? AppOverride()
    own.name = own.name ?? name
    own.path = url.path
    next[id] = own
    page.filter = ""
    if page.icons[id] == nil { page.icons[id] = AppsPageModel.rowIcon(url.path) }
    page.found.insert(id)
    model.change(setting, to: .apps(next))
  }
}

/// One application: its icon and name with what Olm does with it, stretching, then its mode, then its
/// key flush at the right. A mode of its own is drawn in the accent with a reset beside it.
///
/// The mode and the key are drawn here rather than as a pop-up button and a push button, since a
/// page of a few hundred rows of AppKit controls stuttered as it scrolled. A press opens the same
/// menu a pop-up button would, from the pointer.
struct AppRow: View {
  let entry: AppEntry
  let icon: NSImage?
  let chord: String?
  let recording: Bool
  let keyOwn: Bool
  let busy: Bool
  let customize: () -> Void
  let reset: () -> Void
  let remove: () -> Void
  let record: () -> Void
  let resetKey: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: Space.pad) {
      Group {
        if let icon {
          Image(nsImage: icon)
        } else {
          // An application the catalog names and this Mac does not have, the generic picture faded.
          Image(nsImage: AppsPageModel.generic).opacity(0.4)
        }
      }
      .frame(width: 28, height: 28)
      VStack(alignment: .leading, spacing: Space.related / 2) {
        Text(entry.name)
        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      mode
      key
      HStack(spacing: Space.related) {
        mark("arrow.uturn.backward", shown: keyOwn, help: "Back to the key in the config files", action: resetKey)
        mark("minus.circle", shown: entry.removable, help: "Remove \(entry.name) from Olm", action: remove)
      }
      .frame(width: AppColumns.marks)
    }
    .disabled(busy)
  }

  // The behaviour column. Its reset is the sheet's own Reset, and the button's menu.
  private var mode: some View {
    Group {
      Button(action: customize) {
        Field(width: AppColumns.menu, leading: false, set: entry.customized) {
          Image(systemName: "slider.horizontal.3").font(.caption)
          Text("Customize").padding(.leading, Space.related)
        }
      }
      .buttonStyle(.plain)
      .help(entry.customized
        ? AppCustomize.words(entry.own)
        : "How \(entry.name)'s key acts and where its window goes")
      .contextMenu {
        Button("Back to the Default", action: reset).disabled(!entry.customized)
      }
    }
  }

  // The key column, the recorder alone, its reset among the marks.
  private var key: some View {
    Group {
      Button(action: record) {
        Field(width: AppColumns.recorder, leading: false, set: chord != nil || recording) {
          Text(recording ? "Press a key" : (chord.map(KeyName.words) ?? "None"))
        }
      }
      .buttonStyle(.plain)
      .help(recording ? "Press the key for Hyper and it, Delete for none, Escape to leave it" : "Record a key")
      .disabled(entry.action == nil)
      .opacity(entry.action == nil ? 0.5 : 1)
    }
  }

  /// A small borderless button that keeps its place while hidden.
  private func mark(_ symbol: String, shown: Bool, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol).frame(width: AppColumns.mark) }
      .buttonStyle(.borderless)
      .help(help)
      .opacity(shown ? 1 : 0)
      .disabled(!shown)
  }

  private var detail: String {
    var parts: [String] = []
    if let style = entry.catalog?.style { parts.append("Style \(style)" + (entry.catalog?.placed == true ? ", placed" : "")) }
    if entry.own?.path != nil { parts.append("Added") }
    if entry.catalog == nil || entry.catalog?.added == true, let path = entry.path, entry.own?.path != nil { parts.append(path) }
    if icon == nil { parts.append("Not installed") }
    if parts.isEmpty { parts.append(entry.bundle) }
    return parts.joined(separator: " · ")
  }
}

/// A control's face drawn by SwiftUI, the corner a pop-up button has. A value that is set, a mode of
/// the row's own or a key, is drawn in the accent on a light tint with an outline, and one left at
/// the default, Default or None, is muted, so what is set is caught at a glance.
struct Field<Content: View>: View {
  let width: CGFloat
  let leading: Bool
  let set: Bool
  @ViewBuilder let content: Content

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
    HStack(spacing: 0) { content }
      .lineLimit(1)
      .foregroundStyle(set ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
      .padding(.horizontal, Space.pad - 4)
      .frame(width: width, height: 24, alignment: leading ? .leading : .center)
      .background(shape.fill(set ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.quaternary)))
      .overlay(shape.strokeBorder(set ? AnyShapeStyle(.tint.opacity(0.55)) : AnyShapeStyle(.clear), lineWidth: 1))
      .contentShape(Rectangle())
  }
}

/// Temporary, the bridge to Hammerspoon. What the app toggler there knows of each application, its
/// style, whether it is placed and so its action and key, comes in the share as the setting's
/// catalog, the apps of config/apps.lua, which names apps for every machine. Only those on this Mac
/// are shown. Removed whole once the app switcher lives in Olm.app, the list then the scan and the
/// added apps alone, docs/PLAN-STANDALONE.md.
enum HammerspoonCatalog {
  /// The catalog's applications this Mac has, by bundle id.
  static func byBundle(_ catalog: [CatalogApp], found: Set<String>) -> [String: CatalogApp] {
    var out: [String: CatalogApp] = [:]
    for app in catalog where found.contains(app.bundle) && out[app.bundle] == nil { out[app.bundle] = app }
    return out
  }

  /// The catalog's applications this Mac has where the scan does not look, inside a folder, a Chrome
  /// app for one, not yet listed.
  static func outsideScan(_ catalog: [CatalogApp], found: Set<String>, seen: inout Set<String>) -> [CatalogApp] {
    catalog.filter { found.contains($0.bundle) && seen.insert($0.bundle).inserted }
  }
}

/// What a Customize sheet holds until Done: the application, its mode and its place.
struct AppCustomize: Equatable {
  let bundle: String
  let name: String
  var mode: String
  var place: AppPlace
  /// The style its place starts from when it has none of its own, popup, said in the sheet.
  let fromStyle: String?
  let added: Bool
  let path: String?

  static let displays: [(id: String, title: String)] = [
    ("was", "Where it was"), ("active", "Active display"), ("pointer", "Display under the pointer"),
  ]

  /// An application's own mode and place in a few words, for its row.
  static func words(_ own: AppOverride?) -> String {
    var parts: [String] = []
    if let mode = own?.mode { parts.append(mode == "hides" ? "Show and hide" : "Cycle") }
    if let p = own?.place {
      if p.display == "active" { parts.append("Active display") }
      if p.display == "pointer" { parts.append("Pointer") }
      if p.center { parts.append("Centered") }
      if p.sized { parts.append(size(p)) }
      if p.isDefault { parts.append("Where it was") }
    }
    return parts.isEmpty ? "Customize…" : parts.joined(separator: " · ")
  }

  static func number(_ v: Double) -> String { v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v) }

  static func size(_ p: AppPlace) -> String {
    p.percent ? "\(number(p.width))% × \(number(p.height))%" : "\(number(p.width)) × \(number(p.height))"
  }
}

/// An application's Customize sheet: what its key does, and where its window goes when the key shows
/// it, the display, the position and the size, with what that comes to on each display connected now.
struct CustomizeSheet: View {
  @ObservedObject var page: AppsPageModel
  let global: String
  let save: (AppCustomize) -> Void

  var body: some View {
    if let c = page.customizing {
      VStack(alignment: .leading, spacing: Space.group) {
        Text(c.name).font(.title2.weight(.semibold))
        Form {
          Section("When the shortcut is pressed") {
            Picker("Mode", selection: bind(\.mode)) {
              Text("Default, \(global == "hides" ? "show and hide" : "cycle windows")").tag("default")
              Text("Cycle windows").tag("cycle")
              Text("Show and hide").tag("hides")
            }
          }
          Section {
            Picker("Display", selection: bind(\.place.display)) {
              ForEach(AppCustomize.displays, id: \.id) { Text($0.title).tag($0.id) }
            }
            Picker("Position", selection: bind(\.place.center)) {
              Text("Keep where it stands").tag(false)
              Text("Center").tag(true)
            }
            Picker("Size", selection: bind(\.place.sized)) {
              Text("Keep its size").tag(false)
              Text("Set").tag(true)
            }
            if c.place.sized {
              Picker("Measured in", selection: bind(\.place.percent)) {
                Text("Points").tag(false)
                Text("Percent of the display").tag(true)
              }
              LabeledContent("Size") {
                pair(field(\.place.width, "Width"), field(\.place.height, "Height"), c.place.percent ? "%" : "pt")
              }
              LabeledContent("At least") {
                pair(optional(\.place.minWidth, "Width"), optional(\.place.minHeight, "Height"), "pt")
              }
              LabeledContent("At most") {
                pair(optional(\.place.maxWidth, "Width"), optional(\.place.maxHeight, "Height"), "pt")
              }
            }
            if c.place.sized || c.place.center {
              LabeledContent("Padding at the sides") { single(field(\.place.padX, "Sides")) }
              LabeledContent("Padding above and below") { single(field(\.place.padY, "Above and below")) }
            }
            Text(explain(c)).font(.caption).foregroundStyle(.secondary)
          } header: {
            Text("When the shortcut shows it")
          }
          Section("On the displays connected now") {
            ForEach(Array(preview(c.place).enumerated()), id: \.offset) { _, line in
              LabeledContent(line.name) { Text(line.result).foregroundStyle(.secondary) }
            }
          }
        }
        .formStyle(.grouped)
        if let why = problem(c.place) {
          Text(why).font(.caption).foregroundStyle(.secondary)
        }
        HStack {
          Button("Reset") {
            page.customizing?.mode = "default"
            page.customizing?.place = AppPlace()
          }
          Spacer()
          Button("Cancel") { page.customizing = nil }.keyboardShortcut(.cancelAction)
          Button("Done") { done() }
            .keyboardShortcut(.defaultAction)
            .disabled(problem(c.place) != nil)
        }
      }
      .padding(Space.edge)
      .frame(width: 560, height: 700)
    }
  }

  private func explain(_ c: AppCustomize) -> String {
    var lines: [String] = []
    if let style = c.fromStyle { lines.append("Starts from Hammerspoon's \(style) style, what \(c.name) does today.") }
    switch c.place.display {
    case "active": lines.append("It goes to the display holding the window you were working in.")
    case "pointer": lines.append("It goes to the display under the pointer.")
    default: lines.append("It stays on the display it was last on, so moving it moves where it shows.")
    }
    if c.place.sized {
      lines.append("The size is held between at least and at most, then to the display less the padding, which always wins.")
    }
    return lines.joined(separator: " ")
  }

  private func problem(_ p: AppPlace) -> String? {
    guard p.sized else { return nil }
    if p.width <= 0 || p.height <= 0 { return "The width and the height are more than nothing." }
    if p.percent && (p.width > 100 || p.height > 100) { return "A share of the display is at most 100 percent." }
    if [p.minWidth, p.minHeight, p.maxWidth, p.maxHeight].contains(where: { ($0 ?? 1) <= 0 }) {
      return "At least and at most are more than nothing, or left empty."
    }
    if let a = p.minWidth, let b = p.maxWidth, a > b { return "The width at least is more than at most." }
    if let a = p.minHeight, let b = p.maxHeight, a > b { return "The height at least is more than at most." }
    return nil
  }

  /// Ends the edit of the field being typed in, so its number reaches the sheet, then saves what
  /// the sheet holds on the next turn, once that number has landed. Saving the sheet as it was drawn
  /// lost a number typed and not yet committed, and closed the sheet under the field still editing.
  private func done() {
    NSApp.keyWindow?.makeFirstResponder(nil)
    DispatchQueue.main.async {
      guard let now = page.customizing, problem(now.place) == nil else { return }
      save(now)
    }
  }

  /// A binding into the sheet. A field committing as the sheet closes reads it after `customizing`
  /// is gone, so it answers the value the sheet was drawn with then rather than crashing.
  private func bind<T>(_ path: WritableKeyPath<AppCustomize, T>) -> Binding<T> {
    let drawn = page.customizing
    return Binding(
      // Only ever built inside the body's `if let`, so the sheet as drawn is always there.
      get: { (page.customizing ?? drawn)![keyPath: path] },
      set: { page.customizing?[keyPath: path] = $0 })
  }

  /// A number field with its name as the prompt inside it and no label beside it, so a row of two
  /// stays on one line.
  private func field(_ path: WritableKeyPath<AppCustomize, Double>, _ name: String) -> some View {
    TextField(name, value: bind(path), format: .number, prompt: Text(name))
      .labelsHidden().frame(width: 72).multilineTextAlignment(.trailing).help(name)
  }

  /// The same for a value left empty when it is not set, a least or a most.
  private func optional(_ path: WritableKeyPath<AppCustomize, Double?>, _ name: String) -> some View {
    TextField(name, value: bind(path), format: .number, prompt: Text(name))
      .labelsHidden().frame(width: 72).multilineTextAlignment(.trailing).help(name)
  }

  /// One field and its unit.
  private func single<A: View>(_ a: A) -> some View {
    HStack(spacing: Space.related) {
      a
      Text("pt").foregroundStyle(.secondary).frame(width: 20, alignment: .leading)
    }
  }

  /// Two fields, the width first, a times sign between them and the unit after.
  private func pair<A: View, B: View>(_ a: A, _ b: B, _ unit: String) -> some View {
    HStack(spacing: Space.related) {
      a
      Text("×").foregroundStyle(.secondary)
      b
      Text(unit).foregroundStyle(.secondary).frame(width: 20, alignment: .leading)
    }
  }

  /// What the place comes to on each display connected now, the app's own Placement over each
  /// display's visible frame, for a window of the size given or its own.
  private func preview(_ p: AppPlace) -> [(name: String, result: String)] {
    guard let placement = Placement(p.any) else { return [] }
    let screens = NSScreen.screens
    guard let primary = screens.first?.frame else { return [] }
    return screens.map { s in
      let v = s.visibleFrame
      let box = Box(x: v.origin.x, y: primary.maxY - v.origin.y - v.height, w: v.width, h: v.height)
      let name = "\(s.localizedName), \(AppCustomize.number(v.width)) × \(AppCustomize.number(v.height))"
      guard p.sized || p.center else {
        return (name, p.display == "was" ? "Left as it is" : "Its own size, where it stands on its display")
      }
      // A window as large as the display less the padding, so a kept size reads as its own.
      let own = Box(x: box.x, y: box.y, w: 1, h: 1)
      let out = placement.place(current: own, from: box, to: box)
      let size = p.sized ? out.map { "\(AppCustomize.number($0.w)) × \(AppCustomize.number($0.h))" } ?? "" : "Its own size"
      return (name, size + (p.center ? ", centered" : ", where it stands"))
    }
  }
}
