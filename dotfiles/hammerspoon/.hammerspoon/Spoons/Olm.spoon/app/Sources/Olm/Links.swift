// A web link handed to Olm as the default browser, docs/DESIGN-BROWSER-SWITCHER.md. Receiving it
// is the app's, so no link is lost while Hammerspoon reloads. Which browser it opens in is the
// plugin's, asked over the bridge with `link`, the link, the app it came from and whether Option
// was held. A link nobody answers opens in Safari, which every Mac has, and is logged.
//
// Olm never opens a link through the default browser, since that is Olm, so the fallback names
// Safari's bundle outright.

import AppKit
import OlmBridge
import OlmKit

enum Links {
  /// How long the bridge may stay down, a reload, before the link goes to Safari.
  static let connectWait: Double = 3
  /// How long the plugin may take to answer once asked.
  static let answerWait: Double = 2

  static func isWeb(_ url: URL) -> Bool { url.scheme == "http" || url.scheme == "https" }

  /// The app that sent the open, read off the Apple Event being handled, so call it from inside
  /// application(_:open:).
  @MainActor static func sender() -> NSRunningApplication? {
    guard let event = NSAppleEventManager.shared().currentAppleEvent,
      let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value, pid > 0,
      pid != ProcessInfo.processInfo.processIdentifier else { return nil }
    return NSRunningApplication(processIdentifier: pid)
  }

  @MainActor static func route(_ url: URL, bridge: Bridge) {
    let source = sender()
    var params: [String: JSON] = ["url": .string(url.absoluteString),
      "ask": .bool(NSEvent.modifierFlags.contains(.option))]
    if let bundle = source?.bundleIdentifier { params["sourceBundle"] = .string(bundle) }
    if let name = source?.localizedName { params["sourceName"] = .string(name) }
    let message = JSON.object(params)
    Task {
      let handled = await ask(bridge, message)
      if !handled { await MainActor.run { fallback(url) } }
    }
  }

  /// Whether the plugin took the link, waiting out a reload and then a slow answer.
  private static func ask(_ bridge: Bridge, _ message: JSON) async -> Bool {
    let start = Date()
    while true {
      let answer = Once()
      Task {
        do {
          let result = try await bridge.request("link", message)
          answer.fire(.answered(result["handled"] == .bool(true)))
        } catch BridgeError.gone {
          answer.fire(.gone)
        } catch {
          answer.fire(.answered(false))
        }
      }
      Task {
        try? await Task.sleep(nanoseconds: UInt64(answerWait * 1e9))
        answer.fire(.late)
      }
      switch await answer.value() {
      case .answered(let handled): return handled
      case .late:
        NSLog("Olm: a link went unanswered for %.1f s, opened in Safari", answerWait)
        return false
      case .gone:
        if Date().timeIntervalSince(start) > connectWait {
          NSLog("Olm: a link arrived while Hammerspoon was not connected, opened in Safari")
          return false
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
      }
    }
  }

  @MainActor static func fallback(_ url: URL) {
    guard let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else {
      NSLog("Olm: a link had nowhere to open, %@", url.absoluteString)
      return
    }
    NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: NSWorkspace.OpenConfiguration())
  }

  enum Outcome: Sendable { case answered(Bool), gone, late }

  /// The first of several answers, the rest dropped.
  final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: Outcome?
    private var waiting: CheckedContinuation<Outcome, Never>?

    func fire(_ value: Outcome) {
      lock.lock()
      guard outcome == nil else { lock.unlock(); return }
      outcome = value
      let resume = waiting
      waiting = nil
      lock.unlock()
      resume?.resume(returning: value)
    }

    func value() async -> Outcome {
      await withCheckedContinuation { done in
        lock.lock()
        if let outcome { lock.unlock(); done.resume(returning: outcome); return }
        waiting = done
        lock.unlock()
      }
    }
  }
}
