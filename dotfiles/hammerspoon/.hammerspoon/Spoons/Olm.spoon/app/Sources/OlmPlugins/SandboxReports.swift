// What the sandbox refused a plugin, read from macOS's own log, docs/DESIGN-APP-PLUGINS.md A block is
// offered, not hidden. Every rule that refuses ends its report with a line `olm-plugin:<id>`, written
// by the profile Olm makes, so a program the plugin runs is told apart from every other process on the
// Mac without knowing its pid. The kernel writes the report, so a plugin cannot write one, and the tag
// is the report's last line, so a path it tried holding a line of its own cannot pass for another's.
//
// What Olm may offer for a refusal is decided here, one door at a time, in the words of the install
// page. Passwords and keys are never offered, nor a place that would let a plugin act outside its
// sandbox, nor anything as wide as the home folder, which only a manifest may ask for.

import Foundation

/// One refusal, as the sandbox reported it.
public struct SandboxBlock: Sendable, Equatable {
  /// The plugin the refusing rule belongs to.
  public let plugin: String
  /// The process refused, the plugin or a program it ran.
  public let process: String
  /// The sandbox's word for what was refused, file-read-data, mach-lookup.
  public let operation: String
  /// What it was refused, a path, a service's name or an address.
  public let target: String

  public init(plugin: String, process: String, operation: String, target: String) {
    self.plugin = plugin
    self.process = process
    self.operation = operation
    self.target = target
  }

  /// The tag every refusing rule of a plugin's profile carries.
  public static func tag(_ id: String) -> String { "olm-plugin:" + id }

  /// A report's text read, nil for one that is not a plugin's or cannot be read.
  public static func parse(_ message: String) -> SandboxBlock? {
    let lines = message.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard lines.count >= 2, let last = lines.last, last.hasPrefix("olm-plugin:") else { return nil }
    let id = String(last.dropFirst("olm-plugin:".count))
    guard id.range(of: "^[a-z][a-z0-9]{0,31}$", options: .regularExpression) != nil else { return nil }
    // A report the kernel folded together starts with how many it stands for.
    var head = lines[0]
    if let r = head.range(of: #"^\d+ duplicate reports? for "#, options: .regularExpression) { head.removeSubrange(r) }
    guard head.hasPrefix("Sandbox: ") else { return nil }
    head.removeFirst("Sandbox: ".count)
    guard let r = head.range(of: #"^(.+?)\(\d+\) deny\(\d+\) (\S+)(?: (.*))?$"#, options: .regularExpression),
      r.lowerBound == head.startIndex else { return nil }
    let words = head[r]
    guard let open = words.range(of: #"\(\d+\) deny\(\d+\) "#, options: .regularExpression) else { return nil }
    let process = String(words[..<open.lowerBound])
    let rest = words[open.upperBound...]
    let op = rest.split(separator: " ", maxSplits: 1).map(String.init)
    // A path it tried with a line break in it continues on the next lines, all of it what it tried.
    let target = ([op.count > 1 ? op[1] : ""] + lines.dropFirst().dropLast()).joined(separator: "\n")
    return SandboxBlock(plugin: id, process: process, operation: op[0], target: target)
  }
}

/// What Olm offers for one refusal, a grant in the gate's words to Allow, or why it never is.
public struct BlockOffer: Sendable, Equatable {
  /// The gate's line, read:~/Notes, program:/usr/bin/sqlite3, nil when nothing is offered.
  public let grant: String?
  /// What it tried, in the install page's words.
  public let text: String
  /// Why it is never offered, nil when it is.
  public let never: String?

  public static let secret = "Olm never offers passwords or keys"
  public static let escape = "it would let the plugin act outside its sandbox, so Olm never offers it"
  public static let wide = "too wide to offer from one block, the plugin's manifest may ask for it"

  /// Places that hold passwords, keys or what a browser or a mail app keeps signed in, from the home
  /// folder unless they start at the root.
  static let secretPlaces = [
    "~/.ssh", "~/.gnupg", "~/.olm", "~/.aws", "~/.azure", "~/.netrc", "~/.git-credentials", "~/.password-store",
    "~/.docker", "~/.kube", "~/.config/gh", "~/.config/op", "~/.config/gcloud", "~/Library/Keychains",
    "/Library/Keychains", "/private/var/db", "~/Library/Cookies", "~/Library/Safari", "~/Library/Mail",
    "~/Library/Messages", "~/Library/Application Support/com.apple.TCC", "~/Library/Application Support/Google",
    "~/Library/Application Support/BraveSoftware", "~/Library/Application Support/Firefox",
    "~/Library/Application Support/Microsoft Edge", "~/Library/Application Support/Arc",
    "~/Library/Application Support/Vivaldi", "~/Library/Containers/com.apple.Safari",
  ]
  /// Words in a path that mean a key or a store of passwords wherever it is.
  static let secretWords = ["keychain", "1password", "bitwarden", "lastpass", "keepass", "id_rsa", "id_ecdsa", "id_ed25519", "id_dsa"]
  static let secretExtensions = ["pem", "key", "p12", "pfx", "kdbx", "keychain-db", "gpg", "asc"]
  /// Places a write to would start a program outside the sandbox, at login or in the next shell.
  static let escapes = ["~/Library/LaunchAgents", "~/Library/Preferences", "~/Library/Application Scripts",
    "~/Library/Services", "~/Library/Workflows", "~/Library/Scripts", "~/.config"]
  /// System services that hold passwords and keys, or that do for a process what its sandbox keeps
  /// from it, opening apps, the clipboard and the permissions macOS asks about.
  static let secretServices = ["com.apple.security", "com.apple.SecurityServer", "com.apple.securityd",
    "com.apple.tccd", "com.apple.authd", "com.apple.CoreAuthentication", "com.apple.ctkd", "com.apple.pasteboard",
    "com.apple.lsd", "com.apple.coreservices.launchservicesd", "com.apple.coreservices.quarantine-resolver",
    "com.apple.xpc.smd", "com.apple.backgroundtaskmanagement", "com.apple.FileProvider", "com.apple.accountsd",
    "com.apple.cloudd", "com.apple.windowserver", "com.apple.coreservices.appleevents", "com.apple.dock"]

  /// What Olm offers for a block, home the home folder.
  public static func offer(_ b: SandboxBlock, home: String = NSHomeDirectory()) -> BlockOffer {
    let target = b.target
    if target.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || $0.properties.generalCategory == .format }) {
      return BlockOffer(grant: nil, text: "\(verb(b.operation)) a name holding characters that do not show",
        never: "a name that does not show cannot be read before it is allowed, so Olm never offers it")
    }
    let op = b.operation
    if op.hasPrefix("file-read") || op.hasPrefix("file-write") || op.hasPrefix("process-exec") {
      let path = (target as NSString).standardizingPath
      guard path.hasPrefix("/") else { return nothing(b) }
      let shown = tilde(path, home)
      if isSecret(path, home) {
        return BlockOffer(grant: nil, text: "\(verb(op)) \(shown)", never: secret)
      }
      if op.hasPrefix("process-exec") {
        return BlockOffer(grant: "program:\(path)", text: "Run \(shown)", never: nil)
      }
      let fm = FileManager.default
      var dir: ObjCBool = false
      let exists = fm.fileExists(atPath: path, isDirectory: &dir)
      if op.hasPrefix("file-write") {
        guard path.hasPrefix(home + "/") else {
          return BlockOffer(grant: nil, text: "Change \(shown)", never: "it is outside your home folder, so Olm never offers it")
        }
        if under(path, escapes, home) || (shown.hasPrefix("~/.") && !shown.dropFirst(2).contains("/")) {
          return BlockOffer(grant: nil, text: "Change \(shown)", never: escape)
        }
        // A file not there yet is made in its folder, so the folder is what is offered.
        let place = exists ? path : (path as NSString).deletingLastPathComponent
        if place == home || place == "/" { return BlockOffer(grant: nil, text: "Change \(tilde(place, home))", never: wide) }
        let isDir = exists ? dir.boolValue : true
        let words = exists ? (isDir ? "Changes \(tilde(place, home)) and everything in it" : "Changes \(tilde(place, home))")
          : "Makes files in \(tilde(place, home))"
        return BlockOffer(grant: "write:\(tilde(place, home))", text: words, never: nil)
      }
      if path == home || path == "/" || path == "/Users" || path == "/Volumes" {
        return BlockOffer(grant: nil, text: "Read \(shown)", never: wide)
      }
      let words = exists && dir.boolValue ? "Reads \(shown) and everything in it" : "Reads \(shown)"
      return BlockOffer(grant: "read:\(shown)", text: words, never: nil)
    }
    if op == "mach-lookup" {
      let name = target.trimmingCharacters(in: .whitespaces)
      guard !name.isEmpty, !name.contains(" ") else { return nothing(b) }
      if secretServices.contains(where: { name == $0 || name.hasPrefix($0 + ".") || name.hasPrefix($0 + "-") }) {
        return BlockOffer(grant: nil, text: "Talk to the system service \(name)", never: name.contains("security") || name.contains("Security") || name.contains("Auth") ? secret : escape)
      }
      return BlockOffer(grant: "mach:\(name)", text: "Talk to the system service \(name)", never: nil)
    }
    if op.hasPrefix("network-outbound") {
      if target.hasPrefix("/") {
        let path = (target as NSString).standardizingPath
        if isSecret(path, home) { return BlockOffer(grant: nil, text: "Talk to the socket \(tilde(path, home))", never: secret) }
        return BlockOffer(grant: "socket:\(tilde(path, home))", text: "Talks to the socket \(tilde(path, home))", never: nil)
      }
      let host = target.hasPrefix("[") ? String(target.dropFirst().prefix { $0 != "]" })
        : String(target.split(separator: ":").first ?? "")
      if ["localhost", "127.0.0.1", "::1"].contains(host) || host.hasPrefix("127.") {
        return BlockOffer(grant: "network:local", text: "Talks to programs on this Mac over the network", never: nil)
      }
      return BlockOffer(grant: "network:internet", text: "Uses the internet, it tried \(target)", never: nil)
    }
    if op == "iokit-open" {
      let cls = target.split(separator: " ").last.map(String.init) ?? ""
      guard !cls.isEmpty else { return nothing(b) }
      return BlockOffer(grant: "iokit:\(cls)", text: "Opens the device driver \(cls)", never: nil)
    }
    return nothing(b)
  }

  private static func nothing(_ b: SandboxBlock) -> BlockOffer {
    BlockOffer(grant: nil, text: "\(b.operation) \(b.target)".trimmingCharacters(in: .whitespaces),
      never: "Olm has no door to offer for it")
  }

  static func verb(_ op: String) -> String {
    op.hasPrefix("file-write") ? "Change" : op.hasPrefix("process-exec") ? "Run" : op == "mach-lookup" ? "Talk to" : "Read"
  }

  static func tilde(_ path: String, _ home: String) -> String {
    path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
  }

  static func expand(_ place: String, _ home: String) -> String {
    place == "~" ? home : place.hasPrefix("~/") ? home + place.dropFirst(1) : place
  }

  static func under(_ path: String, _ places: [String], _ home: String) -> Bool {
    let low = path.lowercased()
    return places.contains { p in
      let e = expand(p, home).lowercased()
      return low == e || low.hasPrefix(e + "/")
    }
  }

  /// Whether a path is a password, a key or a place keeping them, matched without case, since the file
  /// system ignores it.
  static func isSecret(_ path: String, _ home: String) -> Bool {
    if under(path, secretPlaces, home) { return true }
    let low = path.lowercased()
    if secretWords.contains(where: { low.contains($0) }) { return true }
    let name = (low as NSString).lastPathComponent
    return secretExtensions.contains { name.hasSuffix("." + $0) }
  }
}

/// Follows macOS's log for the refusals of plugins' rules, while Olm runs a plugin. The log program
/// runs as Olm and asks for the kernel's sandbox reports carrying a plugin's tag alone, so the reports
/// of every other sandboxed program on the Mac are filtered out before they reach Olm.
public final class SandboxReports: @unchecked Sendable {
  public static let program = "/usr/bin/log"
  public static let predicate = #"sender == "Sandbox" AND eventMessage CONTAINS "olm-plugin:""#

  private let lock = NSLock()
  private var process: Process?
  private var wanted = false
  private var launching = false
  private var buffer = Data()
  private let heard: @Sendable (SandboxBlock) -> Void

  public init(heard: @escaping @Sendable (SandboxBlock) -> Void) { self.heard = heard }

  /// Starts following, started again a few seconds after the log program ends while it is wanted.
  public func start() {
    lock.lock()
    wanted = true
    lock.unlock()
    // Starting a program can hold its caller a few milliseconds, never Olm's main thread.
    DispatchQueue.global(qos: .utility).async { [weak self] in self?.launch() }
  }

  public func stop() {
    lock.lock(); defer { lock.unlock() }
    wanted = false
    process?.terminate()
    process = nil
  }

  /// Whether the log program is running, for the check.
  public var running: Bool {
    lock.lock(); defer { lock.unlock() }
    return process?.isRunning == true
  }

  /// Starts the log program, the lock held only around what it guards, since starting a program can
  /// take tens of milliseconds and the lock is asked from Olm's main thread.
  private func launch() {
    lock.lock()
    guard wanted, process == nil, !launching else { lock.unlock(); return }
    launching = true
    lock.unlock()
    let p = Process()
    p.executableURL = URL(fileURLWithPath: Self.program)
    // The kernel alone, which writes every report, a third of the cost of asking every process.
    p.arguments = ["stream", "--style", "ndjson", "--process", "0", "--predicate", Self.predicate]
    p.environment = ["PATH": "/usr/bin:/bin"]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    p.standardInput = FileHandle.nullDevice
    out.fileHandleForReading.readabilityHandler = { [weak self] h in
      let data = h.availableData
      if data.isEmpty { h.readabilityHandler = nil; return }
      self?.take(data)
    }
    p.terminationHandler = { [weak self] ended in
      guard let self else { return }
      self.lock.lock()
      if self.process === ended { self.process = nil }
      let again = self.wanted
      self.lock.unlock()
      guard again else { return }
      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) { [weak self] in self?.launch() }
    }
    do {
      try p.run()
      lock.lock()
      launching = false
      if wanted { process = p } else { p.terminate() }
      lock.unlock()
    } catch {
      lock.lock(); launching = false; lock.unlock()
      NSLog("Olm plugins: the sandbox's reports cannot be read, %@", "\(error)")
    }
  }

  private func take(_ data: Data) {
    lock.lock()
    buffer.append(data)
    var lines: [Data] = []
    while let nl = buffer.firstIndex(of: 0x0A) {
      lines.append(buffer[buffer.startIndex..<nl])
      buffer.removeSubrange(buffer.startIndex...nl)
    }
    // A line past what any report holds is the log program misbehaving, never kept.
    if buffer.count > 1 << 20 { buffer.removeAll() }
    lock.unlock()
    for line in lines {
      guard let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
        o["processImagePath"] as? String == "/kernel",
        let text = o["eventMessage"] as? String, let block = SandboxBlock.parse(text) else { continue }
      heard(block)
    }
  }
}

extension BlockOffer {
  /// A door allowed after a block, in the install page's words.
  public static func words(_ grant: String) -> String {
    let parts = grant.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return grant }
    let v = parts[1]
    switch parts[0] {
    case "read": return "Reads \(v)"
    case "write": return "Changes what is in \(v)"
    case "program": return "Runs \(v)"
    case "mach": return "Talks to the system service \(v)"
    case "socket": return "Talks to the socket \(v)"
    case "iokit": return "Opens the device driver \(v)"
    case "network": return v == "internet" ? "Uses the internet" : "Talks to programs on this Mac over the network"
    default: return grant
    }
  }
}
