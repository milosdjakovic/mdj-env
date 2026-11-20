// The app toggler in shadow beside its flip, step 6.2, docs/DESIGN-APP-APPS.md. Each press the app
// runs is handed here with what the app decided and what Lua would have done, and a difference is one
// line in ~/.olm/log/shadow-apps.jsonl. So is a placement the window refused, read back after it was
// set, and a wait that ran out before the app was ready. ~/.olm/log/shadow-apps-count.json says how
// many presses were run and how many agreed, so an empty log is read beside the presses it covers.

import Foundation

public final class AppShadow: @unchecked Sendable {
  public struct Counts: Sendable, Equatable {
    public var ran = 0, same = 0, differs = 0, placed = 0, refused = 0, unplaced = 0, untrusted = 0
  }

  private let queue = DispatchQueue(label: "local.olm.apps.shadow")
  private let logURL: URL?
  private let countURL: URL?
  private var counts = Counts()
  // A refused frame is one off by more than this many points, since a window rounds to whole points
  // and some apps snap a size to their own grid.
  public static let slack = 2.0

  /// log is the folder, ~/.olm/log for the app, nil keeping the counts only, for the check.
  public init(log: URL?) {
    logURL = log?.appendingPathComponent("shadow-apps.jsonl")
    countURL = log?.appendingPathComponent("shadow-apps-count.json")
    if let log { try? FileManager.default.createDirectory(at: log, withIntermediateDirectories: true) }
  }

  public var current: Counts { queue.sync { counts } }

  /// A press run, the app's decision beside Lua's. trusted false is a press run without Accessibility,
  /// a grant taken away within the ten seconds before the app said so.
  public func ran(_ press: AppPress, plan: AppPlan, trusted: Bool) {
    queue.sync {
      counts.ran += 1
      if !trusted {
        counts.untrusted += 1
        write(["kind": "untrusted", "id": press.id])
      }
      if let lua = press.lua {
        if lua == plan {
          counts.same += 1
        } else {
          counts.differs += 1
          write(["kind": "differs", "id": press.id, "app": Self.words(plan), "lua": Self.words(lua)])
        }
      }
      writeCounts()
    }
  }

  /// A placement set and read back.
  public func placed(_ press: AppPress, asked: Box, got: Box) {
    queue.sync {
      let off = [asked.x - got.x, asked.y - got.y, asked.w - got.w, asked.h - got.h].map(abs).max() ?? 0
      if off > Self.slack {
        counts.refused += 1
        write(["kind": "refused", "id": press.id, "asked": Self.box(asked), "got": Self.box(got)])
      } else {
        counts.placed += 1
      }
      writeCounts()
    }
  }

  /// A placement whose wait ran out before the app had a main window and held focus.
  public func unplaced(_ press: AppPress) {
    queue.sync {
      counts.unplaced += 1
      write(["kind": "unplaced", "id": press.id])
      writeCounts()
    }
  }

  private static func words(_ plan: AppPlan) -> [String: Any] {
    var o: [String: Any] = ["outcome": plan.outcome.rawValue]
    if let w = plan.window { o["window"] = Int(w) }
    return o
  }

  private static func box(_ b: Box) -> [Double] { [b.x, b.y, b.w, b.h].map { ($0 * 10).rounded() / 10 } }

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
    guard let countURL else { return }
    let o: [String: Any] = ["ran": counts.ran, "same": counts.same, "differs": counts.differs, "placed": counts.placed,
      "refused": counts.refused, "unplaced": counts.unplaced, "untrusted": counts.untrusted,
      "updated": stamp.string(from: Date())]
    if let data = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) {
      try? data.write(to: countURL, options: .atomic)
    }
  }
}
