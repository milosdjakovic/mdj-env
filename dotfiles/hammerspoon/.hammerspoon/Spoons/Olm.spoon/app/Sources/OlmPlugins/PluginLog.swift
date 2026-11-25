// What each plugin did, docs/DESIGN-APP-PLUGINS.md The log: Olm's own lines and what the plugin wrote,
// told apart so a plugin cannot write a line as Olm. Kept in ~/.olm/log/plugins, which every plugin is
// kept out of, rather than in its folder, where a link would have Olm write wherever it leads. Bounded,
// and written off the main thread.

import Darwin
import Foundation

public final class PluginLog: @unchecked Sendable {
  public enum From: String, Sendable { case olm, plugin }

  public struct Entry: Sendable, Equatable, Identifiable {
    /// Its place in the file, the oldest 0.
    public let id: Int
    public let at: String
    public let from: From
    public let text: String
  }

  public static let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".olm/log/plugins")
  /// Bytes past which the older half goes.
  static let most = 256 * 1024
  /// Lines from one side in one window, the rest left out.
  public static let burst = 200
  public static let window: TimeInterval = 10

  private let dir: URL
  private let queue = DispatchQueue(label: "olm.plugins.log", qos: .utility)
  private let lock = NSLock()
  private var rates: [String: (since: Date, lines: Int)] = [:]
  private let stamp: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
  }()

  public init(dir: URL = PluginLog.path) { self.dir = dir }

  public func file(_ id: String) -> URL { dir.appendingPathComponent(id + ".log") }

  public func add(_ id: String, _ text: String, from: From = .olm) {
    let now = Date(), key = id + "/" + from.rawValue
    lock.lock()
    var rate = rates[key] ?? (now, 0)
    if now.timeIntervalSince(rate.since) > Self.window { rate = (now, 0) }
    rate.lines += 1
    rates[key] = rate
    lock.unlock()
    guard rate.lines <= Self.burst + 1 else { return }
    let over = rate.lines > Self.burst
    queue.async { [self] in
      if over { write(id, "too many lines at once, the rest of these seconds are left out", .olm, now) }
      else { write(id, text, from, now) }
    }
  }

  /// Every line held, the oldest first.
  public func entries(_ id: String) -> [Entry] {
    queue.sync {
      guard let data = try? Data(contentsOf: file(id)) else { return [] }
      var out: [Entry] = []
      for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        if parts.count == 3, !parts[0].isEmpty, let from = From(rawValue: String(parts[1])) {
          out.append(Entry(id: out.count, at: String(parts[0]), from: from, text: String(parts[2])))
        } else if line.hasPrefix("\t"), let last = out.popLast() {
          out.append(Entry(id: last.id, at: last.at, from: last.from, text: last.text + "\n" + line.dropFirst()))
        }
      }
      return out
    }
  }

  /// When it was last written, what a page showing it asks before reading it again.
  public func moved(_ id: String) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: file(id).path))?[.modificationDate] as? Date
  }

  public func remove(_ id: String) {
    queue.async { [self] in try? FileManager.default.removeItem(at: file(id)) }
  }

  // A line of a longer text starts with a tab, and nothing written can start a line as anything else.
  private func write(_ id: String, _ text: String, _ from: From, _ now: Date) {
    let lines = text.split(whereSeparator: \.isNewline).map { Self.plain(String($0)) }.filter { !$0.isEmpty }
    guard !lines.isEmpty else { return }
    let whole = "\(stamp.string(from: now))\t\(from.rawValue)\t" + lines.joined(separator: "\n\t") + "\n"
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = file(id).path
    let fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { return }
    Data(whole.utf8).withUnsafeBytes { raw in _ = Darwin.write(fd, raw.baseAddress, raw.count) }
    var info = stat()
    let size = fstat(fd, &info) == 0 ? Int(info.st_size) : 0
    close(fd)
    if size > Self.most { halve(file(id)) }
  }

  // The newer half, from the first whole entry in it.
  private func halve(_ url: URL) {
    guard let data = try? Data(contentsOf: url) else { return }
    let kept = String(decoding: data.suffix(Self.most / 2), as: UTF8.self).split(separator: "\n").dropFirst()
      .drop { $0.hasPrefix("\t") }
    try? Data((kept.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
  }

  // No control or direction characters, a tab as a space, and at most 2000 characters.
  static func plain(_ text: String) -> String {
    let ok = text.unicodeScalars.prefix(2000).compactMap { c -> Unicode.Scalar? in
      if c == "\t" { return " " }
      switch c.properties.generalCategory {
      case .control, .lineSeparator, .paragraphSeparator: return nil
      case .format: return c.value == 0x200D ? c : nil
      default: return c
      }
    }
    return String(String.UnicodeScalarView(ok))
  }
}

/// What Olm remembers of each plugin, ~/.olm/state/plugin-history.json: why it switched one off itself,
/// kept until the person turns it on or its files move, and when each ability was last used.
public final class PluginHistory: @unchecked Sendable {
  private struct Stop: Codable { var why: String; var print: String? }
  private struct Doc: Codable {
    var version = 1
    var stopped: [String: Stop] = [:]
    var used: [String: [String: Date]] = [:]
  }

  public static let path = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".olm/state/plugin-history.json")
  private let url: URL
  private let lock = NSLock()
  private var doc: Doc
  private var prints: [String: String] = [:]

  public init(url: URL = PluginHistory.path) {
    self.url = url
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    doc = (try? Data(contentsOf: url)).flatMap { try? d.decode(Doc.self, from: $0) } ?? Doc()
  }

  /// Why Olm switched it off, nil while it may run.
  public func stopped(_ id: String) -> String? { locked { doc.stopped[id]?.why } }

  public func stop(_ id: String, _ why: String) {
    locked { doc.stopped[id] = Stop(why: why, print: prints[id]); save() }
  }

  /// The person turned it on, allowed it or took it away.
  public func start(_ id: String) {
    locked { if doc.stopped.removeValue(forKey: id) != nil { save() } }
  }

  /// The files it runs from now. Ones that moved since it was switched off are given a new chance.
  public func runs(_ id: String, _ print: String) {
    locked {
      prints[id] = print
      if let stop = doc.stopped[id], stop.print != print {
        doc.stopped[id] = nil
        save()
      }
    }
  }

  public func used(_ id: String, _ ability: String) -> Date? { locked { doc.used[id]?[ability] } }

  public func use(_ id: String, _ ability: String, at: Date = Date()) {
    locked { doc.used[id, default: [:]][ability] = at; save() }
  }

  /// Uninstalled with its data.
  public func forget(_ id: String) {
    locked { doc.stopped[id] = nil; doc.used[id] = nil; save() }
  }

  private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

  private func save() {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    e.dateEncodingStrategy = .iso8601
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let data = try? e.encode(doc) { try? data.write(to: url, options: .atomic) }
  }
}
