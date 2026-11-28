// When the launcher still asks Hammerspoon for the rows made from what was typed, the first step of
// the typed rows in the app, docs/PLAN-STANDALONE.md stage 6. Hammerspoon's query sources answer a
// typed word and its space, the query scope, a conversion, convert, and a size, window size, and the
// calculator, which the app answers itself. So the app asks only when the query has the shape one of
// the other three answers, each test a little wider than the Lua one, never narrower, since asking
// for nothing costs a round trip and not asking for something loses a row.
// test/fixtures/launcher/typedgate.json, recorded from the Lua sources' own tests, holds it there.

import Foundation

public struct TypedGate: Sendable {
  /// Every live alias of the query scope, lowercased.
  public var scopeWords: Set<String>
  /// The query sources Hammerspoon wired besides the scope, by identity.
  public var sources: Set<String>

  public init(scopeWords: Set<String>, sources: Set<String>) {
    self.scopeWords = scopeWords
    self.sources = sources
  }

  /// The sources this gate knows the shape of.
  public static let known: Set<String> = ["arithmetic", "convert", "windowsize"]

  static func isSpace(_ c: UInt8) -> Bool { c == 32 || (c >= 9 && c <= 13) }

  /// Whether Hammerspoon may answer this query with a row.
  public func asks(_ query: String) -> Bool {
    let b = Array(query.utf8)
    if b.isEmpty { return false }
    // A source this gate does not know may answer anything.
    if !sources.isSubset(of: Self.known) { return true }
    // The scope's "^(%S+)%s+(.*)$", the first word lowercased as Lua's lower does, ASCII alone.
    var i = 0
    while i < b.count, !Self.isSpace(b[i]) { i += 1 }
    if i > 0, i < b.count {
      let word = String(decoding: b[0..<i].map { ($0 >= 65 && $0 <= 90) ? $0 + 32 : $0 }, as: UTF8.self)
      if scopeWords.contains(word) { return true }
    }
    let digit = b.contains { $0 >= 48 && $0 <= 57 }
    guard digit else { return false }
    if sources.contains("convert") {
      let low = String(decoding: b.map { ($0 >= 65 && $0 <= 90) ? $0 + 32 : $0 }, as: UTF8.self)
      if low.contains(" to ") || low.contains("->") { return true }
    }
    if sources.contains("windowsize") {
      if query.contains("x") || query.contains("X") || query.contains("×") { return true }
    }
    return false
  }
}
