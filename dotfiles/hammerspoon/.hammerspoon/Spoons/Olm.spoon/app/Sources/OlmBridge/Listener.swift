// The app's end of the bridge's socket, docs/PROTOCOL-BRIDGE.md, Transport and framing and Access.
// The app listens and Hammerspoon connects, since only the listener can check its peer, step 2.1.
// Everything here runs on one serial queue of its own, never the main thread, rule 8 of
// docs/PLAN-STANDALONE.md, and hands each whole message on as bytes.
//
// It makes the run folder 0700, removes a socket left by an app that did not close, binds, sets the
// socket 0600, and refuses a peer getpeereid says is another user. It keeps one connection, a new one
// taking the old one's place, and posts local.olm.Olm.listening once it listens, so a Hammerspoon
// already loaded connects at once rather than at its next try. test/bridgecheck.swift listens the
// same way.
//
// It watches its run folder, and when its socket file is gone it binds again and posts the note again,
// so the bridge outlives anything that removed the file. test/bridgecheck.swift standing in on the
// same path did exactly that on 2026-11-16, leaving the app listening on a file no longer there and
// its launcher empty until it was relaunched. It waits a moment first and binds only on a path still
// missing then, so a program that removes the file to bind its own takes it, and the app takes it
// back once that program's file is gone. A connection already open is left as it is.

import Foundation

public final class Listener: @unchecked Sendable {
  public static let listeningNote = Notification.Name("local.olm.Olm.listening")

  /// A connection's events, each called on the listener's queue. The id names the connection, so an
  /// event of one already replaced is told apart.
  public struct Events: Sendable {
    public var up: @Sendable (Int) -> Void
    public var message: @Sendable (Int, Data) -> Void
    public var down: @Sendable (Int) -> Void

    public init(up: @escaping @Sendable (Int) -> Void, message: @escaping @Sendable (Int, Data) -> Void,
                down: @escaping @Sendable (Int) -> Void) {
      self.up = up
      self.message = message
      self.down = down
    }
  }

  private let path: String
  private let events: Events
  private let announce: Bool
  private let queue = DispatchQueue(label: "local.olm.Olm.bridge")
  private var listenFD: Int32 = -1
  private var acceptSource: DispatchSourceRead?
  private var conn: (id: Int, fd: Int32, source: DispatchSourceRead, reader: Frame.Reader)?
  private var nextID = 0
  // The run folder watched for the socket file going, and the one check waiting to look.
  private var folderWatch: DispatchSourceFileSystemObject?
  private var healing = false
  private var stopped = false

  /// How long a missing socket file is left before the listener binds again, a program removing the
  /// file to bind its own taking it well within this.
  public static let healDelay: TimeInterval = 0.25

  /// path is the socket, its folder the run folder. announce false posts no notification, for a check
  /// program listening on a path of its own.
  public init(path: String, announce: Bool = true, events: Events) {
    self.path = path
    self.announce = announce
    self.events = events
  }

  /// Listens, answering why it could not. The listener runs until stop.
  public func start() -> String? {
    queue.sync { begin() }
  }

  private func begin() -> String? {
    let folder = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    chmod(folder, 0o700)
    unlink(path)
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    let room = MemoryLayout.size(ofValue: addr.sun_path)
    guard bytes.count < room else { return "the socket path is longer than a socket address holds" }
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in
      raw.copyBytes(from: bytes)
      raw[bytes.count] = 0
    }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return "no socket, errno \(errno)" }
    let bound = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard bound == 0 else { close(fd); return "could not bind \(path), errno \(errno)" }
    chmod(path, 0o600)
    guard listen(fd, 4) == 0 else { close(fd); unlink(path); return "could not listen, errno \(errno)" }
    _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    listenFD = fd
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    source.setEventHandler { [weak self] in self?.accept() }
    source.resume()
    acceptSource = source
    if announce {
      DistributedNotificationCenter.default().postNotificationName(Self.listeningNote, object: nil,
        userInfo: nil, deliverImmediately: true)
    }
    watchFolder(folder)
    return nil
  }

  // Any change in the run folder asks whether the socket file is still there, a folder removed
  // whole included, since its watch ends with it and the next bind makes it and watches it again.
  private func watchFolder(_ folder: String) {
    folderWatch?.cancel()
    folderWatch = nil
    let fd = open(folder, O_EVTONLY)
    guard fd >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename],
      queue: queue)
    source.setEventHandler { [weak self] in self?.missing() }
    source.setCancelHandler { close(fd) }
    source.resume()
    folderWatch = source
  }

  private func missing() {
    guard !stopped, !healing, access(path, F_OK) != 0 else { return }
    healing = true
    queue.asyncAfter(deadline: .now() + Self.healDelay) { [weak self] in
      guard let self else { return }
      self.healing = false
      guard !self.stopped, access(self.path, F_OK) != 0 else { return }
      self.acceptSource?.cancel()
      self.acceptSource = nil
      if self.listenFD >= 0 { close(self.listenFD); self.listenFD = -1 }
      if let why = self.begin() { NSLog("Olm bridge: the socket file went and could not be made again, %@", why) }
    }
  }

  private func accept() {
    let fd = Darwin.accept(listenFD, nil, nil)
    guard fd >= 0 else { return }
    var uid: uid_t = 0, gid: gid_t = 0
    guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
      NSLog("Olm bridge: refused a peer that is not this user, uid %d", uid)
      close(fd)
      return
    }
    // An accepted socket takes the listening one's O_NONBLOCK, and a write here waits for room.
    _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    drop()
    nextID += 1
    let id = nextID
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    source.setEventHandler { [weak self] in self?.read(id) }
    source.setCancelHandler { close(fd) }
    conn = (id, fd, source, Frame.Reader())
    source.resume()
    events.up(id)
  }

  private func read(_ id: Int) {
    guard let fd = conn?.fd, conn?.id == id else { return }
    var chunk = [UInt8](repeating: 0, count: 1 << 16)
    let n = Darwin.read(fd, &chunk, chunk.count)
    if n <= 0 {
      if n < 0 && (errno == EAGAIN || errno == EINTR) { return }
      drop()
      return
    }
    do {
      let messages = try conn!.reader.feed(Data(chunk[0..<n]))
      for m in messages { events.message(id, m) }
    } catch {
      NSLog("Olm bridge: a message that is not framed, %@, the connection closed", "\(error)")
      drop()
    }
  }

  // Ends the connection there is, telling its down.
  private func drop() {
    guard let c = conn else { return }
    conn = nil
    c.source.cancel()
    events.down(c.id)
  }

  /// Sends one message on the connection the id names, nothing when it has gone.
  public func send(_ id: Int, _ body: Data) {
    queue.async { [weak self] in
      guard let self, let c = self.conn, c.id == id else { return }
      let message = Frame.encode(body)
      var sent = 0
      let ok = message.withUnsafeBytes { raw -> Bool in
        while sent < raw.count {
          let n = write(c.fd, raw.baseAddress! + sent, raw.count - sent)
          if n < 0 {
            if errno == EINTR { continue }
            return false
          }
          sent += n
        }
        return true
      }
      if !ok { self.drop() }
    }
  }

  public func stop() {
    queue.sync {
      stopped = true
      folderWatch?.cancel()
      folderWatch = nil
      drop()
      acceptSource?.cancel()
      acceptSource = nil
      if listenFD >= 0 { close(listenFD); listenFD = -1 }
      unlink(path)
    }
  }
}
