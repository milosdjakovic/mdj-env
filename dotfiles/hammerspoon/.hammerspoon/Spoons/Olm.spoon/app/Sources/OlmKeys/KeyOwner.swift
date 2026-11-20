// Olm.app owning a leader's modifier combinations, step 5.3 of docs/PLAN-STANDALONE.md,
// docs/DESIGN-APP-KEYS.md. META first. Hammerspoon keeps the leader's held key and its sheet, and
// lets the app claim the combinations of its modifier half when the app asks, releaseKeys, while
// the socket is up. The app claims each through Carbon, resolves a press with the port of the Lua
// leader's resolver, gates included, and runs the row in Hammerspoon by its id, runKey, repeating a
// row that repeats on the chord engine's own schedule, KeyRepeat. A combination it cannot claim hands
// that whole leader back, reclaimKeys, and a socket gone drops every claim, Hammerspoon taking its
// keys back as it sees the socket go.
//
// Main thread only.

import AppKit
import Foundation

@MainActor
public final class KeyOwner {
  /// What the owner asks of Hammerspoon, each over the bridge.
  public struct Words: Sendable {
    public var release: @Sendable ([String]) async -> [String]
    public var reclaim: @Sendable ([String]) async -> Void
    public var run: @Sendable (String, Int) async -> Void
    public init(release: @escaping @Sendable ([String]) async -> [String], reclaim: @escaping @Sendable ([String]) async -> Void,
      run: @escaping @Sendable (String, Int) async -> Void) {
      self.release = release
      self.reclaim = reclaim
      self.run = run
    }
  }

  private struct Claim {
    let leader: String
    let code: Int
    let mods: Set<Mod>
  }

  private let words: Words
  private let gate: (String) -> Bool
  private let log: (String) -> Void
  private lazy var keys = HotKeys { [weak self] id, down in self?.heard(id, down) }
  private var claims: [UInt32: Claim] = [:]
  private var resolver = Resolver(keymap: Keymap(leaders: [], rows: []))
  // The press repeating now, by its claim, and the count of takes, so a take overtaken by a newer
  // one, or by a drop, changes nothing.
  private var repeating: (id: UInt32, generation: Int)?
  private var generation = 0
  private var take = 0

  public init(words: Words, gate: @escaping (String) -> Bool, log: @escaping (String) -> Void) {
    self.words = words
    self.gate = gate
    self.log = log
  }

  /// The leaders the app holds now.
  public var owned: [String] { Array(Set(claims.values.map(\.leader))).sorted() }

  /// Asks for the leaders the keymap hands the app and claims what Hammerspoon released, every claim
  /// before it dropped first, so a keymap read afresh after a load is what is claimed.
  public func take(_ keymap: Keymap) async {
    take += 1
    let mine = take
    drop()
    resolver = Resolver(keymap: keymap)
    let wanted = keymap.appKeys.filter { name in keymap.leaders.contains { $0.name == name && !($0.mods ?? []).isEmpty } }
    guard !wanted.isEmpty else { return }
    let released = await words.release(wanted)
    guard mine == take else { return }
    var refused: [String] = []
    for name in released {
      guard let leader = keymap.leaders.first(where: { $0.name == name }), let base = leader.mods else { continue }
      var made: [UInt32] = []
      var failed = false
      for combo in Self.combinations(keymap, leader: leader, base: base) {
        if let id = keys.claim(code: combo.code, mods: combo.mods) {
          claims[id] = Claim(leader: name, code: combo.code, mods: combo.mods)
          made.append(id)
        } else {
          failed = true
          log("\(name)'s key \(combo.code) on \(combo.mods.map(\.rawValue).sorted()) could not be claimed, so Hammerspoon keeps \(name)")
          break
        }
      }
      if failed {
        for id in made { keys.release(id); claims[id] = nil }
        refused.append(name)
      } else {
        log("the app holds \(name)'s \(made.count) combination(s)")
      }
    }
    if !refused.isEmpty { await words.reclaim(refused) }
  }

  /// Every claim let go, for a socket gone.
  public func drop() {
    generation += 1
    repeating = nil
    keys.releaseAll()
    claims = [:]
  }

  /// Each combination a leader's modifier half claims, its base set united with a row's own, a catch
  /// all on the base set alone, and a row asking for a modifier the base set holds left to the held
  /// key on a composite, as lib/leader/triggers/modifier.lua claims them.
  public nonisolated static func combinations(_ keymap: Keymap, leader: KeyLeader, base: Set<Mod>) -> [(code: Int, mods: Set<Mod>)] {
    var seen = Set<String>()
    var out: [(code: Int, mods: Set<Mod>)] = []
    for row in keymap.rows where row.leader == leader.name {
      let own = row.mods ?? []
      if leader.composite, !own.isDisjoint(with: base) { continue }
      let mods = base.union(own)
      let key = "\(row.keyCode)|\(mods.map(\.rawValue).sorted())"
      if seen.insert(key).inserted { out.append((row.keyCode, mods)) }
    }
    return out
  }

  private func heard(_ id: UInt32, _ down: Bool) {
    guard let claim = claims[id] else { return }
    guard down else {
      if repeating?.id == id { repeating = nil }
      return
    }
    guard case .runs(let row) = resolver.resolve(code: claim.code, mods: claim.mods, held: [], gate: gate) else { return }
    let words = self.words
    Task { await words.run(row.id, 0) }
    // A press that does not repeat leaves a repeat already running alone, as the chord engine does,
    // and one that repeats takes it over.
    guard row.repeats else { return }
    generation += 1
    let mine = generation
    repeating = (id, mine)
    schedule(id, row.id, depth: 1, after: NSEvent.keyRepeatDelay, generation: mine)
  }

  // One repeat, a beat after the last run returned, while its key is still the one held.
  private func schedule(_ id: UInt32, _ row: String, depth: Int, after: TimeInterval, generation mine: Int) {
    DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.repeating?.id == id, self.repeating?.generation == mine else { return }
        let words = self.words
        Task { @MainActor [weak self] in
          await words.run(row, depth)
          self?.schedule(id, row, depth: depth + 1, after: NSEvent.keyRepeatInterval, generation: mine)
        }
      }
    }
  }
}
