// Browser Switcher, a core plugin built into Olm.app, docs/DESIGN-BROWSER-SWITCHER.md and
// docs/DESIGN-APP-PLUGINS.md. Olm.app is the default browser and opens this list for each link it
// receives, handing it the link, the browsers Olm found and the favourites set in Olm Settings. The
// list asks where the link opens, a browser or one of its profiles, with Copy Link on Command and
// Return and Show All in the actions pane for the rest. It names a browser by Olm's id and Olm opens
// the link there, so the program and its arguments stay Olm's, as they were while it ran sandboxed.
//
// It ran as an external plugin from 2026-11-24 and moved in on 2026-11-28, the same rows and words,
// asked by Milos. The last link is kept in its state folder, so olm://browserswitcher opens it again
// to send it somewhere else.

import Foundation
import OlmKit

public actor BrowserSwitcher: ListSource {
  /// A browser or one of its profiles, as Olm found it.
  public struct Target: Sendable, Equatable {
    public var title: String
    public var browser: String
    public var bundle: String
    /// What Olm opens it by.
    public var id: String

    public init(title: String, browser: String, bundle: String, id: String) {
      self.title = title
      self.browser = browser
      self.bundle = bundle
      self.id = id
    }
  }

  /// What Olm does for it, read at each open so the list follows Olm Settings.
  public struct Host: Sendable {
    /// Every browser and profile it may name, in the order dragged in Olm Settings.
    public var targets: @Sendable () async -> [Target]
    /// The ids checked as favourites, and the order, custom, most or last.
    public var favourites: @Sendable () -> [String]
    public var order: @Sendable () -> String?
    /// Opens the link in the browser or profile by Olm's id, false when Olm refused.
    public var open: @Sendable (String, String) async -> Bool
    public var copy: @Sendable (String) async -> Void
    public var notify: @Sendable (String) -> Void

    public init(targets: @escaping @Sendable () async -> [Target], favourites: @escaping @Sendable () -> [String],
                order: @escaping @Sendable () -> String?, open: @escaping @Sendable (String, String) async -> Bool,
                copy: @escaping @Sendable (String) async -> Void, notify: @escaping @Sendable (String) -> Void) {
      self.targets = targets
      self.favourites = favourites
      self.order = order
      self.open = open
      self.copy = copy
      self.notify = notify
    }
  }

  public static let id = "browserswitcher"
  public nonisolated let manifest: Manifest
  public nonisolated var runsEveryVerb: Bool { true }

  private let host: Host
  private let given: String?
  private let lastFile: URL
  private let usage: Usage
  private var link: String?
  private var targets: [Target] = []
  private var favourites: [String] = []
  private var order: Usage.Order?
  private var showAll = false

  /// link, the one clicked, nil to open the last one again. store, its own folder in Olm's state.
  public init(host: Host, link: String?, store: URL, actions: [Action]) {
    self.host = host
    given = link
    lastFile = store.appendingPathComponent("last.json")
    usage = Usage(store.appendingPathComponent("usage.json"))
    manifest = Manifest(name: Self.id, title: "Browser Switcher", actions: actions,
      statusFallback: StatusLook(title: "Browser Switcher", symbol: "exclamationmark.triangle"))
  }

  // MARK: The last link

  private func remember(_ url: String) {
    try? FileManager.default.createDirectory(at: lastFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let data = try? JSONSerialization.data(withJSONObject: ["url": url]) { try? data.write(to: lastFile, options: .atomic) }
  }

  private func remembered() -> String? {
    guard let data = try? Data(contentsOf: lastFile),
      let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
    return o["url"] as? String
  }

  /// The link with its scheme and www left off, cut in the middle past 64 characters so its start
  /// and its end both show.
  static func placeholder(_ url: String?) -> String {
    guard let url else { return "Open link in" }
    var text = url
    for prefix in ["https://", "http://"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
    if text.hasPrefix("www.") { text.removeFirst(4) }
    let room = 64
    let chars = Array(text)
    guard chars.count > room else { return text }
    let head = Int(Double(room) * 0.6)
    let tail = room - head - 1
    return String(chars[0..<head]) + "…" + String(chars[(chars.count - tail)...])
  }

  /// The favourites shown, by Olm's id for each, or every browser and profile, in order.
  private func shown() -> [Target] {
    let list = showAll || favourites.isEmpty ? targets : targets.filter { favourites.contains($0.id) }
    guard let order else { return list }
    return usage.sorted(list, by: order) { $0.id }
  }

  // MARK: ListSource

  public func open(query: String) async -> Level {
    if let given {
      link = given
      remember(given)
    } else {
      link = remembered()
    }
    targets = await host.targets()
    favourites = host.favourites()
    order = ["most": .most, "last": .last][host.order() ?? ""]
    showAll = false
    return Level(placeholder: Self.placeholder(link))
  }

  public func rows(_ query: Query) async throws -> RowsAnswer {
    guard link != nil else {
      return RowsAnswer(rows: [Row(key: "none", title: "No link yet",
        subtitle: "Links you click while Olm is the default browser land here",
        icon: .symbol("exclamationmark.triangle"), pinned: true, inert: true)])
    }
    let rows = shown().map { t in
      Row(key: "t:" + t.id, title: t.title, icon: .app(t.bundle), keywords: t.browser == t.title ? [] : [t.browser])
    }
    if rows.isEmpty {
      // Not inert, so Copy Link and Show All still act on it, as they did while it ran as a process.
      return RowsAnswer(rows: [Row(key: "none", title: "No favourite is on this Mac",
        subtitle: "Show All in the actions pane lists every browser", icon: .symbol("exclamationmark.triangle"),
        pinned: true)])
    }
    return RowsAnswer(rows: rows)
  }

  public func choose(_ pick: Pick) async -> [Effect] {
    guard let link, pick.key.hasPrefix("t:"), let t = targets.first(where: { "t:" + $0.id == pick.key }) else { return [] }
    // Refused, its profile turned off since the list opened, the list stays so the link is not lost.
    guard await host.open(link, t.id) else {
      host.notify("Olm could not open the link in \(t.title)")
      return []
    }
    usage.note(t.id)
    return [.hide]
  }

  public func actions(on pick: Pick) async -> [String: String]? {
    var out = ["copyLink": "Copy Link"]
    if showAll { out["showFavourites"] = "Show Favourites" }
    else if !favourites.isEmpty { out["showAll"] = "Show All" }
    return out
  }

  public func run(_ action: String, on pick: Pick) async -> [Effect] {
    switch action {
    case "copyLink":
      guard let link else { return [] }
      await host.copy(link)
      host.notify("Link copied")
      return [.hide]
    case "showAll":
      showAll = true
      return [.rows(hold: true)]
    case "showFavourites":
      showAll = false
      return [.rows(hold: true)]
    default:
      return []
    }
  }

  public func close() async {}
}
