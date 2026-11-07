// A probe of the main thread, with nothing of Lua in it, so the drawing code notes what held the
// thread whichever side drives the panel. Entry.swift's perfStart, perfRead and perfStop are its Lua
// face inside Hammerspoon.

import QuartzCore

// Off until started. A timer in the common modes, which run during a scroll's tracking too, notes
// every gap between its ticks long enough to drop frames, and every call into the driver is timed,
// so a stall shows what held the thread or that the driver was not it. perfRead answers the notes
// since the last read.
enum Perf {
  static var on = false
  static var notes: [String] = []
  private static var timer: Timer?
  private static var last: CFTimeInterval = 0
  private static var origin: CFTimeInterval = 0

  static func start() {
    stop()
    on = true
    notes = []
    origin = CACurrentMediaTime()
    last = origin
    let t = Timer(timeInterval: 1.0 / 120, repeats: true) { _ in
      let now = CACurrentMediaTime()
      let gap = (now - last) * 1000
      if gap > 25 { note(String(format: "stall %.0f ms", gap), at: last) }
      last = now
    }
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  static func stop() {
    timer?.invalidate()
    timer = nil
    on = false
  }

  // Times one call from Lua into the library, noted when it held the thread for more than a
  // millisecond, so a stall says which call it was.
  static func timed(_ name: String, _ body: () -> Int32) -> Int32 {
    guard on else { return body() }
    let start = CACurrentMediaTime()
    let answer = body()
    let took = (CACurrentMediaTime() - start) * 1000
    if took > 1 { note(String(format: "native %@ %.1f ms", name, took), at: start) }
    return answer
  }

  static func note(_ text: String, at time: CFTimeInterval = CACurrentMediaTime()) {
    guard on else { return }
    notes.append(String(format: "%7.0f ms  ", (time - origin) * 1000) + text)
    if notes.count > 400 { notes.removeFirst(notes.count - 400) }
  }
}
