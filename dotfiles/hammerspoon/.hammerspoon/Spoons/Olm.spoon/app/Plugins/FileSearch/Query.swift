// File search's grammar, the Swift port of plugins/filesearch/query.lua, step 1.3a of
// docs/PLAN-STANDALONE.md. That file's header has the rules and why they are what they are, and
// test/fixtures/filesearch/ pins them for both sides, so this file only says where the port has
// to take care to read text the way Lua does.
//
// Lua reads a query as bytes. Its %s is the six ASCII whitespace characters, its lower folds A to Z
// alone, and a length or a prefix is counted in bytes. So this works on UTF-8 bytes throughout,
// never on Characters, and a word with an accent is left exactly as typed.

import Foundation

public struct FileQuery: Equatable, Sendable {
  public var raw: String
  public var hidden = false
  public var ignored = false
  public var typeTokens: [String] = []
  /// The union of the extensions the type tokens cover, nil for no type filter.
  public var exts: [String]? = nil
  /// The raw directory token with its trailing slash, nil for none.
  public var scope: String? = nil
  public var text = ""
  public var words: [String] = []
  public var kind: Kind = .recent

  public enum Kind: String, Sendable { case recent, browse, search }

  public init(raw: String) { self.raw = raw }
}

public enum FileQueryGrammar {
  private static func isSpace(_ b: UInt8) -> Bool {
    b == 0x20 || (b >= 0x09 && b <= 0x0D)
  }

  private static func trim(_ s: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
    var lo = s.startIndex, hi = s.endIndex
    while lo < hi, isSpace(s[lo]) { lo += 1 }
    while hi > lo, isSpace(s[hi - 1]) { hi -= 1 }
    return s[lo..<hi]
  }

  // The leading token and what follows it, of a slice that starts with no whitespace.
  private static func peel(_ s: ArraySlice<UInt8>) -> (ArraySlice<UInt8>, ArraySlice<UInt8>) {
    var i = s.startIndex
    while i < s.endIndex, !isSpace(s[i]) { i += 1 }
    return (s[s.startIndex..<i], s[i...])
  }

  private static func words(_ s: ArraySlice<UInt8>) -> [ArraySlice<UInt8>] {
    var out: [ArraySlice<UInt8>] = []
    var i = s.startIndex
    while i < s.endIndex {
      while i < s.endIndex, isSpace(s[i]) { i += 1 }
      let start = i
      while i < s.endIndex, !isSpace(s[i]) { i += 1 }
      if i > start { out.append(s[start..<i]) }
    }
    return out
  }

  private static func string(_ s: ArraySlice<UInt8>) -> String {
    String(decoding: s, as: UTF8.self)
  }

  private static func lowerASCII(_ s: ArraySlice<UInt8>) -> [UInt8] {
    s.map { ($0 >= 0x41 && $0 <= 0x5A) ? $0 + 32 : $0 }
  }

  private static let dot = UInt8(ascii: "."), bang = UInt8(ascii: "!"), slash = UInt8(ascii: "/")

  /// query.parse(raw, types), types the token to extension map from config.
  public static func parse(_ raw: String, types: [String: [String]]) -> FileQuery {
    var q = FileQuery(raw: raw)
    let bytes = Array(raw.utf8)
    var rest = trim(bytes[...])

    // The leading slot, sigils and type tokens in any order until a token is none of them.
    var seen = Set<String>()
    while !rest.isEmpty {
      let (tok, tail) = peel(rest)
      var consumed = false
      if tok.count == 1, tok.first == dot {
        q.hidden = true
        consumed = true
      } else if tok.count == 1, tok.first == bang {
        q.ignored = true
        consumed = true
      } else if tok.count > 1, tok.first == dot {
        let name = String(decoding: lowerASCII(tok.dropFirst()), as: UTF8.self)
        if let exts = types[name] {
          if !seen.contains(name) {
            seen.insert(name)
            q.typeTokens.append(name)
            q.exts = (q.exts ?? []) + exts
          }
          consumed = true
        }
      }
      if !consumed { break }
      rest = trim(tail)
    }

    // The scope slot, the first remaining token when it holds a slash, split at its last slash.
    if !rest.isEmpty {
      let (first, tail) = peel(rest)
      if let last = first.lastIndex(of: slash) {
        q.scope = string(first[first.startIndex...last])
        let remainder = Array(first[(last + 1)...]) + [0x20] + Array(tail)
        rest = trim(remainder[...])
      }
    }

    let split = words(trim(rest))
    q.text = split.map(string).joined(separator: " ")
    q.words = split.map(string)

    // A text starting with a dot asks for hidden paths when no type was read.
    if q.typeTokens.isEmpty, q.text.utf8.first == dot { q.hidden = true }

    q.kind = q.text.isEmpty ? (q.scope != nil ? .browse : .recent) : .search
    return q
  }

  /// query.sameShape(a, b), whether two parses ask about the same files whatever their text.
  public static func sameShape(_ a: FileQuery, _ b: FileQuery) -> Bool {
    a.hidden == b.hidden && a.ignored == b.ignored && a.scope == b.scope && a.exts == b.exts
  }

  /// query.narrows(prev, next), whether next is answered by filtering what prev found, the same
  /// shape and a text that only grew, compared in bytes.
  public static func narrows(_ prev: FileQuery, _ next: FileQuery) -> Bool {
    guard sameShape(prev, next) else { return false }
    let p = Array(prev.text.utf8), n = Array(next.text.utf8)
    return n.count > p.count && Array(n[0..<p.count]) == p
  }
}
