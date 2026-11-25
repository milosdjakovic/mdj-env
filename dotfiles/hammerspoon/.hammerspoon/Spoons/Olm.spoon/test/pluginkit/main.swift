// OlmPluginKit usage, run by test/olmplugins.sh: what is used most, what was used last and the half life.

import Foundation
var t = Date(timeIntervalSince1970: 1_800_000_000)
let f = URL(fileURLWithPath: "\(NSTemporaryDirectory())olm-usage-check.json"); try? FileManager.default.removeItem(at: f)
let u = OlmUsage(f, now: { t })
u.note("b"); u.note("b"); t += 60; u.note("c")
let l = ["a","b","c","d"]
assert(u.sorted(l, by: .most) { $0 } == ["b","c","a","d"])
assert(u.sorted(l, by: .last) { $0 } == ["c","b","a","d"])
t += 14*86400; assert(abs(u.score("c") - 0.5) < 1e-9)
assert(abs(OlmUsage(f, now: { t }).score("c") - 0.5) < 1e-9)
for i in 0..<600 { u.note("k\(i)") }
let n = (try! JSONSerialization.jsonObject(with: Data(contentsOf: f)) as! [String:Any]).count
assert(n == 500); print("usage ok")
