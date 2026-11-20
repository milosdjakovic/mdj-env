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
  private var next: UInt32 = 1
  private var handlerRef: EventHandlerRef?
  private let handler: Handler
  // 'Olm ' as a four character code, naming the app's own claims.
  private static let signature: OSType = 0x4F6C_6D20

  public init(handler: @escaping Handler) {
    self.handler = handler
  }

  /// Claims a key code on a set of modifiers, answering its number, or nil where another program
  /// holds that combination already.
  public func claim(code: Int, mods: Set<Mod>) -> UInt32? {
    installIfNeeded()
    let id = next
    next += 1
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(UInt32(code), Self.carbon(mods), EventHotKeyID(signature: Self.signature, id: id),
      GetEventDispatcherTarget(), 0, &ref)
    guard status == noErr, let ref else { return nil }
    refs[id] = ref
    return id
  }

  /// Lets one claim go.
  public func release(_ id: UInt32) {
    if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
  }

  /// Lets every claim go.
  public func releaseAll() {
    for ref in refs.values { UnregisterEventHotKey(ref) }
    refs = [:]
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
