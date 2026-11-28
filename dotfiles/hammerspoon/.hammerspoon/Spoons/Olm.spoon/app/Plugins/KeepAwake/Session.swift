// Keep awake's session, the port of plugins/caffeinate/engine.lua. It holds macOS's display idle
// assertion, the one hs.caffeinate's displayIdle takes, so the screen stays on and not only the
// system, either for good or until a moment, and owns the one timer that ends a timed hold. The
// session is kept in its state folder on every change and restored when the app starts, an
// indefinite hold indefinite, a timed one with what is left and one whose end passed while the app
// was not running ended, as the Lua engine restores across a reload.
//
// On its first start it takes over a session Hammerspoon kept, the caffeinateSession key hs.settings
// wrote, and removes that key, so Hammerspoon's engine finds nothing to hold on its next load and a
// session is held by one of the two, never both.

import Foundation
import IOKit.pwr_mgt

public actor KeepAwakeSession {
  public typealias Status = KeepAwakeGrammar.Status

  private let file: URL
  private let now: @Sendable () -> Int
  private let onChange: @Sendable () -> Void
  private var status = Status.off
  private var assertion: IOPMAssertionID?
  private var timer: DispatchSourceTimer?
  private var started = false

  /// store, keep awake's own folder in Olm's state. onChange is told after a change the person did
  /// not make, a timed hold ending, so an open list redraws.
  public init(store: URL, now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) },
              onChange: @escaping @Sendable () -> Void = {}) {
    file = store.appendingPathComponent("session.json")
    self.now = now
    self.onChange = onChange
  }

  public func current() -> Status { status }

  /// Restores the kept session, once.
  public func start() {
    guard !started else { return }
    started = true
    let saved = read() ?? Self.takeHammerspoons()
    guard let saved, saved.active else {
      hold(false)
      status = .off
      write()
      return
    }
    guard let expiry = saved.expiry else {
      hold(true)
      status = Status(active: true)
      write()
      return
    }
    let remaining = expiry - now()
    if remaining <= 0 {
      hold(false)
      status = .off
      write()
      return
    }
    hold(true)
    status = Status(active: true, expiry: expiry)
    arm(remaining)
    write()
  }

  public func keepIndefinitely() {
    cancel()
    hold(true)
    status = Status(active: true)
    write()
  }

  public func keepUntil(_ ts: Int) {
    cancel()
    hold(true)
    status = Status(active: true, expiry: ts)
    arm(ts - now())
    write()
  }

  public func keepFor(_ secs: Int) { keepUntil(now() + secs) }

  public func disable() {
    cancel()
    hold(false)
    status = .off
    write()
  }

  // MARK: The assertion and the timer

  private func hold(_ on: Bool) {
    if on, assertion == nil {
      var id = IOPMAssertionID(0)
      let made = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Olm Keep Awake" as CFString, &id)
      if made == kIOReturnSuccess { assertion = id } else { NSLog("Olm keep awake: the assertion was refused, %d", made) }
    } else if !on, let id = assertion {
      IOPMAssertionRelease(id)
      assertion = nil
    }
  }

  /// The end of a timed hold, on the wall clock, so a Mac asleep past it ends the hold on waking.
  private func arm(_ seconds: Int) {
    let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
    t.schedule(wallDeadline: .now() + .seconds(max(0, seconds)))
    t.setEventHandler { [weak self] in
      guard let self else { return }
      Task { await self.ended() }
    }
    timer = t
    t.resume()
  }

  private func ended() {
    guard let expiry = status.expiry, expiry <= now() else { return }
    disable()
    onChange()
  }

  private func cancel() {
    timer?.cancel()
    timer = nil
  }

  // MARK: What is kept

  private func read() -> Status? {
    guard let data = try? Data(contentsOf: file),
      let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
    return Status(active: o["active"] as? Bool ?? false, expiry: (o["expiry"] as? NSNumber)?.intValue)
  }

  private func write() {
    var o: [String: Any] = ["active": status.active]
    if let expiry = status.expiry { o["expiry"] = expiry }
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let data = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) {
      try? data.write(to: file, options: .atomic)
    }
  }

  /// The session Hammerspoon's keep awake kept, taken once and removed from its preferences.
  static func takeHammerspoons() -> Status? {
    let hammerspoon = "org.hammerspoon.Hammerspoon" as CFString, hammerspoonKey = "caffeinateSession" as CFString
    guard let o = CFPreferencesCopyAppValue(hammerspoonKey, hammerspoon) as? [String: Any] else { return nil }
    CFPreferencesSetAppValue(hammerspoonKey, nil, hammerspoon)
    CFPreferencesAppSynchronize(hammerspoon)
    let active = (o["active"] as? NSNumber)?.boolValue ?? false
    return Status(active: active, expiry: (o["expiry"] as? NSNumber)?.intValue)
  }
}
