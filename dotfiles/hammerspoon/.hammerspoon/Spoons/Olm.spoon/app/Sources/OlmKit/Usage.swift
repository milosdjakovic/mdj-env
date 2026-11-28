// What a core plugin's items were used, most or last, the twin of OlmUsage in OlmPluginKit, in the
// same file shape, so a plugin moved into the app keeps the uses it had as an external one. One
// number and one time per key, halved every two weeks as it is read and raised by one on a use, the
// weakest dropped past five hundred. Owned by the plugin's actor, never shared between threads.

import Foundation

public final class Usage {
  public enum Order: Sendable { case most, last }

  private struct Entry: Codable {
    var score: Double
    var at: Double
  }

  private let file: URL
  private let now: () -> Date
  private var entries: [String: Entry]
  static let halfLife: Double = 14 * 86400
  static let most = 500

  public init(_ file: URL, now: @escaping () -> Date = Date.init) {
    self.file = file
    self.now = now
    entries = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
  }

  /// That this was just used.
  public func note(_ key: String) {
    entries[key] = Entry(score: score(key) + 1, at: now().timeIntervalSince1970)
    if entries.count > Self.most {
      let weakest = entries.keys.map { ($0, score($0)) }.sorted { $0.1 < $1.1 }
      for (key, _) in weakest.prefix(entries.count - Self.most) { entries[key] = nil }
    }
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(entries) { try? data.write(to: file, options: .atomic) }
  }

  /// What it is worth now, 0 for one never used.
  public func score(_ key: String) -> Double {
    guard let e = entries[key] else { return 0 }
    return e.score * pow(0.5, max(0, now().timeIntervalSince1970 - e.at) / Self.halfLife)
  }

  /// The items with the most or the last used first, those never used after them as they were.
  public func sorted<T>(_ items: [T], by order: Order, key: (T) -> String) -> [T] {
    items.enumerated().map { (at: $0.offset, item: $0.element, worth: worth(key($0.element), order)) }
      .sorted { $0.worth != $1.worth ? $0.worth > $1.worth : $0.at < $1.at }
      .map(\.item)
  }

  private func worth(_ key: String, _ order: Order) -> Double {
    order == .most ? score(key) : entries[key]?.at ?? 0
  }
}
