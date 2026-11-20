// How a held key repeats once the app claims it, step 5.3 of docs/PLAN-STANDALONE.md, a port of
// lib/chordkey.lua's driven repeat, fixture 0.3f in test/fixtures/keys/repeat.json. The press runs
// at once with depth 0 and the repeat is armed then, the first repeat a delay after the press, and
// every later one an interval after the previous run returned, so a slow run repeats slower and
// never in a burst. The two beats are the machine's own, Delay Until Repeat and Key Repeat.

import Foundation

public enum KeyRepeat {
  /// The runs a hold makes, each its start and its depth, the press included, for a run taking
  /// handler seconds and a key held for hold. The schedule the live repeat keeps, written out for
  /// the fixture.
  public static func schedule(delay: Double, interval: Double, hold: Double, handler: Double) -> [(at: Double, depth: Int)] {
    var runs: [(at: Double, depth: Int)] = [(0, 0)]
    var due = delay
    var depth = 1
    // The press runs on its own, so the first repeat waits only for the delay.
    var free = 0.0
    while due < hold {
      let at = max(due, free)
      runs.append((at, depth))
      free = at + handler
      due = free + interval
      depth += 1
    }
    return runs
  }
}
