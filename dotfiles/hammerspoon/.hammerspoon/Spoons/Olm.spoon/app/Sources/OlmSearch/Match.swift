// The shared search, the Swift port of lib/chooser/match.lua's fuzzy, step 1.3b of
// docs/PLAN-STANDALONE.md. That file's comments hold the rules and the history of each, and
// test/fixtures/ranking/ pins them for both sides, so this file only says where the port has to
// take care to answer exactly what Lua answers.
//
// Lua reads every field as bytes. Its lower folds A to Z alone, its %w, %s, %p and %c are ASCII
// classes, a length is a byte count and a position a byte index. So this works on UTF-8 bytes
// throughout, and a position here is the same 1 based byte index the Lua code uses, read through
// at() below, which answers -1 where Lua's string.byte answers nil. Two out of range reads compare
// equal there as two nils do in Lua.
//
// Lua's numbers are doubles where a fraction is involved and exact integers otherwise, and every
// integer a score holds is exact as a Double, so a Double computed in the same order of operations
// lands on the same value. That matters, since two rows tie only on exactly equal scores, and a
// tie is decided by the supplier's order.
//
// One Fuzzy holds the prepared field memo and the last query parsed, the two caches the Lua module
// keeps, and is not safe to share between threads, so a search actor keeps its own. The long field
// memo of the Lua side is left out, a long field being folded and lowered on every call, which
// answers the same and costs only time.

import Foundation

/// The fields the shared search reads for one row, what rank.lua's fieldsOf builds.
public struct SearchFields {
  /// The name, the row's title or its filterText.
  public var primary: String
  /// Further names never shown, each matched like the primary.
  public var names: [String]?
  /// The subtitle and the keywords, declared marking a keyword.
  public var secondary: [(text: String, declared: Bool)]

  public init(primary: String, names: [String]? = nil, secondary: [(text: String, declared: Bool)] = []) {
    self.primary = primary
    self.names = names
    self.secondary = secondary
  }
}

/// What M.fuzzy answers for a row that matches, in its order.
public struct FuzzyMatch: Equatable {
  public let score: Double
  /// The row's level sum.
  public let level: Int
  public let within: Double
  public let atStart: Bool
  public let phrase: Bool
  public let fromNames: Int
}

public final class Fuzzy {
  public init() {}

  // The weights, as match.lua names them.
  static let MATCH = 1.0, START = 10.0, BOUND = 7.0, CAMEL = 6.0, CONSEC = 10.0
  static let GAP_LEAD = -0.02, GAP_TRAIL = -0.02
  static let TOP = MATCH + max(START, BOUND, CAMEL, CONSEC)
  static let TYPO_MIN = 4, INSIDE_MIN = 3
  static let LONG = 256
  static let OCCURRENCES = 256

  /// The levels a word can match at, strongest first.
  public enum Level {
    public static let nameStart = 4, namePieces = 3, nameEdit = 2, nameInside = 1, declared = 0
  }

  // MARK: Bytes as Lua reads them

  @inline(__always) static func at(_ a: [UInt8], _ j: Int) -> Int {
    (j >= 1 && j <= a.count) ? Int(a[j - 1]) : -1
  }
  @inline(__always) static func isUpper(_ b: Int) -> Bool { b >= 65 && b <= 90 }
  @inline(__always) static func isLower(_ b: Int) -> Bool { b >= 97 && b <= 122 }
  @inline(__always) static func alnum(_ b: Int) -> Bool {
    (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122)
  }
  // C's isspace, Lua's %s.
  @inline(__always) static func isSpace(_ b: UInt8) -> Bool { b == 0x20 || (b >= 0x09 && b <= 0x0D) }
  // C's ispunct and iscntrl, Lua's %p and %c, in the ASCII range they cover.
  @inline(__always) static func isPunctOrControl(_ b: UInt8) -> Bool {
    b < 0x20 || b == 0x7F || (b >= 0x21 && b <= 0x2F) || (b >= 0x3A && b <= 0x40)
      || (b >= 0x5B && b <= 0x60) || (b >= 0x7B && b <= 0x7E)
  }

  static func lower(_ s: [UInt8]) -> [UInt8] {
    s.map { ($0 >= 0x41 && $0 <= 0x5A) ? $0 + 32 : $0 }
  }

  // A plain find of needle in hay from byte init, 1 based, string.find with plain set.
  static func find(_ hay: [UInt8], _ needle: [UInt8], _ initial: Int = 1) -> Int? {
    let n = needle.count, m = hay.count
    if n == 0 { return initial <= m + 1 ? initial : nil }
    guard initial >= 1, initial + n - 1 <= m else { return nil }
    let first = needle[0]
    var i = initial - 1
    let lastStart = m - n
    return hay.withUnsafeBufferPointer { h in
      needle.withUnsafeBufferPointer { w in
        while i <= lastStart {
          if h[i] == first {
            var k = 1
            while k < n && h[i + k] == w[k] { k += 1 }
            if k == n { return i + 1 }
          }
          i += 1
        }
        return nil
      }
    }
  }

  // The non ASCII separators, by their UTF-8 bytes, in match.lua's order.
  static let multiSep: [[UInt8]] = ["\u{00B7}", "\u{25B8}", "\u{2022}", "\u{2014}", "\u{2013}", "\u{203A}", "\u{2192}"]
    .map { Array($0.utf8) }

  // The ASCII punctuation that ends a phrase.
  static func isBreak(_ b: Int) -> Bool { b == 0x2C || b == 0x3B || b == 0x21 || b == 0x3F }

  static func multiSepAt(_ s: [UInt8], _ j: Int) -> Int? {
    let b = at(s, j)
    if b < 128 { return nil }
    for seq in multiSep {
      var ok = true
      for k in 1...seq.count where at(s, j + k - 1) != Int(seq[k - 1]) {
        ok = false
        break
      }
      if ok { return seq.count }
    }
    return nil
  }

  static func wordByteAt(_ s: [UInt8], _ j: Int) -> Bool {
    let b = at(s, j)
    if b < 0 { return false }
    if b < 128 { return alnum(b) }
    for back in 0...2 {
      if j - back >= 1, let len = multiSepAt(s, j - back), len > back { return false }
    }
    return true
  }

  // MARK: The fold

  // FOLD, keyed by a two byte sequence as lead << 8 | continuation. The groups are match.lua's,
  // an upper case letter to an upper case base.
  static let foldTable: [Int: [UInt8]] = {
    let groups: [(String, String)] = [
      ("ÀÁÂÃÄÅĀĂĄ", "A"), ("àáâãäåāăą", "a"), ("Æ", "AE"), ("æ", "ae"),
      ("ÇĆĈĊČ", "C"), ("çćĉċč", "c"), ("ÐĎĐ", "D"), ("ðďđ", "d"),
      ("ÈÉÊËĒĔĖĘĚ", "E"), ("èéêëēĕėęě", "e"), ("ĜĞĠĢ", "G"), ("ĝğġģ", "g"),
      ("ĤĦ", "H"), ("ĥħ", "h"), ("ÌÍÎÏĨĪĬĮİ", "I"), ("ìíîïĩīĭįı", "i"),
      ("Ĳ", "IJ"), ("ĳ", "ij"), ("Ĵ", "J"), ("ĵ", "j"), ("Ķ", "K"), ("ķĸ", "k"),
      ("ĹĻĽĿŁ", "L"), ("ĺļľŀł", "l"), ("ÑŃŅŇŊ", "N"), ("ñńņňŉŋ", "n"),
      ("ÒÓÔÕÖØŌŎŐ", "O"), ("òóôõöøōŏő", "o"), ("Œ", "OE"), ("œ", "oe"),
      ("ŔŖŘ", "R"), ("ŕŗř", "r"), ("ŚŜŞŠȘ", "S"), ("śŝşšșſ", "s"), ("ß", "ss"),
      ("ŢŤŦȚ", "T"), ("ţťŧț", "t"), ("Þ", "TH"), ("þ", "th"),
      ("ÙÚÛÜŨŪŬŮŰŲ", "U"), ("ùúûüũūŭůűų", "u"), ("Ŵ", "W"), ("ŵ", "w"),
      ("ÝŶŸ", "Y"), ("ýÿŷ", "y"), ("ŹŻŽ", "Z"), ("źżž", "z"),
    ]
    var t: [Int: [UInt8]] = [:]
    for (chars, base) in groups {
      for scalar in chars.unicodeScalars {
        let u = Array(String(scalar).utf8)
        if u.count == 2, u[0] >= 192, u[0] <= 223 { t[Int(u[0]) << 8 | Int(u[1])] = Array(base.utf8) }
      }
    }
    return t
  }()

  /// match.lua's fold, Latin letters with diacritics folded to their base letters and combining
  /// marks dropped. The three passes run in Lua's order, each over the text the one before left,
  /// and each, like gsub, moves on one byte where its two byte pattern does not match.
  public static func fold(_ s: [UInt8]) -> [UInt8] {
    if !s.contains(where: { $0 == 195 || $0 == 196 || $0 == 197 || $0 == 200 || $0 == 204 || $0 == 205 }) {
      return s
    }
    var a: [UInt8] = []
    a.reserveCapacity(s.count)
    var i = 0
    while i < s.count {
      let b = s[i]
      if (b >= 195 && b <= 197) || b == 200, i + 1 < s.count, s[i + 1] >= 128, s[i + 1] <= 191 {
        if let base = foldTable[Int(b) << 8 | Int(s[i + 1])] { a += base } else { a += [b, s[i + 1]] }
        i += 2
      } else {
        a.append(b)
        i += 1
      }
    }
    func drop(_ s: [UInt8], _ lead: UInt8, _ hi: UInt8) -> [UInt8] {
      var out: [UInt8] = []
      out.reserveCapacity(s.count)
      var i = 0
      while i < s.count {
        if s[i] == lead, i + 1 < s.count, s[i + 1] >= 128, s[i + 1] <= hi {
          i += 2
        } else {
          out.append(s[i])
          i += 1
        }
      }
      return out
    }
    return drop(drop(a, 204, 191), 205, 175)
  }

  /// The fold of a string, as text.
  public static func fold(_ s: String) -> String {
    String(decoding: fold(Array(s.utf8)), as: UTF8.self)
  }

  // MARK: Scoring pieces

  @inline(__always) static func framed(_ m: Int, _ first: Int, _ lastEnd: Int, _ sum: Double) -> Double {
    sum + Double(first - 1) * GAP_LEAD + Double(m - lastEnd) * GAP_TRAIL
  }
  @inline(__always) static func pieceScore(_ bonus: Double, _ len: Int) -> Double {
    bonus + MATCH + Double(len - 1) * (CONSEC + MATCH)
  }

  static func startBonus(_ s: [UInt8], _ j: Int, _ isWord: (Int) -> Bool) -> Double {
    if !isWord(j) { return 0 }
    if j == 1 { return START }
    if !isWord(j - 1) { return BOUND }
    if isLower(at(s, j - 1)) && isUpper(at(s, j)) { return CAMEL }
    return 0
  }

  // MARK: A short field, prepared

  struct Word {
    var s: Int, e: Int, bonus: Double
    var joined = false, breakAfter = false
  }
  struct Phrase {
    var first: Int, last: Int
    var compact: [UInt8]
    var withAmp: [UInt8]?
  }
  // Word indices here are 0 based into words, byte positions 1 based as in Lua.
  final class Prepared {
    let low: [UInt8]
    let wb: [Bool]
    var words: [Word] = []
    var byFirst: [UInt8: [Int]] = [:]
    var phrases: [Phrase] = []
    init(low: [UInt8], wb: [Bool]) { self.low = low; self.wb = wb }
    @inline(__always) func isWord(_ k: Int) -> Bool { k >= 1 && k < wb.count && wb[k] }
  }

  static let PREP_LIMIT = 20000
  private var prepared: [String: Prepared] = [:]

  func prepare(_ key: String) -> Prepared {
    if let p = prepared[key] { return p }
    let p = Fuzzy.prepare(bytes: Array(key.utf8))
    if prepared.count >= Fuzzy.PREP_LIMIT { prepared = [:] }
    prepared[key] = p
    return p
  }

  static func prepare(bytes key: [UInt8]) -> Prepared {
    let s = fold(key)
    let m = s.count
    var wb = [Bool](repeating: false, count: m + 2)
    var j = 1
    while j <= m {
      if let len = multiSepAt(s, j) {
        j += len
      } else {
        let b = Int(s[j - 1])
        wb[j] = b >= 128 || alnum(b)
        j += 1
      }
    }
    let p = Prepared(low: lower(s), wb: wb)
    let isWord: (Int) -> Bool = { p.isWord($0) }
    j = 1
    while j <= m {
      let bonus = startBonus(s, j, isWord)
      if bonus > 0 {
        var e = j
        while e < m && wb[e + 1] && startBonus(s, e + 1, isWord) == 0 { e += 1 }
        p.words.append(Word(s: j, e: e, bonus: bonus))
        p.byFirst[p.low[j - 1], default: []].append(p.words.count - 1)
        j = e + 1
      } else {
        j += 1
      }
    }
    if p.words.count > 1 {
      for k in 0..<(p.words.count - 1) {
        let w = p.words[k], nx = p.words[k + 1]
        p.words[k].joined = nx.s == w.e + 1
        var broken = false
        var g = w.e + 1
        while g < nx.s {
          if isBreak(at(s, g)) || multiSepAt(s, g) != nil { broken = true; break }
          g += 1
        }
        p.words[k].breakAfter = broken
      }
    }
    // The phrases, each keyed by its lowered text with the spaces out, and with a standalone
    // ampersand out too, the key with it kept beside when the two differ.
    var k = 0
    while k < p.words.count {
      var last = k
      while last < p.words.count - 1 && !p.words[last].breakAfter { last += 1 }
      let text = p.low[(p.words[k].s - 1)..<p.words[last].e]
      var withAmp: [UInt8] = [], compact: [UInt8] = []
      var i = text.startIndex
      while i < text.endIndex {
        if isSpace(text[i]) { i += 1; continue }
        let start = i
        while i < text.endIndex && !isSpace(text[i]) { i += 1 }
        let tok = text[start..<i]
        withAmp += tok
        if !tok.allSatisfy({ $0 == 0x26 }) { compact += tok }
      }
      p.phrases.append(Phrase(first: k, last: last, compact: compact, withAmp: withAmp != compact ? withAmp : nil))
      k = last + 1
    }
    return p
  }

  static func prefixAt(_ low: [UInt8], _ s: Int, _ w: [UInt8]) -> Bool {
    for i in 1...w.count where at(low, s + i - 1) != Int(w[i - 1]) { return false }
    return true
  }

  // MARK: The levels

  // Level A.
  static func atWordStart(_ w: [UInt8], _ p: Prepared) -> Double? {
    guard let list = p.byFirst[w[0]] else { return nil }
    var best: Double? = nil
    let m = p.low.count
    for k in list {
      let word = p.words[k]
      if prefixAt(p.low, word.s, w) {
        let sc = framed(m, word.s, word.s + w.count - 1, pieceScore(word.bonus, w.count))
        if best == nil || sc > best! { best = sc }
      }
    }
    return best
  }

  // Level B, the memo over the query position and the word as match.lua keeps it.
  static func inPieces(_ w: [UInt8], _ p: Prepared) -> Double? {
    guard let first = p.byFirst[w[0]] else { return nil }
    let n = w.count, words = p.words, low = p.low, m = p.low.count
    var memo: [Int: Double?] = [:]
    func wb(_ i: Int) -> Int { Int(w[i - 1]) }
    func after(_ qi: Int, _ k: Int) -> Double? {
      var best: Double? = nil
      var j = k + 1
      while j < words.count {
        let prev = words[j - 1]
        if prev.breakAfter { break }
        if let r = rest(qi, j), best == nil || r > best! { best = r }
        if !prev.joined { break }
        j += 1
      }
      return best
    }
    func rest(_ qi: Int, _ k: Int) -> Double? {
      let key = qi * 1_000_000 + k
      if let hit = memo[key] { return hit }
      let word = words[k]
      var best: Double? = nil
      let len = word.e - word.s + 1
      var L = 0
      while L < len && qi + L <= n && at(low, word.s + L) == wb(qi + L) {
        L += 1
        let here = pieceScore(word.bonus, L)
        var total: Double? = nil
        if qi + L - 1 == n {
          total = here + Double(m - (word.s + L - 1)) * GAP_TRAIL
        } else if let a = after(qi + L, k) {
          total = here + a
        }
        if let t = total, best == nil || t > best! { best = t }
      }
      memo[key] = .some(best)
      return best
    }
    var best: Double? = nil
    for k in first {
      let word = words[k]
      let len = word.e - word.s + 1
      var L = 0
      while L < len && L < n - 1 && at(low, word.s + L) == wb(1 + L) {
        L += 1
        if let a = after(1 + L, k) {
          let total = pieceScore(word.bonus, L) + a + Double(word.s - 1) * GAP_LEAD
          if best == nil || total > best! { best = total }
        }
      }
    }
    return best
  }

  static func oneEditAt(_ low: [UInt8], _ s: Int, _ w: [UInt8], _ wb: (Int) -> Bool) -> Bool {
    let n = w.count
    func wq(_ i: Int) -> Int { at(w, i) }
    var i = 2
    while i <= n && at(low, s + i - 1) == wq(i) { i += 1 }
    if i > n { return false }
    func restEq(_ wi: Int, _ ti: Int) -> Bool {
      var x = 0
      while x <= n - wi {
        if at(low, ti + x) != wq(wi + x) { return false }
        x += 1
      }
      return true
    }
    let here = s + i - 1
    if i < n {
      if wb(here) && restEq(i + 1, here + 1) { return true }
      if restEq(i + 1, here) { return true }
      if at(low, here) == wq(i + 1) && at(low, here + 1) == wq(i) && restEq(i + 2, here + 2) { return true }
    }
    return wb(here) && restEq(i, here + 1)
  }

  // Level C.
  static func withOneEdit(_ w: [UInt8], _ p: Prepared) -> Double? {
    guard let list = p.byFirst[w[0]] else { return nil }
    var best: Double? = nil
    let m = p.low.count
    for k in list {
      let word = p.words[k]
      if oneEditAt(p.low, word.s, w, { p.isWord($0) }) {
        let sc = framed(m, word.s, min(m, word.s + w.count - 1), pieceScore(word.bonus, w.count))
        if best == nil || sc > best! { best = sc }
      }
    }
    return best
  }

  // Level D.
  static func insideWord(_ w: [UInt8], _ low: [UInt8]) -> Double? {
    guard let pos = find(low, w, 1) else { return nil }
    return framed(low.count, pos, pos + w.count - 1, pieceScore(0, w.count))
  }

  // A long field, s folded and low its lowered copy. Answers whether it was a word start and the
  // score, or nil.
  static func longField(_ w: [UInt8], _ s: [UInt8], _ low: [UInt8], _ allowInside: Bool) -> (atStart: Bool, score: Double)? {
    let n = w.count
    var first: Int? = nil, initial = 1, tried = 0
    func scored(_ pos: Int, _ bonus: Double) -> Double {
      Double(min(pos - 1, LONG)) * GAP_LEAD + pieceScore(bonus, n)
    }
    while true {
      guard let pos = find(low, w, initial) else { break }
      let bonus: Double
      let here = at(s, pos)
      if pos > 1, at(s, pos - 1) < 128, here < 128 {
        let prev = at(s, pos - 1)
        if !alnum(prev) {
          bonus = BOUND
        } else if isLower(prev) && isUpper(here) {
          bonus = CAMEL
        } else {
          bonus = 0
        }
      } else {
        bonus = startBonus(s, pos) { wordByteAt(s, $0) }
      }
      if bonus > 0 { return (true, scored(pos, bonus)) }
      first = first ?? pos
      tried += 1
      if tried >= OCCURRENCES { break }
      initial = pos + 1
    }
    if let first, allowInside, n >= INSIDE_MIN { return (false, scored(first, 0)) }
    return nil
  }

  static func longOf(_ text: String) -> (folded: [UInt8], low: [UInt8]) {
    let f = fold(Array(text.utf8))
    return (f, lower(f))
  }

  func matchName(_ w: [UInt8], _ name: String?) -> (level: Int, score: Double)? {
    guard let name, !name.isEmpty else { return nil }
    if name.utf8.count > Fuzzy.LONG {
      let (f, low) = Fuzzy.longOf(name)
      guard let r = Fuzzy.longField(w, f, low, true) else { return nil }
      return (r.atStart ? Level.nameStart : Level.nameInside, r.score)
    }
    let p = prepare(name)
    if p.byFirst[w[0]] != nil {
      if let s = Fuzzy.atWordStart(w, p) { return (Level.nameStart, s) }
      if let s = Fuzzy.inPieces(w, p) { return (Level.namePieces, s) }
      if w.count >= Fuzzy.TYPO_MIN, let s = Fuzzy.withOneEdit(w, p) { return (Level.nameEdit, s) }
    }
    if w.count >= Fuzzy.INSIDE_MIN, let s = Fuzzy.insideWord(w, p.low) { return (Level.nameInside, s) }
    return nil
  }

  func spellsWhole(_ w: [UInt8], _ n: String) -> Bool {
    n.utf8.count <= Fuzzy.LONG && prepare(n).low == w
  }

  func matchNames(_ w: [UInt8], _ name: String, _ names: [String]?) -> (level: Int, score: Double, named: Bool)? {
    var best = matchName(w, name)
    var further: (level: Int, score: Double)? = nil
    for n in names ?? [] {
      guard let r = matchName(w, n) else { continue }
      if spellsWhole(w, n) {
        if best == nil || r.level > best!.level || (r.level == best!.level && r.score > best!.score) { best = r }
      } else if further == nil || r.level > further!.level || (r.level == further!.level && r.score > further!.score) {
        further = r
      }
    }
    if let f = further, best == nil || f.level > best!.level { return (f.level, f.score, true) }
    if let b = best { return (b.level, b.score, false) }
    return nil
  }

  static func runTogether(_ w: [UInt8], _ p: Prepared) -> Double? {
    var best: Double? = nil
    let m = p.low.count
    func starts(_ key: [UInt8]) -> Bool { key.count >= w.count && key[0..<w.count].elementsEqual(w) }
    for ph in p.phrases {
      if starts(ph.compact) || (ph.withAmp.map(starts) ?? false) {
        let first = p.words[ph.first]
        let sc = framed(m, first.s, min(m, first.s + w.count - 1), pieceScore(first.bonus, w.count))
        if best == nil || sc > best! { best = sc }
      }
    }
    return best
  }

  // Level E.
  func matchDeclared(_ w: [UInt8], _ secondary: [(text: String, declared: Bool)]) -> Double? {
    var best: Double? = nil
    for f in secondary where !f.text.isEmpty {
      var s: Double? = nil
      if f.text.utf8.count > Fuzzy.LONG {
        let (folded, low) = Fuzzy.longOf(f.text)
        if let r = Fuzzy.longField(w, folded, low, false), r.atStart { s = r.score }
      } else {
        let p = prepare(f.text)
        s = Fuzzy.atWordStart(w, p)
        if f.declared, let r = Fuzzy.runTogether(w, p), s == nil || r > s! { s = r }
      }
      if let s, best == nil || s > best! { best = s }
    }
    return best
  }

  func inOnePhrase(_ cores: [[UInt8]], _ secondary: [(text: String, declared: Bool)]) -> Bool {
    if cores.count < 2 { return false }
    for f in secondary where !f.text.isEmpty && f.text.utf8.count <= Fuzzy.LONG {
      let p = prepare(f.text)
      for ph in p.phrases {
        var k = ph.first, ok = true
        for c in cores {
          while k <= ph.last && !Fuzzy.prefixAt(p.low, p.words[k].s, c) { k += 1 }
          if k > ph.last { ok = false; break }
          k += 1
        }
        if ok { return true }
      }
    }
    return false
  }

  func lowOf(_ text: String) -> [UInt8] {
    text.utf8.count > Fuzzy.LONG ? Fuzzy.longOf(text).low : prepare(text).low
  }

  func holds(_ t: [UInt8], _ fields: SearchFields) -> Bool {
    if !fields.primary.isEmpty, Fuzzy.find(lowOf(fields.primary), t) != nil { return true }
    for n in fields.names ?? [] where !n.isEmpty {
      if Fuzzy.find(lowOf(n), t) != nil { return true }
    }
    for f in fields.secondary where !f.text.isEmpty {
      if Fuzzy.find(lowOf(f.text), t) != nil { return true }
    }
    return false
  }

  // MARK: The query

  struct QueryWord { var word: [UInt8], lead: [UInt8], core: [UInt8] }
  private var lastQuery: String? = nil
  private var lastWords: [QueryWord] = []

  func queryWords(_ query: String) -> [QueryWord] {
    if query == lastQuery { return lastWords }
    let q = Fuzzy.lower(Fuzzy.fold(Array(query.utf8)))
    var list: [QueryWord] = []
    var i = 0
    while i < q.count {
      if Fuzzy.isSpace(q[i]) { i += 1; continue }
      let start = i
      while i < q.count && !Fuzzy.isSpace(q[i]) { i += 1 }
      let word = Array(q[start..<i])
      var l = 0
      while l < word.count && Fuzzy.isPunctOrControl(word[l]) { l += 1 }
      list.append(QueryWord(word: word, lead: Array(word[0..<l]), core: Array(word[l...])))
    }
    lastQuery = query
    lastWords = list
    return list
  }

  /// M.fuzzy(query, hay, fields), the one search. nil when the row does not match.
  public func match(_ query: String, _ fields: SearchFields) -> FuzzyMatch? {
    var level = 0, fromNames = 0
    var within = 0.0, spread = 0.0
    var atStart = true
    var cores: [[UInt8]] = []
    let words = queryWords(query)
    for qw in words {
      if qw.core.isEmpty {
        if !holds(qw.word, fields) { return nil }
      } else {
        if !qw.lead.isEmpty && !holds(qw.lead, fields) { return nil }
        let wordLevel: Int, score: Double
        if let r = matchNames(qw.core, fields.primary, fields.names) {
          wordLevel = r.level
          score = r.score
          if r.named { fromNames += 1 }
        } else {
          guard let s = matchDeclared(qw.core, fields.secondary) else { return nil }
          wordLevel = Level.declared
          score = s
        }
        level += wordLevel
        within = within + score
        if wordLevel != Level.nameStart { atStart = false }
        spread = spread + Double(qw.core.count) * Fuzzy.TOP + Double(Fuzzy.LONG) * max(-Fuzzy.GAP_LEAD, -Fuzzy.GAP_TRAIL)
        cores.append(qw.core)
      }
    }
    if words.isEmpty { return FuzzyMatch(score: 0, level: 0, within: 0, atStart: true, phrase: false, fromNames: 0) }
    let phrase = inOnePhrase(cores, fields.secondary)
    let band = Double(cores.count + 1) * spread
    let inLevel = within - Double(fromNames) * spread
    let score = Double(level) * 2 * band + inLevel + (phrase ? band : 0)
    return FuzzyMatch(score: score, level: level, within: inLevel + (phrase ? spread : 0),
      atStart: atStart, phrase: phrase, fromNames: fromNames)
  }
}
