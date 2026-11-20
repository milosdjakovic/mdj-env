// The keys in shadow, step 5.1 of docs/PLAN-STANDALONE.md, docs/DESIGN-APP-KEYS.md. Hammerspoon
// binds every key. The app hears each press, resolves it against the keymap Hammerspoon compiled,
// and pairs what it would run with what Hammerspoon says it ran, the bridge's keyFired. A press
// the app resolved that Hammerspoon did not run, and a run the app did not resolve, are each one
// line in ~/.olm/log/shadow-keys.jsonl, and the gate is that log empty through ordinary use.
// ~/.olm/log/shadow-keys-count.json says how many were paired, so an empty log is read beside the
// presses it covered.
//
// Everything runs on one serial queue of its own. A press is handed over by the tap's thread, a
// run by the bridge, and the list going up or down by the main thread, and none of them waits.

import CoreGraphics
import Foundation

public final class KeyShadow: @unchecked Sendable {
  /// Seconds within which a press and a run are one.
  public static let window = 1.0
  /// Seconds a press of a row that runs once its leader is released waits for its run.
  public static let releaseWindow = 10.0
  /// Seconds after a list goes down in which presses are still the list's.
  static let listSettle = 0.3
  /// Seconds after a repeating row's key comes up in which a last repeat is still a repeat.
  static let repeatSettle = 0.25

  private let keymapURL: URL
  private let logURL: URL
  private let countURL: URL
  private let queue = DispatchQueue(label: "olm.keys.shadow")
  private let say: @Sendable (String) -> Void

  // Read and written on queue alone.
  private var resolver: Resolver?
  private var keymapStamp: Date?
  private var keymapChecked = 0.0
  private var held: Set<Int> = []
  private var leaderKeys: Set<Int> = []
  private var listUp = false
  private var listDownAt = -Double.infinity
  private var pendingApp: [(row: KeyRow, mods: Set<Mod>, at: Double)] = []
  private var pendingRuns: [(id: String, at: Double)] = []
  // A repeating row whose press was heard, by its key, and when its key came up, nil while down.
  private var repeating: [Int: (id: String, upAt: Double?)] = [:]
  private var counts = Counts()
  private var countsWritten = Counts()
  private var unknownGates: Set<String> = []
  private var timer: DispatchSourceTimer?

  struct Counts: Equatable {
    var heard = 0
    var paired = 0
    var appOnly = 0
    var hammerspoonOnly = 0
  }

  /// run is ~/.olm/run, where keymap.json is, and log ~/.olm/log.
  public init(run: URL, log: URL, say: @escaping @Sendable (String) -> Void = { NSLog("Olm keys: %@", $0) }) {
    keymapURL = run.appendingPathComponent("keymap.json")
    logURL = log.appendingPathComponent("shadow-keys.jsonl")
    countURL = log.appendingPathComponent("shadow-keys-count.json")
    self.say = say
    try? FileManager.default.createDirectory(at: log, withIntermediateDirectories: true)
  }

  public func start() {
    queue.async { [self] in
      reloadIfChanged(force: true)
      let t = DispatchSource.makeTimerSource(queue: queue)
      t.schedule(deadline: .now() + 0.5, repeating: 0.5)
      t.setEventHandler { [weak self] in self?.tick() }
      timer = t
      t.resume()
    }
  }

  /// A key event the tap heard, from the tap's thread.
  public func heard(_ event: KeyEvent) {
    queue.async { [self] in take(event) }
  }

  /// Hammerspoon ran a global row, the bridge's keyFired.
  public func fired(_ id: String) {
    let at = ProcessInfo.processInfo.systemUptime
    queue.async { [self] in ran(id, at: at) }
  }

  /// One of the app's lists went up or down, from the stage.
  public func list(up: Bool) {
    let at = ProcessInfo.processInfo.systemUptime
    queue.async { [self] in
      listUp = up
      if !up { listDownAt = at }
    }
  }

  // MARK: On the queue

  private func reloadIfChanged(force: Bool = false) {
    let now = ProcessInfo.processInfo.systemUptime
    guard force || now - keymapChecked > 1 else { return }
    keymapChecked = now
    let stamp = (try? FileManager.default.attributesOfItem(atPath: keymapURL.path))?[.modificationDate] as? Date
    guard stamp != keymapStamp || force else { return }
    keymapStamp = stamp
    do {
      let keymap = try Keymap.read(keymapURL)
      resolver = Resolver(keymap: keymap)
      leaderKeys = Set(keymap.leaders.compactMap { $0.held ? $0.keyCode : nil })
      say("read the keymap, \(keymap.rows.count) rows on \(keymap.leaders.map(\.name).joined(separator: ", "))")
    } catch {
      if resolver != nil || force { say("no keymap to shadow, \(error)") }
      resolver = nil
    }
  }

  private func listOwns(_ at: Double) -> Bool {
    listUp || at - listDownAt < Self.listSettle
  }

  private func take(_ e: KeyEvent) {
    switch e.kind {
    case .flags:
      return
    case .up:
      held.remove(e.code)
      if var r = repeating[e.code] {
        r.upAt = e.at
        repeating[e.code] = r
      }
    case .down:
      if leaderKeys.contains(e.code) {
        held.insert(e.code)
        return
      }
      guard !e.autorepeat else { return }
      reloadIfChanged()
      guard let resolver, !listOwns(e.at) else { return }
      counts.heard += 1
      guard case .runs(let row) = resolver.resolve(code: e.code, mods: e.mods, held: held, gate: gate) else { return }
      if row.repeats { repeating[e.code] = (row.id, nil) }
      if let i = pendingRuns.firstIndex(where: { $0.id == row.id }) {
        pendingRuns.remove(at: i)
        counts.paired += 1
      } else {
        pendingApp.append((row, e.mods, e.at))
      }
    }
  }

  private func ran(_ id: String, at: Double) {
    if listOwns(at) { return }
    // A repeat of a row whose press was heard and whose key is still down, or just came up.
    if repeating.values.contains(where: { $0.id == id && ($0.upAt.map { at - $0 < Self.repeatSettle } ?? true) }) {
      if let i = pendingApp.firstIndex(where: { $0.row.id == id }) {
        pendingApp.remove(at: i)
        counts.paired += 1
      }
      return
    }
    if let i = pendingApp.firstIndex(where: { $0.row.id == id }) {
      pendingApp.remove(at: i)
      counts.paired += 1
    } else {
      pendingRuns.append((id, at))
    }
  }

  // The gates the app answers itself, by the Lua predicate's name. One it does not know answers
  // true, as the Lua leader answers one, and is said once.
  private func gate(_ name: String) -> Bool {
    switch name {
    case "multipleDisplays":
      var count: UInt32 = 0
      CGGetActiveDisplayList(0, nil, &count)
      return count > 1
    default:
      if unknownGates.insert(name).inserted { say("a gate the app does not answer yet, \(name), taken as open") }
      return true
    }
  }

  private func tick() {
    let now = ProcessInfo.processInfo.systemUptime
    pendingApp.removeAll { p in
      guard now - p.at > (p.row.afterRelease ? Self.releaseWindow : Self.window) else { return false }
      counts.appOnly += 1
      write(["kind": "appOnly", "id": p.row.id, "leader": p.row.leader ?? "plain", "key": p.row.key,
        "mods": p.mods.map(\.rawValue).sorted()])
      return true
    }
    pendingRuns.removeAll { r in
      guard now - r.at > Self.window else { return false }
      counts.hammerspoonOnly += 1
      write(["kind": "hammerspoonOnly", "id": r.id])
      return true
    }
    repeating = repeating.filter { _, r in r.upAt.map { now - $0 < Self.repeatSettle } ?? true }
    if counts != countsWritten { writeCounts() }
  }

  // Used on the queue alone, since a formatter is not safe across threads.
  private let stamp: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  private func write(_ line: [String: Any]) {
    var line = line
    line["at"] = stamp.string(from: Date())
    guard var data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
    data.append(0x0A)
    if let h = try? FileHandle(forWritingTo: logURL) {
      h.seekToEndOfFile()
      h.write(data)
      try? h.close()
    } else {
      try? data.write(to: logURL)
    }
  }

  private func writeCounts() {
    countsWritten = counts
    let o: [String: Any] = ["heard": counts.heard, "paired": counts.paired, "appOnly": counts.appOnly,
      "hammerspoonOnly": counts.hammerspoonOnly, "updated": stamp.string(from: Date())]
    if let data = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) {
      try? data.write(to: countURL, options: .atomic)
    }
  }
}
