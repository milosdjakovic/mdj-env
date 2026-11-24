// The parts every page of Olm Settings is built from, so a row, a page and the way between them look
// and behave alike wherever they appear. docs/DESIGN-APP-SETTINGS.md, under Parts, states the rules,
// asked by Milos on 2026-11-24. A page needing something these do not cover adds a part here and to
// that list, never a one off in its own file.
//
// A row's right group is always, in this order, the undo, then the gear when the row has a page of
// its own, then the control, each in a column that keeps its place when its part is hidden.

import SwiftUI

/// Undo, the first of a row's actions on the right. Puts the row back to the value in the config
/// files, or takes off what this window set. Kept in place while hidden, so it appearing moves
/// nothing.
struct UndoButton: View {
  let shown: Bool
  var help: String = "Back to the value in the config files"
  let action: () -> Void

  var body: some View {
    Button(action: action) { Image(systemName: "arrow.uturn.backward").frame(width: Space.mark) }
      .buttonStyle(.borderless)
      .help(help)
      .opacity(shown ? 1 : 0)
      .disabled(!shown)
  }
}

/// The gear, after the undo and before the control, opening the row's own page inside the window,
/// a plugin's settings or an application's. Drawn in the accent when that page holds anything set,
/// the rule every set value follows.
struct PageButton: View {
  let set: Bool
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "gearshape")
        .foregroundStyle(set ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(width: Space.mark)
    }
    .buttonStyle(.borderless)
    .help(help)
  }
}

/// Back, at the top left of a page a gear opened, naming the page it returns to, a glass button as
/// the system draws one, asked by Milos on 2026-11-24, the bordered one before macOS 26.
struct BackButton: View {
  let title: String
  let action: () -> Void

  var body: some View {
    if #available(macOS 26, *) {
      button.buttonStyle(.glass)
    } else {
      button.buttonStyle(.bordered)
    }
  }

  private var button: some View {
    Button(action: action) { Label(title, systemImage: "chevron.left") }
      .help("Back to \(title)")
  }
}

extension View {
  /// Back for a page a gear opened, title the page it returns to, at the pane's top left in the
  /// window's top bar, centred on the window's buttons, asked by Milos on 2026-11-24. Nothing when
  /// title is nil, the page being a section's own. The page leaves the top bar's height free above
  /// its header.
  func backBar(_ title: String?, model: SettingsModel, action: @escaping () -> Void) -> some View {
    overlay(alignment: .topLeading) {
      if let title {
        BackButton(title: title, action: action)
          .frame(height: model.buttonsMid * 2)
          .padding(.leading, Space.edge)
          .ignoresSafeArea(.container, edges: .top)
      }
    }
  }
}

/// A page's header, its picture in a glass circle, its title and the line under it, and the note
/// at its right when there is something to say. The height is fixed, so the note coming and going
/// moves nothing.
struct PageHeader<Picture: View>: View {
  let title: String
  let subtitle: String
  var note: (text: String, symbol: String)? = nil
  @ViewBuilder let picture: Picture

  var body: some View {
    HStack(spacing: Space.pad + 4) {
      picture
        .frame(width: SectionPage.header, height: SectionPage.header)
        .glassCircle()
      VStack(alignment: .leading, spacing: Space.row) {
        Text(title).font(.largeTitle.weight(.semibold))
        Text(subtitle).font(.callout).foregroundStyle(.secondary)
      }
      Spacer(minLength: Space.group)
      if let note, !note.text.isEmpty { Note(text: note.text, symbol: note.symbol) }
    }
    .frame(height: SectionPage.header)
  }
}

/// A section's symbol as a header's picture.
struct SectionSymbol: View {
  let symbol: String

  var body: some View {
    Image(systemName: symbol)
      // look-exempt, the section's picture in its glass circle, sized as System Settings does.
      .font(.system(size: 26, weight: .medium))
      .foregroundStyle(.tint)
  }
}

/// Where a setting's control sits against its label, the middle of the label's first line, the
/// title, so a label grown by a detail or a reserved line keeps its title level with the control
/// beside it, a picker, a switch or a slider. The label's other lines hang below.
extension VerticalAlignment {
  private enum TitleLine: AlignmentID {
    static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
  }
  static let titleLine = VerticalAlignment(TitleLine.self)
}

extension View {
  /// Marks this view's middle as the title line, on a row's title and on its control.
  func onTitleLine() -> some View { alignmentGuide(.titleLine) { $0[VerticalAlignment.center] } }
}

/// A row that folds open a short list belonging to it, switched in place, the chevron at its left
/// in a column every such row keeps, folding or not, so the titles line up. The one exception to a
/// page with Back, for a list that is part of its row, the plugins under a permission, asked by
/// Milos on 2026-11-24. Several may be open at once. Opening one moves the rows below, which the
/// person did.
struct DisclosureRow<Header: View, Content: View>: View {
  let open: Bool
  /// Whether there is anything to fold open, the chevron's place kept empty when not.
  let folds: Bool
  let toggle: () -> Void
  @ViewBuilder let header: Header
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center, spacing: Space.related) {
        Button(action: toggle) {
          Image(systemName: "chevron.right")
            .rotationEffect(.degrees(open ? 90 : 0))
            .foregroundStyle(.secondary)
            .frame(width: Space.mark, height: Space.mark)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .opacity(folds ? 1 : 0)
        .disabled(!folds)
        .help(open ? "Fold" : "Show what uses it")
        header
      }
      if open && folds {
        VStack(alignment: .leading, spacing: 0) { content }
          .padding(.leading, Space.mark + Space.related)
          .padding(.top, Space.pad)
      }
    }
  }
}

/// One ability a plugin declared, with its switch, on the plugin's page and under its permission on
/// the Permissions page, one setting in both places, docs/DESIGN-APP-PLUGINS.md. Undo, then the
/// switch, in the control column. While Olm lacks the permission the switch keeps what was set,
/// greyed, and the row says what to fix. A refused ability says why and has no switch.
struct AbilityRow: View {
  let setting: Setting
  @ObservedObject var model: SettingsModel
  /// The plugin's name, shown under a permission, nil on the plugin's own page.
  var plugin: String? = nil

  private var ability: Ability? { setting.ability }

  /// Whether Olm holds the permission now, an Olm gate always, a permission it does not list never.
  private var held: Bool {
    guard let ability else { return false }
    if ability.olmGate { return true }
    return model.granted[ability.permission] ?? false
  }

  private var flag: Binding<Bool> {
    Binding(get: { setting.value.flag ?? false }, set: { value in
      if value != setting.value.flag { model.change(setting, to: .flag(value)) }
    })
  }

  var body: some View {
    HStack(alignment: .titleLine, spacing: Space.pad) {
      VStack(alignment: .leading, spacing: Space.related / 2) {
        Text(plugin ?? setting.title).onTitleLine()
        Text(line).font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        // Always there, so a switch flipped grows no row.
        Text(status).font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: Space.pad)
      HStack(spacing: Space.pad) {
        Spacer(minLength: 0)
        UndoButton(shown: setting.differs && setting.locked == nil, help: "Turn it back on") {
          model.change(setting, to: .none, reset: true)
        }
        Toggle(setting.title, isOn: flag)
          .toggleStyle(.switch)
          .controlSize(.mini)
          .labelsHidden()
          .opacity(ability?.refused == nil ? 1 : 0)
          .disabled(ability?.refused != nil || !held || model.busy.contains(setting.id))
      }
      .frame(width: Space.control)
    }
    .opacity(held || ability?.refused != nil ? 1 : 0.6)
    .help(setting.locked ?? "")
  }

  /// Under a permission, the reason and the ability's name; on the plugin's page, the reason and the
  /// permission it rides on.
  private var line: String {
    let why = setting.detail ?? ""
    guard let ability else { return why }
    if plugin != nil { return "\(why) · \(setting.title)" }
    return ability.olmGate ? "\(why) · Olm's own gate" : "\(why) · \(ability.permissionTitle)"
  }

  private var status: String {
    guard let ability else { return "" }
    if let refused = ability.refused { return "Refused, it \(refused)" }
    if !held { return "Waits for Olm to have \(ability.permissionTitle)" }
    if setting.value.flag == false { return ability.breaks.map { "Off, \($0)" } ?? "Off" }
    return "On"
  }
}
