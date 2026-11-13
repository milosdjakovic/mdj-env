// The app's side of the bridge, docs/PROTOCOL-BRIDGE.md, step 2.3 of docs/PLAN-STANDALONE.md. It
// listens, says hello on each connection, sends requests and matches their answers by id, and hands
// on the notifications Hammerspoon sends, memory to the bridged launcher and shadow to whoever
// compares. A lost connection fails every request still waiting and resets the launcher, so nothing
// outlives a connection and the next one starts from hello.
//
// The listener's events are taken in the order they came through one stream, so an answer never
// overtakes the message before it. Starting a session waits for answers, so it runs beside that
// stream rather than in it.

import Foundation

public enum BridgeError: Error, Equatable {
  /// No connection, or the one the request went on has gone.
  case gone
  /// The other side answered an error, its code and message.
  case answered(Int, String)
  /// An answer that is not the shape asked for.
  case malformed(String)

  /// JSON-RPC's code for a request superseded before it ran, never run.
  public static let stale = -32011
}

/// What the Lua side settled on for a query, the shadow notification, step 2.3.
public struct Settled: Sendable, Equatable {
  public var tool: String
  public var query: String
  public var keys: [String]
  public var status: String?
  public var claimed: Bool

  public init(tool: String, query: String, keys: [String], status: String?, claimed: Bool) {
    self.tool = tool
    self.query = query
    self.keys = keys
    self.status = status
    self.claimed = claimed
  }
}

public actor Bridge {
  public static let protocolVersion = 1

  private enum Event: Sendable {
    case up(Int), message(Int, Data), down(Int)
  }

  private let path: String
  private let announce: Bool
  private var listener: Listener?
  private var conn: Int?
  private var nextID = 0
  private var pending: [String: (conn: Int, done: CheckedContinuation<JSON, Error>)] = [:]
  private var launcher: BridgedLauncher?
  private var shownLauncher: BridgedLauncher?
  // The room a row's text has, the stage's, sent as metrics after hello and whenever it changes.
  private var textBudget: Double?
  private var settled: (@Sendable (Settled) -> Void)?
  private var log: @Sendable (String) -> Void

  /// path is the socket, ~/.olm/run/bridge.sock for the app. announce false posts no listening note,
  /// for a check program on a path of its own.
  public init(path: String, announce: Bool = true, log: @escaping @Sendable (String) -> Void = { NSLog("Olm bridge: %@", $0) }) {
    self.path = path
    self.announce = announce
    self.log = log
  }

  /// The launcher the session opens, the shadow's, the one a person opens on the trial key, step
  /// 3.2, and who hears each settled answer.
  public func attach(launcher: BridgedLauncher, shown: BridgedLauncher? = nil,
    settled: @escaping @Sendable (Settled) -> Void) {
    self.launcher = launcher
    self.shownLauncher = shown
    self.settled = settled
  }

  private var launchers: [BridgedLauncher] { [launcher, shownLauncher].compactMap { $0 } }

  /// The room a row's text has, docs/PROTOCOL-BRIDGE.md metrics, sent now when a session is open and
  /// after every hello.
  public func setTextBudget(_ budget: Double) {
    guard budget != textBudget else { return }
    textBudget = budget
    if open { sendMetrics() }
  }

  private func sendMetrics() {
    guard let textBudget else { return }
    notify("metrics", .object(["textBudget": .number(textBudget.rounded()),
      "font": .object(["title": .string("body"), "subtitle": .string("caption")])]))
  }

  /// Listens, answering why it could not.
  public func start() -> String? {
    let (stream, feed) = AsyncStream<Event>.makeStream()
    let listener = Listener(path: path, announce: announce, events: .init(
      up: { feed.yield(.up($0)) },
      message: { feed.yield(.message($0, $1)) },
      down: { feed.yield(.down($0)) }))
    if let why = listener.start() { return why }
    self.listener = listener
    Task { for await event in stream { await self.take(event) } }
    return nil
  }

  public func stop() {
    listener?.stop()
    listener = nil
  }

  /// Whether a session is open, hello answered.
  public private(set) var open = false

  private func take(_ event: Event) async {
    switch event {
    case .up(let id):
      conn = id
      open = false
      log("Hammerspoon connected")
      Task { await self.begin(id) }
    case .message(let id, let data):
      guard id == conn else { return }
      await receive(data)
    case .down(let id):
      guard id == conn else { return }
      conn = nil
      open = false
      for (key, p) in pending where p.conn == id {
        pending[key] = nil
        p.done.resume(throwing: BridgeError.gone)
      }
      for l in launchers { await l.reset() }
      log("Hammerspoon's connection went")
    }
  }

  // hello, metrics once the stage has measured a list, then the shadow launcher's open,
  // docs/PROTOCOL-BRIDGE.md, step 3.2.
  private func begin(_ id: Int) async {
    do {
      let hello = try await request("hello", .object(["protocol": .number(Double(Self.protocolVersion)),
        "app": .string(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"),
        "features": .array([])]))
      guard hello["protocol"].int == Self.protocolVersion else {
        log("Hammerspoon speaks protocol \(hello["protocol"].int ?? 0), this app \(Self.protocolVersion)")
        return
      }
      guard conn == id else { return }
      open = true
      sendMetrics()
      for l in launchers.reversed() { try await l.connected(rowLimit: hello["limits"]["rowLimit"].int) }
    } catch {
      log("the session did not start, \(error)")
    }
  }

  private func receive(_ data: Data) async {
    guard let message = JSON.decode(data), message["jsonrpc"].string == "2.0" else {
      log("a message that is not JSON-RPC")
      return
    }
    if let method = message["method"].string {
      // A request of the Lua side's, which sends none yet, or a notification.
      if let id = message["id"].string {
        reply(id, error: (-32601, "no method \(method)"))
        return
      }
      await notified(method, message["params"])
      return
    }
    guard let id = message["id"].string, let p = pending.removeValue(forKey: id) else { return }
    if !message["error"].isNull {
      p.done.resume(throwing: BridgeError.answered(message["error"]["code"].int ?? 0, message["error"]["message"].string ?? ""))
    } else {
      p.done.resume(returning: message["result"])
    }
  }

  // Awaited in the stream's order, so a memory notification lands before any answer after it.
  private func notified(_ method: String, _ params: JSON) async {
    switch method {
    case "memory":
      if let changes = params["memory"].object { for l in launchers { await l.remember(changes) } }
    case "shadow":
      guard let tool = params["tool"].string, let query = params["query"].string else { return }
      let keys = (params["keys"].array ?? []).compactMap { $0.string ?? $0.int.map(String.init) }
      settled?(Settled(tool: tool, query: query, keys: keys, status: params["status"].string,
        claimed: params["claimed"].bool ?? false))
    default:
      // A notification of a newer peer is read as nothing, the protocol's hello.
      break
    }
  }

  private func reply(_ id: String, error: (Int, String)) {
    guard let conn, let body = JSON.object(["jsonrpc": .string("2.0"), "id": .string(id),
      "error": .object(["code": .number(Double(error.0)), "message": .string(error.1)])]).encoded() else { return }
    listener?.send(conn, body)
  }

  /// One notification, sent when a connection is up and dropped when none is.
  public func notify(_ method: String, _ params: JSON) {
    guard let conn, let listener, let body = JSON.object(["jsonrpc": .string("2.0"), "method": .string(method),
      "params": params]).encoded() else { return }
    listener.send(conn, body)
  }

  /// One request, answered with its result, or thrown as gone or as the error the other side said.
  public func request(_ method: String, _ params: JSON) async throws -> JSON {
    guard let conn, let listener else { throw BridgeError.gone }
    nextID += 1
    let id = "a\(nextID)"
    guard let body = JSON.object(["jsonrpc": .string("2.0"), "id": .string(id), "method": .string(method),
      "params": params]).encoded() else { throw BridgeError.malformed("the request could not be encoded") }
    return try await withCheckedThrowingContinuation { done in
      pending[id] = (conn, done)
      listener.send(conn, body)
    }
  }
}
