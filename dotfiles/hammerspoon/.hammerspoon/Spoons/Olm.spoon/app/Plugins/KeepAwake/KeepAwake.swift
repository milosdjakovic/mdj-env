// Keep Awake, a core list built into Olm.app since step 4.4 of docs/PLAN-STANDALONE.md, the port of
// plugins/caffeinate. One row that follows the field, the toggle while it is empty, a hold until a
// clock or for a span once one is typed, and a row that only says keep typing or what is wrong
// otherwise, so Return never applies a bad value. The list ranks nothing, its field being a value
// and not a search, and is as tall as its one row.
//
// The session outlives the list, so the composition root makes one KeepAwake for the app's life
// and starts it at launch, which restores a hold kept from before.

import Foundation
import OlmKit

public actor KeepAwake: ListSource {
  public static let id = "caffeinate"
  public nonisolated let manifest = Manifest(name: KeepAwake.id, title: "Keep Awake")
  public nonisolated var runsEveryVerb: Bool { false }

  /// The Lua manifest's icons, by the key a row names.
  static let symbols = ["on": "sun.max", "off": "moon.zzz", "clock": "clock", "duration": "timer",
    "hint": "keyboard", "error": "exclamationmark.triangle"]

  public let session: KeepAwakeSession
  private let calendar: @Sendable () -> Calendar
  private let now: @Sendable () -> Int

  public init(store: URL, now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) },
              calendar: @escaping @Sendable () -> Calendar = { Calendar.current }) {
    session = KeepAwakeSession(store: store, now: now)
    self.now = now
    self.calendar = calendar
  }

  public func start() async { await session.start() }

  private func line(_ query: String) async -> KeepAwakeGrammar.Line {
    KeepAwakeGrammar.line(query: query, status: await session.current(), now: now(), calendar: calendar())
  }

  static func key(_ choice: KeepAwakeGrammar.Choice?) -> String {
    switch choice {
    case .indefinite: return "indefinite"
    case .off: return "off"
    case .until: return "until"
    case .span: return "for"
    case nil: return "hint"
    }
  }

  // MARK: ListSource

  public func open(query: String) async -> Level {
    Level(placeholder: "Time or duration", ranking: .source, fit: true)
  }

  public func rows(_ query: Query) async throws -> RowsAnswer {
    let l = await line(query.text)
    let row = Row(key: Self.key(l.choice), title: l.title, subtitle: l.subtitle,
      icon: .symbol(Self.symbols[l.icon] ?? "play"), inert: l.choice == nil)
    // A timed hold's status counts down, so the empty field's row is asked again as it changes.
    let timed = (await session.current()).expiry != nil
    return RowsAnswer(rows: [row], pending: l.choice == .off && timed)
  }

  /// The empty field's status again once it reads differently, each minute while under an hour is
  /// left, at the hour and at the end before that.
  public func rowsLanded(_ query: Query) async throws -> RowsAnswer? {
    guard let expiry = (await session.current()).expiry else { return nil }
    let rem = expiry - now()
    let wait = rem <= 0 ? 1 : rem <= 3600 ? (rem % 60) + 1 : rem - 3600 + 1
    try await Task.sleep(nanoseconds: UInt64(max(1, wait)) * 1_000_000_000)
    return try await rows(query)
  }

  public func choose(_ pick: Pick) async -> [Effect] {
    guard let choice = (await line(pick.query)).choice else { return [] }
    switch choice {
    case .indefinite: await session.keepIndefinitely()
    case .off: await session.disable()
    case .until(let ts): await session.keepUntil(ts)
    case .span(let secs): await session.keepFor(secs)
    }
    return [.hide]
  }

  public func run(_ action: String, on pick: Pick) async -> [Effect] { [] }
  public func actions(on pick: Pick) async -> [String: String]? { [:] }
  public func close() async {}
}
