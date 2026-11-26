// The install page of Plugins and the row that leads to it, docs/DESIGN-APP-PLUGINS.md The install
// page. Nothing of a plugin builds or runs until the button here is pressed.

import AppKit
import SwiftUI

extension SettingsModel {
  static let heldPrefix = ExternalPlugins.prefix + "held."

  /// Shows the page of a folder waiting in ~/.olm/plugins.
  func reviewPlugin(_ id: String) { ask { await $0.review(id) } }

  /// Shows the page of what was dropped or chosen, one at a time.
  func takePlugin(_ urls: [URL]) {
    guard urls.count == 1, let url = urls.first else {
      refusal = urls.isEmpty ? nil : "Drop one plugin at a time."
      return
    }
    ask { await $0.take(url) }
  }

  private func ask(_ what: @escaping @MainActor (PluginInstaller) async -> PluginInstaller.Answer) {
    guard let installer, !offerBusy else { return }
    offerTurn += 1
    let turn = offerTurn
    Task { @MainActor in
      let answer = await what(installer)
      guard turn == offerTurn else {
        if let offer = answer.offer { installer.leave(offer) }
        return
      }
      refusal = answer.why
      if let offer = answer.offer {
        if let old = self.offer { installer.leave(old) }
        self.offer = offer
      }
    }
  }

  func allowOffer() {
    guard let installer, let offer, !offerBusy else { return }
    offerBusy = true
    refusal = nil
    Task { @MainActor in
      let answer = await installer.allow(offer)
      offerBusy = false
      refusal = answer.why
      // Left while it built, the Plugins row says how it went.
      guard self.offer?.id == offer.id else {
        if let next = answer.offer { installer.leave(next) }
        return
      }
      if answer.offer == nil, answer.why != nil { return }
      // Allowed, the page becomes the plugin's own, the one its gear opens.
      if answer.offer == nil { pluginPage = offer.plugin }
      self.offer = answer.offer
    }
  }

  /// Asks first, in the system's own dialog, with whether its data goes too, unticked each time. Return
  /// does nothing there, so the plugin goes only by a click.
  func askUninstall(_ id: String, _ title: String) {
    guard !offerBusy, let window = NSApp.keyWindow else { return }
    let alert = NSAlert()
    alert.messageText = "Uninstall \(title)?"
    alert.informativeText = "It goes to the Trash. Its data and settings stay for when you install it again."
    alert.showsSuppressionButton = true
    alert.suppressionButton?.title = "Delete its data and settings too"
    alert.suppressionButton?.state = .off
    let go = alert.addButton(withTitle: "Uninstall")
    go.hasDestructiveAction = true
    go.keyEquivalent = ""
    alert.addButton(withTitle: "Cancel")
    alert.beginSheetModal(for: window) { [weak self] answer in
      guard answer == .alertFirstButtonReturn else { return }
      self?.uninstall(id, data: alert.suppressionButton?.state == .on)
    }
  }

  /// Uninstalls a plugin and goes back to the list it was in.
  private func uninstall(_ id: String, data: Bool) {
    guard let installer, !offerBusy else { return }
    offerBusy = true
    Task { @MainActor in
      let why = await installer.remove(id, data)
      offerBusy = false
      refusal = why
      guard why == nil else { return }
      if pluginPage == id { pluginPage = nil }
      if offer?.plugin == id { leaveOffer() }
    }
  }

  /// Leaves the page, by Cancel, Back or another section. What is being built goes on.
  func leaveOffer() {
    offerTurn += 1
    guard let offer else { return }
    if !offerBusy { installer?.leave(offer) }
    self.offer = nil
  }
}

/// The way in, the first card of Plugins, with a place to drop and a button that opens a file panel.
struct InstallRow: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    HStack(alignment: .titleLine, spacing: Space.pad) {
      VStack(alignment: .leading, spacing: Space.related / 2) {
        Text("Install a Plugin").onTitleLine()
        Text("Drop a plugin folder or a .olmplugin file on this page. Olm shows what it asks for before anything in it runs.")
          .font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: Space.pad)
      HStack {
        Spacer(minLength: 0)
        Button("Choose…") { choose() }.disabled(model.offerBusy)
      }
      .frame(width: Space.control)
      .onTitleLine()
    }
    .cardRow()
    .glassCard()
  }

  private func choose() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"
    if panel.runModal() == .OK, let url = panel.url { model.takePlugin([url]) }
  }
}

extension View {
  /// Takes a plugin dropped anywhere on the page.
  @ViewBuilder func pluginDrop(_ on: Bool, _ model: SettingsModel) -> some View {
    if on {
      dropDestination(for: URL.self) { urls, _ in
        model.dropping = false
        model.takePlugin(urls)
        return true
      } isTargeted: { over in
        if model.dropping != over { model.dropping = over }
      }
      .overlay { if model.dropping { DropHere().padding(Space.edge).allowsHitTesting(false) } }
    } else {
      self
    }
  }
}

/// Over the whole page while a file is held over it, where it lands and what happens then.
struct DropHere: View {
  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Space.corner, style: .continuous)
    VStack(spacing: Space.pad) {
      Image(systemName: "arrow.down.circle")
        // look-exempt, the drop's picture, the one thing on the page while a file is held over it.
        .font(.system(size: 44, weight: .light))
        .foregroundStyle(.tint)
      Text("Drop to Install").font(.title2.weight(.semibold))
      Text("Olm shows what it asks for first. Nothing runs until you allow it.").foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(shape.fill(.regularMaterial))
    .overlay(shape.strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
  }
}

/// Uninstall, the last card of a plugin's page.
struct UninstallRow: View {
  let setting: Setting
  @ObservedObject var model: SettingsModel
  let plugin: String
  let title: String

  var body: some View {
    HStack(alignment: .titleLine, spacing: Space.pad) {
      VStack(alignment: .leading, spacing: Space.related / 2) {
        Text(setting.title).onTitleLine()
        if let detail = setting.detail {
          Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: Space.pad)
      HStack {
        Spacer(minLength: 0)
        Button("Uninstall…", role: .destructive) { model.askUninstall(plugin, title) }.disabled(model.offerBusy)
      }
      .frame(width: Space.control)
      .onTitleLine()
    }
  }
}

/// What a plugin is and everything it asks for, with Cancel and Allow.
struct InstallPage: View {
  let offer: PluginOffer
  @ObservedObject var model: SettingsModel

  var body: some View {
    ScrollView {
      GlassGroup {
        VStack(alignment: .leading, spacing: Space.group) {
          PageHeader(title: offer.title, subtitle: subtitle, note: note) {
            SectionSymbol(symbol: "puzzlepiece.extension")
          }
          VStack(alignment: .leading, spacing: Space.related) {
            if !offer.about.isEmpty { Text("It says, \u{201C}\(offer.about)\u{201D}") }
            Text(intro).foregroundStyle(.secondary)
            if offer.data { Text("It gets the data an earlier plugin called \(offer.plugin) left.").foregroundStyle(.secondary) }
          }
          .fixedSize(horizontal: false, vertical: true)
          .bareText()
          if case .failed(let errors) = offer.state {
            Text(errors)
              .font(.callout.monospaced()).textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
              .cardRow()
              .glassCard()
          }
          ForEach(offer.groups) { group in
            CardSection(group.title) {
              CardList(group.lines) { line in
                VStack(alignment: .leading, spacing: Space.related / 2) {
                  Text(line.text)
                  if let detail = line.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
          HStack(spacing: Space.pad) {
            if offer.from == nil {
              Button("Uninstall…", role: .destructive) { model.askUninstall(offer.plugin, offer.title) }.disabled(model.offerBusy)
            }
            Spacer(minLength: 0)
            Button("Cancel") { model.leaveOffer() }
            Button(offer.button) { model.allowOffer() }
              .buttonStyle(.borderedProminent)
              .disabled(model.offerBusy)
          }
        }
        .padding(Space.edge)
        .padding(.top, model.buttonsBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .ignoresSafeArea(.container, edges: .top)
    .softTopEdge()
    .backBar("Plugins", model: model) { model.leaveOffer() }
  }

  private var subtitle: String {
    var parts = [offer.plugin, "Version \(offer.version)"]
    if let old = offer.replaces { parts.append("replaces version \(old)") }
    parts.append(offer.from.map { "from \($0)" } ?? "in ~/.olm/plugins")
    return parts.joined(separator: " · ")
  }

  private var intro: String {
    let end = "Allowing it trusts its author with that."
    switch offer.state {
    case .new where offer.groups.isEmpty:
      return "It asks for nothing. It runs in a sandbox with its own folder and nothing else of yours."
    case .new: return "It runs in a sandbox that gives it what is listed here and nothing else of yours. \(end)"
    case .more: return "It asks for more than you allowed before, listed here. Until you allow it, it does not run. \(end)"
    case .same: return "It asks for nothing you have not allowed."
    case .failed: return "You allowed it, and it did not build."
    }
  }

  private var note: (text: String, symbol: String) {
    if model.offerBusy { return ("Building", "hammer") }
    if let refusal = model.refusal { return (refusal, "exclamationmark.triangle") }
    return ("", "hammer")
  }
}
