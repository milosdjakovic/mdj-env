// Keep awake's one row, the field read as a clock or a span, the port of plugins/caffeinate/init.lua's
// rows, its grammar and its words kept exactly, plugins/caffeinate/AGENTS.md has why each rule is
// what it is. Pure, so test/fixtures/keepawake/rows.json, recorded from the Lua, pins it in
// olm-fixtures. Time is whole seconds since 1970, as os.time counts it, and a day is the calendar's,
// so a check names its zone and the app passes the Mac's.

import Foundation

public enum KeepAwakeGrammar {
  /// A session as the engine holds it, expiry nil while active meaning indefinite.
  public struct Status: Sendable, Equatable {
    public var active: Bool
    public var expiry: Int?

    public init(active: Bool, expiry: Int? = nil) {
      self.active = active
      self.expiry = active ? expiry : nil
    }

    public static let off = Status(active: false)
  }

  /// What choosing the row does.
  public enum Choice: Sendable, Equatable {
    case indefinite
    case off
    case until(Int)
    case span(Int)
  }

  /// The one row, its icon by the Lua manifest's key, choice nil for a row that only says something.
  public struct Line: Sendable, Equatable {
    public var title: String
    public var subtitle: String
    public var icon: String
    public var choice: Choice?
  }

  /// A safety rail of a month, so an absurd number reads as an error rather than a date.
  static let maxSecs = 31 * 86400
  static let examples = "a time like 18:45, or 2h30m as a duration"

  public static func line(query: String, status: Status, now: Int, calendar: Calendar) -> Line {
    let q = String(query.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
    if q.isEmpty {
      if status.active {
        return Line(title: "Stop Keeping Awake", subtitle: statusText(status, now: now, calendar: calendar), icon: "off",
          choice: .off)
      }
      return Line(title: "Keep Awake Indefinitely", subtitle: "Specify " + examples, icon: "on", choice: .indefinite)
    }
    if let (h, m) = parseClock(q) {
      let ts = nextOccurrence(h, m, now: now, calendar: calendar)
      return Line(title: "Keep Awake until " + endLabel(ts, now: now, calendar: calendar),
        subtitle: "In " + humanSpan(ts - now), icon: "clock", choice: .until(ts))
    }
    if let secs = parseDuration(q) ?? parseBareHours(q) {
      return Line(title: "Keep Awake for " + humanSpan(secs),
        subtitle: "Ends " + endLabel(now + secs, now: now, calendar: calendar), icon: "duration", choice: .span(secs))
    }
    if isIncomplete(q) {
      return Line(title: "Keep typing", subtitle: examples, icon: "hint", choice: nil)
    }
    return Line(title: "Not a time or duration", subtitle: examples, icon: "error", choice: nil)
  }

  /// The live status under Stop Keeping Awake.
  public static func statusText(_ s: Status, now: Int, calendar: Calendar) -> String {
    guard s.active else { return "Currently off. Stays awake for good." }
    guard let expiry = s.expiry else { return "On, indefinite" }
    let rem = expiry - now
    if rem <= 0 { return "Ending" }
    let hh = endLabel(expiry, now: now, calendar: calendar)
    let mins = rem / 60
    if mins < 60 { return "On until \(hh), \(max(1, mins)) min left" }
    return "On until " + hh
  }

  /// The end as the time alone today, tomorrow and the time the next day, the whole date past that.
  static func endLabel(_ ts: Int, now: Int, calendar: Calendar) -> String {
    let end = Date(timeIntervalSince1970: TimeInterval(ts))
    let start = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(now)))
    let span = calendar.startOfDay(for: end).timeIntervalSince(start)
    let days = Int((span / 86400 + 0.5).rounded(.down))
    if days <= 0 { return format("HH:mm", end, calendar) }
    if days == 1 { return "tomorrow " + format("HH:mm", end, calendar) }
    return format("EEE dd MMM yyyy, HH:mm", end, calendar)
  }

  static func format(_ pattern: String, _ date: Date, _ calendar: Calendar) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = calendar
    f.timeZone = calendar.timeZone
    f.dateFormat = pattern
    return f.string(from: date)
  }

  /// The next time the clock reads h:m, tomorrow once it already passed today.
  static func nextOccurrence(_ h: Int, _ m: Int, now: Int, calendar: Calendar) -> Int {
    let today = calendar.date(bySettingHour: h, minute: m, second: 0,
      of: Date(timeIntervalSince1970: TimeInterval(now))) ?? Date(timeIntervalSince1970: TimeInterval(now))
    var ts = Int(today.timeIntervalSince1970)
    if ts <= now { ts += 86400 }
    return ts
  }

  static func digits(_ s: Substring) -> Bool { !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isNumber } }

  /// HH:MM or H:MM, hours to 23, two minute digits, the colon required.
  static func parseClock(_ q: String) -> (Int, Int)? {
    let parts = q.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2, digits(parts[0]), digits(parts[1]),
      let h = Int(parts[0]), let m = Int(parts[1]), h <= 23, m <= 59 else { return nil }
    return (h, m)
  }

  /// A count of seconds within the rail, nil past it or for nothing.
  static func railed(_ secs: Int?) -> Int? {
    guard let secs, secs > 0, secs <= maxSecs else { return nil }
    return secs
  }

  /// At most one hours part before at most one minutes part, minutes under 60 beside hours.
  static func parseDuration(_ q: String) -> Int? {
    if q.hasSuffix("m"), let hAt = q.firstIndex(of: "h") {
      let h = q[..<hAt], m = q[q.index(after: hAt)..<q.index(before: q.endIndex)]
      guard digits(h), digits(m) else { return nil }
      guard let mins = Int(m) else { return nil }
      if mins > 59 { return nil }
      return railed(Int(h).flatMap { mul($0, 3600) }.flatMap { add($0, mins * 60) })
    }
    if q.hasSuffix("h") {
      let h = q.dropLast()
      guard digits(h) else { return nil }
      return railed(Int(h).flatMap { mul($0, 3600) })
    }
    if q.hasSuffix("m") {
      let m = q.dropLast()
      guard digits(m) else { return nil }
      return railed(Int(m).flatMap { mul($0, 60) })
    }
    return nil
  }

  /// A bare number of hours, once it cannot be a clock hour.
  static func parseBareHours(_ q: String) -> Int? {
    let s = Substring(q)
    guard digits(s) else { return nil }
    guard let n = Int(s) else { return nil }
    if n < 24 { return nil }
    guard let secs = mul(n, 3600), secs <= maxSecs else { return nil }
    return secs
  }

  /// A bare hour under 24, or a clock with its colon and not yet both minute digits.
  static func isIncomplete(_ q: String) -> Bool {
    let s = Substring(q)
    if digits(s) { return Int(s).map { $0 < 24 } ?? false }
    let parts = q.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count <= 1, digits(parts[0]),
      parts[1].isEmpty || digits(parts[1]), let hh = Int(parts[0]) else { return false }
    return hh <= 23
  }

  /// 1h 30m, 2h or 45m.
  static func humanSpan(_ secs: Int) -> String {
    let h = secs / 3600, m = (secs % 3600) / 60
    if h > 0 && m > 0 { return "\(h)h \(m)m" }
    if h > 0 { return "\(h)h" }
    return "\(m)m"
  }

  static func mul(_ a: Int, _ b: Int) -> Int? {
    let (v, o) = a.multipliedReportingOverflow(by: b)
    return o ? nil : v
  }

  static func add(_ a: Int, _ b: Int) -> Int? {
    let (v, o) = a.addingReportingOverflow(b)
    return o ? nil : v
  }
}
