// The Olm Settings window, docs/DESIGN-APP-SETTINGS.md. An ordinary macOS window drawn with the
// system's own controls and built on Liquid Glass: the floating glass sidebar of sections with a
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

/// What the window is showing, the section chosen, the search typed, a slider being dragged and the
/// last refusal. A class the window owns rather than view state, since the command line tools the
/// app builds with ship no SwiftUI macros and @State is one in macOS 27's SDK.
@MainActor
final class SettingsModel: ObservableObject {
  @Published var share: SettingsShare?
  @Published var selection: String?
  @Published var query = ""
  /// A slider's value while it is dragged, sent when it is let go.
  @Published var drafts: [String: Double] = [:]
  /// The last change Hammerspoon refused, the setting's title and why.
  @Published var refusal: String?
  /// A change taken that applies on reload, so the window reloads once when it closes.
  @Published var reloadDue = false
  @Published var busy: Set<String> = []
  let service: SettingsService?

  init(share: SettingsShare?, service: SettingsService?) {
    self.share = share
    self.service = service
    selection = share?.sections.first?.id
  }

  var sections: [SettingsSection] { share?.matching(query) ?? [] }

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

  public init(share: @escaping () -> SettingsShare? = { SettingsShare.read() }, service: SettingsService? = nil) {
    self.share = share
    self.service = service
  }

  public var isShown: Bool { window?.isVisible ?? false }

  /// Shows the window over the app in front, centred on the screen under the pointer when it was
  /// closed, and makes it key, since typing goes into its search. The app becomes an ordinary one
  /// while it is open, so Command Tab finds it.
  public func show() {
    if window != nil, let model {
      // The share as Hammerspoon wrote it at its last load, the section and search kept.
      model.share = share()
      if !model.sections.contains(where: { $0.id == model.selection }) { model.selection = model.sections.first?.id }
    } else {
      let model = SettingsModel(share: share(), service: service)
      self.model = model
      let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
      w.title = "Olm Settings"
      w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
      // A compact toolbar with no background and no line under it, so the search sits just under
      // the window's buttons and the pane runs to the top, as System Settings draws.
      w.toolbar = NSToolbar(identifier: "OlmSettings")
      w.toolbarStyle = .unifiedCompact
      w.titlebarSeparatorStyle = .none
      w.isReleasedWhenClosed = false
      w.setContentSize(NSSize(width: 1100, height: 740))
      w.contentMinSize = NSSize(width: 820, height: 500)
      // The size is kept between openings and the place is not, since it opens centred. Named
      // afresh with each larger default, so a size saved at an older one is not restored.
      w.setFrameAutosaveName("OlmSettingsFrame")
      w.delegate = self
      window = w
    }
    if let window, !window.isVisible { Self.centre(window) }
    NSApp.setActivationPolicy(.regular)
    NSApp.mainMenu = Self.menu()
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
    if let window { DispatchQueue.main.async { Self.widenSidebar(window) } }
  }

  /// The sidebar's width, set on the split view AppKit draws. SwiftUI's column width is not honoured
  /// in a window made by hand, which left the sidebar at about 140 points twice, so the split
  /// view's own item is given the bounds and the divider moved out when it sits inside them.
  static let sidebarWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (300, 320, 400)

  static func widenSidebar(_ window: NSWindow) {
    guard let content = window.contentView, let split = splitView(in: content),
          let sidebar = split.arrangedSubviews.first else { return }
    if let controller = split.delegate as? NSSplitViewController, let item = controller.splitViewItems.first {
      item.minimumThickness = sidebarWidth.min
      item.maximumThickness = sidebarWidth.max
    }
    if sidebar.frame.width < sidebarWidth.min {
      split.setPosition(sidebarWidth.ideal, ofDividerAt: 0)
    }
    NSLog("OlmSettings sidebar %.0f pt", sidebar.frame.width)
  }

  static func splitView(in view: NSView) -> NSSplitView? {
    if let split = view as? NSSplitView { return split }
    for sub in view.subviews { if let found = splitView(in: sub) { return found } }
    return nil
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

struct SettingsView: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    NavigationSplitView {
      List(selection: $model.selection) {
        Section { AppIdentity() }
        Section {
          ForEach(model.sections) { section in
            Label(section.title, systemImage: section.symbol).tag(section.id)
          }
        }
      }
      .navigationSplitViewColumnWidth(min: SettingsWindow.sidebarWidth.min, ideal: SettingsWindow.sidebarWidth.ideal,
        max: SettingsWindow.sidebarWidth.max)
      .searchable(text: $model.query, placement: .sidebar, prompt: "Search")
    } detail: {
      ZStack {
        Backdrop()
        if model.share == nil {
          ContentUnavailableView("No settings yet", systemImage: "gearshape",
            description: Text("Hammerspoon writes them when it loads, with the olmapp piece on."))
        } else if let section = model.current {
          SectionPage(section: section, model: model)
            .id(section.id)
        } else {
          ContentUnavailableView.search(text: model.query)
        }
      }
    }
    .navigationTitle("Olm Settings")
    .titleHidden()
    .toolbarBackgroundHidden()
    .onChange(of: model.query) {
      let sections = model.sections
      if let first = sections.first, !sections.contains(where: { $0.id == model.selection }) {
        model.selection = first.id
      }
    }
  }
}

/// The app's icon, name and version at the head of the sidebar, where System Settings shows the
/// account.
struct AppIdentity: View {
  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
  }

  var body: some View {
    HStack(spacing: 12) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .interpolation(.high)
        .frame(width: 44, height: 44)
      VStack(alignment: .leading, spacing: 1) {
        Text("Olm").font(.headline)
        Text("Version \(version)").font(.subheadline).foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 6)
  }
}

/// The wash behind the detail, the accent colour fading out, carried under the floating sidebar on
/// macOS 26 and later so the sidebar's glass bends it too.
struct Backdrop: View {
  var body: some View {
    let wash = ZStack {
      Rectangle().fill(.background)
      LinearGradient(colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.04), .clear],
        startPoint: .topLeading, endPoint: .bottomTrailing)
      RadialGradient(colors: [Color.accentColor.opacity(0.14), .clear], center: .bottomTrailing,
        startRadius: 10, endRadius: 520)
    }
    .ignoresSafeArea()
    if #available(macOS 26, *) {
      wash.backgroundExtensionEffect()
    } else {
      wash
    }
  }
}

/// One section, its header, a line when a change waits for the window to close or was refused, and
/// its settings on one glass card.
struct SectionPage: View {
  let section: SettingsSection
  @ObservedObject var model: SettingsModel

  var body: some View {
    ScrollView {
      GlassGroup {
        VStack(alignment: .leading, spacing: 22) {
          HStack(spacing: 16) {
            Image(systemName: section.symbol)
              // The window follows the system's look and not the chooser's.
              // look-exempt, the section's picture in its glass circle, sized as System Settings does.
              .font(.system(size: 26, weight: .medium))
              .foregroundStyle(.tint)
              .frame(width: 60, height: 60)
              .glassCircle()
            VStack(alignment: .leading, spacing: 4) {
              Text(section.title).font(.largeTitle.weight(.semibold))
              Text(section.settings.count == 1 ? "1 setting" : "\(section.settings.count) settings")
                .font(.callout).foregroundStyle(.secondary)
            }
          }
          if let refusal = model.refusal {
            Note(text: refusal, symbol: "exclamationmark.triangle")
          } else if model.reloadDue {
            Note(text: "Changes marked to apply on reload apply when this window closes.", symbol: "arrow.clockwise")
          }
          VStack(spacing: 0) {
            ForEach(Array(section.settings.enumerated()), id: \.element.id) { index, setting in
              if index > 0 { Divider().padding(.leading, 18) }
              SettingRow(setting: setting, model: model)
                .padding(.horizontal, 18).padding(.vertical, 12)
            }
          }
          .glassCard(cornerRadius: 22)
        }
        .padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 28)
        .frame(maxWidth: 820, alignment: .leading)
        .frame(maxWidth: .infinity)
      }
    }
    .softTopEdge()
  }
}

/// One line in a glass capsule over the card.
struct Note: View {
  let text: String
  let symbol: String

  var body: some View {
    Label(text, systemImage: symbol)
      .font(.callout).foregroundStyle(.secondary)
      .padding(.horizontal, 14).padding(.vertical, 8)
      .glassCard(cornerRadius: 999)
  }
}

struct SettingRow: View {
  let setting: Setting
  @ObservedObject var model: SettingsModel

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      label
      Spacer(minLength: 12)
      if setting.differs && setting.locked == nil {
        Button {
          model.change(setting, to: .none, reset: true)
        } label: {
          Image(systemName: "arrow.uturn.backward")
        }
        .buttonStyle(.borderless)
        .help("Back to the value in the config files")
      }
      control.labelsHidden()
    }
    .disabled(setting.locked != nil || model.busy.contains(setting.id))
    .help(setting.locked ?? "")
  }

  @ViewBuilder private var label: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(setting.title)
      if let detail = setting.detail, !detail.isEmpty {
        Text(detail).font(.caption).foregroundStyle(.secondary)
      }
      if let locked = setting.locked {
        Text("Locked, \(locked)").font(.caption).foregroundStyle(.secondary)
      } else if setting.needsReload {
        Label("Applies on reload", systemImage: "arrow.clockwise")
          .font(.caption).foregroundStyle(.secondary)
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
      Toggle(setting.title, isOn: flag)
        .toggleStyle(.switch)
    case .number:
      HStack(spacing: 10) {
        if let lo = setting.min, let hi = setting.max, lo < hi {
          Slider(value: number(lo, hi), in: lo...hi) { editing in
            if !editing, let v = model.drafts[setting.id] {
              if v != setting.value.number { model.change(setting, to: .number(v)) } else { model.drafts[setting.id] = nil }
            }
          }
          .frame(width: 200)
        }
        Text(SettingFormat.number(model.drafts[setting.id] ?? setting.value.number ?? 0, step: setting.step,
          unit: setting.unit))
          .monospacedDigit()
          .frame(minWidth: 64, alignment: .trailing)
      }
    case .font:
      Picker(setting.title, selection: choice) {
        ForEach(FontChoices.names(including: setting.value.text), id: \.self) { name in
          Text(SettingFormat.font(name)).tag(name)
        }
      }
      .fixedSize()
    case .other:
      Text(String(describing: setting.value))
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
      GlassEffectContainer(spacing: 22) { content }
    } else {
      content
    }
  }
}

extension View {
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

  /// The window keeps its title for Mission Control and the Window menu, and the toolbar shows none,
  /// since each section's header names it.
  @ViewBuilder func titleHidden() -> some View {
    if #available(macOS 15, *) {
      toolbar(removing: .title)
    } else {
      self
    }
  }

  /// No toolbar band over the pane, the wash showing to the top of the window.
  @ViewBuilder func toolbarBackgroundHidden() -> some View {
    if #available(macOS 15, *) {
      toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    } else {
      self
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
