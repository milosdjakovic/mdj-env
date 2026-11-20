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
  /// The list in System Settings it is turned on in.
  public let settingsURL: String
  /// Whether macOS gives it now. Called on the main thread, often, so it must be cheap.
  public let check: @MainActor @Sendable () -> Bool
  /// Asks macOS, which lists the app in System Settings, nil where there is nothing to ask.
  public let ask: (@MainActor @Sendable () -> Void)?

  public init(id: String, title: String, detail: String, symbol: String, settingsURL: String,
    check: @escaping @MainActor @Sendable () -> Bool, ask: (@MainActor @Sendable () -> Void)? = nil) {
    self.id = id
    self.title = title
    self.detail = detail
    self.symbol = symbol
    self.settingsURL = settingsURL
    self.check = check
    self.ask = ask
  }
}

/// The page's own section, after every section the share lists.
enum PermissionsPage {
  static let id = "olm.permissions"
  static let section = SettingsSection(id: id, title: "Permissions", symbol: "lock.shield", settings: [])

  /// Whether a sidebar search finds the page, by its title or any permission's words.
  static func matches(_ query: String, _ permissions: [Permission]) -> Bool {
    let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    if words.isEmpty { return true }
    let hay = (["permissions", "privacy", "security", "grant"] + permissions.flatMap { [$0.title, $0.detail] })
      .joined(separator: " ").lowercased()
    return words.allSatisfy { hay.contains($0) }
  }
}

/// The page: its header, then one card holding a row per permission.
struct PermissionsView: View {
  @ObservedObject var model: SettingsModel
  // Read again every second while the page is up.
  private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    ScrollView {
      GlassGroup {
        VStack(alignment: .leading, spacing: Space.group) {
          HStack(spacing: Space.pad + 4) {
            Image(systemName: PermissionsPage.section.symbol)
              // look-exempt, the section's picture in its glass circle, sized as System Settings does.
              .font(.system(size: 26, weight: .medium))
              .foregroundStyle(.tint)
              .frame(width: SectionPage.header, height: SectionPage.header)
              .glassCircle()
            VStack(alignment: .leading, spacing: Space.row) {
              Text("Permissions").font(.largeTitle.weight(.semibold))
              Text(summary).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.group)
          }
          .frame(height: SectionPage.header)
          VStack(spacing: 0) {
            ForEach(Array(model.permissions.enumerated()), id: \.element.id) { index, permission in
              if index > 0 { Divider().padding(.leading, Space.pad + 4) }
              PermissionRow(permission: permission, granted: model.granted[permission.id] ?? false)
                .padding(.horizontal, Space.pad + 4).padding(.vertical, Space.pad)
            }
          }
          .glassCard(cornerRadius: 20)
        }
        .padding(Space.edge)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .ignoresSafeArea(.container, edges: .top)
    .softTopEdge()
    .onAppear { model.recheck() }
    .onReceive(tick) { _ in model.recheck() }
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
      }
      .frame(width: Space.control)
    }
  }
}
