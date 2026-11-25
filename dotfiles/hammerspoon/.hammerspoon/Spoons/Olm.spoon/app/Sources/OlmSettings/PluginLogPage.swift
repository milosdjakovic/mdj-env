// A plugin's log in Olm Settings, docs/DESIGN-APP-PLUGINS.md The log, a page behind the plugin's own.

import AppKit
import Combine
import OlmPlugins
import SwiftUI

extension SettingsModel {
  /// Reads the log again once it moved, off the main thread.
  func readLog(_ id: String, first: Bool = false) {
    let moved = ExternalPlugins.log.moved(id)
    if first { logEntries = [] } else if moved == logMoved { return }
    logMoved = moved
    Task { @MainActor in
      let read = await Task.detached { Array(ExternalPlugins.log.entries(id).suffix(PluginLogPage.most).reversed()) }.value
      if pluginPage == id, logPage { logEntries = read }
    }
  }
}

/// The way in, a card on the plugin's page.
struct LogRow: View {
  let setting: Setting
  @ObservedObject var model: SettingsModel

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
        Button("Show Log") { model.logPage = true }
      }
      .frame(width: Space.control)
      .onTitleLine()
    }
  }
}

/// Every line, the newest first, Olm's plain and the plugin's own in code.
struct PluginLogPage: View {
  nonisolated static let most = 500
  let plugin: String
  let title: String
  @ObservedObject var model: SettingsModel
  private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    ScrollView {
      GlassGroup {
        VStack(alignment: .leading, spacing: Space.group) {
          HStack(spacing: Space.pad) {
            PageHeader(title: "\(title) Log", subtitle: "Newest first. Lines in code are the plugin's own words.") {
              SectionSymbol(symbol: "text.alignleft")
            }
            Spacer(minLength: Space.pad)
            GlassButton(title: "Copy", symbol: "doc.on.doc", help: "Copy what is shown, the oldest first") { copy() }
              .disabled(model.logEntries.isEmpty)
          }
          if model.logEntries.isEmpty {
            Text("Nothing yet.").foregroundStyle(.secondary).cardRow().glassCard()
          } else {
            LazyVStack(spacing: 0) {
              ForEach(model.logEntries) { entry in
                if entry.id != model.logEntries.first?.id { CardDivider() }
                line(entry).cardRow()
              }
            }
            .glassCard()
          }
        }
        .padding(Space.edge)
        .padding(.top, model.buttonsBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .ignoresSafeArea(.container, edges: .top)
    .softTopEdge()
    .backBar(title, model: model) { model.logPage = false }
    .onAppear { model.readLog(plugin, first: true) }
    .onReceive(tick) { _ in model.readLog(plugin) }
  }

  private func line(_ entry: PluginLog.Entry) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Space.pad) {
      Text(entry.at).font(.caption).monospacedDigit().foregroundStyle(.secondary).fixedSize()
      Text(entry.text)
        .font(entry.from == .plugin ? .callout.monospaced() : .body)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func copy() {
    let text = model.logEntries.reversed()
      .map { "\($0.at)  \($0.from == .plugin ? "plugin: " : "")\($0.text)" }.joined(separator: "\n")
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}
