// Olm.app's shell, steps 1.1 and 1.2 of docs/PLAN-STANDALONE.md. It runs as an accessory, so it has
// no Dock icon and no menu bar, keeps one instance, and answers olm:// URLs, docs/PROTOCOL-BRIDGE.md.
// olm://ping?nonce=N writes N to ~/.olm/run/ping so a test can tell this app answered it, and
// olm://filesearch?query=TEXT shows the file search's chooser with TEXT in its input field. An
// olm:// URL never runs anything, and one this app does not know is logged and dropped.
//
// The chooser is the swift chooser's own panel from the OlmChooser package. Its types are internal
// to that package today, so this file reaches them through a testable import, which the package's
// -enable-testing allows. Step 1.3, which gives the app its own search, makes the panel's API public.

import AppKit
@testable import OlmChooser

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

// The file search's chooser, step 1.2. It shows the panel with the query in its input field and a
// list that says search arrives in the next step, so the trigger can be tried before the search
// exists. It hides on Escape, on a press outside it and when it loses key. The layout is fixed
// here until step 1.3 brings the engine's geometry over.
final class FileSearch: ChooserSource {
  private lazy var panel: ChooserPanel = {
    let panel = ChooserPanel(source: self)
    var style = Style()
    style.radius = 18
    style.highlightRadius = 10
    style.fieldFont = NSFont.systemFont(ofSize: 22)
    panel.applyStyle(style)
    return panel
  }()

  func show(query: String) {
    panel.place(Self.placement())
    var state = ViewState()
    state.placeholder = "Search Files"
    state.empty = true
    state.emptyText = "Search arrives with step 1.3"
    panel.setRows([])
    panel.update(state)
    panel.start()
    panel.show()
    panel.setText(query)
  }

  func hide() {
    guard panel.isVisible else { return }
    panel.hide()
    panel.stop()
  }

  func ask(_ event: String, _ args: [PanelValue]) -> Bool {
    switch event {
    case "dismiss", "resignedKey", "pressOutside": hide()
    default: break
    }
    return false
  }

  // A chooser 640 points wide a fifth of the way down the screen under the pointer, in
  // Hammerspoon's space, y measured down from the top of the primary screen, which is what the
  // panel is placed in.
  private static func placement() -> Placement {
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let primary = NSScreen.screens.first?.frame.height ?? visible.maxY
    let width: CGFloat = 640
    let height: CGFloat = 160
    let top = primary - visible.maxY + visible.height * 0.2
    var p = Placement()
    p.canvas = NSRect(x: visible.midX - width / 2, y: top, width: width, height: height)
    p.window = p.canvas
    p.listFrame = NSRect(x: 0, y: 0, width: width, height: height)
    p.field = NSRect(x: 20, y: 14, width: width - 40, height: 40)
    p.list = NSRect(x: 8, y: 64, width: width - 16, height: height - 72)
    p.rowH = 40
    p.padX = 12
    p.pad = 8
    return p
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let fileSearch = FileSearch()

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
      } else if url.scheme == "olm", url.host == "filesearch" {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        fileSearch.show(query: items?.first(where: { $0.name == "query" })?.value ?? "")
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
