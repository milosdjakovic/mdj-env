// Olm.app's composition root, docs/DESIGN-APP.md, and the only file that names a concrete plugin.
// It builds the stage, constructs every source, registers it under its manifest's name and answers
// olm:// URLs, docs/PROTOCOL-BRIDGE.md, by asking the stage to open a list. Nothing else lives here.
//
// It runs as an accessory, so it has no Dock icon and no menu bar, and keeps one instance.
// olm://ping?nonce=N answers a test, Ping.swift. olm://<name>?screen=MODE&query=TEXT opens the
// source registered under that name with TEXT in its input field, on the screen MODE names.
// olm://shadow?tool=<name>&id=N compares the Lua list's answer with the app's, OlmCore's Shadow, and
// the distributed notification local.olm.Olm.shadow, object "<name>:<N>", asks the same, which is
// how host/bridge asks it.
// An olm:// URL never runs anything, and one this app does not know is logged and dropped.

import AppKit
import FileSearchPlugin
import OlmCore
import OlmKit

let home = FileManager.default.homeDirectoryForCurrentUser
let olm = home.appendingPathComponent(".olm")
let context = PluginContext(
  run: olm.appendingPathComponent("run"),
  cache: olm.appendingPathComponent("cache"),
  resources: Bundle.main.resourceURL ?? URL(fileURLWithPath: "."),
  store: olm.appendingPathComponent("state/filesearch"))

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let searcher = Searcher()
  private lazy var stage = Stage(searcher: searcher)
  private let sources: [String: any ListSource]
  private let shadows: [String: Shadow]

  override init() {
    let fileSearch = FileSearchSource(context: context, asksAccess: true)
    sources = [fileSearch.manifest.name: fileSearch]
    // The shadow answers on a source of its own, so a list a person has open is never touched.
    let shadowed = FileSearchSource(context: context)
    shadows = [shadowed.manifest.name: Shadow(tool: shadowed.manifest.name, source: shadowed,
      searcher: searcher, run: context.run, log: olm.appendingPathComponent("log"),
      skip: { FileSearchSource.shadowSkip($0, settings: .read(from: context.run)) })]
    super.init()
  }

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
      return
    }
    // Each answer the Lua list settles on is told by a distributed notification whose object is
    // "<tool>:<id>", host/bridge's _tell, rather than olm://shadow, since running open while the
    // Lua list was up left it with no rows, found in the 1.3f trial on 2026-11-08.
    DistributedNotificationCenter.default().addObserver(self, selector: #selector(shadowNote(_:)),
      name: Notification.Name("local.olm.Olm.shadow"), object: nil, suspensionBehavior: .deliverImmediately)
    // A served key tells the running app its olm:// URL the same way, host/bridge's serves, some
    // fifty milliseconds sooner than open, measured in the 1.4a trial on 2026-11-08.
    DistributedNotificationCenter.default().addObserver(self, selector: #selector(openNote(_:)),
      name: Notification.Name("local.olm.Olm.open"), object: nil, suspensionBehavior: .deliverImmediately)
  }

  @objc private func openNote(_ note: Notification) {
    guard let object = note.object as? String, let url = URL(string: object) else { return }
    application(NSApp, open: [url])
  }

  @objc private func shadowNote(_ note: Notification) {
    guard let object = note.object as? String else { return }
    let parts = object.split(separator: ":")
    guard parts.count == 2, let shadow = shadows[String(parts[0])], let id = Int(parts[1]) else { return }
    shadow.run(id: id)
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      guard url.scheme == "olm" else { continue }
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      func item(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
      if let nonce = Ping.nonce(url) {
        Ping.answer(nonce, in: context.run)
      } else if url.host == "shadow", let tool = item("tool"), let shadow = shadows[tool],
        let id = item("id").flatMap({ Int($0) }) {
        shadow.run(id: id)
      } else if let host = url.host, let source = sources[host] {
        stage.open(source, query: item("query") ?? "", screen: item("screen"))
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
