// Combinations of real modifiers claimed for Olm.app through Carbon's RegisterEventHotKey, step 5.3
// of docs/PLAN-STANDALONE.md, docs/DESIGN-APP-KEYS.md. It is the interface hs.hotkey itself stands on,
// needs no grant, and swallows the key it claims, so a claimed chord reaches no app. One claim per
// combination, a press and a release told by its number.
//
// Main thread only, since Carbon delivers its events on the main run loop.

import Carbon.HIToolbox
import Foundation

@MainActor
public final class HotKeys {
  public typealias Handler = @MainActor (_ id: UInt32, _ down: Bool) -> Void

  private var refs: [UInt32: EventHotKeyRef] = [:]
  // Every claim made, kept so a suspend can let all of them go and a resume claim them again.
  private var specs: [UInt32: (code: Int, mods: Set<Mod>, exclusive: Bool)] = [:]
  private var suspended = false
  private var next: UInt32 = 1
  private var handlerRef: EventHandlerRef?
  private let handler: Handler
  // 'Olm ' as a four character code, naming the app's own claims.
  private static let signature: OSType = 0x4F6C_6D20

  public init(handler: @escaping Handler) {
    self.handler = handler
  }

  /// Claims a key code on a set of modifiers, answering its number, or nil where another program
  /// holds that combination already. Exclusive, as hs.hotkey claims every key, so no other program
  /// and not macOS itself answers it too, a tap of fn showing macOS's own input source picker beside
  /// Olm's cycle otherwise, Milos's report on 2026-11-23. A claim that is not exclusive lets macOS
  /// answer as well, and a second program claim the same combination.
  public func claim(code: Int, mods: Set<Mod>, exclusive: Bool = true) -> UInt32? {
    installIfNeeded()
    let id = next
    next += 1
    if !suspended {
      guard let ref = register(id, code: code, mods: mods, exclusive: exclusive) else { return nil }
      refs[id] = ref
    }
    specs[id] = (code, mods, exclusive)
    return id
  }

  private func register(_ id: UInt32, code: Int, mods: Set<Mod>, exclusive: Bool) -> EventHotKeyRef? {
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(UInt32(code), Self.carbon(mods), EventHotKeyID(signature: Self.signature, id: id),
      GetEventDispatcherTarget(), exclusive ? OptionBits(kEventHotKeyExclusive) : 0, &ref)
    return status == noErr ? ref : nil
  }

  /// Lets every claim go for a while and keeps them, so a key recorder in the app hears a
  /// combination the app holds, every key claimed again by resume.
  public func suspend() {
    guard !suspended else { return }
    suspended = true
    for ref in refs.values { UnregisterEventHotKey(ref) }
    refs = [:]
  }

  /// Claims again every combination suspend let go, a claim another program took meanwhile left out.
  public func resume() {
    guard suspended else { return }
    suspended = false
    for (id, spec) in specs {
      if let ref = register(id, code: spec.code, mods: spec.mods, exclusive: spec.exclusive) { refs[id] = ref }
    }
  }

  /// Lets one claim go.
  public func release(_ id: UInt32) {
    if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
    specs[id] = nil
  }

  /// Lets every claim go.
  public func releaseAll() {
    for ref in refs.values { UnregisterEventHotKey(ref) }
    refs = [:]
    specs = [:]
  }

  static func carbon(_ mods: Set<Mod>) -> UInt32 {
    var out: UInt32 = 0
    if mods.contains(.cmd) { out |= UInt32(cmdKey) }
    if mods.contains(.shift) { out |= UInt32(shiftKey) }
    if mods.contains(.alt) { out |= UInt32(optionKey) }
    if mods.contains(.ctrl) { out |= UInt32(controlKey) }
    return out
  }

  private func installIfNeeded() {
    guard handlerRef == nil else { return }
    var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                 EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
    let me = Unmanaged.passUnretained(self).toOpaque()
    InstallEventHandler(GetEventDispatcherTarget(), { _, event, me in
      guard let event, let me else { return OSStatus(eventNotHandledErr) }
      var hot = EventHotKeyID()
      let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hot)
      guard status == noErr, hot.signature == HotKeys.signature else { return OSStatus(eventNotHandledErr) }
      let down = GetEventKind(event) == UInt32(kEventHotKeyPressed)
      let keys = Unmanaged<HotKeys>.fromOpaque(me).takeUnretainedValue()
      MainActor.assumeIsolated { keys.handler(hot.id, down) }
      return noErr
    }, types.count, &types, me, &handlerRef)
  }
}
