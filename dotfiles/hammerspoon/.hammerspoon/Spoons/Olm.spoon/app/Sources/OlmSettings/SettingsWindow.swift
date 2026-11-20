// The Olm Settings window, docs/DESIGN-APP-SETTINGS.md. An ordinary macOS window drawn with the
// system's own controls, as System Settings is: a sidebar of sections with a search field over it,
// and the chosen section's settings as a grouped form on the right. It draws whatever the share
// lists, SettingsShare, read again each time the window is shown, since Hammerspoon writes it at
// every load.
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
      w.toolbar = NSToolbar(identifier: "OlmSettings")
      w.toolbarStyle = .unified
      w.titlebarAppearsTransparent = false
      w.isReleasedWhenClosed = false
      w.setContentSize(NSSize(width: 780, height: 540))
      w.contentMinSize = NSSize(width: 620, height: 380)
      w.setFrameAutosaveName("OlmSettings")
      w.delegate = self
      if w.frame.origin == .zero { w.center() }
      window = w
    }
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
  }

  public func close() { window?.close() }
}

struct SettingsView: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    NavigationSplitView {
      List(model.sections, selection: $model.selection) { section in
        Label(section.title, systemImage: section.symbol).tag(section.id)
      }
      .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
      .searchable(text: $model.query, placement: .sidebar, prompt: "Search")
    } detail: {
      if model.share == nil {
        ContentUnavailableView("No settings yet", systemImage: "gearshape",
          description: Text("Hammerspoon writes them when it loads, with the olmapp piece on."))
      } else if let section = model.current {
        SectionForm(section: section, searching: !model.query.isEmpty)
          .id(section.id)
      } else {
        ContentUnavailableView.search(text: model.query)
      }
    }
    .onChange(of: model.query) {
      let sections = model.sections
      if let first = sections.first, !sections.contains(where: { $0.id == model.selection }) {
        model.selection = first.id
      }
    }
  }
}

struct SectionForm: View {
  let section: SettingsSection
  let searching: Bool

  var body: some View {
    Form {
      Section {
        ForEach(section.settings) { setting in SettingRow(setting: setting) }
      } header: {
        Text("Every value shown is the one in use. Changing one here comes in the next step.")
          .font(.caption).foregroundStyle(.secondary).textCase(nil)
      }
    }
    .formStyle(.grouped)
    .navigationTitle(section.title)
  }
}

struct SettingRow: View {
  let setting: Setting

  var body: some View {
    control
      .disabled(true)
      .help(setting.locked ?? "")
  }

  @ViewBuilder private var label: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(setting.title)
      if let detail = setting.detail, !detail.isEmpty {
        Text(detail).font(.caption).foregroundStyle(.secondary)
      }
      if let locked = setting.locked {
        Text("Locked, \(locked)").font(.caption).foregroundStyle(.secondary)
      } else if setting.needsReload {
        Text("Applies on reload").font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder private var control: some View {
    switch setting.kind {
    case .choice:
      Picker(selection: .constant(setting.value.text ?? "")) {
        ForEach(setting.choices) { choice in Text(choice.title).tag(choice.value) }
        if let v = setting.value.text, !setting.choices.contains(where: { $0.value == v }) {
          Text(v).tag(v)
        }
      } label: { label }
    case .switch:
      Toggle(isOn: .constant(setting.value.flag ?? false)) { label }
        .toggleStyle(.switch)
    case .number:
      LabeledContent {
        HStack(spacing: 10) {
          if let lo = setting.min, let hi = setting.max, lo < hi {
            Slider(value: .constant(min(max(setting.value.number ?? lo, lo), hi)), in: lo...hi)
              .frame(width: 180)
          }
          Text(SettingFormat.number(setting.value.number ?? 0, step: setting.step, unit: setting.unit))
            .monospacedDigit()
            .frame(minWidth: 64, alignment: .trailing)
        }
      } label: { label }
    case .font:
      LabeledContent {
        Text(SettingFormat.font(setting.value.text ?? ""))
          .font(.custom(setting.value.text ?? "", size: NSFont.systemFontSize))
      } label: { label }
    case .other:
      LabeledContent { Text(String(describing: setting.value)) } label: { label }
    }
  }
}
