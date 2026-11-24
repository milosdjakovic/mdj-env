// The Window Management page of Olm Settings, docs/DESIGN-APP-SETTINGS.md Window Management. Every
// window action with its shortcut, the layouts, the display moves, the named sizes and the steps, and
// below them the numbers the steps and sizes read. The actions come from the window manager's
// catalog, the sizes setting's extra, so the page names every action without knowing how one works.
//
// A named size is the window manager's setting `windowmanager.sizes`, edited here in a sheet: a name,
// a width and a height in points or a percent of the screen, one of nine anchors and a display. Small
// and Recording ship and can be changed, not removed. A shortcut is Olm's own setting `keys`, as on
// the Applications page, META implied, since Olm.app holds META's combinations and pressing one
// would run it. Every change applies on the reload the window's close runs.

import AppKit
import SwiftUI

enum WindowsPage {
  static let keysId = "keys"

  /// The sizes setting of a section, when it is the Window Management page's.
  static func setting(in section: SettingsSection) -> Setting? {
    section.settings.first { $0.kind == .sizes }
  }

  static let anchors: [(id: String, title: String)] = [
    ("topLeft", "Top Left"), ("top", "Top"), ("topRight", "Top Right"),
    ("left", "Left"), ("center", "Center"), ("right", "Right"),
    ("bottomLeft", "Bottom Left"), ("bottom", "Bottom"), ("bottomRight", "Bottom Right"),
  ]
  static let displays: [(id: String, title: String)] = [
    ("current", "Where it is"), ("builtin", "Built-in display"), ("external", "External display"),
    ("pointer", "Display under the pointer"),
  ]

  static func anchorTitle(_ id: String) -> String { anchors.first { $0.id == id }?.title ?? "Center" }
  static func displayTitle(_ id: String) -> String { displays.first { $0.id == id }?.title ?? "Where it is" }

  /// A size in words, 700 × 800 pt, Center, Where it is.
  static func words(_ z: WindowSize) -> String {
    let n = { (v: Double) in v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v) }
    let size = z.percent ? "\(n(z.width))% × \(n(z.height))% of the screen" : "\(n(z.width)) × \(n(z.height)) pt"
    return [size, anchorTitle(z.anchor), displayTitle(z.display)].joined(separator: " · ")
  }

  /// An id of letters and digits for a new size, from its name, unique among ids.
  static func newId(_ name: String, taken: Set<String>) -> String {
    var base = String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
      .map(Character.init))
    while let c = base.first, !c.isLetter { base.removeFirst() }
    if base.isEmpty { base = "size" }
    var id = base, n = 2
    while taken.contains(id) {
      id = base + String(n)
      n += 1
    }
    return id
  }
}

/// The size being edited in the sheet, held by the window's model since a view here keeps no state.
@MainActor
final class SizeEditor: ObservableObject {
  @Published var draft: WindowSize?
  @Published var isNew = false
}

struct WindowsView: View {
  let section: SettingsSection
  let setting: Setting
  @ObservedObject var model: SettingsModel
  @ObservedObject var page: AppsPageModel
  @ObservedObject var editor: SizeEditor

  var body: some View {
    ScrollViewReader { proxy in
    ScrollView {
      VStack(alignment: .leading, spacing: Space.group) {
        header
        card("Layouts", actions("layout"))
        card("Displays", actions("display"))
        sizesCard
        card("Moving and Resizing", actions("step"))
        card("Other", actions("other"))
        stepsCard
      }
      .padding(Space.edge)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .ignoresSafeArea(.container, edges: .top)
    .searchJump(model, proxy, Set(setting.windowActions.map { SearchTarget.window($0.action) }
      + (setting.value.sizes ?? []).map { SearchTarget.size($0.id) }
      + section.settings.map { SearchTarget.setting($0.id) }))
    }
    .onDisappear { page.stop() }
    .sheet(isPresented: Binding(get: { editor.draft != nil }, set: { if !$0 { editor.draft = nil } })) {
      SizeSheet(editor: editor, save: save)
    }
  }

  private var header: some View {
    HStack(spacing: Space.pad + 4) {
      Image(systemName: section.symbol)
        // look-exempt, the section's picture in its glass circle, sized as System Settings does.
        .font(.system(size: 26, weight: .medium))
        .foregroundStyle(.tint)
        .frame(width: SectionPage.header, height: SectionPage.header)
        .glassCircle()
      VStack(alignment: .leading, spacing: Space.row) {
        Text(section.title).font(.largeTitle.weight(.semibold))
        Text("Every layout and size with its shortcut, META and a key").font(.callout).foregroundStyle(.secondary)
      }
      Spacer(minLength: Space.group)
      if let note { Note(text: note.text, symbol: note.symbol) }
    }
    .frame(height: SectionPage.header)
  }

  private var note: (text: String, symbol: String)? {
    if let refusal = model.refusal { return (refusal, "exclamationmark.triangle") }
    if model.reloadDue { return ("Applies when this window closes", "arrow.clockwise") }
    return nil
  }

  // MARK: The cards

  private func actions(_ group: String) -> [WindowAction] { setting.windowActions.filter { $0.group == group } }

  @ViewBuilder private func card(_ title: String, _ list: [WindowAction]) -> some View {
    if !list.isEmpty {
      VStack(alignment: .leading, spacing: Space.related) {
        cardHeader(title)
        rows(list.count) { i in
          let a = list[i]
          HStack(spacing: Space.pad) {
            Text(a.title).frame(maxWidth: .infinity, alignment: .leading)
            recorder(a.action)
          }
          .searchMark(model, SearchTarget.window(a.action))
        }
      }
    }
  }

  private var sizesCard: some View {
    let sizes = setting.value.sizes ?? []
    return VStack(alignment: .leading, spacing: Space.related) {
      HStack {
        cardHeader("Sizes")
        Button {
          editor.isNew = true
          editor.draft = WindowSize(id: "", name: "", width: 1200, height: 800)
        } label: {
          Label("Add Size…", systemImage: "plus")
        }
        .help("Add a size of your own, its name, size, place and display")
      }
      rows(sizes.count) { i in
        let z = sizes[i]
        HStack(spacing: Space.pad) {
          VStack(alignment: .leading, spacing: Space.related / 2) {
            Text(z.name)
            Text(WindowsPage.words(z)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          Button("Edit…") {
            editor.isNew = false
            editor.draft = z
          }
          Button { remove(z) } label: { Image(systemName: "minus.circle") }
            .buttonStyle(.borderless)
            .help(z.shipped ? "\(z.name) ships with Olm and stays" : "Remove \(z.name)")
            .opacity(z.shipped ? 0 : 1)
            .disabled(z.shipped)
          recorder(action(of: z))
        }
        .searchMark(model, SearchTarget.size(z.id))
      }
    }
  }

  private var stepsCard: some View {
    let numbers = section.settings.filter { $0.kind != .sizes }
    return VStack(alignment: .leading, spacing: Space.related) {
      cardHeader("Steps and Sizes")
      rows(numbers.count) { i in
        SettingRow(setting: numbers[i], model: model).searchMark(model, SearchTarget.setting(numbers[i].id))
      }
    }
  }

  private func cardHeader(_ title: String) -> some View {
    HStack {
      Text(title).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, Space.pad + 4)
  }

  /// Rows on one plain card, a divider between each, as the Applications page draws its lists.
  private func rows<Row: View>(_ count: Int, @ViewBuilder _ row: @escaping (Int) -> Row) -> some View {
    VStack(spacing: 0) {
      ForEach(0..<count, id: \.self) { i in
        if i > 0 { Divider().padding(.leading, Space.pad + 4) }
        row(i).padding(.horizontal, Space.pad + 4).padding(.vertical, Space.pad - 4)
      }
    }
    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.quaternary.opacity(0.5)))
  }

  // MARK: Shortcuts, as the Applications page records them, META implied

  private var allSettings: [Setting] { model.share?.sections.flatMap(\.settings) ?? [] }
  private var keysSetting: Setting? { allSettings.first { $0.id == WindowsPage.keysId } }
  private var keysTable: [String: String?] { keysSetting?.value.keys ?? [:] }

  private func id(_ action: String) -> String { "windowmanager." + action }

  private func action(of z: WindowSize) -> String {
    setting.windowActions.first { $0.size == z.id }?.action
      ?? (z.id == "small" ? "smallSize" : z.id == "recording" ? "screenRecording" : "size" + z.id.prefix(1).uppercased() + z.id.dropFirst())
  }

  private func chord(_ action: String) -> String? {
    if let own = keysTable[id(action)] { return own }
    return page.keys[id(action)]
  }

  private func recorder(_ action: String) -> some View {
    let own = keysTable[id(action)] != nil
    let recording = page.recording == id(action)
    let held = chord(action)
    return HStack(spacing: Space.related) {
      UndoButton(shown: own, help: "Back to the key in the config files") { resetKey(action) }
      Button { record(action) } label: {
        Field(width: AppColumns.recorder, leading: false, set: held != nil || recording) {
          Text(recording ? "Press a key" : (held.map(KeyName.words) ?? "None"))
        }
      }
      .buttonStyle(.plain)
      .help(recording ? "Press the key for META and it, Delete for none, Escape to leave it" : "Record a key")
    }
    .disabled(!model.busy.isEmpty)
  }

  private func record(_ action: String) {
    guard let keys = keysSetting else { return }
    let full = id(action)
    page.record(full) { name, _ in
      var next = keysTable
      if let name {
        let chord = "meta+" + name
        if let holder = holder(of: chord, besides: full) {
          model.refusal = "\(KeyName.words(chord)) is \(holder)'s, clear it there first."
          return
        }
        next[full] = .some(chord)
      } else {
        next[full] = .some(nil)
      }
      model.change(keys, to: .keys(next))
    }
  }

  private func resetKey(_ action: String) {
    guard let keys = keysSetting else { return }
    var next = keysTable
    next[id(action)] = nil
    model.change(keys, to: .keys(next))
  }

  private func holder(of chord: String, besides action: String) -> String? {
    let want = chord.lowercased()
    for (other, own) in keysTable where other != action && own?.lowercased() == want { return other }
    for (other, held) in page.keys where other != action && held.lowercased() == want && keysTable[other] == nil {
      return other
    }
    return nil
  }

  // MARK: Sizes, the whole list sent at once

  private func save(_ z: WindowSize) {
    var list = setting.value.sizes ?? []
    var z = z
    if editor.isNew {
      z.id = WindowsPage.newId(z.name, taken: Set(list.map(\.id)))
      list.append(z)
    } else if let i = list.firstIndex(where: { $0.id == z.id }) {
      list[i] = z
    }
    editor.draft = nil
    model.change(setting, to: .sizes(list))
  }

  private func remove(_ z: WindowSize) {
    guard !z.shipped else { return }
    let list = (setting.value.sizes ?? []).filter { $0.id != z.id }
    model.change(setting, to: .sizes(list))
    // Its shortcut goes with it, since its action does.
    if keysTable[id(action(of: z))] != nil { resetKey(action(of: z)) }
  }
}

/// The sheet a size is added or changed in: its name, its size in points or a percent of the screen,
/// where it stands, picked on a grid of the nine anchors, and the display it goes to.
struct SizeSheet: View {
  @ObservedObject var editor: SizeEditor
  let save: (WindowSize) -> Void

  var body: some View {
    if let z = editor.draft {
      VStack(alignment: .leading, spacing: Space.group) {
        Text(editor.isNew ? "New Size" : "Edit \(z.name)").font(.title2.weight(.semibold))
        Form {
          TextField("Name", text: bind(\.name))
          Picker("Measured in", selection: bind(\.percent)) {
            Text("Points").tag(false)
            Text("Percent of the screen").tag(true)
          }
          TextField(z.percent ? "Width, percent" : "Width, points", value: bind(\.width), format: .number)
          TextField(z.percent ? "Height, percent" : "Height, points", value: bind(\.height), format: .number)
          LabeledContent("Position") { anchorGrid(z.anchor) }
          Picker("Display", selection: bind(\.display)) {
            ForEach(WindowsPage.displays, id: \.id) { Text($0.title).tag($0.id) }
          }
        }
        .formStyle(.grouped)
        if let why = problem(z) {
          Text(why).font(.caption).foregroundStyle(.secondary)
        }
        HStack {
          Spacer()
          Button("Cancel") { editor.draft = nil }.keyboardShortcut(.cancelAction)
          Button(editor.isNew ? "Add" : "Save") { save(z) }
            .keyboardShortcut(.defaultAction)
            .disabled(problem(z) != nil)
        }
      }
      .padding(Space.edge)
      .frame(width: 460)
    }
  }

  /// What keeps the size from being saved, nil when nothing does.
  private func problem(_ z: WindowSize) -> String? {
    if z.name.trimmingCharacters(in: .whitespaces).isEmpty { return "A size needs a name." }
    if z.width <= 0 || z.height <= 0 { return "The width and the height are more than nothing." }
    if z.percent && (z.width > 100 || z.height > 100) { return "A share of the screen is at most 100 percent." }
    return nil
  }

  private func bind<T>(_ path: WritableKeyPath<WindowSize, T>) -> Binding<T> {
    Binding(get: { editor.draft![keyPath: path] }, set: { editor.draft?[keyPath: path] = $0 })
  }

  /// The nine anchors as a three by three grid of squares, the chosen one filled.
  private func anchorGrid(_ chosen: String) -> some View {
    VStack(spacing: Space.row * 2) {
      ForEach(0..<3, id: \.self) { row in
        HStack(spacing: Space.row * 2) {
          ForEach(0..<3, id: \.self) { col in
            let a = WindowsPage.anchors[row * 3 + col]
            Button { editor.draft?.anchor = a.id } label: {
              RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(a.id == chosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                .frame(width: 22, height: 16)
            }
            .buttonStyle(.plain)
            .help(a.title)
          }
        }
      }
    }
  }
}
