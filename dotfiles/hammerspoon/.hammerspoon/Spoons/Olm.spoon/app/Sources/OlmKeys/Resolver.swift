// What a press runs, ported from lib/leader.lua's _resolve and the three triggers under
// lib/leader/triggers, docs/DESIGN-APP-KEYS.md. It is pure, handed the keymap, which held function
// keys are down and how each gate answers, so the check drives it with no keyboard.
//
// The global layer only. A list's own keys are the list's, answered by the app's own lists, and
// Hammerspoon's lists are Hammerspoon's until their keys move.

import Foundation

public enum Resolution: Sendable, Equatable {
  /// The row that runs.
  case runs(KeyRow)
  /// A key some row binds on whose every matching row is gated off, swallowed as a no op.
  case swallowed
}

public struct Resolver: Sendable {
  public var keymap: Keymap

  public init(keymap: Keymap) {
    self.keymap = keymap
  }

  /// The resolution of a key pressed with these real modifiers while these function keys are held,
  /// nil for a key nothing binds, which passes through. gate answers a row's predicate, an unknown
  /// name answering true as the Lua leader does.
  public func resolve(code: Int, mods: Set<Mod>, held: Set<Int>, gate: (String) -> Bool) -> Resolution? {
    for leader in keymap.leaders {
      // A held leader whose key is down hears every key under it, with the modifiers held.
      if leader.held, let fkey = leader.keyCode, held.contains(fkey), code != fkey {
        if let r = resolve(rows(on: leader.name, code: code), leader: leader, present: mods, gate: gate) { return r }
        continue
      }
      // A leader of modifiers claims its base set united with a row's own, exactly, so a catch all
      // is claimed on the base set alone. The modifier half of a composite leaves a row asking for a
      // modifier the base set holds to the held half.
      if let base = leader.mods, !base.isEmpty, base.isSubset(of: mods) {
        let sub = mods.subtracting(base)
        let claimed = rows(on: leader.name, code: code).filter { row in
          guard let rm = row.mods else { return sub.isEmpty }
          if leader.composite, !rm.isDisjoint(with: base) { return false }
          return rm == sub
        }
        if let r = resolve(claimed, leader: leader, present: sub, gate: gate) { return r }
      }
    }
    // A plain combo, claimed on exactly its own modifiers.
    let plain = rows(on: nil, code: code).filter { ($0.mods ?? []) == mods }
    return resolve(plain, leader: KeyLeader(name: "", held: false, keyCode: nil, mods: [], ranked: false),
      present: mods, gate: gate)
  }

  private func rows(on leader: String?, code: Int) -> [KeyRow] {
    keymap.rows.filter { $0.leader == leader && $0.keyCode == code }
  }

  // The global pass of lib/leader.lua's _resolve. An exact match on the modifiers beats a catch all.
  // On a ranked leader every eligible row competes and the best priority wins, the first among
  // equals, and a gated one drops out of its tier. On any other the first matching exact row
  // answers and a gated one is swallowed there, and among catch alls the last passing one answers,
  // a gated one after it clearing it. A key whose every matching row is gated off is swallowed.
  func resolve(_ list: [KeyRow], leader: KeyLeader, present: Set<Mod>, gate: (String) -> Bool) -> Resolution? {
    guard !list.isEmpty else { return nil }
    func passes(_ row: KeyRow) -> Bool { row.gate.map(gate) ?? true }
    if leader.ranked {
      var gated = false
      var exact: KeyRow?, exactP = -Double.infinity
      var catchAll: KeyRow?, catchP = -Double.infinity
      for row in list where row.mods == nil || row.mods == present {
        guard passes(row) else {
          gated = true
          continue
        }
        if row.mods != nil {
          if row.priority > exactP { exact = row; exactP = row.priority }
        } else if row.priority > catchP {
          catchAll = row
          catchP = row.priority
        }
      }
      if let chosen = exact ?? catchAll { return .runs(chosen) }
      return gated ? .swallowed : nil
    }
    var catchAll: KeyRow?
    var catchGated = false
    for row in list {
      if let rm = row.mods {
        if rm == present { return passes(row) ? .runs(row) : .swallowed }
      } else if passes(row) {
        catchAll = row
        catchGated = false
      } else {
        catchAll = nil
        catchGated = true
      }
    }
    if let catchAll { return .runs(catchAll) }
    return catchGated ? .swallowed : nil
  }
}
