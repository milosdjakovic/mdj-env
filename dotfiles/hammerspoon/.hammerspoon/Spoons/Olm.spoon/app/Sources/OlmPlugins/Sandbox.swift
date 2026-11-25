// The rules an external plugin runs under, written from its manifest each time it starts,
// docs/DESIGN-APP-PLUGINS.md The sandbox. macOS's own sandbox engine enforces them, through
// sandbox-exec and its rule language, which are deprecated but were proved on macOS 27.0.1 on
// 2026-11-20 before anything leaned on them, decisions/olm-standalone.md. A program the plugin runs
// is inside the same rules, so what that program needs is declared too.

import Foundation

public struct Sandbox: Sendable {
  /// Where a bare program name is looked for, the system's folders and Homebrew's, never the
  /// person's PATH, so a plugin runs the same program on every machine that has it.
  public static let programPath = ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "/opt/homebrew/bin", "/usr/local/bin"]

  /// The folder the plugin lives in, read only to it.
  public var folder: URL
  /// Its data folder, written by it alone.
  public var data: URL
  /// Its temporary folder, TMPDIR for it.
  public var temp: URL
  /// The program it is, inside its folder.
  public var executable: URL
  public var permissions: PluginManifest.Permissions

  public init(folder: URL, data: URL, temp: URL, executable: URL, permissions: PluginManifest.Permissions) {
    self.folder = folder
    self.data = data
    self.temp = temp
    self.executable = executable
    self.permissions = permissions
  }

  /// A program the plugin declared, resolved to the file that really runs, nil when this machine has
  /// none. The name it was declared by is what the plugin is told it under.
  public static func resolve(_ program: String) -> (link: String, real: String)? {
    let candidates = program.hasPrefix("/") ? [program] : programPath.map { $0 + "/" + program }
    for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
      return (path, real(path))
    }
    return nil
  }

  /// The rules, and the programs resolved by the name each was declared under. A program this machine
  /// lacks is left out and named, so the plugin is told it is missing rather than refused at run.
  public func profile() -> (rules: String, programs: [String: String], missing: [String]) {
    var programs: [String: String] = [:]
    var missing: [String] = []
    var r = """
    (version 1)
    (deny default)
    (import "bsd.sb")
    (allow process-fork)
    (allow signal (target same-sandbox))
    (allow system-info)
    (allow user-preference-read (preference-domain "kCFPreferencesAnyApplication"))
    (deny mach-lookup (with no-log) (global-name "com.apple.lsd.modifydb") (global-name "com.apple.coreservices.quarantine-resolver"))

    """
    r += "(allow process-exec \(Self.literal(Self.real(executable.path))))\n"
    for program in permissions.programs {
      guard let found = Self.resolve(program) else {
        missing.append(program)
        continue
      }
      programs[program] = found.link
      r += "(allow process-exec \(Self.literal(found.real)))\n"
      r += "(allow file-read* \(Self.literal(found.link)) \(Self.literal(found.real)))\n"
      // A program inside an application bundle loads the bundle's own frameworks.
      if let range = found.real.range(of: ".app/") {
        r += "(allow file-read* (subpath \(Self.quote(String(found.real[..<range.lowerBound]) + ".app"))))\n"
      }
    }
    for grant in permissions.files {
      let place = Self.place(grant.path)
      r += grant.write ? "(allow file-read* file-write* \(Self.subpath(place)))\n" : "(allow file-read* \(Self.subpath(place)))\n"
    }
    // Olm's own folder is never part of a granted place, what the person allowed and the signing key
    // among it, and a plugin's own places are given back after, since the last rule that matches wins.
    r += "(deny file-read* file-write* \(Self.subpath(Self.place("~/.olm"))))\n"
    r += "(allow file-read* \(Self.subpath(folder)))\n"
    r += "(allow file-read* file-write* \(Self.subpath(data)) \(Self.subpath(temp)))\n"
    switch permissions.network {
    case .none:
      break
    case .local:
      r += "(allow network-outbound (remote ip \"localhost:*\"))\n"
    case .internet:
      r += "(allow network-outbound)\n(allow system-socket)\n"
      r += "(allow mach-lookup (global-name \"com.apple.dnssd.service\") (global-name \"com.apple.SystemConfiguration.configd\")"
      r += " (global-name \"com.apple.networkd\") (global-name \"com.apple.trustd.agent\") (global-name \"com.apple.nsurlsessiond\"))\n"
    }
    for service in permissions.services {
      switch service {
      case .mach(let name):
        r += "(allow mach-lookup (global-name \(Self.quote(name))))\n"
      case .socket(let path):
        r += "(allow network-outbound (remote unix-socket (path-literal \(Self.quote(Self.real(path))))))\n"
      case .iokit(let cls):
        r += "(allow iokit-open (iokit-user-client-class \(Self.quote(cls))))\n"
      }
    }
    return (r, programs, missing)
  }

  /// A declared place as the sandbox matches it, `~` expanded and symlinks resolved.
  static func place(_ path: String) -> URL {
    URL(fileURLWithPath: real((path as NSString).expandingTildeInPath))
  }

  /// The path the sandbox sees, every symlink resolved by realpath, /private/var/run for /var/run.
  /// Foundation's resolvingSymlinksInPath strips /private again, which the rules then never match,
  /// found on 2026-11-20 when mullvad was refused its daemon's socket. A path that does not exist yet
  /// is kept as written.
  static func real(_ path: String) -> String {
    guard let p = realpath(path, nil) else { return path }
    defer { free(p) }
    return String(cString: p)
  }

  static func subpath(_ url: URL) -> String {
    "(subpath \(quote(real(url.path))))"
  }

  static func literal(_ path: String) -> String {
    "(literal \(quote(path)))"
  }

  static func quote(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }
}
