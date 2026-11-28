// The calculator, the port of plugins/arithmetic, docs/PLAN-STANDALONE.md stage 6. The Lua plugin
// hands a whitelisted expression to Lua's own load, so this is Lua 5.4's arithmetic, its grammar and
// its numbers: an integer stays an integer through + - * // and % and wraps as Lua's does, / and ^
// always give a float, // and % on integers by zero fail, a name of any kind fails, and the result is
// kept only when it is a finite number. test/fixtures/arithmetic/rows.json, recorded from the Lua
// plugin by test/arithmetic-record.lua, holds both to the same answers.

import Foundation

public enum Arithmetic {
  /// The result as the row's title, the text it copies, or nil when the query is not a sum.
  public static func answer(_ query: String) -> String? {
    guard let v = evaluate(query) else { return nil }
    return format(v)
  }

  enum Num: Equatable {
    case int(Int64)
    case float(Double)
    var double: Double {
      switch self {
      case .int(let i): return Double(i)
      case .float(let d): return d
      }
    }
  }

  // Lua's %s, the C locale's isspace.
  static func isSpace(_ c: UInt8) -> Bool { c == 32 || (c >= 9 && c <= 13) }
  static func isDigit(_ c: UInt8) -> Bool { c >= 48 && c <= 57 }

  static func trim(_ b: [UInt8]) -> [UInt8] {
    var s = 0, e = b.count
    while s < e, isSpace(b[s]) { s += 1 }
    while e > s, isSpace(b[e - 1]) { e -= 1 }
    return Array(b[s..<e])
  }

  /// The Lua evaluate, step for step.
  static func evaluate(_ query: String) -> Num? {
    var q = trim(Array(query.utf8))
    // A leading equals and the space after it.
    if q.first == UInt8(ascii: "=") {
      q.removeFirst()
      while let f = q.first, isSpace(f) { q.removeFirst() }
    }
    if q.isEmpty { return nil }
    let allowed = Set("eE+-*/%^.()".utf8)
    guard q.allSatisfy({ isDigit($0) || isSpace($0) || allowed.contains($0) }) else { return nil }
    let ops = Set("+-*/%^".utf8)
    guard q.contains(where: { ops.contains($0) }), q.contains(where: isDigit) else { return nil }
    for i in 0..<(q.count - 1) {
      if q[i] == UInt8(ascii: "-") && q[i + 1] == UInt8(ascii: "-") { return nil }
      if q[i] == UInt8(ascii: ".") && q[i + 1] == UInt8(ascii: ".") { return nil }
    }
    q = rewritePercent(q)
    var p = Parser(tokens: [])
    guard let tokens = lex(q) else { return nil }
    p.tokens = tokens
    guard let tree = p.expression(0), p.at == p.tokens.count else { return nil }
    guard let v = run(tree) else { return nil }
    if case .float(let d) = v, !d.isFinite { return nil }
    return v
  }

  /// `gsub("([%d%.]+)%%(.?)", ...)`: a run of digits and dots before a percent becomes a division by a
  /// hundred unless a digit or a dot follows the percent, which keeps it Lua's modulo.
  static func rewritePercent(_ q: [UInt8]) -> [UInt8] {
    func numeric(_ c: UInt8) -> Bool { isDigit(c) || c == UInt8(ascii: ".") }
    var out: [UInt8] = []
    var i = 0
    while i < q.count {
      guard numeric(q[i]) else {
        out.append(q[i])
        i += 1
        continue
      }
      var j = i
      while j < q.count, numeric(q[j]) { j += 1 }
      guard j < q.count, q[j] == UInt8(ascii: "%") else {
        // No match starting anywhere in this run, so it is copied as it stands.
        out.append(contentsOf: q[i..<j])
        i = j
        continue
      }
      let num = q[i..<j]
      var after: [UInt8] = []
      if j + 1 < q.count { after = [q[j + 1]] }
      if let a = after.first, numeric(a) {
        out.append(contentsOf: num)
        out.append(UInt8(ascii: "%"))
      } else {
        out.append(contentsOf: Array("(".utf8) + num + Array("/100)".utf8))
      }
      out.append(contentsOf: after)
      i = j + 1 + after.count
    }
    return out
  }

  enum Token: Equatable {
    case num(Num)
    case op(String)
    case open, close
    case name
  }

  /// Lua's lexer over the whitelisted alphabet. A numeral reads digits, dots, e and E with a sign
  /// after an exponent mark, as read_numeral does, and is then a number or malformed. A run of
  /// letters is a name, which Lua compiles and which then fails, since every name is nil.
  static func lex(_ q: [UInt8]) -> [Token]? {
    var out: [Token] = []
    var i = 0
    while i < q.count {
      let c = q[i]
      if isSpace(c) {
        i += 1
      } else if isDigit(c) || (c == UInt8(ascii: ".") && i + 1 < q.count && isDigit(q[i + 1])) {
        var j = i
        while j < q.count {
          let d = q[j]
          if d == UInt8(ascii: "e") || d == UInt8(ascii: "E") {
            j += 1
            if j < q.count, q[j] == UInt8(ascii: "+") || q[j] == UInt8(ascii: "-") { j += 1 }
          } else if isDigit(d) || d == UInt8(ascii: ".") {
            j += 1
          } else {
            break
          }
        }
        guard let n = numeral(String(decoding: q[i..<j], as: UTF8.self)) else { return nil }
        out.append(.num(n))
        i = j
      } else if c == UInt8(ascii: "e") || c == UInt8(ascii: "E") {
        var j = i
        while j < q.count, q[j] == UInt8(ascii: "e") || q[j] == UInt8(ascii: "E") || isDigit(q[j]) { j += 1 }
        out.append(.name)
        i = j
      } else if c == UInt8(ascii: "/") && i + 1 < q.count && q[i + 1] == UInt8(ascii: "/") {
        out.append(.op("//"))
        i += 2
      } else if c == UInt8(ascii: "(") {
        out.append(.open)
        i += 1
      } else if c == UInt8(ascii: ")") {
        out.append(.close)
        i += 1
      } else if c == UInt8(ascii: ".") {
        // A dot that starts no numeral, which Lua reads as an index and which cannot compile here.
        return nil
      } else {
        out.append(.op(String(UnicodeScalar(c))))
        i += 1
      }
    }
    return out
  }

  /// lua_stringtonumber over a decimal numeral: an integer when it is digits alone and fits, a float
  /// otherwise, nil when malformed.
  static func numeral(_ s: String) -> Num? {
    if s.utf8.allSatisfy(isDigit) {
      if let i = Int64(s) { return .int(i) }
      return strtod(s)
    }
    // Swift's Double accepts forms Lua refuses, so the shape is checked first: digits with at most
    // one dot, at least one digit, then an optional exponent with digits.
    let b = Array(s.utf8)
    var i = 0, digits = 0, dots = 0
    while i < b.count, isDigit(b[i]) || b[i] == UInt8(ascii: ".") {
      if b[i] == UInt8(ascii: ".") { dots += 1 } else { digits += 1 }
      i += 1
    }
    guard digits > 0, dots <= 1 else { return nil }
    if i < b.count {
      guard b[i] == UInt8(ascii: "e") || b[i] == UInt8(ascii: "E") else { return nil }
      i += 1
      if i < b.count, b[i] == UInt8(ascii: "+") || b[i] == UInt8(ascii: "-") { i += 1 }
      var exp = 0
      while i < b.count, isDigit(b[i]) {
        exp += 1
        i += 1
      }
      guard exp > 0, i == b.count else { return nil }
    }
    return strtod(s)
  }

  /// C's strtod over the whole string, which is what Lua's l_str2d does with a decimal numeral.
  static func strtod(_ s: String) -> Num? {
    s.withCString { p -> Num? in
      var end: UnsafeMutablePointer<CChar>?
      let d = Foundation.strtod(p, &end)
      guard let end, end.pointee == 0 else { return nil }
      return .float(d)
    }
  }

  indirect enum Tree {
    case leaf(Num)
    case name
    case neg(Tree)
    case bin(String, Tree, Tree)
    case call
  }

  /// Lua's subexpr: + and - at 10, * / // % at 11, unary minus at 12, ^ at 14 binding right, its
  /// right side a unary expression.
  struct Parser {
    var tokens: [Token]
    var at = 0

    static let left: [String: Int] = ["+": 10, "-": 10, "*": 11, "/": 11, "//": 11, "%": 11, "^": 14]
    static let right: [String: Int] = ["+": 10, "-": 10, "*": 11, "/": 11, "//": 11, "%": 11, "^": 13]
    static let unary = 12

    mutating func expression(_ limit: Int) -> Tree? {
      var lhs: Tree
      if at < tokens.count, tokens[at] == .op("-") {
        at += 1
        guard let operand = expression(Self.unary) else { return nil }
        lhs = .neg(operand)
      } else {
        guard let simple = simple() else { return nil }
        lhs = simple
      }
      while at < tokens.count, case .op(let op) = tokens[at], let l = Self.left[op], l > limit {
        at += 1
        guard let rhs = expression(Self.right[op]!) else { return nil }
        lhs = .bin(op, lhs, rhs)
      }
      return lhs
    }

    mutating func simple() -> Tree? {
      guard at < tokens.count else { return nil }
      switch tokens[at] {
      case .num(let n):
        at += 1
        return .leaf(n)
      case .name, .open:
        // A prefix expression, a name or a parenthesised one, which may be called.
        var tree: Tree
        if tokens[at] == .name {
          at += 1
          tree = .name
        } else {
          at += 1
          guard let inner = expression(0), at < tokens.count, tokens[at] == .close else { return nil }
          at += 1
          tree = inner
        }
        while at < tokens.count, tokens[at] == .open {
          at += 1
          if at < tokens.count, tokens[at] == .close {
            at += 1
          } else {
            guard expression(0) != nil, at < tokens.count, tokens[at] == .close else { return nil }
            at += 1
          }
          tree = .call
        }
        return tree
      default:
        return nil
      }
    }
  }

  static func run(_ t: Tree) -> Num? {
    switch t {
    case .leaf(let n): return n
    case .name, .call: return nil
    case .neg(let a):
      guard let v = run(a) else { return nil }
      switch v {
      case .int(let i): return .int(0 &- i)
      case .float(let d): return .float(-d)
      }
    case .bin(let op, let a, let b):
      guard let x = run(a), let y = run(b) else { return nil }
      return arith(op, x, y)
    }
  }

  static func arith(_ op: String, _ x: Num, _ y: Num) -> Num? {
    if case .int(let a) = x, case .int(let b) = y {
      switch op {
      case "+": return .int(a &+ b)
      case "-": return .int(a &- b)
      case "*": return .int(a &* b)
      case "//":
        if b == 0 { return nil }
        if b == -1 { return .int(0 &- a) }
        var q = a / b
        if a % b != 0 && (a ^ b) < 0 { q -= 1 }
        return .int(q)
      case "%":
        if b == 0 { return nil }
        if b == -1 { return .int(0) }
        var m = a % b
        if m != 0 && (m ^ b) < 0 { m += b }
        return .int(m)
      default: break
      }
    }
    let a = x.double, b = y.double
    switch op {
    case "+": return .float(a + b)
    case "-": return .float(a - b)
    case "*": return .float(a * b)
    case "/": return .float(a / b)
    case "^": return .float(pow(a, b))
    case "//": return .float((a / b).rounded(.down))
    case "%":
      var m = fmod(a, b)
      if m > 0 ? b < 0 : (m < 0 && b != m) { m += b }
      return .float(m)
    default: return nil
    }
  }

  /// An integral value under 1e15 without a decimal tail, anything else to ten significant digits,
  /// string.format's %d and %.10g.
  static func format(_ v: Num) -> String {
    switch v {
    case .int(let i):
      // math.abs of the smallest integer wraps to itself, which is under 1e15 too.
      if i == Int64.min || abs(i) < 1_000_000_000_000_000 { return String(i) }
      return String(format: "%.10g", Double(i))
    case .float(let d):
      if d == d.rounded(.down) && abs(d) < 1e15 { return String(Int64(d)) }
      return String(format: "%.10g", d)
    }
  }
}
