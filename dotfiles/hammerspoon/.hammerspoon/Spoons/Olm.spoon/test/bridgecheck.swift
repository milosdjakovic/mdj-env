// The live check of step 2.2 of docs/PLAN-STANDALONE.md, a command line client standing in for
// Olm.app. It listens on the bridge's socket as the app will, docs/PROTOCOL-BRIDGE.md, sets the
// folder 0700 and the socket 0600, posts local.olm.Olm.listening, takes the one connection the
// running Hammerspoon makes, checks its peer is this user, and then asks hello, catalog, icons,
// open for the launcher and rows for the query given, printing what came back and how long each
// took. It runs nothing on the Lua side, which serves nothing that could.
//
// test/bridgecheck.sh builds and runs it. Exit 0 when every answer came back well formed.

import Foundation

let args = CommandLine.arguments
let query = args.count > 1 ? args[1] : "saf"
let home = FileManager.default.homeDirectoryForCurrentUser.path
let run = home + "/.olm/run"
let path = run + "/bridge.sock"

func fail(_ text: String) -> Never {
  FileHandle.standardError.write(("bridgecheck: " + text + "\n").data(using: .utf8)!)
  unlink(path)
  exit(1)
}

// Listening, as the app will.
chmod(run, 0o700)
unlink(path)
let listener = socket(AF_UNIX, SOCK_STREAM, 0)
var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutableBytes(of: &addr.sun_path) { raw in
  _ = path.utf8CString.withUnsafeBytes { src in memcpy(raw.baseAddress!, src.baseAddress!, min(raw.count, src.count)) }
}
let bound = withUnsafePointer(to: &addr) {
  $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
if bound != 0 { fail("could not listen on \(path)") }
chmod(path, 0o600)
listen(listener, 1)
DistributedNotificationCenter.default().postNotificationName(Notification.Name("local.olm.Olm.listening"),
  object: nil, userInfo: nil, deliverImmediately: true)
print("listening on \(path), waiting for Hammerspoon")

// One connection, from this user only.
var tv = timeval(tv_sec: 15, tv_usec: 0)
setsockopt(listener, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
let fd = accept(listener, nil, nil)
if fd < 0 { fail("Hammerspoon did not connect within 15 s, is the bridge's socket setting on?") }
var uid: uid_t = 0, gid: gid_t = 0
if getpeereid(fd, &uid, &gid) != 0 || uid != getuid() { fail("the peer is not this user") }
print("connected, peer uid \(uid) is this user")
setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

var buffer = Data()
func fill() {
  var chunk = [UInt8](repeating: 0, count: 1 << 16)
  let n = read(fd, &chunk, chunk.count)
  if n <= 0 { fail("the connection went or timed out") }
  buffer.append(chunk, count: n)
}
func readMessage() -> [String: Any] {
  while buffer.firstIndex(of: 10) == nil { fill() }
  let nl = buffer.firstIndex(of: 10)!
  guard let len = Int(String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)) else { fail("a bad length line") }
  buffer.removeSubrange(buffer.startIndex...nl)
  while buffer.count < len { fill() }
  let body = buffer.prefix(len)
  buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + len))
  guard let doc = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { fail("an answer that is not JSON") }
  return doc
}
func send(_ doc: [String: Any]) {
  let body = try! JSONSerialization.data(withJSONObject: doc)
  let message = "\(body.count)\n".data(using: .utf8)! + body
  _ = message.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
}
var next = 0
func ask(_ method: String, _ params: [String: Any]) -> (result: [String: Any]?, error: [String: Any]?, ms: Double) {
  next += 1
  let id = "a\(next)"
  let t0 = DispatchTime.now().uptimeNanoseconds
  send(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
  let answer = readMessage()
  let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
  guard answer["id"] as? String == id else { fail("an answer to \(answer["id"] ?? "nothing") where \(id) was asked") }
  return (answer["result"] as? [String: Any], answer["error"] as? [String: Any], ms)
}
func say(_ text: String, _ ms: Double) { print(String(format: "%-60@ %7.1f ms", text, ms)) }

let hello = ask("hello", ["protocol": 1, "app": "bridgecheck", "features": [String]()])
guard let h = hello.result, h["protocol"] as? Int == 1 else { fail("hello answered \(hello.error ?? [:])") }
say("hello, protocol 1, olm \(h["olm"] ?? "?")", hello.ms)

let catalog = ask("catalog", [:])
guard let c = catalog.result, let rows = c["rows"] as? [[String: Any]], let revision = c["revision"] as? String else {
  fail("catalog answered \(catalog.error ?? [:])")
}
say("catalog, \(rows.count) rows, revision \(revision)", catalog.ms)
for row in rows.prefix(5) { print("    \(row["title"] ?? "?")  ·  \(row["subtitle"] ?? "")  [\(row["key"] ?? "")]") }
let again = ask("catalog", ["have": revision])
guard again.result?["unchanged"] as? Bool == true else { fail("the same catalog asked again was not unchanged") }
say("catalog again with have, unchanged", again.ms)

let icons = ask("icons", ["owner": "launcher"])
guard let declared = icons.result?["icons"] as? [String: Any] else { fail("icons answered \(icons.error ?? [:])") }
say("icons of the launcher, \(declared.count) declared", icons.ms)

let refused = ask("open", ["what": ["tool": "clipboard"], "query": ""])
guard refused.error?["code"] as? Int == -32013 else { fail("a tool not served yet was not refused with -32013") }
say("open a tool not served yet, refused -32013", refused.ms)

let open = ask("open", ["what": ["launcher": true], "query": ""])
guard let level = open.result?["level"] as? [String: Any], let id = level["id"] as? String else {
  fail("open answered \(open.error ?? [:])")
}
let memory = level["memory"] as? [String: Any] ?? [:]
say("open the launcher, level \(id), \(memory.count) remembered queries", open.ms)

let first = ask("rows", ["level": id, "q": 1, "query": query])
guard let r = first.result, let changes = r["changes"] as? [String: Any], let order = changes["order"] as? [Any] else {
  fail("rows answered \(first.error ?? [:])")
}
let upsert = changes["upsert"] as? [[String: Any]] ?? []
say("rows for \"\(query)\", \(order.count) rows, revision \(r["revision"] ?? "?")", first.ms)
for row in upsert.prefix(3) { print("    \(row["title"] ?? "?")  [\(row["key"] ?? "")]") }
let same = ask("rows", ["level": id, "q": 2, "query": query, "have": r["revision"] ?? ""])
guard same.result != nil, same.result?["changes"] == nil else { fail("the same rows asked again carried changes") }
say("rows again with have, no changes", same.ms)

let choose = ask("choose", ["level": id, "q": 2, "h": 1, "ref": (upsert.first?["ref"] as? String) ?? ""])
guard choose.error?["code"] as? Int == -32601 else { fail("choose was not refused, so something could be run") }
say("choose, refused -32601, nothing can be run", choose.ms)

let closed = ask("close", ["level": id])
guard closed.error == nil else { fail("close answered \(closed.error ?? [:])") }
say("close the level", closed.ms)
print("bridgecheck: every answer came back well formed")
close(fd)
unlink(path)
