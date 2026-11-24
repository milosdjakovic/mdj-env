// The Olm Settings window, docs/DESIGN-APP-SETTINGS.md. An ordinary macOS window drawn with the
// system's own controls and built on Liquid Glass: the system's own sidebar of sections with a
// search field over it, and on the right the chosen section's header and its settings on glass
// cards over a soft wash of the accent colour, so the glass has something to bend. It draws
// whatever the share lists, SettingsShare, read again each time the window is shown, since
// Hammerspoon writes it at every load.
//
// While the window is open the app is an ordinary one, in the Dock and in Command Tab with a menu
// bar of its own, and it goes back to running without either when the window closes, since the
// lists it shows otherwise belong to no app a person switches to.
//
// A change goes to Hammerspoon over the bridge, S.3, which checks it, saves it and applies it, and
// answers with the share as it stands, which the window then draws, so it never shows a value
// Hammerspoon did not take. A setting that applies on reload is applied once, when the window
// closes.

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// What the window is showing, the section chosen, the search typed, a slider being dragged and the
/// last refusal. A class the window owns rather than view state, since the command line tools the
/// app builds with ship no SwiftUI macros and @State is one in macOS 27's SDK.
@MainActor
final class SettingsModel: ObservableObject {
  @Published var share: SettingsShare?
  @Published var selection: String? {
    didSet { if oldValue != selection { pluginPage = nil } }
  }
  /// The plugin whose own page is open inside Plugins, nil for the Plugins list itself.
  @Published var pluginPage: String?
  @Published var query = ""
  /// The search result highlighted in the dropdown, by its place.
  @Published var hit = 0
  /// The row a search chose, which its page scrolls to once it holds it, and the row lit for it.
  @Published var focus: String?
  @Published var lit: String?
  /// A slider's value while it is dragged, sent when it is let go.
  @Published var drafts: [String: Double] = [:]
  /// A text setting's words while they are typed, sent on Return or when the field is left.
  @Published var texts: [String: String] = [:]
  /// The last change Hammerspoon refused, the setting's title and why.
  @Published var refusal: String?
  /// A change taken that applies on reload, so the window reloads once when it closes.
  @Published var reloadDue = false
  @Published var busy: Set<String> = []
  /// Where the window's close button starts, which the sidebar's search and the app's row line up
  /// with.
  @Published var leading: CGFloat = 20
  /// How far the window's buttons reach down from the top, which the search sits a group's gap under.
  @Published var buttonsBottom: CGFloat = 32
  /// How far down the window's buttons' middle is, which Back on a page is centred on.
  @Published var buttonsMid: CGFloat = 20
  let service: SettingsService?
  /// The permissions the Permissions page lists, and whether macOS gives each now.
  let permissions: [Permission]
  @Published var granted: [String: Bool] = [:]
  /// The Applications page's own state, what is installed and the filter, kept across visits.
  let appsPage = AppsPageModel()
  /// The Window Management page's size being edited.
  let sizeEditor = SizeEditor()

  /// Each setting's value as Hammerspoon runs it, read when the window opens, so a row says it
  /// applies on reload only once its value has moved off that one.
  @Published var running: [String: SettingValue] = [:]

  func markRunning() {
    var values: [String: SettingValue] = [:]
    for section in share?.sections ?? [] { for setting in section.settings where values[setting.id] == nil {
      values[setting.id] = setting.value
    } }
    running = values
  }

  /// The browsers and profiles found, for a picks setting whose source is browsers, read as its row
  /// is shown.
  @Published var browsers: BrowserScan?

  /// Each handler setting's scheme to the path of the app macOS opens it with now.
  @Published var handlers: [String: String] = [:]

  func readHandler(_ scheme: String) {
    guard let probe = URL(string: scheme + "://example.com") else { return }
    let path = NSWorkspace.shared.urlForApplication(toOpen: probe)?.path ?? ""
    if handlers[scheme] != path { handlers[scheme] = path }
  }

  /// Whether a setting's saved value waits for the reload as the window closes.
  func waitsForReload(_ setting: Setting) -> Bool {
    setting.needsReload && running[setting.id].map { $0 != setting.value } == true
  }

  init(share: SettingsShare?, service: SettingsService?, permissions: [Permission] = []) {
    self.share = share
    self.service = service
    self.permissions = permissions
    selection = share?.sections.first?.id ?? (permissions.isEmpty ? nil : PermissionsPage.id)
    appsPage.warm(share)
    markRunning()
  }

  /// The share's sections, then the Permissions page when it has any to list. A search never
  /// narrows them, it answers in the dropdown under the field.
  var sections: [SettingsSection] {
    var out = share?.sections ?? []
    if !permissions.isEmpty { out.append(PermissionsPage.section) }
    return out
  }

  /// What the search finds now.
  var hits: [SearchHit] { SettingsSearch.find(query, in: SettingsSearch.index(self)) }

  /// Opens the hit's section and hands its page the row to go to, closing the dropdown.
  func jump(to hit: SearchHit) {
    if hit.id.hasPrefix("app:") { appsPage.filter = "" }
    selection = hit.section
    pluginPage = hit.page
    focus = hit.id
    query = ""
  }

  /// Asks macOS about each permission again, publishing only a change.
  func recheck() {
    var now: [String: Bool] = [:]
    for p in permissions { now[p.id] = p.check() }
    if now != granted { granted = now }
  }

  var current: SettingsSection? { sections.first(where: { $0.id == selection }) ?? sections.first }

  /// Sends one change, or a reset, and draws the share Hammerspoon answers with.
  func change(_ setting: Setting, to value: SettingValue, reset: Bool = false) {
    guard let service else {
      refusal = "\(setting.title) was not changed, Olm.app has no bridge to Hammerspoon."
      return
    }
    busy.insert(setting.id)
    Task { @MainActor in
      let answer = await service.change(setting.id, value, reset)
      busy.remove(setting.id)
      drafts[setting.id] = nil
      if let share = answer.share { self.share = share }
      if answer.ok {
        refusal = nil
        if setting.needsReload { reloadDue = true }
      } else {
        refusal = "\(setting.title) \(answer.why ?? "was not taken")."
      }
    }
  }
}

/// The window, made once and shown again with the share as it stands.
@MainActor
public final class SettingsWindow: NSObject, NSWindowDelegate {
  private var window: NSWindow?
  private var model: SettingsModel?
  private let share: () -> SettingsShare?
  private let service: SettingsService?
  private let permissions: [Permission]

  /// permissions, every permission the app uses, listed on the Permissions page.
  public init(share: @escaping () -> SettingsShare? = { SettingsShare.read() }, service: SettingsService? = nil,
    permissions: [Permission] = []) {
    self.share = share
    self.service = service
    self.permissions = permissions
  }

  public var isShown: Bool { window?.isVisible ?? false }

  /// Shows the window over the app in front, centred on the screen under the pointer when it was
  /// closed, and makes it key, since typing goes into its search. The app becomes an ordinary one
  /// while it is open, so Command Tab finds it.
  public func show() {
    if window != nil, let model {
      // The share as Hammerspoon wrote it at its last load, the section and search kept.
      model.share = share()
      model.markRunning()
      if !model.sections.contains(where: { $0.id == model.selection }) { model.selection = model.sections.first?.id }
    } else {
      build()
    }
    if let window, !window.isVisible { Self.centre(window) }
    let becoming = NSApp.activationPolicy() != .regular
    NSApp.setActivationPolicy(.regular)
    NSApp.mainMenu = Self.menu()
    window?.makeKeyAndOrderFront(nil)
    alignToButtons()
    // An app turned ordinary is activated once the change has taken, a turn of the run loop later.
    // Activated in the same turn, macOS never counted it as the app in front, so Command Tab kept it
    // last however recently it was used.
    //
    // NSApp.activate is only a request since macOS 14, and one made from Olm's own list, a panel
    // that never activates, or from the bridge is turned down: the window still took key, so it
    // looked in front, while macOS never counted Olm as used and the switchers listed it last. So
    // Olm also opens itself through Launch Services, as the Dock does, which macOS honours.
    let front = {
      NSApp.activate()
      self.window?.makeKeyAndOrderFront(nil)
      guard !NSApp.isActive else { return }
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in }
    }
    if becoming { DispatchQueue.main.async(execute: front) } else { front() }
    watchEscape()
  }

  private var escape: Any?

  /// Escape closes the window, unless the search has text, which Escape clears first, or a menu or
  /// the key recorder is taking it.
  private func watchEscape() {
    guard escape == nil else { return }
    escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let window = self.window, event.window === window, event.keyCode == 53,
        event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .function]).isEmpty,
        self.model?.appsPage.recording == nil else { return event }
      if let editor = window.firstResponder as? NSTextView, !editor.string.isEmpty { return event }
      window.performClose(nil)
      return nil
    }
  }

  /// The sidebar's search and the app's row start where the close button does, read off the
  /// window rather than guessed, since the system places the buttons.
  private func alignToButtons() {
    guard let window, let model, let close = window.standardWindowButton(.closeButton) else { return }
    let frame = close.convert(close.bounds, to: nil)
    let left = frame.minX
    if left > 0, abs(model.leading - left) > 0.5 { model.leading = left }
    if let height = window.contentView?.bounds.height {
      let bottom = height - frame.minY
      if bottom > 0, abs(model.buttonsBottom - bottom) > 0.5 { model.buttonsBottom = bottom }
      let mid = height - frame.midY
      if mid > 0, abs(model.buttonsMid - mid) > 0.5 { model.buttonsMid = mid }
    }
  }

  /// Builds the window and lays it out without showing it, called by the app a moment after it
  /// starts, so the first open shows a window already drawn rather than building SwiftUI's views
  /// while it comes up, which was slow and flickered.
  public func prepare() {
    guard window == nil else { return }
    build()
    window?.contentView?.layoutSubtreeIfNeeded()
    alignToButtons()
  }

  private func build() {
    let model = SettingsModel(share: share(), service: service, permissions: permissions)
    self.model = model
    let w = NSWindow(contentViewController: SettingsSplit(model: model))
    w.title = "Olm Settings"
    w.titleVisibility = .hidden
    w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    // An empty toolbar in the full unified style, as Finder has, so the window's buttons sit lower
    // and further in with room around them, over a see-through title bar with no line, so no band is
    // drawn over the pane. The compact style drew one when the pointer reached the top.
    w.toolbar = NSToolbar(identifier: "OlmSettings")
    w.toolbarStyle = .unified
    w.titlebarAppearsTransparent = true
    w.titlebarSeparatorStyle = .none
    w.isReleasedWhenClosed = false
    w.setContentSize(NSSize(width: 1100, height: 740))
    w.contentMinSize = NSSize(width: SettingsSplit.sidebarWidth + 560, height: 520)
    // The size is kept between openings and the place is not, since it opens centred. Named
    // afresh with each larger default, so a size saved at an older one is not restored.
    w.setFrameAutosaveName("OlmSettingsPaneFrame")
    w.delegate = self
    window = w
  }

  public func close() { window?.close() }

  /// The window centred on the screen under the pointer, the screen every Olm list opens on, and
  /// no larger than that screen leaves room for.
  static func centre(_ window: NSWindow) {
    let pointer = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main
    else { return window.center() }
    let room = screen.visibleFrame
    var frame = window.frame
    frame.size.width = min(frame.width, room.width)
    frame.size.height = min(frame.height, room.height)
    frame.origin = NSPoint(x: (room.midX - frame.width / 2).rounded(), y: (room.midY - frame.height / 2).rounded())
    window.setFrame(frame, display: false)
  }

  /// Back to an app with no Dock icon and no menu bar once the window is gone, the app in front
  /// before it given the keyboard back, and a change waiting for a reload applied.
  public func windowWillClose(_ notification: Notification) {
    if let model, model.reloadDue, let service {
      model.reloadDue = false
      Task { await service.done() }
    }
    DispatchQueue.main.async {
      guard !(self.window?.isVisible ?? false) else { return }
      NSApp.mainMenu = nil
      NSApp.setActivationPolicy(.accessory)
      NSApp.deactivate()
    }
  }

  /// The menu bar while the window is open, the app's own menu, Edit for the search field's
  /// Command C and V, and Window for Command W and M.
  static func menu() -> NSMenu {
    let main = NSMenu()
    func add(_ title: String, _ items: [NSMenuItem?]) {
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      let menu = NSMenu(title: title)
      for i in items { menu.addItem(i ?? .separator()) }
      item.submenu = menu
      main.addItem(item)
    }
    func item(_ title: String, _ action: String, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
      let i = NSMenuItem(title: title, action: Selector(action), keyEquivalent: key)
      i.keyEquivalentModifierMask = mods
      return i
    }
    add("Olm", [item("Hide Olm", "hide:", "h"), nil, item("Quit Olm", "terminate:", "q")])
    add("Edit", [item("Undo", "undo:", "z"), item("Redo", "redo:", "z", [.command, .shift]), nil,
      item("Cut", "cut:", "x"), item("Copy", "copy:", "c"), item("Paste", "paste:", "v"),
      item("Select All", "selectAll:", "a")])
    add("Window", [item("Minimize", "performMiniaturize:", "m"), item("Close", "performClose:", "w")])
    return main
  }
}

/// The sidebar and the pane as AppKit's own split, a sidebar item so it is drawn as the running
/// system draws sidebars, macOS 27 having left macOS 26's floating glass panel, and runs under the
/// window's buttons. SwiftUI's NavigationSplitView ignored its column width in a
/// window made by hand, about 140 points whatever was asked, and a width forced onto its split view
/// afterwards flickered as the window resized and collapsed when dragged left. Here the width is
/// the item's own, fixed, the divider takes no drag and the sidebar cannot collapse.
@MainActor
final class SettingsSplit: NSSplitViewController {
  static let sidebarWidth: CGFloat = 280

  init(model: SettingsModel) {
    super.init(nibName: nil, bundle: nil)
    // Neither hosting controller sizes the window, which it otherwise does once SwiftUI has measured
    // its views, after the window is up, and which showed as a flicker on open.
    let side = NSHostingController(rootView: SettingsSidebar(model: model))
    side.sizingOptions = []
    let sidebar = NSSplitViewItem(sidebarWithViewController: side)
    sidebar.minimumThickness = Self.sidebarWidth
    sidebar.maximumThickness = Self.sidebarWidth
    sidebar.canCollapse = false
    sidebar.allowsFullHeightLayout = true
    sidebar.holdingPriority = .required
    let pane = NSHostingController(rootView: SettingsDetail(model: model))
    pane.sizingOptions = []
    let detail = NSSplitViewItem(viewController: pane)
    detail.minimumThickness = 560
    addSplitViewItem(sidebar)
    addSplitViewItem(detail)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("not from a nib") }

  /// No place on the divider answers a drag, so the width cannot be changed or the sidebar hidden.
  override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect,
                          forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect { .zero }

  override func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }
}

/// Every gap in the window is one of these, so the layout reads as one system and a change keeps
/// to it. docs/DESIGN-APP-SETTINGS.md, under Layout, states the rules beside them.
enum Space {
  /// From a container's edge to what it holds, the pane's page on all four sides.
  static let edge: CGFloat = 24
  /// Between groups, the header and the card, the search and the sections, the sections and the
  /// app's row.
  static let group: CGFloat = 20
  /// Inside a card or a sidebar row, from its edge to its content, and between a picture and its
  /// text.
  static let pad: CGFloat = 12
  /// Between related elements, a title and the line under it, a control and its value.
  static let related: CGFloat = 6
  /// Between the rows of one list.
  static let row: CGFloat = 2
  /// The height of a sidebar row and of the search, one line of text and its pad.
  static let rowHeight: CGFloat = 32
  /// The width a number's value is shown in, the widest it can be, so dragging moves nothing.
  static let value: CGFloat = 76
  /// A number's slider.
  static let slider: CGFloat = 200
  /// A reset beside a control, kept in place while hidden.
  static let mark: CGFloat = 16
  /// The column a row's control sits in, fixed, so a popup's width changing with its choice moves
  /// nothing else in the row. Made of its widest content, a number's reset, slider and value with
  /// a pad between each, since a column narrower than that let the value overflow it, centred, and
  /// stand half the overflow nearer the card's right edge than the title stands to its left.
  static let control: CGFloat = mark + pad + slider + pad + value
}

/// The search, the sections and the app's row. The sidebar's edge is where the window's close
/// button starts, read off the window, so the search, every row's highlight and the buttons share
/// one left edge, and the same gap is kept on the right.
struct SettingsSidebar: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    let hits = model.query.isEmpty ? [] : model.hits
    VStack(alignment: .leading, spacing: Space.group) {
      SearchField(text: $model.query, move: { move($0, hits.count) }, submit: {
        if hits.indices.contains(model.hit) { model.jump(to: hits[model.hit]) }
      })
      ScrollView {
        VStack(spacing: Space.row) {
          ForEach(model.sections) { section in
            SidebarRow(section: section, selected: section.id == model.current?.id) {
              model.selection = section.id
            }
          }
        }
      }
      .scrollIndicators(.never)
      // The dropdown stands over the sections while something is typed, so nothing below moves.
      .overlay(alignment: .top) {
        if !model.query.isEmpty {
          SearchResults(model: model, page: model.appsPage, hits: hits, highlighted: model.hit) { model.jump(to: $0) }
            .fixedSize(horizontal: false, vertical: hits.count < 12)
        }
      }
      AppIdentity(model: model).padding(.horizontal, Space.pad)
    }
    // Half the close button's distance from the window's edge on the left, the right and the foot,
    // and half a group's gap under the window's buttons, measured from the window's top rather than
    // from under the title bar, asked by Milos on 2026-11-24. The buttons stay where macOS puts them.
    .padding(.horizontal, model.leading / 2)
    .padding(.top, model.buttonsBottom + Space.group / 2)
    .padding(.bottom, model.leading / 2)
    .ignoresSafeArea(.container, edges: .top)
    .onChange(of: model.query) { model.hit = 0 }
  }

  /// Up and down in the search move through the results while there are any, and between the
  /// sections otherwise, as in System Settings.
  private func move(_ by: Int, _ count: Int) {
    if !model.query.isEmpty {
      if count > 0 { model.hit = min(max(model.hit + by, 0), count - 1) }
      return
    }
    let sections = model.sections
    guard !sections.isEmpty else { return }
    let at = sections.firstIndex(where: { $0.id == model.current?.id }) ?? 0
    model.selection = sections[min(max(at + by, 0), sections.count - 1)].id
  }
}

/// One section in the sidebar. The highlight is a fill behind the row and nothing else changes when
/// it moves, no weight and no size, so choosing a section shifts nothing.
struct SidebarRow: View {
  let section: SettingsSection
  let selected: Bool
  let choose: () -> Void

  var body: some View {
    Button(action: choose) {
      HStack(spacing: Space.pad) {
        Image(systemName: section.symbol)
          .foregroundStyle(.tint)
          .frame(width: 20)
        Text(section.title)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, Space.pad)
      .frame(height: Space.rowHeight)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(selected ? Color.primary.opacity(0.09) : .clear)
      )
    }
    .buttonStyle(.plain)
  }
}

/// The search over the sections, a Liquid Glass capsule a row tall and a little more, its magnifier
/// in line with the sections' symbols, the field inside it plain so the glass is the only bezel. The
/// clear button keeps its place when hidden, so typing moves nothing.
struct SearchField: View {
  @Binding var text: String
  let move: (Int) -> Void
  let submit: () -> Void

  var body: some View {
    HStack(spacing: Space.pad) {
      Image(systemName: "magnifyingglass").foregroundStyle(.secondary).frame(width: 20)
      TextField("Search", text: $text)
        .textFieldStyle(.plain)
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onSubmit(submit)
      Button { text = "" } label: {
        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .opacity(text.isEmpty ? 0 : 1)
      .disabled(text.isEmpty)
    }
    .padding(.horizontal, Space.pad)
    .frame(height: Space.rowHeight + 4)
    .glassCapsule()
  }
}

/// The chosen section on the window's own background.
struct SettingsDetail: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    Group {
      if model.current?.id == PermissionsPage.id {
        PermissionsView(model: model)
      } else if let section = model.current, let apps = AppsPage.setting(in: section) {
        AppsView(setting: apps, model: model, page: model.appsPage)
          .id(section.id)
      } else if let section = model.current, let sizes = WindowsPage.setting(in: section) {
        WindowsView(section: section, setting: sizes, model: model, page: model.appsPage, editor: model.sizeEditor)
          .id(section.id)
      } else if model.share == nil {
        ContentUnavailableView("No settings yet", systemImage: "gearshape",
          description: Text("Hammerspoon writes them when it loads, with the olmapp piece on."))
      } else if let section = model.current, let plugin = model.pluginPage,
        section.settings.contains(where: { $0.page == plugin }) {
        SectionPage(section: section, model: model, plugin: plugin)
          .id(section.id + "/" + plugin)
      } else if let section = model.current {
        SectionPage(section: section, model: model)
          .id(section.id)
      } else {
        ContentUnavailableView.search(text: model.query)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// The app's icon, name and version at the foot of the sidebar, its icon's left edge in line with
/// the sections' symbols.
struct AppIdentity: View {
  @ObservedObject var model: SettingsModel

  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
  }

  var body: some View {
    HStack(spacing: Space.pad) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .interpolation(.high)
        .frame(width: 36, height: 36)
      VStack(alignment: .leading, spacing: Space.row) {
        Text("Olm").font(.headline)
        Text("Version \(version)").font(.subheadline).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      // Olm's whole config, every value set in this window, written to a file and read back, so a
      // second Mac takes the same Olm, docs/DESIGN-APP-SETTINGS.md Export and import.
      Menu {
        Button("Export Olm Config…") { OlmConfig.export(model) }
        Button("Import Olm Config…") { OlmConfig.importInto(model) }
      } label: {
        Image(systemName: "square.and.arrow.up.on.square")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .help("Export or import Olm's config")
    }
  }
}

/// Olm's config as a file, the values of ~/.olm/state/settings.json, the one store, under a kind so
/// an import knows it holds one.
@MainActor
enum OlmConfig {
  static let kind = "olm.config"
  static var store: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".olm/state/settings.json")
  }

  static func export(_ model: SettingsModel) {
    let doc = (try? Data(contentsOf: store)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    let values = doc?["values"] as? [String: Any] ?? [:]
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Olm Config.json"
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let out: [String: Any] = ["kind": kind, "version": 1,
      "exported": ISO8601DateFormatter().string(from: Date()), "values": values]
    guard let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]),
      (try? data.write(to: url, options: .atomic)) != nil else {
      model.refusal = "The config could not be written to \(url.lastPathComponent)."
      return
    }
    model.refusal = nil
  }

  static func importInto(_ model: SettingsModel) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url,
      let data = try? Data(contentsOf: url),
      let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let values = doc["values"] as? [String: Any],
      let json = try? JSONSerialization.data(withJSONObject: values) else {
      model.refusal = "That file holds no Olm config."
      return
    }
    guard let service = model.service else {
      model.refusal = "The config was not imported, Olm.app has no bridge to Hammerspoon."
      return
    }
    Task { @MainActor in
      let answer = await service.importValues(json)
      if let share = answer.share { model.share = share }
      model.reloadDue = true
      model.refusal = answer.refused.isEmpty ? nil : "Imported, except \(answer.refused.joined(separator: "; "))."
    }
  }
}

/// One section, its header and its settings on one glass card. The line saying a change waits for
/// the window to close, or was refused, sits in a fixed place at the header's right, so it comes and
/// goes without moving the card.
struct SectionPage: View {
  /// The header's height, the section's picture.
  static let header: CGFloat = 60
  let section: SettingsSection
  @ObservedObject var model: SettingsModel
  /// The plugin whose own page this is, its switch first and its settings after, nil for the
  /// section's own page, which leaves those settings to each plugin's page.
  var plugin: String? = nil

  /// The plugin's switch in Plugins, whose title and picture its page wears.
  private var owner: Setting? { section.settings.first { $0.plugin != nil && $0.plugin == plugin } }

  private var rows: [Setting] {
    guard let plugin else { return section.settings.filter { $0.page == nil } }
    return (owner.map { [$0] } ?? []) + section.settings.filter { $0.page == plugin }
  }

  /// The plugins that have a page of their own, each reached from its switch.
  private var pages: Set<String> { Set(section.settings.compactMap(\.page)) }

  var body: some View {
    ScrollViewReader { proxy in
    ScrollView {
      GlassGroup {
        VStack(alignment: .leading, spacing: Space.group) {
          PageHeader(title: owner?.title ?? section.title,
            subtitle: rows.count == 1 ? "1 setting" : "\(rows.count) settings", note: note) {
            SectionSymbol(symbol: section.symbol)
          }
          VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, setting in
              if index > 0 { Divider().padding(.leading, Space.pad + 4) }
              // A plugin with a page of its own is reached by the gear just before its switch, so
              // every switch stays in the one column at the right.
              let page = plugin == nil ? setting.plugin.flatMap { pages.contains($0) ? $0 : nil } : nil
              SettingRow(setting: setting, model: model, page: page,
                pageSet: page.map { p in section.settings.contains { $0.page == p && $0.differs } } ?? false)
              .padding(.horizontal, Space.pad + 4).padding(.vertical, Space.pad)
              .searchMark(model, SearchTarget.setting(setting.id))
            }
          }
          .glassCard(cornerRadius: 20)
        }
        .padding(Space.edge)
        // Room under Back, which sits in the window's top bar beside its buttons.
        .padding(.top, plugin == nil ? 0 : model.buttonsBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    // The gap is measured from the window's edge at the top too, since nothing is drawn over the
    // pane, so the page sits the same distance from all four edges.
    .ignoresSafeArea(.container, edges: .top)
    .softTopEdge()
    .backBar(plugin == nil ? nil : section.title, model: model) { model.pluginPage = nil }
    .searchJump(model, proxy, Set(rows.map { SearchTarget.setting($0.id) }))
    }
  }

  private var note: (text: String, symbol: String) {
    if let refusal = model.refusal { return (refusal, "exclamationmark.triangle") }
    if model.reloadDue { return ("Applies when this window closes", "arrow.clockwise") }
    return ("", "arrow.clockwise")
  }
}

/// One line in a glass capsule as wide as its words, at the header's right, a long refusal wrapped to
/// two lines in its place rather than pushing the header.
struct Note: View {
  let text: String
  let symbol: String

  var body: some View {
    // As wide as its words on one line, and only a long refusal wraps to two, at most 420 wide.
    ViewThatFits(in: .horizontal) {
      capsule(Label(text, systemImage: symbol).lineLimit(1).fixedSize())
      capsule(Label(text, systemImage: symbol).lineLimit(2).frame(width: 420, alignment: .leading))
    }
  }

  private func capsule(_ content: some View) -> some View {
    content
      .font(.callout).foregroundStyle(.secondary)
      .padding(.horizontal, Space.pad).padding(.vertical, Space.related + 2)
      .glassCard(cornerRadius: 999)
  }
}

struct SettingRow: View {
  let setting: Setting
  @ObservedObject var model: SettingsModel
  /// The plugin page the gear before the control opens, nil for a row with none.
  var page: String? = nil
  /// Whether that page holds a value moved off the config files, the gear then in the accent.
  var pageSet = false

  var body: some View {
    // The reset button sits a pad's gap before the control, in the control's column of fixed width,
    // and keeps its place when hidden, so the reset appearing moves nothing in the row.
    let canReset = setting.differs && setting.locked == nil
    VStack(alignment: .leading, spacing: Space.pad) {
    HStack(alignment: .center, spacing: Space.pad) {
      label
      Spacer(minLength: Space.pad)
      HStack(spacing: Space.pad) {
        Spacer(minLength: 0)
        UndoButton(shown: canReset) { model.change(setting, to: .none, reset: true) }
        if let page {
          PageButton(set: pageSet, help: "Settings of \(setting.title)") { model.pluginPage = page }
        }
        control.labelsHidden()
      }
      .frame(width: Space.control)
    }
      // A text of several lines takes the row's whole width under its title, since a list of
      // entries is wider than the control column.
      if setting.kind == .text, (setting.lines ?? 1) > 1 { TextSetting(setting: setting, model: model) }
      if setting.kind == .picks { PicksSetting(setting: setting, model: model) }
    }
    .disabled(setting.locked != nil || model.busy.contains(setting.id))
    .help(setting.locked ?? "")
  }

  @ViewBuilder private var label: some View {
    VStack(alignment: .leading, spacing: Space.related / 2) {
      Text(setting.title)
      if let detail = setting.detail, !detail.isEmpty {
        Text(detail).font(.caption).foregroundStyle(.secondary)
      }
      if let locked = setting.locked {
        Text("Locked, \(locked)").font(.caption).foregroundStyle(.secondary)
      } else if setting.needsReload {
        // Said only once the value has moved off the running one, its line kept while hidden so
        // a change grows no row.
        Label("Applies on reload", systemImage: "arrow.clockwise")
          .font(.caption).foregroundStyle(.secondary)
          .opacity(model.waitsForReload(setting) ? 1 : 0)
      }
    }
  }

  private var choice: Binding<String> {
    Binding(get: { setting.value.text ?? "" }, set: { value in
      if value != setting.value.text { model.change(setting, to: .text(value)) }
    })
  }

  private var flag: Binding<Bool> {
    Binding(get: { setting.value.flag ?? false }, set: { value in
      if value != setting.value.flag { model.change(setting, to: .flag(value)) }
    })
  }

  /// The slider's value, the drag's while it is held, snapped to the setting's step.
  private func number(_ lo: Double, _ hi: Double) -> Binding<Double> {
    Binding(get: { model.drafts[setting.id] ?? min(max(setting.value.number ?? lo, lo), hi) }, set: { value in
      var v = value
      if let step = setting.step, step > 0 { v = (v / step).rounded() * step }
      model.drafts[setting.id] = min(max(v, lo), hi)
    })
  }

  @ViewBuilder private var control: some View {
    switch setting.kind {
    case .choice:
      Picker(setting.title, selection: choice) {
        ForEach(setting.choices) { choice in Text(choice.title).tag(choice.value) }
        if let v = setting.value.text, !setting.choices.contains(where: { $0.value == v }) {
          Text(v).tag(v)
        }
      }
      .fixedSize()
    case .switch:
      // The mini switch System Settings draws, so a row's switch never outweighs its title.
      Toggle(setting.title, isOn: flag)
        .toggleStyle(.switch)
        .controlSize(.mini)
    case .checkbox:
      Toggle(setting.title, isOn: flag)
        .toggleStyle(.checkbox)
    case .handler:
      HandlerSetting(setting: setting, model: model)
    case .picks:
      // Drawn under the title across the row, PicksSetting.
      EmptyView()
    case .text:
      if (setting.lines ?? 1) > 1 { EmptyView() } else { TextSetting(setting: setting, model: model) }
    case .number:
      HStack(spacing: Space.pad) {
        if let lo = setting.min, let hi = setting.max, lo < hi {
          Slider(value: number(lo, hi), in: lo...hi) { editing in
            if !editing, let v = model.drafts[setting.id] {
              if v != setting.value.number { model.change(setting, to: .number(v)) } else { model.drafts[setting.id] = nil }
            }
          }
          .frame(width: Space.slider)
        }
        Text(SettingFormat.number(model.drafts[setting.id] ?? setting.value.number ?? 0, step: setting.step,
          unit: setting.unit))
          .monospacedDigit()
          .lineLimit(1)
          .frame(width: Space.value, alignment: .trailing)
      }
    case .font:
      Picker(setting.title, selection: choice) {
        ForEach(FontChoices.names(including: setting.value.text), id: \.self) { name in
          Text(SettingFormat.font(name)).tag(name)
        }
      }
      .fixedSize()
    case .apps, .keys, .sizes:
      // Drawn by their own page, AppsView, never as a row.
      EmptyView()
    case .other:
      Text(String(describing: setting.value))
    }
  }
}

/// A text setting's field, sent when Return is pressed or the field is left, a text past its length
/// cut there as it is typed.
struct TextSetting: View {
  let setting: Setting
  @ObservedObject var model: SettingsModel
  @FocusState private var focused: Bool

  private var text: Binding<String> {
    Binding(get: { model.texts[setting.id] ?? setting.value.text ?? "" }, set: { value in
      model.texts[setting.id] = setting.maxLength.map { String(value.prefix($0)) } ?? value
    })
  }

  var body: some View {
    if let lines = setting.lines, lines > 1 {
      // Return starts a new entry, so the words are sent when the box is left or the page closes.
      TextEditor(text: text)
        .font(.body.monospaced())
        .scrollContentBackground(.hidden)
        .padding(Space.related)
        .frame(height: CGFloat(lines) * 17 + Space.related * 2)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        .overlay(alignment: .topLeading) {
          if text.wrappedValue.isEmpty, let placeholder = setting.placeholder {
            Text(placeholder).font(.body.monospaced()).foregroundStyle(.tertiary)
              .padding(Space.related).padding(.leading, 5).allowsHitTesting(false)
          }
        }
        .focused($focused)
        .onChange(of: focused) { if !focused { send() } }
        .onDisappear(perform: send)
    } else {
      TextField(setting.title, text: text, prompt: setting.placeholder.map { Text($0) })
        .textFieldStyle(.roundedBorder)
        .frame(width: Space.slider)
        .focused($focused)
        .onSubmit(send)
        .onChange(of: focused) { if !focused { send() } }
        .onDisappear(perform: send)
    }
  }

  private func send() {
    guard let text = model.texts.removeValue(forKey: setting.id) else { return }
    if text != (setting.value.text ?? "") { model.change(setting, to: .text(text)) }
  }
}

/// A list of names checked off what Olm.app finds, a checkbox each, the found ones first and the
/// fixed ones after, saved in that order. A name saved and no longer found stays listed, checked,
/// so it can be taken off. What macOS kept from Olm is said under the list, with the way to the
/// permission that lifts it.
struct PicksSetting: View {
  let setting: Setting
  @ObservedObject var model: SettingsModel

  private var picked: [String] {
    if case .names(let n) = setting.value { return n }
    return []
  }

  private var found: [String] {
    switch setting.source {
    case "browsers": return model.browsers?.targets.map(\.title) ?? []
    default: return []
    }
  }

  private var options: [String] {
    var all = found + setting.fixed
    for name in picked where !all.contains(name) { all.append(name) }
    return all
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Space.related) {
      ForEach(options, id: \.self) { name in
        Toggle(isOn: Binding(get: { picked.contains(name) }, set: { flip(name, $0) })) {
          Text(found.contains(name) || setting.fixed.contains(name) ? name : "\(name), not on this Mac")
        }
        .toggleStyle(.checkbox)
      }
      if setting.source == "browsers", let hidden = model.browsers?.hidden, !hidden.isEmpty {
        HStack(spacing: Space.related) {
          Text("macOS keeps \(hidden.joined(separator: ", "))'s profiles from Olm until it has Full Disk Access.")
            .font(.caption).foregroundStyle(.secondary)
          Button("Open Permissions") { model.selection = PermissionsPage.id }
            .buttonStyle(.link).font(.caption)
        }
      }
    }
    .onAppear { if setting.source == "browsers" { model.browsers = Browsers.refresh() } }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      if setting.source == "browsers" { model.browsers = Browsers.refresh() }
    }
  }

  private func flip(_ name: String, _ on: Bool) {
    var set = Set(picked)
    if on { set.insert(name) } else { set.remove(name) }
    let next = options.filter { set.contains($0) }
    if next != picked { model.change(setting, to: .names(next)) }
  }
}

/// Which app macOS opens a scheme with, every app that can, Olm among them, read live from Launch
/// Services rather than saved, since it is a fact about the Mac. Choosing one asks macOS, which shows
/// its own question, and the row reads the answer again once it is given and whenever the window is
/// shown. A web scheme is changed through http, which macOS keeps https beside.
struct HandlerSetting: View {
  let setting: Setting
  @ObservedObject var model: SettingsModel

  private var scheme: String { setting.scheme ?? "https" }

  var body: some View {
    let current = model.handlers[scheme] ?? ""
    let apps = Self.apps(for: scheme)
    Picker(setting.title, selection: Binding(get: { current }, set: { choose($0) })) {
      ForEach(apps, id: \.path) { url in
        Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
          .tag(url.path)
      }
      if !apps.contains(where: { $0.path == current }) { Text("Unknown").tag(current) }
    }
    .fixedSize()
    .onAppear { model.readHandler(scheme) }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      model.readHandler(scheme)
    }
  }

  static func apps(for scheme: String) -> [URL] {
    guard let probe = URL(string: scheme + "://example.com") else { return [] }
    var seen = Set<String>()
    return NSWorkspace.shared.urlsForApplications(toOpen: probe)
      .filter { seen.insert($0.path).inserted }
      .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
  }

  private func choose(_ path: String) {
    guard path != model.handlers[scheme], !path.isEmpty else { return }
    let web = scheme == "https" || scheme == "http"
    NSWorkspace.shared.setDefaultApplication(at: URL(fileURLWithPath: path),
      toOpenURLsWithScheme: web ? "http" : scheme) { _ in
      Task { @MainActor in model.readHandler(scheme) }
    }
  }
}

/// The fonts a font setting offers, the system's two and every family installed, with the one in
/// use first when it is none of them.
enum FontChoices {
  @MainActor static let families = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }

  @MainActor static func names(including current: String?) -> [String] {
    var out = [".AppleSystemUIFont", ".AppleSystemUIFontMonospaced"]
    if let current, !current.isEmpty, !out.contains(current), !families.contains(current) { out.append(current) }
    return out + families
  }
}

/// Glass where the system has it, macOS 26 and later, and the material it replaced before that.
struct GlassGroup<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    if #available(macOS 26, *) {
      GlassEffectContainer(spacing: Space.group) { content }
    } else {
      content
    }
  }
}

extension View {
  @ViewBuilder func glassCapsule() -> some View {
    if #available(macOS 26, *) {
      glassEffect(.regular.interactive(), in: Capsule())
    } else {
      background(.thinMaterial, in: Capsule())
    }
  }

  @ViewBuilder func glassCard(cornerRadius: CGFloat) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    if #available(macOS 26, *) {
      glassEffect(.regular, in: shape)
    } else {
      background(.regularMaterial, in: shape)
    }
  }

  @ViewBuilder func glassCircle() -> some View {
    if #available(macOS 26, *) {
      glassEffect(.regular.tint(Color.accentColor.opacity(0.18)).interactive(), in: Circle())
    } else {
      background(.regularMaterial, in: Circle())
    }
  }

  @ViewBuilder func softTopEdge() -> some View {
    if #available(macOS 26, *) {
      scrollEdgeEffectStyle(.soft, for: .top)
    } else {
      self
    }
  }
}
