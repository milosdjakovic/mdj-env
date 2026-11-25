// One external plugin's process, started inside its sandbox and spoken to over its own pipes,
// docs/DESIGN-APP-PLUGINS.md The shape. Its stdin and stdout carry the bridge protocol's frames, its
// stderr is read line by line for its log, and it runs in a process group of its own, so killing it kills every
// program it started too. Nothing here waits: writes go out on a queue of their own, so a plugin
// that stops reading never holds its runner, and what it sends arrives as events on one stream.

import Darwin
import Foundation
import OlmBridge

final class PluginProcess: @unchecked Sendable {
  enum Event: Sendable {
    /// One whole message, its JSON.
    case message(Data)
    /// It broke the framing or sent a message past the limit, so nothing after can be trusted.
    case broken(String)
    /// A line it wrote to stderr, for its log.
    case said(String)
    /// It is gone, its wait status.
    case exited(Int32)
  }

  enum Failure: Error, CustomStringConvertible {
    case noSandbox
    case noDisclaim
    case spawn(Int32)

    var description: String {
      switch self {
      case .noSandbox: return "this Mac has no sandbox-exec, so no plugin runs"
      case .noDisclaim: return "this macOS has no way to keep a plugin from Olm's own permissions, so no plugin runs"
      case .spawn(let code): return "it could not be started, \(String(cString: strerror(code)))"
      }
    }
  }

  static let sandboxExec = "/usr/bin/sandbox-exec"

  let pid: pid_t
  let events: AsyncStream<Event>
  private let continuation: AsyncStream<Event>.Continuation
  private let input: Int32
  private let output: Int32
  private let errors: Int32
  private let queue: DispatchQueue
  private let writer: DispatchQueue
  // Read and changed on queue alone.
  private var reader = Frame.Reader()
  private var readSource: DispatchSourceRead?
  private var exitSource: DispatchSourceProcess?
  private var errorSource: DispatchSourceRead?
  private var line = Data()
  // Lines passed on since when, the rest dropped here, so a flood never grows Olm.
  private var passed = (since: Date(), lines: 0)
  // Whether each pipe's descriptor is still ours to read.
  private var outputOpen = true
  private var errorsOpen = true
  private var inputOpen = true

  private init(pid: pid_t, input: Int32, output: Int32, errors: Int32, label: String) {
    self.pid = pid
    self.input = input
    self.output = output
    self.errors = errors
    queue = DispatchQueue(label: "olm.plugin.\(label).read")
    writer = DispatchQueue(label: "olm.plugin.\(label).write")
    (events, continuation) = AsyncStream.makeStream(of: Event.self)
  }

  /// Starts the program under the rules, disclaiming Olm's own macOS permissions, at the quality of
  /// service given, with only the environment given.
  static func spawn(executable: URL, rules: String, environment: [String: String],
                    qos: qos_class_t, label: String) throws -> PluginProcess {
    guard FileManager.default.isExecutableFile(atPath: sandboxExec) else { throw Failure.noSandbox }
    guard let disclaim = Self.disclaim else { throw Failure.noDisclaim }

    var toChild: [Int32] = [0, 0]
    var fromChild: [Int32] = [0, 0]
    var said: [Int32] = [0, 0]
    guard pipe(&toChild) == 0 else { throw Failure.spawn(errno) }
    guard pipe(&fromChild) == 0 else {
      let code = errno
      toChild.forEach { close($0) }
      throw Failure.spawn(code)
    }
    guard pipe(&said) == 0 else {
      let code = errno
      (toChild + fromChild).forEach { close($0) }
      throw Failure.spawn(code)
    }
    defer {
      close(toChild[0])
      close(fromChild[1])
      close(said[1])
    }
    for fd in [toChild[1], fromChild[0], said[0]] { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
    // Never waited on, a program it started may hold the other end after it went.
    for fd in [fromChild[0], said[0]] { _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) }
    // A plugin gone while a write is on its way answers EPIPE rather than a signal that kills Olm.
    _ = fcntl(toChild[1], F_SETNOSIGPIPE, 1)

    var actions: posix_spawn_file_actions_t? = nil
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_adddup2(&actions, toChild[0], 0)
    posix_spawn_file_actions_adddup2(&actions, fromChild[1], 1)
    posix_spawn_file_actions_adddup2(&actions, said[1], 2)

    var attr: posix_spawnattr_t? = nil
    posix_spawnattr_init(&attr)
    defer { posix_spawnattr_destroy(&attr) }
    // Every descriptor of Olm's closed in the child but the three above, and a group of its own.
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
    posix_spawnattr_setpgroup(&attr, 0)
    var all = sigset_t()
    sigfillset(&all)
    posix_spawnattr_setsigdefault(&attr, &all)
    var none = sigset_t()
    sigemptyset(&none)
    posix_spawnattr_setsigmask(&attr, &none)
    posix_spawnattr_set_qos_class_np(&attr, qos)
    _ = disclaim(&attr, 1)

    let argv = [sandboxExec, "-p", rules, executable.path]
    let env = environment.map { "\($0.key)=\($0.value)" }
    var cargv = argv.map { strdup($0) } + [nil]
    var cenv = env.map { strdup($0) } + [nil]
    defer {
      cargv.forEach { free($0) }
      cenv.forEach { free($0) }
    }
    var pid: pid_t = 0
    let rc = posix_spawn(&pid, sandboxExec, &actions, &attr, &cargv, &cenv)
    guard rc == 0 else {
      close(toChild[1])
      close(fromChild[0])
      close(said[0])
      throw Failure.spawn(rc)
    }
    let process = PluginProcess(pid: pid, input: toChild[1], output: fromChild[0], errors: said[0], label: label)
    process.listen()
    return process
  }

  // The private call macOS's own Terminal makes, so the child answers for its own macOS permissions
  // rather than borrowing Olm's. Proved on 2026-11-20: without it a child read the Accessibility
  // grant of the program that started it, with it the child had none. nil where macOS dropped it.
  private typealias DisclaimFn = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
  private static let disclaim: DisclaimFn? = {
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim") else { return nil }
    return unsafeBitCast(sym, to: DisclaimFn.self)
  }()

  private func listen() {
    let read = DispatchSource.makeReadSource(fileDescriptor: output, queue: queue)
    read.setEventHandler { [weak self] in self?.drain() }
    read.setCancelHandler { [output] in close(output) }
    readSource = read
    read.resume()
    let said = DispatchSource.makeReadSource(fileDescriptor: errors, queue: queue)
    said.setEventHandler { [weak self] in self?.drainErrors() }
    said.setCancelHandler { [errors] in close(errors) }
    errorSource = said
    said.resume()
    let exit = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
    exit.setEventHandler { [weak self] in
      guard let self else { return }
      var status: Int32 = 0
      waitpid(self.pid, &status, 0)
      self.exitSource?.cancel()
      // What it wrote before it went is read first, so its last answer is not lost.
      self.drain()
      self.drainErrors()
      self.say(all: true)
      self.endOutput()
      self.endErrors()
      self.continuation.yield(.exited(status))
      self.continuation.finish()
    }
    exitSource = exit
    exit.resume()
  }

  private func endOutput() {
    outputOpen = false
    readSource?.cancel()
  }

  private func endErrors() {
    errorsOpen = false
    errorSource?.cancel()
  }

  // A read at a time, so a plugin that writes without end holds only itself.
  private func drainErrors() {
    guard errorsOpen else { return }
    var buffer = [UInt8](repeating: 0, count: 65536)
    let n = Darwin.read(errors, &buffer, buffer.count)
    if n == 0 { endErrors() }
    guard n > 0 else { return }
    line.append(contentsOf: buffer[0..<n])
    say(all: false)
  }

  private func say(all: Bool) {
    var rest = line[...]
    while let end = rest.firstIndex(of: 10) {
      yieldLine(rest[..<end])
      rest = rest[(end + 1)...]
    }
    if all || rest.count > 8192 {
      yieldLine(rest)
      rest = rest[rest.endIndex...]
    }
    line = Data(rest)
  }

  private func yieldLine(_ bytes: Data) {
    guard !bytes.isEmpty else { return }
    if Date().timeIntervalSince(passed.since) > PluginLog.window { passed = (Date(), 0) }
    passed.lines += 1
    if passed.lines <= PluginLog.burst + 1 { continuation.yield(.said(String(decoding: bytes.prefix(8192), as: UTF8.self))) }
  }

  private func drain() {
    guard outputOpen else { return }
    var buffer = [UInt8](repeating: 0, count: 65536)
    while true {
      let n = Darwin.read(output, &buffer, buffer.count)
      if n <= 0 {
        if n == 0 { endOutput() }
        return
      }
      do {
        for message in try reader.feed(Data(buffer[0..<n])) { continuation.yield(.message(message)) }
      } catch {
        continuation.yield(.broken("\(error)"))
        endOutput()
        return
      }
      if n < buffer.count { return }
    }
  }

  /// One message, framed and written on the writer's queue, dropped once the input is closed.
  func send(_ body: Data) {
    let framed = Frame.encode(body)
    writer.async { [self] in
      guard inputOpen else { return }
      framed.withUnsafeBytes { raw in
        var offset = 0
        while offset < raw.count {
          let n = Darwin.write(input, raw.baseAddress! + offset, raw.count - offset)
          if n < 0 {
            if errno == EINTR { continue }
            return
          }
          offset += n
        }
      }
    }
  }

  /// Its stdin closed, which a plugin reads as the app asking it to go.
  func closeInput() {
    writer.async { [self] in
      guard inputOpen else { return }
      inputOpen = false
      close(input)
    }
  }

  /// The plugin and every program it started, at once.
  func kill() {
    _ = Darwin.kill(-pid, SIGKILL)
    _ = Darwin.kill(pid, SIGKILL)
    closeInput()
  }

  /// Its memory, the footprint Activity Monitor shows, and the processor time it has used, nil once
  /// it is gone.
  func usage() -> (footprint: UInt64, cpu: Double)? {
    var info = rusage_info_v4()
    let rc = withUnsafeMutablePointer(to: &info) { p in
      p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    guard rc == 0 else { return nil }
    let ticks = Double(info.ri_user_time + info.ri_system_time)
    return (info.ri_phys_footprint, ticks * Self.secondsPerTick)
  }

  private static let secondsPerTick: Double = {
    var base = mach_timebase_info_data_t()
    mach_timebase_info(&base)
    return Double(base.numer) / Double(base.denom) / 1e9
  }()
}
