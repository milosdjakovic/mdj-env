// Hearing the keyboard, docs/DESIGN-APP-KEYS.md. A listen only event tap at the HID level, the
// earliest place a key is a keyboard event, after hidutil's remap and kanata and before
// Hammerspoon's own tap and hotkeys, so it hears a key Hammerspoon then swallows or claims. A
// listen only tap is handed a copy and can neither change nor delay anything. It runs on a thread
// of its own with its own run loop, so it never waits on the main thread nor the main thread on it.
// It needs the Input Monitoring grant.

import CoreGraphics
import Foundation

public struct KeyEvent: Sendable, Equatable {
  public enum Kind: Sendable, Equatable { case down, up, flags }

  public var kind: Kind
  public var code: Int
  public var mods: Set<Mod>
  public var autorepeat: Bool
  /// Seconds on the monotonic clock.
  public var at: Double

  public init(kind: Kind, code: Int, mods: Set<Mod>, autorepeat: Bool, at: Double) {
    self.kind = kind
    self.code = code
    self.mods = mods
    self.autorepeat = autorepeat
    self.at = at
  }

  static func mods(_ flags: CGEventFlags) -> Set<Mod> {
    var out: Set<Mod> = []
    if flags.contains(.maskShift) { out.insert(.shift) }
    if flags.contains(.maskControl) { out.insert(.ctrl) }
    if flags.contains(.maskAlternate) { out.insert(.alt) }
    if flags.contains(.maskCommand) { out.insert(.cmd) }
    return out
  }
}

public final class KeyTap: @unchecked Sendable {
  private let handle: @Sendable (KeyEvent) -> Void
  private let log: @Sendable (String) -> Void
  private let report: @Sendable (Bool) -> Void
  private var thread: Thread?
  // Read and written on the tap's own thread alone.
  private var port: CFMachPort?
  private var saidDenied = false

  /// report is told whether macOS lets the app hear the keyboard at every try, for the grants
  /// file the setup's prober reads.
  public init(handle: @escaping @Sendable (KeyEvent) -> Void, log: @escaping @Sendable (String) -> Void,
              report: @escaping @Sendable (Bool) -> Void = { _ in }) {
    self.handle = handle
    self.log = log
    self.report = report
  }

  /// Whether this app may hear the keyboard, macOS's Input Monitoring.
  public static var allowed: Bool { CGPreflightListenEventAccess() }

  /// Asks macOS for Input Monitoring, which shows its own prompt once and lists Olm in System
  /// Settings, Privacy and Security, Input Monitoring.
  public static func ask() { _ = CGRequestListenEventAccess() }

  /// Starts the tap's thread, which keeps trying every ten seconds until the grant is given.
  public func start() {
    guard thread == nil else { return }
    let t = Thread { [self] in run() }
    t.name = "olm.keys.tap"
    t.qualityOfService = .userInteractive
    thread = t
    t.start()
  }

  private func run() {
    while port == nil {
      report(Self.allowed)
      if let made = makeTap() {
        port = made
        let source = CFMachPortCreateRunLoopSource(nil, made, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: made, enable: true)
        log("hearing the keyboard")
        CFRunLoopRun()
        return
      }
      if !saidDenied {
        saidDenied = true
        log("Olm.app cannot hear the keyboard until Input Monitoring is allowed for it, so the keys are not shadowed")
      }
      Thread.sleep(forTimeInterval: 10)
    }
  }

  private func makeTap() -> CFMachPort? {
    let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
    let me = Unmanaged.passUnretained(self).toOpaque()
    return CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .listenOnly,
      eventsOfInterest: CGEventMask(mask), callback: { _, type, event, info in
        guard let info else { return Unmanaged.passUnretained(event) }
        Unmanaged<KeyTap>.fromOpaque(info).takeUnretainedValue().take(type, event)
        return Unmanaged.passUnretained(event)
      }, userInfo: me)
  }

  private func take(_ type: CGEventType, _ event: CGEvent) {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      // macOS turns a tap off that it judges slow, so it is turned on again and said.
      if let port { CGEvent.tapEnable(tap: port, enable: true) }
      log("the key tap was turned off by macOS and on again")
      return
    case .keyDown, .keyUp, .flagsChanged:
      let kind: KeyEvent.Kind = type == .keyDown ? .down : type == .keyUp ? .up : .flags
      handle(KeyEvent(kind: kind, code: Int(event.getIntegerValueField(.keyboardEventKeycode)),
        mods: KeyEvent.mods(event.flags), autorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
        at: ProcessInfo.processInfo.systemUptime))
    default:
      return
    }
  }
}
