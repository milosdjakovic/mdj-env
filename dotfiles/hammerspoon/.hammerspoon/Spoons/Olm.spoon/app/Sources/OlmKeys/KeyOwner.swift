// Olm.app owning a leader's modifier combinations, step 5.3 of docs/PLAN-STANDALONE.md,
// docs/DESIGN-APP-KEYS.md. META first. Hammerspoon keeps the leader's held key and its sheet, and
// lets the app claim the combinations of its modifier half when the app asks, releaseKeys, while
// the socket is up. The app claims each through Carbon, resolves a press with the port of the Lua
// leader's resolver, gates included, and runs the row in Hammerspoon by its id, runKey, repeating a
// row that repeats on the chord engine's own schedule, KeyRepeat. A leader's list keys, Hyper's J and
// K over a list among them, are claimed too, from the combinations Hammerspoon hands back with the
// release, and a press on one goes to Hammerspoon's list pass first, listKey, which runs it while a
// list is open there and answers no otherwise, the global row running then, as _resolve orders the
// two. A combination it cannot claim hands
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
    public var release: @Sendable ([String]) async -> Released
    public var reclaim: @Sendable ([String]) async -> Void
    public var run: @Sendable (String, Int) async -> Void
    /// A press on a list key's combination, the leader, the key, the modifiers beyond the base set
    /// and the depth, answering whether a list ran it and whether that binding repeats.
    public var list: @Sendable (String, Int, Set<Mod>, Int) async -> ListAnswer
    public init(release: @escaping @Sendable ([String]) async -> Released, reclaim: @escaping @Sendable ([String]) async -> Void,
      run: @escaping @Sendable (String, Int) async -> Void,
      list: @escaping @Sendable (String, Int, Set<Mod>, Int) async -> ListAnswer = { _, _, _, _ in ListAnswer() }) {
      self.release = release
      self.reclaim = reclaim
      self.run = run
      self.list = list
    }
  }

  /// What releaseKeys answered, the leaders let go and each one's list key combinations.
  public struct Released: Sendable, Equatable {
    public var leaders: [String]
    public var lists: [String: [ListCombo]]
    public init(leaders: [String], lists: [String: [ListCombo]] = [:]) {
      self.leaders = leaders
      self.lists = lists
    }
  }

  /// A combination a list key sits on, its key and the modifiers it adds to the base set.
  public struct ListCombo: Sendable, Equatable {
    public var code: Int
    public var mods: Set<Mod>
    public init(code: Int, mods: Set<Mod>) {
      self.code = code
      self.mods = mods
    }
  }

  public struct ListAnswer: Sendable, Equatable {
    public var ran: Bool
    public var repeats: Bool
    public init(ran: Bool = false, repeats: Bool = false) {
      self.ran = ran
      self.repeats = repeats
    }
  }

  private struct Claim {
    let leader: String
    let code: Int
    let mods: Set<Mod>
    // The modifiers beyond the leader's base set, which the list pass compares.
    let sub: Set<Mod>
    // Whether a list key sits on it, so a press asks the list pass first.
    let list: Bool
  }

  private let words: Words
  private let gate: (String) -> Bool
  private let log: (String) -> Void
  /// Told what the app holds after every take and drop, each leader with its combinations' count.
  public var onChange: (([String: Int]) -> Void)?
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
    for name in released.leaders {
      guard let leader = keymap.leaders.first(where: { $0.name == name }), let base = leader.mods else { continue }
      var made: [UInt32] = []
      var failed = false
      let lists = released.lists[name] ?? []
      for combo in Self.combinations(keymap, leader: leader, base: base, lists: lists) {
        if let id = keys.claim(code: combo.code, mods: combo.mods) {
          claims[id] = Claim(leader: name, code: combo.code, mods: combo.mods, sub: combo.mods.subtracting(base),
            list: lists.contains { $0.code == combo.code && base.union($0.mods) == combo.mods })
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
    tell()
  }

  private func tell() {
    var held: [String: Int] = [:]
    for claim in claims.values { held[claim.leader, default: 0] += 1 }
    onChange?(held)
  }

  /// Every claim let go, for a socket gone.
  public func drop() {
    generation += 1
    repeating = nil
    keys.releaseAll()
    claims = [:]
    tell()
  }

  /// Each combination a leader's modifier half claims, its base set united with a row's own, a catch
  /// all on the base set alone, and a row asking for a modifier the base set holds left to the held
  /// key on a composite, as lib/leader/triggers/modifier.lua claims them, then each list key
  /// combination not already among them.
  public nonisolated static func combinations(_ keymap: Keymap, leader: KeyLeader, base: Set<Mod>,
    lists: [ListCombo] = []) -> [(code: Int, mods: Set<Mod>)] {
    var seen = Set<String>()
    var out: [(code: Int, mods: Set<Mod>)] = []
    func add(_ code: Int, _ own: Set<Mod>) {
      if leader.composite, !own.isDisjoint(with: base) { return }
      let mods = base.union(own)
      let key = "\(code)|\(mods.map(\.rawValue).sorted())"
      if seen.insert(key).inserted { out.append((code, mods)) }
    }
    for row in keymap.rows where row.leader == leader.name { add(row.keyCode, row.mods ?? []) }
    for combo in lists { add(combo.code, combo.mods) }
    return out
  }

  private func heard(_ id: UInt32, _ down: Bool) {
    guard let claim = claims[id] else { return }
    guard down else {
      if repeating?.id == id { repeating = nil }
      return
    }
    let words = self.words
    guard claim.list else { return global(id, claim) }
    // The list pass first, and the global row only when no list ran the press. The press is
    // remembered as held so a release before the answer stops a repeat it would start.
    generation += 1
    let mine = generation
    repeating = (id, mine)
    Task { @MainActor [weak self] in
      let answer = await words.list(claim.leader, claim.code, claim.sub, 0)
      guard let self else { return }
      let still = self.repeating?.id == id && self.repeating?.generation == mine
      if !(answer.ran && answer.repeats && still), self.repeating?.generation == mine { self.repeating = nil }
      guard answer.ran else { return self.global(id, claim) }
      guard answer.repeats, still else { return }
      self.schedule(id, depth: 1, after: NSEvent.keyRepeatDelay, generation: mine) { depth in
        _ = await words.list(claim.leader, claim.code, claim.sub, depth)
      }
    }
  }

  // The global row a press resolves to, run in Hammerspoon by its id, and repeated when it repeats.
  private func global(_ id: UInt32, _ claim: Claim) {
    guard case .runs(let row) = resolver.resolve(code: claim.code, mods: claim.mods, held: [], gate: gate) else { return }
    let words = self.words
    Task { await words.run(row.id, 0) }
    // A press that does not repeat leaves a repeat already running alone, as the chord engine does,
    // and one that repeats takes it over.
    guard row.repeats else { return }
    generation += 1
    let mine = generation
    repeating = (id, mine)
    schedule(id, depth: 1, after: NSEvent.keyRepeatDelay, generation: mine) { depth in await words.run(row.id, depth) }
  }

  // One repeat, a beat after the last run returned, while its key is still the one held.
  private func schedule(_ id: UInt32, depth: Int, after: TimeInterval, generation mine: Int,
    _ step: @escaping @Sendable (Int) async -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.repeating?.id == id, self.repeating?.generation == mine else { return }
        Task { @MainActor [weak self] in
          await step(depth)
          self?.schedule(id, depth: depth + 1, after: NSEvent.keyRepeatInterval, generation: mine, step)
        }
      }
    }
  }
}
