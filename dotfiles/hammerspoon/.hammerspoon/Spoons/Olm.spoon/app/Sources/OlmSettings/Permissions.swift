// The Permissions page of Olm Settings, asked for by Milos on 2026-11-20: every permission Olm.app
// uses, whether macOS gives it now, and a button to the list in System Settings where it is turned
// on or off. An app cannot switch its own permission, so the button takes the person there, asking
// macOS first where the permission has never been asked for, which adds the app to that list. The
// page reads each one again every second while it is shown, so a switch flipped in System Settings
// shows here at once.
//
// What the permissions are is the composition root's, which hands them in, since only it knows the
// parts that use them. This page draws whatever it is given.

import AppKit
import Combine
import SwiftUI

/// One permission the app uses.
public struct Permission: Identifiable, Sendable {
  public let id: String
  public let title: String
  /// What stops working without it, one line.
  public let detail: String
  public let symbol: String
  /// What Olm itself uses it for, listed greyed above the plugins under it, nil when only plugins do.
  public let ownUse: String?
  /// The list in System Settings it is turned on in.
  public let settingsURL: String
  /// Whether macOS gives it now. Called on the main thread, often, so it must be cheap.
  public let check: @MainActor @Sendable () -> Bool
  /// Asks macOS, which lists the app in System Settings, nil where there is nothing to ask.
  public let ask: (@MainActor @Sendable () -> Void)?

  /// ownUse defaults to detail, a permission Olm uses for what its line says, and pluginsOnly says
  /// Olm uses it for nothing of its own.
  public init(id: String, title: String, detail: String, symbol: String, settingsURL: String,
    ownUse: String? = nil, pluginsOnly: Bool = false,
    check: @escaping @MainActor @Sendable () -> Bool, ask: (@MainActor @Sendable () -> Void)? = nil) {
    self.id = id
    self.title = title
    self.detail = detail
    self.symbol = symbol
    self.ownUse = pluginsOnly ? nil : (ownUse ?? detail)
    self.settingsURL = settingsURL
    self.check = check
    self.ask = ask
  }
}

/// The page's own section, after every section the share lists.
enum PermissionsPage {
  static let id = "olm.permissions"
  static let section = SettingsSection(id: id, title: "Permissions", symbol: "lock.shield", settings: [])
}

/// The page: its header, then one card holding a row per permission.
struct PermissionsView: View {
  @ObservedObject var model: SettingsModel
  // Read again every second while the page is up.
  private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    ScrollViewReader { proxy in
    ScrollView {
      GlassGroup {
        VStack(alignment: .leading, spacing: Space.group) {
          PageHeader(title: "Permissions", subtitle: summary) {
            SectionSymbol(symbol: PermissionsPage.section.symbol)
          }
          CardList(rows) { permission in
            let uses = model.abilities(riding: permission.id)
            DisclosureRow(open: model.openPermissions.contains(permission.id), folds: !uses.isEmpty,
              toggle: { model.togglePermission(permission.id) }) {
              PermissionRow(permission: permission, granted: granted(permission),
                plugins: Set(uses.compactMap { $0.ability?.owner }).count)
            } content: {
              if let own = permission.ownUse {
                OwnUseRow(text: own)
                Divider()
              }
              ForEach(Array(uses.enumerated()), id: \.element.id) { i, use in
                if i > 0 { Divider() }
                AbilityRow(setting: use, model: model, plugin: model.pluginTitle(use.ability?.owner ?? ""))
                  .padding(.vertical, Space.pad)
              }
            }
            .searchMark(model, SearchTarget.permission(permission.id))
          }
        }
        .padding(Space.edge)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .ignoresSafeArea(.container, edges: .top)
    .softTopEdge()
    .searchJump(model, proxy, Set(model.permissions.map { SearchTarget.permission($0.id) }))
    }
    .onAppear { model.recheck() }
    .onReceive(tick) { _ in model.recheck() }
  }

  /// Olm's permissions, then any a plugin's ability rides on that Olm does not list, held never, or
  /// always for a gate of Olm's own.
  private var rows: [Permission] {
    let known = Set(model.permissions.map(\.id))
    var extra: [String: Permission] = [:]
    for use in model.share?.abilities ?? [] {
      guard let a = use.ability, !a.permission.isEmpty, !known.contains(a.permission), extra[a.permission] == nil
      else { continue }
      let olm = a.olmGate
      extra[a.permission] = Permission(id: a.permission, title: a.permissionTitle,
        detail: olm ? "Olm's own gate, which Olm always holds" : "Olm does not use it yet, so nothing here can",
        symbol: olm ? "lock.shield" : "questionmark.circle", settingsURL: "", pluginsOnly: true,
        check: { olm })
    }
    return model.permissions + extra.values.sorted { $0.title < $1.title }
  }

  private func granted(_ permission: Permission) -> Bool {
    model.granted[permission.id] ?? (model.permissions.contains { $0.id == permission.id } ? false : permission.check())
  }

  private var summary: String {
    let given = model.permissions.filter { model.granted[$0.id] == true }.count
    return "\(given) of \(model.permissions.count) allowed"
  }
}

/// One permission: its picture, name and what it is for, whether it is allowed, and the button. The
/// status and the button sit in the control column of fixed width, so a change of status moves
/// nothing in the row.
struct PermissionRow: View {
  let permission: Permission
  let granted: Bool
  /// How many plugins use it, said beside the status.
  var plugins: Int = 0

  var body: some View {
    HStack(alignment: .center, spacing: Space.pad) {
      Image(systemName: permission.symbol)
        .foregroundStyle(.tint)
        .frame(width: 20)
      VStack(alignment: .leading, spacing: Space.related / 2) {
        Text(permission.title)
        Text(permission.detail).font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: Space.pad)
      Text(plugins == 0 ? "No plugins" : plugins == 1 ? "1 plugin" : "\(plugins) plugins")
        .font(.caption).foregroundStyle(.secondary)
        .monospacedDigit()
      HStack(spacing: Space.pad) {
        Spacer(minLength: 0)
        Label(granted ? "Allowed" : "Not allowed", systemImage: granted ? "checkmark.circle.fill" : "xmark.circle")
          .foregroundStyle(granted ? Color.green : Color.secondary)
          .frame(width: 110, alignment: .leading)
        Button("Open Settings") {
          if !granted { permission.ask?() }
          if let url = URL(string: permission.settingsURL) { NSWorkspace.shared.open(url) }
        }
        .help("Turn \(permission.title) on or off for Olm in System Settings")
        .opacity(permission.settingsURL.isEmpty ? 0 : 1)
        .disabled(permission.settingsURL.isEmpty)
      }
      .frame(width: Space.control)
    }
  }
}

/// What Olm itself uses a permission for, first under it, greyed and with no switch, since only
/// macOS can take Olm's permission away.
struct OwnUseRow: View {
  let text: String

  var body: some View {
    VStack(alignment: .leading, spacing: Space.related / 2) {
      Text("Olm")
      Text(text).font(.caption)
    }
    .foregroundStyle(.secondary)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, Space.pad)
  }
}
