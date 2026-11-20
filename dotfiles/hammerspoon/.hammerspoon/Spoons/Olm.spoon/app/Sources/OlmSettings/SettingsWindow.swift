// The Olm Settings window, docs/DESIGN-APP-SETTINGS.md. An ordinary macOS window drawn with the
// system's own controls and built on Liquid Glass: the system's own sidebar of sections with a
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
  /// Where the window's close button starts, which the sidebar's search and the app's row line up
  /// with.
  @Published var leading: CGFloat = 20
  /// How far the window's buttons reach down from the top, which the search sits a group's gap under.
  @Published var buttonsBottom: CGFloat = 32
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
      build()
    }
    if let window, !window.isVisible { Self.centre(window) }
    NSApp.setActivationPolicy(.regular)
    NSApp.mainMenu = Self.menu()
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
    alignToButtons()
  }

  /// The sidebar's search and the app's row start where the close button does, read off the
  /// window rather than guessed, since the system places the buttons.
  private func alignToButtons() {
    guard let window, let model, let close = window.standardWindowButton(.closeButton) else { return }
    let frame = close.convert(close.bounds, to: nil)
    let left = frame.minX
    if left > 0, abs(model.leading - left) > 0.5 { model.leading = left }
    if let height = window.contentView?.bounds.height {
      let bottom = height - frame.minY
      if bottom > 0, abs(model.buttonsBottom - bottom) > 0.5 { model.buttonsBottom = bottom }
    }
  }

  /// Builds the window and lays it out without showing it, called by the app a moment after it
  /// starts, so the first open shows a window already drawn rather than building SwiftUI's views
  /// while it comes up, which was slow and flickered.
  public func prepare() {
    guard window == nil else { return }
    build()
    window?.contentView?.layoutSubtreeIfNeeded()
    alignToButtons()
  }

  private func build() {
    let model = SettingsModel(share: share(), service: service)
    self.model = model
    let w = NSWindow(contentViewController: SettingsSplit(model: model))
    w.title = "Olm Settings"
    w.titleVisibility = .hidden
    w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    // An empty toolbar in the full unified style, as Finder has, so the window's buttons sit lower
    // and further in with room around them, over a see-through title bar with no line, so no band is
    // drawn over the pane. The compact style drew one when the pointer reached the top.
    w.toolbar = NSToolbar(identifier: "OlmSettings")
    w.toolbarStyle = .unified
    w.titlebarAppearsTransparent = true
    w.titlebarSeparatorStyle = .none
    w.isReleasedWhenClosed = false
    w.setContentSize(NSSize(width: 1100, height: 740))
    w.contentMinSize = NSSize(width: SettingsSplit.sidebarWidth + 560, height: 520)
    // The size is kept between openings and the place is not, since it opens centred. Named
    // afresh with each larger default, so a size saved at an older one is not restored.
    w.setFrameAutosaveName("OlmSettingsPaneFrame")
    w.delegate = self
    window = w
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

/// The sidebar and the pane as AppKit's own split, a sidebar item so it is drawn as the running
/// system draws sidebars, macOS 27 having left macOS 26's floating glass panel, and runs under the
/// window's buttons. SwiftUI's NavigationSplitView ignored its column width in a
/// window made by hand, about 140 points whatever was asked, and a width forced onto its split view
/// afterwards flickered as the window resized and collapsed when dragged left. Here the width is
/// the item's own, fixed, the divider takes no drag and the sidebar cannot collapse.
@MainActor
final class SettingsSplit: NSSplitViewController {
  static let sidebarWidth: CGFloat = 280

  init(model: SettingsModel) {
    super.init(nibName: nil, bundle: nil)
    // Neither hosting controller sizes the window, which it otherwise does once SwiftUI has measured
    // its views, after the window is up, and which showed as a flicker on open.
    let side = NSHostingController(rootView: SettingsSidebar(model: model))
    side.sizingOptions = []
    let sidebar = NSSplitViewItem(sidebarWithViewController: side)
    sidebar.minimumThickness = Self.sidebarWidth
    sidebar.maximumThickness = Self.sidebarWidth
    sidebar.canCollapse = false
    sidebar.allowsFullHeightLayout = true
    sidebar.holdingPriority = .required
    let pane = NSHostingController(rootView: SettingsDetail(model: model))
    pane.sizingOptions = []
    let detail = NSSplitViewItem(viewController: pane)
    detail.minimumThickness = 560
    addSplitViewItem(sidebar)
    addSplitViewItem(detail)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("not from a nib") }

  /// No place on the divider answers a drag, so the width cannot be changed or the sidebar hidden.
  override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect,
                          forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect { .zero }

  override func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }
}

/// Every gap in the window is one of these, so the layout reads as one system and a change keeps
/// to it. docs/DESIGN-APP-SETTINGS.md, under Layout, states the rules beside them.
enum Space {
  /// From a container's edge to what it holds, the pane's page on all four sides.
  static let edge: CGFloat = 24
  /// Between groups, the header and the card, the search and the sections, the sections and the
  /// app's row.
  static let group: CGFloat = 20
  /// Inside a card or a sidebar row, from its edge to its content, and between a picture and its
  /// text.
  static let pad: CGFloat = 12
  /// Between related elements, a title and the line under it, a control and its value.
  static let related: CGFloat = 6
  /// Between the rows of one list.
  static let row: CGFloat = 2
  /// The height of a sidebar row and of the search, one line of text and its pad.
  static let rowHeight: CGFloat = 32
  /// The column a row's control sits in, fixed, so a popup's width changing with its choice moves
  /// nothing else in the row.
  static let control: CGFloat = 300
  /// The width a number's value is shown in, the widest it can be, so dragging moves nothing.
  static let value: CGFloat = 76
}

/// The search, the sections and the app's row. The sidebar's edge is where the window's close
/// button starts, read off the window, so the search, every row's highlight and the buttons share
/// one left edge, and the same gap is kept on the right.
struct SettingsSidebar: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    VStack(alignment: .leading, spacing: Space.group) {
      SearchField(text: $model.query, move: move)
      ScrollView {
        VStack(spacing: Space.row) {
          ForEach(model.sections) { section in
            SidebarRow(section: section, selected: section.id == model.current?.id) {
              model.selection = section.id
            }
          }
        }
      }
      .scrollIndicators(.never)
      AppIdentity().padding(.horizontal, Space.pad)
    }
    .padding(.horizontal, model.leading)
    // The search a group's gap under the window's buttons, measured from the window's top rather
    // than from under the title bar, whose height left a gap of about forty points.
    .padding(.top, model.buttonsBottom + Space.group)
    .padding(.bottom, model.leading)
    .ignoresSafeArea(.container, edges: .top)
    .onChange(of: model.query) {
      let sections = model.sections
      if let first = sections.first, !sections.contains(where: { $0.id == model.selection }) {
        model.selection = first.id
      }
    }
  }

  /// Up and down in the search move between the sections, as in System Settings.
  private func move(_ by: Int) {
    let sections = model.sections
    guard !sections.isEmpty else { return }
    let at = sections.firstIndex(where: { $0.id == model.current?.id }) ?? 0
    model.selection = sections[min(max(at + by, 0), sections.count - 1)].id
  }
}

/// One section in the sidebar. The highlight is a fill behind the row and nothing else changes when
/// it moves, no weight and no size, so choosing a section shifts nothing.
struct SidebarRow: View {
  let section: SettingsSection
  let selected: Bool
  let choose: () -> Void

  var body: some View {
    Button(action: choose) {
      HStack(spacing: Space.pad) {
        Image(systemName: section.symbol)
          .foregroundStyle(.tint)
          .frame(width: 20)
        Text(section.title)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, Space.pad)
      .frame(height: Space.rowHeight)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(selected ? Color.primary.opacity(0.09) : .clear)
      )
    }
    .buttonStyle(.plain)
  }
}

/// The search over the sections, a Liquid Glass capsule a row tall and a little more, its magnifier
/// in line with the sections' symbols, the field inside it plain so the glass is the only bezel. The
/// clear button keeps its place when hidden, so typing moves nothing.
struct SearchField: View {
  @Binding var text: String
  let move: (Int) -> Void

  var body: some View {
    HStack(spacing: Space.pad) {
      Image(systemName: "magnifyingglass").foregroundStyle(.secondary).frame(width: 20)
      TextField("Search", text: $text)
        .textFieldStyle(.plain)
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
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

/// The chosen section on the window's own background.
struct SettingsDetail: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    Group {
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
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// The app's icon, name and version at the foot of the sidebar, its icon's left edge in line with
/// the sections' symbols.
struct AppIdentity: View {
  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
  }

  var body: some View {
    HStack(spacing: Space.pad) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .interpolation(.high)
        .frame(width: 36, height: 36)
      VStack(alignment: .leading, spacing: Space.row) {
        Text("Olm").font(.headline)
        Text("Version \(version)").font(.subheadline).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
  }
}

/// One section, its header and its settings on one glass card. The line saying a change waits for
/// the window to close, or was refused, sits in a fixed place at the header's right, so it comes and
/// goes without moving the card.
struct SectionPage: View {
  /// The header's height, the section's picture.
  static let header: CGFloat = 60
  let section: SettingsSection
  @ObservedObject var model: SettingsModel

  var body: some View {
    ScrollView {
      GlassGroup {
        VStack(alignment: .leading, spacing: Space.group) {
          HStack(spacing: Space.pad + 4) {
            Image(systemName: section.symbol)
              // The window follows the system's look and not the chooser's.
              // look-exempt, the section's picture in its glass circle, sized as System Settings does.
              .font(.system(size: 26, weight: .medium))
              .foregroundStyle(.tint)
              .frame(width: Self.header, height: Self.header)
              .glassCircle()
            VStack(alignment: .leading, spacing: Space.row) {
              Text(section.title).font(.largeTitle.weight(.semibold))
              Text(section.settings.count == 1 ? "1 setting" : "\(section.settings.count) settings")
                .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.group)
            // Left out when there is nothing to say, not made transparent, since glass draws its
            // capsule whatever the opacity. The header's height is fixed, so this moves nothing.
            if !note.text.isEmpty { Note(text: note.text, symbol: note.symbol) }
          }
          .frame(height: Self.header)
          VStack(spacing: 0) {
            ForEach(Array(section.settings.enumerated()), id: \.element.id) { index, setting in
              if index > 0 { Divider().padding(.leading, Space.pad + 4) }
              SettingRow(setting: setting, model: model)
                .padding(.horizontal, Space.pad + 4).padding(.vertical, Space.pad)
            }
          }
          .glassCard(cornerRadius: 20)
        }
        .padding(Space.edge)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    // The gap is measured from the window's edge at the top too, since nothing is drawn over the
    // pane, so the page sits the same distance from all four edges.
    .ignoresSafeArea(.container, edges: .top)
    .softTopEdge()
  }

  private var note: (text: String, symbol: String) {
    if let refusal = model.refusal { return (refusal, "exclamationmark.triangle") }
    if model.reloadDue { return ("Applies when this window closes", "arrow.clockwise") }
    return ("", "arrow.clockwise")
  }
}

/// One line in a glass capsule, at most two lines wide enough to read, so a long refusal wraps in
/// its place rather than pushing the header.
struct Note: View {
  let text: String
  let symbol: String

  var body: some View {
    Label(text, systemImage: symbol)
      .font(.callout).foregroundStyle(.secondary)
      .lineLimit(2)
      .frame(maxWidth: 340, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, Space.pad).padding(.vertical, Space.related + 2)
      .glassCard(cornerRadius: 999)
  }
}

struct SettingRow: View {
  let setting: Setting
  @ObservedObject var model: SettingsModel

  var body: some View {
    // The reset button keeps its place when hidden and the control sits in a column of fixed width,
    // so a value changing, or the reset appearing, moves nothing in the row.
    let canReset = setting.differs && setting.locked == nil
    HStack(alignment: .center, spacing: Space.pad) {
      label
      Spacer(minLength: Space.pad)
      Button {
        model.change(setting, to: .none, reset: true)
      } label: {
        Image(systemName: "arrow.uturn.backward")
      }
      .buttonStyle(.borderless)
      .help("Back to the value in the config files")
      .opacity(canReset ? 1 : 0)
      .disabled(!canReset)
      control.labelsHidden()
        .frame(width: Space.control, alignment: .trailing)
    }
    .disabled(setting.locked != nil || model.busy.contains(setting.id))
    .help(setting.locked ?? "")
  }

  @ViewBuilder private var label: some View {
    VStack(alignment: .leading, spacing: Space.related / 2) {
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
      HStack(spacing: Space.pad) {
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
          .lineLimit(1)
          .frame(width: Space.value, alignment: .trailing)
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
      GlassEffectContainer(spacing: Space.group) { content }
    } else {
      content
    }
  }
}

extension View {
  @ViewBuilder func glassCapsule() -> some View {
    if #available(macOS 26, *) {
      glassEffect(.regular.interactive(), in: Capsule())
    } else {
      background(.thinMaterial, in: Capsule())
    }
  }

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

  @ViewBuilder func softTopEdge() -> some View {
    if #available(macOS 26, *) {
      scrollEdgeEffectStyle(.soft, for: .top)
    } else {
      self
    }
  }
}
