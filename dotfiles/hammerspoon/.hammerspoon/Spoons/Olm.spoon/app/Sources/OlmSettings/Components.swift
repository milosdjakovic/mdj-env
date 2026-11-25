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
/// a plugin's settings or an application's. Always muted, whatever its page holds, asked by Milos on
/// 2026-11-25.
struct PageButton: View {
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "gearshape")
        .foregroundStyle(.secondary)
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

/// Rows on one glass card, a divider between each, every list in the window.
struct CardList<Item: Identifiable, Row: View>: View {
  let items: [Item]
  @ViewBuilder let row: (Item) -> Row

  init(_ items: [Item], @ViewBuilder row: @escaping (Item) -> Row) {
    self.items = items
    self.row = row
  }

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
        if index > 0 { CardDivider() }
        row(item).cardRow()
      }
    }
    .glassCard()
  }
}

/// The line between two rows of a card, starting where their words do.
struct CardDivider: View {
  var body: some View { Divider().padding(.leading, Space.pad + 4) }
}

/// A card's title over it, with what belongs to the whole card at its right. The title is bare words,
/// so it stands at the card's inset, over the rows' words. A control there has a shape of its own and
/// ends at the card's edge, and words there take `bareText`.
struct CardSection<Trailing: View, Content: View>: View {
  let title: String
  @ViewBuilder let trailing: Trailing
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: Space.pad) {
      HStack(spacing: Space.pad) {
        Text(title).font(.headline).bareText().frame(maxWidth: .infinity, alignment: .leading)
        trailing
      }
      content
    }
  }
}

extension View {
  /// Words outside a card, held in by the card's inset so they line up with the words inside it. What
  /// has a shape of its own, a button, a search or a card, takes none and reaches the page's edge.
  func bareText() -> some View { padding(.horizontal, Space.pad + 4) }
}

extension CardSection where Trailing == EmptyView {
  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.init(title: title, trailing: { EmptyView() }, content: content)
  }
}

private struct UnitsKey: EnvironmentKey {
  static let defaultValue: [String] = []
}

extension EnvironmentValues {
  /// Every unit on the card, so each takes the widest one's room.
  var units: [String] {
    get { self[UnitsKey.self] }
    set { self[UnitsKey.self] = newValue }
  }
}

extension View {
  /// The units of a card's numbers.
  func units(_ settings: [Setting]) -> some View {
    environment(\.units, Set(settings.filter { $0.kind == .number }
      .map { SettingFormat.entry(step: $0.step, unit: $0.unit).unit }).sorted())
  }
}

/// The unit after a number, ending where every control ends, the card's inset, in a column as wide as
/// the card's widest unit so its fields stand in one line.
struct UnitLabel: View {
  let text: String
  @Environment(\.units) private var units

  init(_ text: String) { self.text = text }

  var body: some View {
    ZStack(alignment: .trailing) {
      ForEach(units, id: \.self) { Text($0).hidden() }
      Text(text).foregroundStyle(.secondary)
    }
    .fixedSize()
  }
}

/// A name and its control, a row of a page that edits one thing.
struct LabelRow<Control: View>: View {
  let title: String
  @ViewBuilder let control: Control

  init(_ title: String, @ViewBuilder control: () -> Control) {
    self.title = title
    self.control = control()
  }

  var body: some View {
    HStack(alignment: .center, spacing: Space.pad) {
      Text(title)
      Spacer(minLength: Space.pad)
      control.labelsHidden()
    }
    .cardRow()
  }
}

/// A search on a Liquid Glass capsule, the sidebar's and a page's, the field inside it plain so the
/// glass is the only bezel. The clear button keeps its place when hidden, so typing moves nothing.
struct GlassSearch: View {
  let prompt: String
  @Binding var text: String
  var move: (Int) -> Void = { _ in }
  var submit: () -> Void = {}

  var body: some View {
    HStack(spacing: Space.pad) {
      Image(systemName: "magnifyingglass").foregroundStyle(.secondary).frame(width: 20)
      TextField(prompt, text: $text)
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

/// A button on the same capsule, as tall as a search beside it, what a page adds to itself.
struct GlassButton: View {
  let title: String
  let symbol: String
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: symbol)
        .lineLimit(1)
        .padding(.horizontal, Space.pad + 4)
        .frame(height: Space.rowHeight + 4)
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .glassCapsule()
    .fixedSize()
    .help(help)
  }
}

extension View {
  /// A row's room inside its card, the same on every page.
  func cardRow() -> some View {
    frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, Space.pad + 4).padding(.vertical, Space.pad)
  }
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
        // Read again as time passes, its last use said beside it.
        TimelineView(.periodic(from: .now, by: 5)) { context in
          Text(status + used(context.date)).font(.caption).foregroundStyle(.secondary)
        }
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

  /// When a plugin Olm.app runs last used it, nothing for one Hammerspoon runs, whose uses Olm does
  /// not see.
  private func used(_ now: Date) -> String {
    guard let ability, ability.refused == nil, setting.id.hasPrefix(ExternalPlugins.prefix) else { return "" }
    guard let at = ExternalPlugins.history.used(ability.owner, ability.use) else { return " · not used yet" }
    return " · used " + SettingFormat.ago(at, now)
  }

  private var status: String {
    guard let ability else { return "" }
    if let refused = ability.refused { return "Refused, it \(refused)" }
    if !held { return "Waits for Olm to have \(ability.permissionTitle)" }
    if setting.value.flag == false { return ability.breaks.map { "Off, \($0)" } ?? "Off" }
    return "On"
  }
}
