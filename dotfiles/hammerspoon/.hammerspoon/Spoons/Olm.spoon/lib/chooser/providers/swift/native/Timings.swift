// The three timings of docs/PLAN-STANDALONE.md, step 1.3f, measured inside the panel itself, so the
// Lua file search inside Hammerspoon and Olm.app's are timed by the same code on the same clock,
// whichever side drives the panel.
//
//   echo     a key down to the commit that draws the field with that key in it
//   rows     a key down to the commit that draws the first rows sent after it
//   settled  a key down to the commit that draws the last rows sent before the next key
//   stall    the longest gap between ticks of a timer on the main thread while the list is open
//
// A commit is the run loop's turn ending, the before waiting observer ordered after Core
// Animation's own, which is when what was drawn reaches the render server. A key whose rows did
// not change sends no rows, so it has a rows time only when its answer changed what is drawn. The
// clock is the system uptime, the one NSEvent's timestamp is on.
//
// It is off unless `~/.olm/run/timings` exists, read on every open, so neither process pays for it
// outside a trial. Each open writes one line to `~/.olm/log/timings.jsonl` when it closes, the
// process, the list by its placeholder, and every sample in milliseconds.

import AppKit

enum Timings {
  private static var on = false
  private static var openedAt: TimeInterval = 0
  private static var echo: [Double] = []
  private static var rows: [Double] = []
  private static var settled: [Double] = []
  private static var keyAt: TimeInterval?
  private static var echoOwed = false
  private static var rowsOwed = false
  private static var firstRowsTaken = false
  private static var lastRowsDrawn: TimeInterval?
  private static var timer: Timer?
  private static var lastTick: TimeInterval = 0
  private static var longest: Double = 0
  private static var stalls = 0
  private static var observer: CFRunLoopObserver?

  private static var home: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".olm") }
  private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

  static func begin() {
    if on { finish(list: nil) }
    guard FileManager.default.fileExists(atPath: home.appendingPathComponent("run/timings").path) else { return }
    on = true
    openedAt = now
    echo = []; rows = []; settled = []
    keyAt = nil; echoOwed = false; rowsOwed = false; firstRowsTaken = false; lastRowsDrawn = nil
    longest = 0; stalls = 0
    lastTick = now
    let t = Timer(timeInterval: 1.0 / 120, repeats: true) { _ in
      let at = now
      let gap = (at - lastTick) * 1000
      if gap > longest { longest = gap }
      if gap > 25 { stalls += 1 }
      lastTick = at
    }
    RunLoop.main.add(t, forMode: .common)
    timer = t
    if observer == nil {
      // Core Animation commits at order 2000000, so this runs after what was drawn is committed.
      let o = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 2_100_000) { _, _ in
        committed()
      }
      CFRunLoopAddObserver(CFRunLoopGetMain(), o, .commonModes)
      observer = o
    }
  }

  /// A key changed the field's text, at the key down's own time when the change came from one.
  static func typed(at: TimeInterval?) {
    guard on else { return }
    closeSettled()
    keyAt = at ?? now
    echoOwed = true
    rowsOwed = false
    firstRowsTaken = false
  }

  /// Rows were handed to the list.
  static func rowsSent() {
    guard on, keyAt != nil else { return }
    rowsOwed = true
  }

  private static func committed() {
    guard on, let key = keyAt else { return }
    let at = now
    if echoOwed {
      echo.append(ms(at - key))
      echoOwed = false
    }
    if rowsOwed {
      if !firstRowsTaken {
        rows.append(ms(at - key))
        firstRowsTaken = true
      }
      lastRowsDrawn = at
      rowsOwed = false
    }
  }

  private static func closeSettled() {
    if let key = keyAt, let drawn = lastRowsDrawn { settled.append(ms(drawn - key)) }
    lastRowsDrawn = nil
  }

  /// The list closed, list naming it by its placeholder.
  static func finish(list: String?) {
    guard on else { return }
    committed()
    closeSettled()
    on = false
    timer?.invalidate()
    timer = nil
    let line: [String: Any] = [
      "at": ISO8601DateFormatter().string(from: Date()),
      "process": ProcessInfo.processInfo.processName,
      "list": list ?? "",
      "openMs": ms(now - openedAt),
      "echo": echo, "rows": rows, "settled": settled,
      "stallMs": (longest * 10).rounded() / 10, "stalls": stalls,
    ]
    guard var data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
    data.append(0x0A)
    let log = home.appendingPathComponent("log/timings.jsonl")
    try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let handle = try? FileHandle(forWritingTo: log) {
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
    } else {
      try? data.write(to: log)
    }
  }

  private static func ms(_ seconds: TimeInterval) -> Double { (seconds * 10_000).rounded() / 10 }
}
