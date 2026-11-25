// What the install page shows before a plugin may build or run, docs/DESIGN-APP-PLUGINS.md The install
// page: who it says it is and everything it asks for, each line made from the same reading of the
// manifest the sandbox's rules are made from. A plugin's own words are kept apart from Olm's.

import Foundation
import OlmPlugins

public struct PluginOffer: Equatable, Sendable, Identifiable {
  public enum State: Equatable, Sendable {
    /// Never allowed.
    case new
    /// Allowed before, and asks for more now.
    case more
    /// Asks for nothing it was not allowed.
    case same
    /// Allowed, and it did not build.
    case failed(String)
  }

  public struct Line: Equatable, Sendable, Identifiable {
    /// The word it is recorded by once allowed, PluginGate.asks.
    public let id: String
    public let text: String
    public let detail: String?
  }

  public struct Group: Equatable, Sendable, Identifiable {
    public let title: String
    public let lines: [Line]
    public var id: String { title }
  }

  /// Which reading of which files this is, the host's.
  public let id: String
  public let plugin: String
  public let title: String
  public let version: String
  public let about: String
  /// The file or folder dropped, nil for a folder already in ~/.olm/plugins.
  public let from: String?
  /// The version of the one it takes the place of.
  public let replaces: String?
  public let state: State
  /// Whether data an earlier plugin by its id left is there for it.
  public let data: Bool
  public let groups: [Group]

  /// given, what was allowed before, nil for a plugin never allowed.
  public init(id: String, manifest: PluginManifest, declared: PluginDeclarations?, from: String?, replaces: String?,
    given: Set<String>?, failed: String? = nil, data: Bool = false) {
    self.data = data && given == nil
    self.id = id
    plugin = manifest.id
    title = manifest.title
    version = manifest.version
    about = Self.clean(declared?.description ?? "", 300)
    self.from = from.map { Self.clean($0, 100) }
    self.replaces = replaces
    let new = PluginGate.asks(manifest).subtracting(given ?? [])
    if let failed, new.isEmpty { state = .failed(failed) } else {
      state = given == nil ? .new : new.isEmpty ? .same : .more
    }
    groups = Self.groups(manifest, declared).compactMap { g in
      let lines = g.lines.filter { new.contains($0.id) }
      return lines.isEmpty ? nil : Group(title: g.title, lines: lines)
    }
  }

  /// The button that lets it through.
  public var button: String {
    switch state {
    case .new, .more: return "Allow"
    case .same: return from == nil ? "Allow" : "Update"
    case .failed: return "Build Again"
    }
  }

  /// Every line a manifest makes, one for each thing PluginGate asks, which the check holds it to.
  static func groups(_ m: PluginManifest, _ declared: PluginDeclarations?) -> [Group] {
    let home = NSHomeDirectory()
    var out: [Group] = []
    out.append(Group(title: "Programs it runs", lines: m.permissions.programs.map { name in
      Line(id: "program:\(name)", text: name,
        detail: Sandbox.resolve(name).map { "\($0.link), inside the same sandbox" } ?? "Not on this Mac")
    }))
    out.append(Group(title: "Files", lines: m.permissions.files.map { f in
      let path = (f.path as NSString).expandingTildeInPath
      let real = Sandbox.resolved(f.path)
      var notes: [String] = []
      if real != path, !f.path.hasSuffix("/") { notes.append("It is at \(real)") }
      let whole = real == "/" || home == real || home.hasPrefix(real + "/")
      if whole { notes.append(real == "/" ? "That is every file on this Mac you can reach, Olm's own folder left out" : "That is your whole home folder, Olm's own folder left out") }
      if f.write, whole || real == home + "/Library" || real.hasPrefix(home + "/Library/LaunchAgents") {
        notes.append("What it changes there can run outside its sandbox")
      }
      return Line(id: "\(f.write ? "write" : "read"):\(f.path)", text: "\(f.write ? "Reads and changes" : "Reads") \(f.path)",
        detail: notes.isEmpty ? nil : notes.joined(separator: ". "))
    }))
    switch m.permissions.network {
    case .none: break
    case .local:
      out.append(Group(title: "Network", lines: [Line(id: "network:local", text: "Talks to programs on this Mac over the network", detail: nil)]))
    case .internet:
      out.append(Group(title: "Network", lines: [Line(id: "network:internet", text: "Uses the internet",
        detail: "It can send out anything it reads")]))
    }
    out.append(Group(title: "System services", lines: m.permissions.services.map { s in
      let outside = "What the service does for it is outside its sandbox"
      switch s {
      case .mach(let n): return Line(id: "mach:\(n)", text: n, detail: outside)
      case .socket(let p): return Line(id: "socket:\(p)", text: "The socket \(p)", detail: outside)
      case .iokit(let c): return Line(id: "iokit:\(c)", text: "The device driver \(c)", detail: outside)
      }
    }))
    if m.background {
      out.append(Group(title: "When it runs", lines: [Line(id: "background", text: "Runs while you are not using it", detail: nil)]))
    }
    let needs = ["copy": "Puts text on your clipboard", "notify": "Shows you a line of text",
      "open": "Opens a web link after you choose something in its list"]
    out.append(Group(title: "What it asks of Olm", lines: m.needs.sorted().map { Line(id: "need:\($0)", text: needs[$0] ?? $0, detail: nil) }))
    out.append(Group(title: "What Olm does for it with Olm's permissions", lines: m.abilities.sorted().map { use in
      guard let about = Abilities.describe(use) else {
        return Line(id: "ability:\(use)", text: use, detail: "Not one of Olm's abilities, so it is refused")
      }
      let permission = Abilities.permissions[about.entry.permission]
      let why = declared?.abilities.first { $0.use == use }.map { clean($0.why, 200) }
      let gate = permission.map { $0.olm ? "Olm's own gate" : $0.title } ?? ""
      return Line(id: "ability:\(use)", text: about.entry.title + (about.subject.map { " " + $0 } ?? ""),
        detail: "Olm \(about.entry.does), \(gate)" + (why.map { ". It says, \u{201C}\($0)\u{201D}" } ?? ""))
    }))
    return out.filter { !$0.lines.isEmpty }
  }

  /// A plugin's own words on one line, nothing in them that does not show, cut at most.
  static func clean(_ s: String, _ most: Int) -> String {
    let kept = s.unicodeScalars.map { u -> Character in
      switch u.properties.generalCategory {
      case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .unassigned: return " "
      default: return Character(u)
      }
    }
    return String(String(kept).prefix(most))
  }
}

/// What the window asks the host of plugins, each answer an offer to show or why there is none.
public struct PluginInstaller: Sendable {
  public struct Answer: Sendable {
    public var offer: PluginOffer?
    public var why: String?
    public init(offer: PluginOffer? = nil, why: String? = nil) {
      self.offer = offer
      self.why = why
    }
  }

  /// A folder in ~/.olm/plugins waiting to be allowed, by its name.
  public let review: @MainActor @Sendable (String) async -> Answer
  /// A folder or a .olmplugin dropped on Plugins.
  public let take: @MainActor @Sendable (URL) async -> Answer
  /// Puts it in place, records it and builds it. No offer and no why once it runs.
  public let allow: @MainActor @Sendable (PluginOffer) async -> Answer
  /// The page was left, what was copied aside is thrown away.
  public let leave: @MainActor @Sendable (PluginOffer) -> Void
  /// Uninstalls a plugin by its folder's name, its data too when told, why not when it was not.
  public let remove: @MainActor @Sendable (String, Bool) async -> String?

  public init(review: @escaping @MainActor @Sendable (String) async -> Answer,
    take: @escaping @MainActor @Sendable (URL) async -> Answer,
    allow: @escaping @MainActor @Sendable (PluginOffer) async -> Answer,
    leave: @escaping @MainActor @Sendable (PluginOffer) -> Void,
    remove: @escaping @MainActor @Sendable (String, Bool) async -> String?) {
    self.review = review
    self.take = take
    self.allow = allow
    self.leave = leave
    self.remove = remove
  }
}
