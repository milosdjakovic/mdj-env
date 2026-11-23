// Step 5.1's check, docs/DESIGN-APP-KEYS.md. The resolver against the rules of lib/leader.lua's
// _resolve and its three triggers, case by case, and the shadow's pairing driven through a keymap
// written to a folder of its own, a press and a run paired, each alone logged, a held key's repeats
// taken as one press and a press while a list is up left to the list. It hears no keyboard.
//
//   olm-keys-check            exits 0 when every case held, 1 otherwise
//   olm-keys-check --live F   also resolves, for every row of the keymap share F, the press that
//                             reaches it, ~/.olm/run/keymap.json as this machine's Hammerspoon wrote it

import Foundation
import OlmKeys

var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: String) {
  checks += 1
  if !ok {
    failures += 1
    print("  FAIL \(what)")
  }
}

let hyperMods: Set<Mod> = [.shift, .ctrl, .alt, .cmd]
let metaMods: Set<Mod> = [.shift, .ctrl, .alt]
let hyper = KeyLeader(name: "hyper", held: true, keyCode: 79, mods: hyperMods, ranked: true)
let meta = KeyLeader(name: "meta", held: true, keyCode: 106, mods: metaMods, ranked: false)
let A = 0, J = 38, LEFT = 123, FOUR = 21, BACKTICK = 50

func ran(_ r: Resolution?) -> String? {
  if case .runs(let row) = r { return row.id }
  return nil
}

// The triggers.
do {
  let keymap = Keymap(leaders: [hyper, meta], rows: [
    KeyRow(id: "apptoggler.Safari", leader: "hyper", key: "a", keyCode: A, mods: []),
    KeyRow(id: "capture.copy", leader: "hyper", key: "4", keyCode: FOUR, mods: [.shift]),
    KeyRow(id: "windowmanager.leftHalf", leader: "meta", key: "left", keyCode: LEFT, mods: nil, repeats: true),
    KeyRow(id: "apptoggler.Ghostty", leader: nil, key: "`", keyCode: BACKTICK, mods: [.alt]),
  ])
  let r = Resolver(keymap: keymap)
  let open: (String) -> Bool = { _ in true }
  check(ran(r.resolve(code: A, mods: [], held: [79], gate: open)) == "apptoggler.Safari", "Hyper held as F18 and A")
  check(ran(r.resolve(code: A, mods: hyperMods, held: [], gate: open)) == "apptoggler.Safari", "Hyper as four modifiers and A")
  check(r.resolve(code: A, mods: [], held: [], gate: open) == nil, "A alone passes through")
  check(r.resolve(code: A, mods: [.cmd], held: [], gate: open) == nil, "Command and A passes through")
  check(ran(r.resolve(code: FOUR, mods: [.shift], held: [79], gate: open)) == "capture.copy", "F18, Shift and 4")
  check(r.resolve(code: FOUR, mods: hyperMods, held: [], gate: open) == nil,
    "the four modifiers and 4 leave Hyper and Shift and 4 to the held key, since Shift is in the set")
  check(ran(r.resolve(code: LEFT, mods: metaMods, held: [], gate: open)) == "windowmanager.leftHalf", "META as modifiers, a catch all")
  check(r.resolve(code: LEFT, mods: metaMods.union([.cmd]), held: [], gate: open) == nil,
    "a catch all on a leader of modifiers is claimed on the set alone")
  check(ran(r.resolve(code: LEFT, mods: [.cmd], held: [106], gate: open)) == "windowmanager.leftHalf",
    "a catch all under a held key fires with any modifiers")
  check(ran(r.resolve(code: BACKTICK, mods: [.alt], held: [], gate: open)) == "apptoggler.Ghostty", "a plain combo")
  check(r.resolve(code: BACKTICK, mods: [.alt, .shift], held: [], gate: open) == nil, "a plain combo is exact")
  check(r.resolve(code: 79, mods: [], held: [79], gate: open) == nil, "the leader's own key resolves nothing")
}

// The two tier rules and the gates.
do {
  let ranked = KeyLeader(name: "r", held: true, keyCode: 80, mods: nil, ranked: true)
  let first = KeyLeader(name: "f", held: true, keyCode: 90, mods: nil, ranked: false)
  func rows(_ leader: String) -> [KeyRow] {
    [
      KeyRow(id: "\(leader).shiftJ", leader: leader, key: "j", keyCode: J, mods: [.shift], gate: "off"),
      KeyRow(id: "\(leader).anyJ", leader: leader, key: "j", keyCode: J, mods: nil),
      KeyRow(id: "\(leader).plainA1", leader: leader, key: "a", keyCode: A, mods: [], priority: 0),
      KeyRow(id: "\(leader).plainA2", leader: leader, key: "a", keyCode: A, mods: [], priority: 5),
      KeyRow(id: "\(leader).any1", leader: leader, key: "left", keyCode: LEFT, mods: nil),
      KeyRow(id: "\(leader).any2", leader: leader, key: "left", keyCode: LEFT, mods: nil),
      KeyRow(id: "\(leader).gated", leader: leader, key: "4", keyCode: FOUR, mods: [], gate: "off"),
    ]
  }
  let r = Resolver(keymap: Keymap(leaders: [ranked, first], rows: rows("r") + rows("f")))
  let gate: (String) -> Bool = { $0 != "off" }
  check(ran(r.resolve(code: J, mods: [.shift], held: [80], gate: gate)) == "r.anyJ",
    "ranked, an exact row gated off leaves the catch all to answer")
  check(r.resolve(code: J, mods: [.shift], held: [90], gate: gate) == .swallowed,
    "first exact, an exact row gated off is swallowed there")
  check(ran(r.resolve(code: A, mods: [], held: [80], gate: gate)) == "r.plainA2", "ranked, the higher priority wins")
  check(ran(r.resolve(code: A, mods: [], held: [90], gate: gate)) == "f.plainA1", "first exact, the first bound wins")
  check(ran(r.resolve(code: LEFT, mods: [], held: [80], gate: gate)) == "r.any1", "ranked, the first catch all among equals")
  check(ran(r.resolve(code: LEFT, mods: [], held: [90], gate: gate)) == "f.any2", "first exact, the last catch all")
  check(r.resolve(code: FOUR, mods: [], held: [80], gate: gate) == .swallowed, "ranked, every row gated off swallows")
  check(r.resolve(code: FOUR, mods: [], held: [90], gate: gate) == .swallowed, "first exact, every row gated off swallows")
  check(r.resolve(code: 1, mods: [], held: [80], gate: gate) == nil, "a key nothing binds passes through")
}

// The share as Hammerspoon writes it.
do {
  let json = """
  {"version":1,"leaders":[{"name":"hyper","held":true,"keyCode":79,"mods":["shift","ctrl","alt","cmd"],"ranked":true}],
   "rows":[{"id":"apptoggler.Safari","leader":"hyper","key":"a","keyCode":0,"mods":[],"repeats":false},
           {"id":"windowmanager.leftHalf","leader":"meta","key":"left","keyCode":123,"repeats":true},
           {"id":"nokey.row","leader":"hyper","key":"globe"}]}
  """
  let k = try? Keymap.parse(Data(json.utf8))
  check(k?.leaders.first?.mods == hyperMods && k?.leaders.first?.ranked == true, "a leader read")
  check(k?.rows.count == 2, "a row with no keycode left out")
  check(k?.rows[0].mods == [] && k?.rows[1].mods == nil, "an exact row and a catch all told apart")
  check((try? Keymap.parse(Data(#"{"version":2}"#.utf8))) == nil, "another version refused")
}

// The shadow's pairing, through a keymap in a folder of its own.
func counts(_ dir: URL) -> [String: Int] {
  let url = dir.appendingPathComponent("log/shadow-keys-count.json")
  guard let data = try? Data(contentsOf: url), let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
  return o.compactMapValues { $0 as? Int }
}
func lines(_ dir: URL) -> [String] {
  (try? String(contentsOf: dir.appendingPathComponent("log/shadow-keys.jsonl"), encoding: .utf8))?
    .split(separator: "\n").map(String.init) ?? []
}
func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }
do {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("olm-keys-check-\(getpid())")
  try? FileManager.default.removeItem(at: dir)
  let run = dir.appendingPathComponent("run")
  try! FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
  let json = """
  {"version":1,"leaders":[{"name":"hyper","held":true,"keyCode":79,"mods":["shift","ctrl","alt","cmd"],"ranked":true},
   {"name":"meta","held":true,"keyCode":106,"mods":["shift","ctrl","alt"],"ranked":false}],
   "rows":[{"id":"apptoggler.Safari","leader":"hyper","key":"a","keyCode":0,"mods":[]},
           {"id":"windowmanager.leftHalf","leader":"meta","key":"left","keyCode":123,"repeats":true}]}
  """
  try! Data(json.utf8).write(to: run.appendingPathComponent("keymap.json"))
  let shadow = KeyShadow(run: run, log: dir.appendingPathComponent("log"), say: { _ in })
  shadow.start()
  func now() -> Double { ProcessInfo.processInfo.systemUptime }
  func press(_ code: Int, _ mods: Set<Mod>, repeat r: Bool = false) {
    shadow.heard(KeyEvent(kind: .down, code: code, mods: mods, autorepeat: r, at: now()))
  }
  func release(_ code: Int, _ mods: Set<Mod>) {
    shadow.heard(KeyEvent(kind: .up, code: code, mods: mods, autorepeat: false, at: now()))
  }
  pause(0.2)
  // A press and its run.
  press(A, hyperMods)
  pause(0.02)
  shadow.fired("apptoggler.Safari")
  // A run that came before the press was heard.
  shadow.fired("apptoggler.Safari")
  press(A, hyperMods)
  // A held repeating key, its run and three repeats, the OS's own autorepeats not presses.
  press(LEFT, metaMods)
  for _ in 0..<3 {
    shadow.fired("windowmanager.leftHalf")
    press(LEFT, metaMods, repeat: true)
    pause(0.03)
  }
  release(LEFT, metaMods)
  shadow.fired("windowmanager.leftHalf")
  pause(1.8)
  var c = counts(dir)
  check(c["paired"] == 3, "a press and its run paired either way round, and a held key's repeats one press, \(c)")
  check(c["appOnly"] == 0 && c["hammerspoonOnly"] == 0, "and nothing logged, \(lines(dir))")
  // A press Hammerspoon did not run, and a run the app did not hear.
  press(A, hyperMods)
  shadow.fired("windowmanager.leftHalf")
  pause(1.8)
  c = counts(dir)
  check(c["appOnly"] == 1 && c["hammerspoonOnly"] == 1, "each alone logged, \(c)")
  let logged = lines(dir)
  check(logged.count == 2 && logged[0].contains("appOnly") && logged[0].contains("apptoggler.Safari")
    && logged[1].contains("hammerspoonOnly"), "one line each, \(logged)")
  // A list of the app's own up takes its presses.
  shadow.list(up: true)
  press(A, hyperMods)
  shadow.fired("apptoggler.Safari")
  shadow.list(up: false)
  pause(1.8)
  c = counts(dir)
  check(c["appOnly"] == 1 && c["hammerspoonOnly"] == 1 && c["paired"] == 3, "a press while a list is up is the list's, \(c)")
  try? FileManager.default.removeItem(at: dir)
}

// Every row of a real share reached by the press that should reach it, a leader's modifiers with
// the row's own, or its held key where the modifier half leaves the row to it, and a plain combo's
// own modifiers. Another row on the same chord answering is its tier rule, which the cases above
// pin, so only a press reaching nothing or a row on another chord is a failure.
if let i = CommandLine.arguments.firstIndex(of: "--live"), i + 1 < CommandLine.arguments.count {
  let url = URL(fileURLWithPath: (CommandLine.arguments[i + 1] as NSString).expandingTildeInPath)
  if let keymap = try? Keymap.read(url) {
    let r = Resolver(keymap: keymap)
    var reached = 0
    for row in keymap.rows {
      var mods = row.mods ?? []
      var held: Set<Int> = []
      if let name = row.leader, let leader = keymap.leaders.first(where: { $0.name == name }) {
        if let base = leader.mods, row.mods.map({ $0.isDisjoint(with: base) }) ?? true, !(leader.held && row.mods == nil) {
          mods = base.union(row.mods ?? [])
        } else if leader.held, let code = leader.keyCode {
          held = [code]
        }
      }
      let got = r.resolve(code: row.keyCode, mods: mods, held: held, gate: { _ in true })
      if case .runs(let other) = got, other.keyCode == row.keyCode, other.leader == row.leader {
        reached += 1
        if other.id != row.id { print("  note \(row.id) on its chord answers \(other.id), its tier rule") }
      } else {
        check(false, "live: \(row.id), \(row.leader ?? "plain") \(row.key) with \(mods.map(\.rawValue).sorted()) held \(held), got \(String(describing: got))")
      }
    }
    checks += 1
    print("live: \(reached) of \(keymap.rows.count) rows reached by their own press, on \(keymap.leaders.map(\.name).joined(separator: ", "))")
  } else {
    check(false, "live: no keymap share at \(url.path)")
  }
}

// The chord engine's repeat timing, fixture 0.3f, recorded from lib/chordkey.lua by
// test/repeattiming.lua, answered by the port the app repeats a claimed key on, step 5.3.
do {
  let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  let url = here.appendingPathComponent("../../../test/fixtures/keys/repeat.json").standardizedFileURL
  if let data = try? Data(contentsOf: url), let doc = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
    let cases = doc["cases"] as? [[String: Any]] {
    for c in cases {
      let got = KeyRepeat.schedule(delay: c["delay"] as! Double, interval: c["interval"] as! Double,
        hold: c["hold"] as! Double, handler: (c["handler"] as! NSNumber).doubleValue)
      let want = (c["runs"] as! [[String: Any]]).map { ((($0["at"] as! NSNumber).doubleValue * 1000).rounded(), $0["depth"] as! Int) }
      let mine = got.map { (($0.at * 1000).rounded(), $0.depth) }
      check(mine.count == want.count && zip(mine, want).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 },
        "repeat: \(c["name"] ?? ""), wanted \(want), got \(mine)")
    }
  } else {
    check(false, "repeat: no fixture at \(url.path)")
  }
}

// The combinations the app claims for a leader it holds, as the modifier trigger claims them, and
// the leaders the share hands it.
do {
  let base: Set<Mod> = [.shift, .ctrl, .alt]
  let meta = KeyLeader(name: "meta", held: true, keyCode: 106, mods: base, ranked: false)
  let km = Keymap(leaders: [meta], rows: [
    KeyRow(id: "w.left", leader: "meta", key: "left", keyCode: 123, mods: nil),
    KeyRow(id: "w.leftShift", leader: "meta", key: "left", keyCode: 123, mods: [.shift]),
    KeyRow(id: "w.leftCmd", leader: "meta", key: "left", keyCode: 123, mods: [.cmd]),
    KeyRow(id: "w.again", leader: "meta", key: "left", keyCode: 123, mods: nil),
    KeyRow(id: "h.a", leader: "hyper", key: "a", keyCode: 0, mods: nil),
  ])
  let combos = KeyOwner.combinations(km, leader: meta, base: base)
  check(combos.count == 2, "owner: one claim per combination, a row asking for a base modifier left to the held key, \(combos)")
  check(combos.contains { $0.code == 123 && $0.mods == base }, "owner: a catch all on the base set alone")
  check(combos.contains { $0.code == 123 && $0.mods == base.union([.cmd]) }, "owner: a row's own modifier added to the base set")
  // A list key's combinations join the global rows', one already claimed by a row not claimed twice,
  // and one asking for a base modifier left to the held key as a row's is.
  let lists = [KeyOwner.ListCombo(code: 38, mods: []), KeyOwner.ListCombo(code: 123, mods: []),
    KeyOwner.ListCombo(code: 38, mods: [.cmd]), KeyOwner.ListCombo(code: 40, mods: [.shift])]
  let withLists = KeyOwner.combinations(km, leader: meta, base: base, lists: lists)
  check(withLists.count == 4, "owner: list combinations join the rows', none twice, \(withLists)")
  check(withLists.contains { $0.code == 38 && $0.mods == base }, "owner: a list key on the base set alone")
  check(withLists.contains { $0.code == 38 && $0.mods == base.union([.cmd]) }, "owner: a list key's own modifier added")
  check(!withLists.contains { $0.code == 40 }, "owner: a list key asking for a base modifier is left to the held key")
  // The plain leader claims each row with no leader on exactly its own modifiers, and resolves it.
  let plainMap = Keymap(leaders: [meta], rows: [
    KeyRow(id: "clipboard.appendCopy", leader: nil, key: "c", keyCode: 8, mods: [.ctrl, .alt]),
    KeyRow(id: "inputsources.cycle", leader: nil, key: "globe", keyCode: 179, mods: []),
    KeyRow(id: "w.left", leader: "meta", key: "left", keyCode: 123, mods: nil),
  ])
  let plainCombos = KeyOwner.combinations(plainMap, leader: KeyLeader.plain, base: [])
  check(plainCombos.count == 2, "owner: the plain leader claims only the rows with no leader, \(plainCombos)")
  check(plainCombos.contains { $0.code == 8 && $0.mods == [.ctrl, .alt] }, "owner: a plain row on its own modifiers")
  check(plainCombos.contains { $0.code == 179 && $0.mods.isEmpty }, "owner: a bare key on none")
  let plainHit = Resolver(keymap: plainMap).resolve(code: 8, mods: [.ctrl, .alt], held: [], gate: { _ in true })
  check(plainHit == .runs(plainMap.rows[0]), "owner: a plain claim resolves to its row")
  let share = #"{"version":1,"leaders":[],"rows":[],"appKeys":["meta"]}"#
  check((try? Keymap.parse(Data(share.utf8)))?.appKeys == ["meta"], "owner: the share names the leaders the app holds")
}

print("olm-keys-check, \(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
