// The browsers this Mac has and their profiles, found by Olm.app for the Browser Switcher's
// favourites and its list, docs/DESIGN-BROWSER-SWITCHER.md. A browser is an app that opens https.
// A Chromium browser keeps its profiles in `Local State` and Firefox in `profiles.ini`, each under
// Application Support, which macOS keeps from any program without Full Disk Access. A browser whose
// list is there and refused is named in `hidden`, so the page can say so. Safari's profiles cannot
// be opened into from outside, so Safari is one browser.
//
// What is found is written to ~/.olm/run/browsers.json, which the plugin reads to open a profile.
//
// The profiles are read only while a plugin has the browserProfiles ability on, the one ability Olm
// performs itself, docs/DESIGN-APP-PLUGINS.md. Turned off, each browser is listed once, with none.

import AppKit
import Foundation

public struct BrowserTarget: Equatable, Sendable, Codable {
  /// What a row says, the profile's name, or the browser's where it has none, the icon saying which
  /// browser, asked by Milos on 2026-11-25.
  public let title: String
  /// The browser's name, a word its profile's row is found by.
  public let browser: String
  /// The profile's name, nil for the browser itself.
  public let profile: String?
  public let bundle: String
  public let path: String
  /// What the browser's own program is started with to open a link in the profile, none for the
  /// browser itself.
  public let args: [String]

  /// What a plugin names it by, looked up in a scan of Olm's own and never read as a path.
  /// Favourites are saved by it too.
  public var id: String { ([bundle] + args).joined(separator: "|") }

  /// What it was titled until 2026-11-25, which favourites were saved by.
  public var oldTitle: String { profile.map { "\(browser) (\($0))" } ?? browser }
}

/// A profile a browser keeps, owned when signed in to or named by the person.
public struct BrowserProfile: Equatable, Sendable {
  public let name: String
  public let args: [String]
  public let owned: Bool
  public init(name: String, args: [String], owned: Bool) {
    self.name = name
    self.args = args
    self.owned = owned
  }
}

public struct BrowserScan: Equatable, Sendable, Codable {
  public var targets: [BrowserTarget] = []
  /// The browsers whose profiles macOS would not let Olm read.
  public var hidden: [String] = []
}

public enum Browsers {
  static let chromium: [String: String] = [
    "com.google.Chrome": "Google/Chrome",
    "com.google.Chrome.beta": "Google/Chrome Beta",
    "com.brave.Browser": "BraveSoftware/Brave-Browser",
    "com.microsoft.edgemac": "Microsoft Edge",
    "org.chromium.Chromium": "Chromium",
    "com.vivaldi.Vivaldi": "Vivaldi",
  ]
  static let firefox: [String: String] = ["org.mozilla.firefox": "Firefox"]
  static let skipped: Set<String> = ["local.olm.Olm", "org.hammerspoon.Hammerspoon"]

  public static let path = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".olm/run/browsers.json")

  static var support: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
  }

  /// Every browser, as its profiles where it has any and profiles is true.
  public static func scan(profiles readProfiles: Bool = true) -> BrowserScan {
    var out = BrowserScan()
    guard let probe = URL(string: "https://example.com") else { return out }
    var seen = Set<String>()
    let apps = NSWorkspace.shared.urlsForApplications(toOpen: probe).compactMap { url -> (String, String, URL)? in
      guard let bundle = Bundle(url: url)?.bundleIdentifier, !skipped.contains(bundle),
        seen.insert(bundle).inserted else { return nil }
      return (FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""), bundle, url)
    }.sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    for (name, bundle, url) in apps {
      var profiles: [BrowserProfile]? = []
      if readProfiles {
        if let folder = chromium[bundle] { profiles = chromiumProfiles(folder) }
        if let folder = firefox[bundle] { profiles = firefoxProfiles(folder) }
      }
      if profiles == nil { out.hidden.append(name) }
      out.targets += targets(browser: name, bundle: bundle, path: url.path, profiles: profiles ?? [])
    }
    return out
  }

  /// A browser's rows. With no profile, or one nobody signed in to or named, it is the browser by its
  /// name. With any other, each profile by its name and no row for the browser itself, the one profile
  /// nobody signed in to or named reading Chrome (No profile).
  public static func targets(browser: String, bundle: String, path: String, profiles: [BrowserProfile]) -> [BrowserTarget] {
    let bare = profiles.filter { !$0.owned }
    if profiles.isEmpty || (profiles.count == 1 && bare.count == 1) {
      return [BrowserTarget(title: browser, browser: browser, profile: nil, bundle: bundle, path: path, args: [])]
    }
    return profiles.map { p in
      BrowserTarget(title: !p.owned && bare.count == 1 ? "\(browser) (No profile)" : p.name, browser: browser,
        profile: p.name, bundle: bundle, path: path, args: p.args)
    }
  }

  /// Scans and writes what it found for the plugin, answering it. The profiles are read when share,
  /// the settings share, read from its file when not handed, has a plugin with browserProfiles on.
  @discardableResult public static func refresh(share: SettingsShare? = nil) -> BrowserScan {
    let found = scan(profiles: (share ?? ExternalPlugins.merged(SettingsShare.read()))?.allows("browserProfiles") ?? false)
    if let data = try? JSONEncoder().encode(found) {
      try? FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: path, options: .atomic)
    }
    return found
  }

  /// nil when the file is there and refused, empty when there is none.
  private static func read(_ url: URL) -> Data? {
    guard FileManager.default.fileExists(atPath: url.path) else { return Data() }
    return try? Data(contentsOf: url)
  }

  private static func chromiumProfiles(_ folder: String) -> [BrowserProfile]? {
    guard let data = read(support.appendingPathComponent(folder).appendingPathComponent("Local State")) else { return nil }
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let profile = root["profile"] as? [String: Any],
      let cache = profile["info_cache"] as? [String: Any] else { return [] }
    let order = (profile["profiles_order"] as? [String]) ?? cache.keys.sorted()
    return order.compactMap { dir in
      guard let info = cache[dir] as? [String: Any], let name = info["name"] as? String else { return nil }
      let signedIn = ["user_name", "gaia_id"].contains { !(info[$0] as? String ?? "").isEmpty }
      let named = !(info["is_using_default_name"] as? Bool ?? false)
      return BrowserProfile(name: name, args: ["--profile-directory=\(dir)"], owned: signedIn || named)
    }
  }

  private static func firefoxProfiles(_ folder: String) -> [BrowserProfile]? {
    guard let data = read(support.appendingPathComponent(folder).appendingPathComponent("profiles.ini")) else { return nil }
    let text = String(decoding: data, as: UTF8.self)
    return text.split(whereSeparator: \.isNewline).compactMap { line in
      guard line.hasPrefix("Name=") else { return nil }
      let name = String(line.dropFirst(5))
      // Firefox makes default and default-release itself.
      return BrowserProfile(name: name, args: ["-P", name], owned: !name.hasPrefix("default"))
    }
  }
}
