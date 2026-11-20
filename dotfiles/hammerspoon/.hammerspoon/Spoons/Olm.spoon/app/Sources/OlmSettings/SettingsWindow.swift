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
// Step S.2 shows every setting and changes none, so each control is drawn disabled. Changing one
// goes over the bridge in S.3, which is where Hammerspoon checks, saves and applies it.

import AppKit
import Combine
import SwiftUI

/// What the window is showing, the section chosen and the search typed. A class the window owns
/// rather than view state, since the command line tools the app builds with ship no SwiftUI macros
/// and @State is one in macOS 27's SDK.
@MainActor
final class SettingsModel: ObservableObject {
  @Published var share: SettingsShare?
  @Published var selection: String?
  @Published var query = ""

  init(share: SettingsShare?) {
    self.share = share
    selection = share?.sections.first?.id
  }

  var sections: [SettingsSection] { share?.matching(query) ?? [] }

  var current: SettingsSection? { sections.first(where: { $0.id == selection }) ?? sections.first }
}

/// The window, made once and shown again with the share as it stands.
@MainActor
public final class SettingsWindow: NSObject, NSWindowDelegate {
  private var window: NSWindow?
  private var model: SettingsModel?
  private let share: () -> SettingsShare?

  public init(share: @escaping () -> SettingsShare? = { SettingsShare.read() }) {
    self.share = share
  }

  public var isShown: Bool { window?.isVisible ?? false }

  /// Shows the window over the app in front and makes it key, since typing goes into its search.
  /// The app becomes an ordinary one while it is open, so Command Tab finds it.
  public func show() {
    if window != nil, let model {
      // The share as Hammerspoon wrote it at its last load, the section and search kept.
      model.share = share()
      if !model.sections.contains(where: { $0.id == model.selection }) { model.selection = model.sections.first?.id }
    } else {
      let model = SettingsModel(share: share())
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
      w.setContentSize(NSSize(width: 1000, height: 700))
      w.contentMinSize = NSSize(width: 760, height: 480)
      // Named afresh with the larger size, so a frame saved at the old one is not restored.
      w.setFrameAutosaveName("OlmSettingsWindow")
      w.delegate = self
      if w.frame.origin == .zero { w.center() }
      window = w
    }
    NSApp.setActivationPolicy(.regular)
    NSApp.mainMenu = Self.menu()
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
  }

  public func close() { window?.close() }

  /// Back to an app with no Dock icon and no menu bar once the window is gone, and the app in front
  /// before it given the keyboard back.
  public func windowWillClose(_ notification: Notification) {
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
      .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 340)
      .searchable(text: $model.query, placement: .sidebar, prompt: "Search")
    } detail: {
      ZStack {
        Backdrop()
        if model.share == nil {
          ContentUnavailableView("No settings yet", systemImage: "gearshape",
            description: Text("Hammerspoon writes them when it loads, with the olmapp piece on."))
        } else if let section = model.current {
          SectionPage(section: section)
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

/// The app's name and version at the head of the sidebar, where System Settings shows the account.
struct AppIdentity: View {
  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
  }

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "command")
        .font(.title2.weight(.semibold))
        .foregroundStyle(.tint)
        .frame(width: 40, height: 40)
        .glassCircle()
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

/// One section, its header and its settings on one glass card.
struct SectionPage: View {
  let section: SettingsSection

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
          Label("Every value shown is the one in use. Changing one here comes in the next step.",
            systemImage: "info.circle")
            .font(.callout).foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .glassCard(cornerRadius: 999)
          VStack(spacing: 0) {
            ForEach(Array(section.settings.enumerated()), id: \.element.id) { index, setting in
              if index > 0 { Divider().padding(.leading, 18) }
              SettingRow(setting: setting)
                .padding(.horizontal, 18).padding(.vertical, 12)
            }
          }
          .glassCard(cornerRadius: 22)
        }
        .padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 28)
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity)
      }
    }
    .softTopEdge()
  }
}

struct SettingRow: View {
  let setting: Setting

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      label
      Spacer(minLength: 12)
      control.labelsHidden()
    }
    .disabled(true)
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

  @ViewBuilder private var control: some View {
    switch setting.kind {
    case .choice:
      Picker(setting.title, selection: .constant(setting.value.text ?? "")) {
        ForEach(setting.choices) { choice in Text(choice.title).tag(choice.value) }
        if let v = setting.value.text, !setting.choices.contains(where: { $0.value == v }) {
          Text(v).tag(v)
        }
      }
      .fixedSize()
    case .switch:
      Toggle(setting.title, isOn: .constant(setting.value.flag ?? false))
        .toggleStyle(.switch)
    case .number:
      HStack(spacing: 10) {
        if let lo = setting.min, let hi = setting.max, lo < hi {
          Slider(value: .constant(min(max(setting.value.number ?? lo, lo), hi)), in: lo...hi)
            .frame(width: 180)
        }
        Text(SettingFormat.number(setting.value.number ?? 0, step: setting.step, unit: setting.unit))
          .monospacedDigit()
          .frame(minWidth: 64, alignment: .trailing)
      }
    case .font:
      Text(SettingFormat.font(setting.value.text ?? ""))
        .font(.custom(setting.value.text ?? "", size: NSFont.systemFontSize))
    case .other:
      Text(String(describing: setting.value))
    }
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
