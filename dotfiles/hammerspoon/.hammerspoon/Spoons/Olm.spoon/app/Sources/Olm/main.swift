// Olm.app's shell, step 1.1 of docs/PLAN-STANDALONE.md. It runs as an accessory, so it has no Dock
// icon and no menu bar, keeps one instance, and answers olm:// URLs. Today the only URL it knows is
// olm://ping?nonce=N, which writes N to ~/.olm/run/ping so a test can tell this app answered it. An
// olm:// URL never runs anything, docs/PROTOCOL-BRIDGE.md, and one this app does not know is logged
// and dropped. The panel it will show comes from the OlmChooser package, linked here already so a
// change there that breaks the app fails this build.

import AppKit
import OlmChooser

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

final class AppDelegate: NSObject, NSApplicationDelegate {
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
