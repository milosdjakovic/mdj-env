// The window manager in shadow, step 6.3b of docs/PLAN-STANDALONE.md, docs/DESIGN-APP-WINDOWS.md.
// Before a META window key is handed to Hammerspoon the app reads the focused window and the screens,
// WindowRead, and Hammerspoon answers runKey with what it read, what it planned and, for Hide Others,
// what it hid. Here the two reads are compared, and the app's own plan, WindowPlan over its read with
// Hammerspoon's settings and memory, is compared with Hammerspoon's. A difference is one line in
// ~/.olm/log/shadow-windows.jsonl, and ~/.olm/log/shadow-windows-count.json says how many presses
// ran and agreed, so an empty log is read beside the presses it covers. Nothing here moves a window.

import Foundation

public final class WindowShadow: @unchecked Sendable {
  public struct Counts: Sendable, Equatable {
    public var ran = 0, same = 0, differs = 0, unanswered = 0
    /// Since the flip, the presses the app ran itself, the frames that landed and those refused.
    public var placed = 0, refused = 0
    /// The slowest read, in milliseconds, since it runs before the press goes on.
    public var slowest = 0.0
  }

  private let queue = DispatchQueue(label: "local.olm.windows.shadow")
  private let logURL: URL?
  private let countURL: URL?
  private var counts = Counts()
  /// Points two frames may differ by and still agree, since Accessibility and Hammerspoon round alike
  /// and only a real difference matters.
  public static let slack = 0.5

  /// log is the folder, ~/.olm/log for the app, nil keeping the counts only, for the check.
  public init(log: URL?) {
    logURL = log?.appendingPathComponent("shadow-windows.jsonl")
    countURL = log?.appendingPathComponent("shadow-windows-count.json")
    if let log { try? FileManager.default.createDirectory(at: log, withIntermediateDirectories: true) }
  }

  public var current: Counts { queue.sync { counts } }

  /// The window action a keymap row runs, windowmanager.leftHalf as leftHalf, nil for any other row.
  public static func action(_ id: String) -> String? {
    let prefix = "windowmanager."
    guard id.hasPrefix(prefix) else { return nil }
    let name = String(id.dropFirst(prefix.count))
    return name.isEmpty ? nil : name
  }

  /// One press compared: the app's read before it, and Hammerspoon's report, runKey's window member as
  /// Foundation answers JSON, nil when it sent none.
  public func compare(action: String, depth: Int, app: WindowSnapshot, settings: WindowSettings? = nil, lua: Any?) {
    let problems = Self.differences(action: action, app: app, settings: settings, lua: lua)
    queue.sync {
      counts.ran += 1
      counts.slowest = max(counts.slowest, app.took)
      switch problems {
      case nil:
        counts.unanswered += 1
        write(["kind": "unanswered", "action": action])
      case let p? where p.isEmpty:
        counts.same += 1
      case let p?:
        counts.differs += 1
        write(["kind": "differs", "action": action, "depth": depth, "what": p, "app": Self.words(app),
          "lua": lua ?? NSNull()])
      }
      writeCounts()
    }
  }

  /// A frame the app wrote, read back. Off by more than the slack a terminal's cell takes, 20 points
  /// as Lua's read back allows, is a window that refused it.
  public func placed(action: String, asked: WindowRect, got: WindowRect) {
    queue.sync {
      let off = [asked.x - got.x, asked.y - got.y, asked.w - got.w, asked.h - got.h].map(abs).max() ?? 0
      if off > 20 {
        counts.refused += 1
        write(["kind": "refused", "action": action, "asked": Self.rect(asked), "got": Self.rect(got)])
      } else {
        counts.placed += 1
      }
      writeCounts()
    }
  }

  /// What differs, empty when nothing does, nil when Hammerspoon reported nothing to compare.
  /// settings, the app's own from Olm's config, compared with the ones Hammerspoon planned with and
  /// planned with in their place, nil planning with Hammerspoon's.
  public static func differences(action: String, app: WindowSnapshot, settings: WindowSettings? = nil,
    lua: Any?) -> [String]? {
    guard let report = lua as? [String: Any] else { return nil }
    var out: [String] = []
    if action == "hideAllExceptFocused" {
      let hid = Set((report["hidden"] as? [Any] ?? []).compactMap { $0 as? String })
      if hid != Set(app.others) { out.append("hidden") }
      return out
    }
    let input = report["input"] as? [String: Any] ?? [:]
    let theirs = WindowInput(json: input)
    if !near(app.window, theirs.window) { out.append("window") }
    if app.id != theirs.id { out.append("id") }
    if app.screen != theirs.screen { out.append("screen") }
    if app.screens.count != theirs.screens.count
      || zip(app.screens, theirs.screens).contains(where: {
        $0.uuid != $1.uuid || !near($0.frame, $1.frame) || $0.builtin != $1.builtin
      }) {
      out.append("screens")
    }
    // The app's plan over its own read and its own settings, with Hammerspoon's depth and memory.
    var mine = theirs
    mine.window = app.window
    mine.id = app.id
    mine.screen = app.screen
    mine.screens = app.screens
    if let p = app.pointer { mine.pointer = p }
    if let settings {
      if settings.margins != theirs.margins || settings.gap != theirs.gap || settings.sizing != theirs.sizing {
        out.append("settings")
      }
      mine.margins = settings.margins
      mine.gap = settings.gap
      mine.sizing = settings.sizing
    }
    // The plan Hammerspoon ran, namedSize for a named size whose key names the size.
    let planned = WindowPlan.plan(report["action"] as? String ?? action, mine)
    let wanted = (report["result"] as? [String: Any]).flatMap(WindowResult.init(json:))
    switch (planned, wanted) {
    case (nil, nil): break
    case let (p?, w?):
      if !near(p.frame, w.frame) { out.append("frame") }
      if p.screen != w.screen { out.append("lands") }
    default: out.append("plan")
    }
    return out
  }

  static func near(_ a: WindowRect?, _ b: WindowRect?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (a?, b?):
      return abs(a.x - b.x) <= slack && abs(a.y - b.y) <= slack && abs(a.w - b.w) <= slack && abs(a.h - b.h) <= slack
    default: return false
    }
  }

  private static func rect(_ r: WindowRect?) -> Any {
    guard let r else { return NSNull() }
    return [r.x, r.y, r.w, r.h].map { ($0 * 10).rounded() / 10 }
  }

  private static func words(_ s: WindowSnapshot) -> [String: Any] {
    ["window": rect(s.window), "id": s.id.map { Int($0) } ?? NSNull(), "screen": s.screen ?? NSNull(),
      "screens": s.screens.map { ["uuid": $0.uuid, "frame": rect($0.frame)] }, "bundle": s.bundle ?? NSNull(),
      "others": s.others, "took": (s.took * 10).rounded() / 10]
  }

  // Used on the queue alone, since a formatter is not safe across threads.
  private let stamp: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  private func write(_ line: [String: Any]) {
    guard let logURL else { return }
    var line = line
    line["at"] = stamp.string(from: Date())
    guard JSONSerialization.isValidJSONObject(line),
      var data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
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
    guard let countURL else { return }
    let o: [String: Any] = ["ran": counts.ran, "same": counts.same, "differs": counts.differs,
      "unanswered": counts.unanswered, "slowestRead": (counts.slowest * 10).rounded() / 10,
      "placed": counts.placed, "refused": counts.refused,
      "updated": stamp.string(from: Date())]
    if let data = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) {
      try? data.write(to: countURL, options: .atomic)
    }
  }
}
