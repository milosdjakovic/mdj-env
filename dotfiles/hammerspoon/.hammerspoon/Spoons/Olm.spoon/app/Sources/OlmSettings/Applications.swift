// The Applications page of Olm Settings, every application an app key can reach, what Olm does with
// each, and a mode of its own over its style's and the global one, docs/DESIGN-APP-SETTINGS.md
// Applications. The page draws the app toggler's setting `apptoggler.apps`, a table of applications by
// bundle id, and its catalog, what the plugin knows of each, both from the share. The applications
// installed here are the page's own to find, read at the top of /Applications, /System/Applications
// and ~/Applications and never inside a folder there, so a suite's helpers and an app's bundled
// utilities stay out, and an app that runs with no Dock icon, an agent or a background helper, is
// left out too. One kept anywhere else is added with Add Application, a file picker.
//
// A change goes to Hammerspoon as every setting's does, the whole table at once, and applies on the
// reload the window's close runs.

import AppKit
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

/// The page's own state, the applications found and the filter typed, held by the window's model
/// since a view here can keep none of its own.
@MainActor
final class AppsPageModel: ObservableObject {
  @Published var installed: [InstalledApp] = []
  @Published var filter = ""
  @Published var scanned = false
  /// Each app action's key as words, Hyper C, read from the keymap Hammerspoon shares.
  @Published var keys: [String: String] = [:]

  func scan() {
    guard !scanned else { return }
    scanned = true
    Task.detached(priority: .userInitiated) {
      let found = AppScan.scan()
      let keys = AppsPageModel.readKeys()
      await MainActor.run {
        self.installed = found
        self.keys = keys
      }
    }
  }

  /// The keys of the app actions, apptoggler.<name>, from ~/.olm/run/keymap.json, spelled in words.
  nonisolated static func readKeys() -> [String: String] {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".olm/run/keymap.json")
    guard let data = try? Data(contentsOf: url),
      let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    var out: [String: String] = [:]
    for row in doc["rows"] as? [[String: Any]] ?? [] {
      guard let id = row["id"] as? String, id.hasPrefix("apptoggler."), let key = row["key"] as? String else { continue }
      let name = String(id.dropFirst("apptoggler.".count))
      var words: [String] = []
      if let leader = row["leader"] as? String { words.append(leader.capitalized) }
      for mod in ["ctrl", "alt", "shift", "cmd"] where (row["mods"] as? [String] ?? []).contains(mod) {
        words.append(["ctrl": "Control", "alt": "Option", "shift": "Shift", "cmd": "Command"][mod] ?? mod)
      }
      words.append(key.count == 1 ? key.uppercased() : key.capitalized)
      if out[name] == nil { out[name] = words.joined(separator: " ") }
    }
    return out
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
  /// In the catalog or given something of its own, so listed first.
  var configured: Bool { catalog != nil || own != nil }
  /// Added on this page from outside the catalog, so it can be removed here.
  var removable: Bool { catalog == nil || catalog?.added == true }
}

enum AppsPage {
  static let settingId = "apptoggler.apps"
  static let modeId = "apptoggler.mode"

  /// The applications setting of a section, when it is the Applications page's.
  static func setting(in section: SettingsSection) -> Setting? {
    section.settings.first { $0.kind == .apps }
  }
}

struct AppsView: View {
  let setting: Setting
  @ObservedObject var model: SettingsModel
  @ObservedObject var page: AppsPageModel

  var body: some View {
    ScrollView {
      GlassGroup {
        VStack(alignment: .leading, spacing: Space.group) {
          header
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
          if !configured.isEmpty { card("Configured", configured) }
          if !others.isEmpty { card("Other Applications", others) }
          if !page.scanned || (page.installed.isEmpty && entries.isEmpty) {
            ProgressView().frame(maxWidth: .infinity)
          }
        }
        .padding(Space.edge)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .ignoresSafeArea(.container, edges: .top)
    .softTopEdge()
    .onAppear { page.scan() }
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
        Text("Each app key \(globalWords.lowercased()) unless an app says otherwise")
          .font(.callout).foregroundStyle(.secondary)
      }
      Spacer(minLength: Space.group)
      if let note { Note(text: note.text, symbol: note.symbol) }
    }
    .frame(height: SectionPage.header)
  }

  private var note: (text: String, symbol: String)? {
    if let refusal = model.refusal { return (refusal, "exclamationmark.triangle") }
    if model.reloadDue { return ("Applies when this window closes", "arrow.clockwise") }
    return nil
  }

  private func card(_ title: String, _ list: [AppEntry]) -> some View {
    VStack(alignment: .leading, spacing: Space.related) {
      Text(title).font(.headline).padding(.leading, Space.pad + 4)
      LazyVStack(spacing: 0) {
        ForEach(Array(list.enumerated()), id: \.element.id) { index, entry in
          if index > 0 { Divider().padding(.leading, Space.pad + 4) }
          AppRow(entry: entry, key: entry.catalog.flatMap { page.keys[$0.name] }, globalWords: globalWords,
            busy: model.busy.contains(setting.id), choose: { choose(entry, $0) }, remove: { remove(entry) })
            .padding(.horizontal, Space.pad + 4).padding(.vertical, Space.pad - 4)
        }
      }
      .glassCard(cornerRadius: 20)
    }
  }

  // MARK: What is listed

  private var table: [String: AppOverride] { setting.value.apps ?? [:] }

  private var global: String {
    model.share?.sections.flatMap(\.settings).first { $0.id == AppsPage.modeId }?.value.text ?? "cycle"
  }

  var globalWords: String { AppRow.words(global) }

  private var entries: [AppEntry] {
    var out: [AppEntry] = []
    var seen = Set<String>()
    let installed = Dictionary(page.installed.map { ($0.bundle, $0) }, uniquingKeysWith: { a, _ in a })
    for app in setting.catalog where seen.insert(app.bundle).inserted {
      out.append(AppEntry(bundle: app.bundle, name: installed[app.bundle]?.name ?? app.name,
        path: app.path ?? installed[app.bundle]?.path, catalog: app, own: table[app.bundle]))
    }
    for (bundle, own) in table where seen.insert(bundle).inserted {
      out.append(AppEntry(bundle: bundle, name: own.name ?? installed[bundle]?.name ?? bundle,
        path: own.path ?? installed[bundle]?.path, catalog: nil, own: own))
    }
    for app in page.installed where seen.insert(app.bundle).inserted {
      out.append(AppEntry(bundle: app.bundle, name: app.name, path: app.path, catalog: nil, own: nil))
    }
    let words = page.filter.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    return out
      .filter { e in words.allSatisfy { (e.name + " " + e.bundle).lowercased().contains($0) } }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private var configured: [AppEntry] { entries.filter(\.configured) }
  private var others: [AppEntry] { entries.filter { !$0.configured } }

  // MARK: Changes, the whole table sent at once

  private func send(_ next: [String: AppOverride]) {
    model.change(setting, to: .apps(next))
  }

  /// "default", "cycle" or "hides". Default on an app outside the catalog with nothing else of its own
  /// takes it off the table.
  private func choose(_ entry: AppEntry, _ mode: String) {
    var next = table
    var own = next[entry.bundle] ?? AppOverride()
    own.mode = mode == "default" ? nil : mode
    if entry.catalog == nil || entry.catalog?.added == true {
      own.name = own.name ?? entry.name
      own.path = own.path ?? entry.path
    }
    if own.mode == nil && entry.catalog != nil && entry.catalog?.added != true {
      next[entry.bundle] = nil
    } else if own.mode == nil && entry.catalog == nil && own.path == nil {
      next[entry.bundle] = nil
    } else {
      next[entry.bundle] = own
    }
    send(next)
  }

  private func remove(_ entry: AppEntry) {
    var next = table
    next[entry.bundle] = nil
    send(next)
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
    send(next)
  }
}

/// One application: its icon, its name, what Olm does with it, and its mode, the default naming the
/// style's or the global one it follows.
struct AppRow: View {
  let entry: AppEntry
  let key: String?
  let globalWords: String
  let busy: Bool
  let choose: (String) -> Void
  let remove: () -> Void

  static func words(_ mode: String) -> String { mode == "hides" ? "Shows and hides" : "Cycles through windows" }

  var body: some View {
    HStack(alignment: .center, spacing: Space.pad) {
      Image(nsImage: icon)
        .resizable()
        .frame(width: 28, height: 28)
      VStack(alignment: .leading, spacing: Space.related / 2) {
        Text(entry.name)
        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
      }
      Spacer(minLength: Space.pad)
      HStack(spacing: Space.pad) {
        Spacer(minLength: 0)
        Button(action: remove) { Image(systemName: "minus.circle") }
          .buttonStyle(.borderless)
          .help("Remove \(entry.name) from Olm")
          .opacity(entry.removable && entry.own != nil ? 1 : 0)
          .disabled(!(entry.removable && entry.own != nil))
        Picker(entry.name, selection: Binding(get: { entry.own?.mode ?? "default" }, set: choose)) {
          Text(defaultTitle).tag("default")
          Divider()
          Text("Cycle through windows").tag("cycle")
          Text("Show and hide").tag("hides")
        }
        .labelsHidden()
        .fixedSize()
      }
      .frame(width: Space.control)
    }
    .disabled(busy)
  }

  /// What the default follows, the style's hides where it states one, otherwise the global mode.
  private var defaultTitle: String {
    if let hides = entry.catalog?.hides, let style = entry.catalog?.style {
      return "Default, \(Self.words(hides ? "hides" : "cycle")) (\(style))"
    }
    return "Default, \(globalWords)"
  }

  private var detail: String {
    var parts: [String] = []
    if let key { parts.append(key) }
    if let style = entry.catalog?.style { parts.append("Style \(style)" + (entry.catalog?.placed == true ? ", placed" : "")) }
    if entry.own?.mode != nil { parts.append("Its own mode") }
    if entry.catalog == nil || entry.catalog?.added == true {
      parts.append(entry.own == nil ? "Not used by Olm" : "Added")
    }
    if parts.isEmpty { parts.append("In the catalog") }
    if let path = entry.path, entry.catalog?.added == true || entry.catalog == nil, entry.own?.path != nil {
      parts.append(path)
    }
    return parts.joined(separator: " · ")
  }

  private var icon: NSImage {
    if let path = entry.path { return NSWorkspace.shared.icon(forFile: path) }
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundle) {
      return NSWorkspace.shared.icon(forFile: url.path)
    }
    return NSWorkspace.shared.icon(for: .applicationBundle)
  }
}
