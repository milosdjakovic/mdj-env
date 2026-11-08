// Olm.app's shell, steps 1.1 and 1.2 of docs/PLAN-STANDALONE.md. It runs as an accessory, so it has
// no Dock icon and no menu bar, keeps one instance, and answers olm:// URLs, docs/PROTOCOL-BRIDGE.md.
// olm://ping?nonce=N writes N to ~/.olm/run/ping so a test can tell this app answered it, and
// olm://filesearch?query=TEXT shows the file search's chooser with TEXT in its input field, and
// olm://shadow?tool=filesearch&id=N compares the Lua file search's answer with the app's, Shadow.swift. An
// olm:// URL never runs anything, and one this app does not know is logged and dropped.
//
// The chooser is the swift chooser's own panel from the OlmChooser package. Its types are internal
// to that package today, so this file reaches them through a testable import, which the package's
// -enable-testing allows. Step 1.3, which gives the app its own search, makes the panel's API public.

import AppKit
@testable import OlmChooser
import OlmSearch

enum Ping {
  /// The nonce a ping carries, or nil when the URL is not a well formed ping. A nonce is what a
  /// test wrote, so it is short and plain, and anything else is refused rather than written.
  static func nonce(_ url: URL) -> String? {
    guard url.scheme == "olm", url.host == "ping",
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
      let nonce = items.first(where: { $0.name == "nonce" })?.value,
      !nonce.isEmpty, nonce.count <= 64,
      nonce.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
    else { return nil }
    return nonce
  }

  /// Writes the nonce through a temporary file and a rename, so a reader never sees half of it.
  static func answer(_ nonce: String) {
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".olm/run")
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let tmp = dir.appendingPathComponent("ping.tmp")
      try (nonce + "\n").write(to: tmp, atomically: false, encoding: .utf8)
      _ = try FileManager.default.replaceItemAt(dir.appendingPathComponent("ping"), withItemAt: tmp)
    } catch {
      NSLog("Olm: could not answer a ping, %@", "\(error)")
    }
  }
}

// The file search's chooser, steps 1.2 and 1.3d. The panel is the swift chooser's own, and what it
// lists comes from FileSearchEngine in OlmSearch, which parses, asks the index and ranks off the
// main thread, so this class only hands the panel what the engine answered. Return opens the
// highlighted file, Command and Return shows it in Finder, and either closes the list. It hides on
// Escape, on a press outside it and when it loses key. How it looks and where it stands is the swift
// chooser's own, Look.swift, handed over by the bridge.
//
// The settings, file search's types and limits, are the ones config/filesearch.lua holds. The
// bridge host writes them to ~/.olm/run/filesearch.json on every load where the olmapp piece is
// on, and the app reads that file on every show, so the config keeps one owner.
final class FileSearch: ChooserSource {
  private static let home = FileManager.default.homeDirectoryForCurrentUser.path
  private let engine: FileSearchEngine
  private var rows: [IndexRow] = []
  private var highlight = 1
  // Each file's icon once it has been drawn, so a row is sent with its icon whenever it has one.
  // A row sent without one is drawn blank until the list asks for it, which flickered every icon
  // on every keystroke, reported in the 1.3d trial on 2026-11-08.
  private let icons = NSCache<NSString, NSImage>()

  init() {
    engine = FileSearchEngine(index: Self.index(), settings: Self.settings().0)
  }

  // The index the helper keeps, asked through the helper bundled in the app.
  static func index() -> FileIndex {
    let helper = Bundle.main.resourceURL?.appendingPathComponent("fileindex").path ?? "fileindex"
    return FileIndex(helper: helper, index: home + "/.olm/cache/filesearch/file-index.txt")
  }

  private lazy var panel = ChooserPanel(source: self)
  // The swift chooser's look as the bridge last wrote it, read on every show, Look.swift.
  private var look: Look?
  private var placeholder = ""
  private var text = ""

  // config/filesearch.lua's types, limits and placeholder, as the bridge wrote them, or the Lua
  // defaults.
  static func settings() -> (FileSearchSettings, String) {
    var settings = FileSearchSettings()
    let url = URL(fileURLWithPath: home + "/.olm/run/filesearch.json")
    guard let data = try? Data(contentsOf: url),
      let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (settings, "") }
    if let types = doc["types"] as? [String: [String]] { settings.types = types }
    let limits = doc["limits"] as? [String: Any] ?? [:]
    if let n = limits["retainCap"] as? Int { settings.retainCap = n }
    if let n = limits["minChars"] as? Int { settings.minChars = n }
    if let n = limits["recentDays"] as? Int { settings.recentDays = n }
    if let n = limits["recentCount"] as? Int { settings.recentCount = n }
    return (settings, doc["placeholder"] as? String ?? "")
  }

  // screen is the placement choice the URL carried, lib/overlaydisplay.lua's mode.
  func show(query: String, screen mode: String? = nil) {
    (engine.settings, placeholder) = Self.settings()
    engine.reset()
    look = Look.read()
    if let look, let screen = Look.screen(for: mode) {
      panel.applyStyle(look.style())
      panel.place(look.placement(on: screen))
    } else {
      // No look has been written yet, so the panel draws on its own defaults until Hammerspoon
      // loads with the piece on.
      NSLog("Olm: no chooser look at %@, the panel's defaults are used", Look.path)
      panel.place(Self.placement())
    }
    rows = []
    panel.setRows([])
    apply(status: nil)
    panel.start()
    panel.show()
    panel.setText(query)
    search(query)
  }

  func hide() {
    guard panel.isVisible else { return }
    panel.hide()
    panel.stop()
  }

  private func search(_ text: String) {
    self.text = text
    engine.query(text) { [weak self] answer in
      guard let self else { return }
      // The same files in the same order are left as they are drawn, so a keystroke that does
      // not change the results redraws nothing.
      if answer.rows.map(\.path) != self.rows.map(\.path) {
        self.rows = answer.rows
        self.panel.setRows(answer.rows.map(self.row))
      }
      self.highlight = answer.rows.isEmpty ? 0 : 1
      self.apply(status: answer.status)
    }
  }

  // The state the Lua view sends, providers/swift/view.lua's redraw. The first nine rows carry
  // Command and their digit wherever the list scrolls, the selected row Return, and a typed query
  // with no rows says so in the canvas view's words, or the engine's status where it has one.
  private func apply(status: String?) {
    var state = ViewState()
    state.placeholder = placeholder
    state.highlight = highlight
    state.lineBreak = look?.lineBreak ?? .byTruncatingTail
    if look?.showNumbers == true, !rows.isEmpty { state.slots = Array(1...min(9, rows.count)) }
    state.empty = rows.isEmpty && (status != nil || !text.isEmpty)
    state.emptyText = status ?? "No results"
    panel.update(state)
  }

  private func row(_ r: IndexRow) -> Row {
    var row = Row()
    row.title = r.name
    let dir = (r.path as NSString).deletingLastPathComponent
    row.subtitle = dir.hasPrefix(Self.home) ? "~" + dir.dropFirst(Self.home.count) : dir
    row.image = icons.object(forKey: r.path as NSString)
    return row
  }

  private func icon(_ path: String) -> NSImage {
    if let image = icons.object(forKey: path as NSString) { return image }
    let image = NSWorkspace.shared.icon(forFile: path)
    icons.setObject(image, forKey: path as NSString)
    return image
  }

  private func act(on index: Int, reveal: Bool) {
    guard index >= 1, index <= rows.count else { return }
    let url = URL(fileURLWithPath: rows[index - 1].path)
    hide()
    if reveal {
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } else {
      NSWorkspace.shared.open(url)
    }
  }

  func ask(_ event: String, _ args: [PanelValue]) -> Bool {
    switch event {
    case "dismiss", "resignedKey", "pressOutside":
      hide()
    case "text":
      if case .string(let text)? = args.first { search(text) }
    case "highlighted":
      if case .int(let index)? = args.first { highlight = index }
    case "choose":
      if case .int(let index)? = args.first { act(on: index, reveal: false) }
    case "wantIcons":
      guard case .string(let list)? = args.first else { break }
      let images = list.split(separator: ",").compactMap { Int($0) }
        .filter { $0 >= 1 && $0 <= rows.count }
        .map { ($0 - 1, icon(rows[$0 - 1].path), false) }
      if !images.isEmpty { panel.setImages(images) }
    case "listKey":
      guard case .bytes(let data)? = args.first,
        let event = CGEvent(withDataAllocator: nil, data: data as CFData) else { return false }
      let code = event.getIntegerValueField(.keyboardEventKeycode)
      // Command and a digit opens the row in that slot, as the engine's _chooseSlot does, where
      // the list shows its numbers.
      if event.flags.contains(.maskCommand), look?.showNumbers == true,
        let slot = Self.digitKeys.firstIndex(of: code) {
        act(on: slot + 1, reveal: false)
        return true
      }
      guard code == 36 || code == 76 else { return false }
      act(on: highlight, reveal: event.flags.contains(.maskCommand))
      return true
    default:
      break
    }
    return false
  }

  // The digit keys one through nine, as virtual key codes.
  private static let digitKeys: [Int64] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

  // Only while no look has been written. A chooser 680 points wide a fifth of the way down the screen under the pointer, in
  // Hammerspoon's space, y measured down from the top of the primary screen, which is what the
  // panel is placed in. Eight rows show at once.
  private static func placement() -> Placement {
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let primary = NSScreen.screens.first?.frame.height ?? visible.maxY
    let width: CGFloat = 680
    let rowH: CGFloat = 44
    let height: CGFloat = 64 + rowH * 8 + 8
    let top = primary - visible.maxY + visible.height * 0.18
    var p = Placement()
    p.canvas = NSRect(x: visible.midX - width / 2, y: top, width: width, height: height)
    p.window = p.canvas
    p.listFrame = NSRect(x: 0, y: 0, width: width, height: height)
    p.field = NSRect(x: 20, y: 14, width: width - 40, height: 40)
    p.list = NSRect(x: 8, y: 64, width: width - 16, height: height - 72)
    p.rowH = rowH
    p.iconSize = 28
    p.iconFrame = 32
    p.iconPad = (rowH - 28) / 2
    p.iconPadLeft = 12
    p.iconGap = 10
    p.padX = 12
    p.pad = 8
    return p
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let fileSearch = FileSearch()
  private lazy var shadow = FileSearchShadow(index: FileSearch.index())

  func applicationDidFinishLaunching(_ notification: Notification) {
    // LaunchServices keeps one instance for a bundle it opens, LSMultipleInstancesProhibited in
    // Info.plist. A second copy started some other way, the executable run by hand, leaves at once.
    let me = NSRunningApplication.current
    let others = NSRunningApplication.runningApplications(
      withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.olm.Olm"
    ).filter { $0.processIdentifier != me.processIdentifier }
    if !others.isEmpty {
      NSLog("Olm: another instance is running, pid %d, leaving", others[0].processIdentifier)
      NSApp.terminate(nil)
    }
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      if let nonce = Ping.nonce(url) {
        Ping.answer(nonce)
      } else if url.scheme == "olm", url.host == "shadow" {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        guard items?.first(where: { $0.name == "tool" })?.value == "filesearch",
          let id = items?.first(where: { $0.name == "id" })?.value.flatMap({ Int($0) })
        else {
          NSLog("Olm: a shadow URL this app does not know, %@", url.absoluteString)
          continue
        }
        shadow.run(id: id, settings: FileSearch.settings().0)
      } else if url.scheme == "olm", url.host == "filesearch" {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        fileSearch.show(query: items?.first(where: { $0.name == "query" })?.value ?? "",
          screen: items?.first(where: { $0.name == "screen" })?.value)
      } else {
        NSLog("Olm: an olm URL this app does not know, %@", url.absoluteString)
      }
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
