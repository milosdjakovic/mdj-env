// Pictures of files, step 1.4b of docs/PLAN-STANDALONE.md, the port of plugins/filesearch/thumbs.lua.
// The same chain over the same two generators, in the same order. A raster or an icon set no larger
// than nativeMaxBytes is drawn from the file itself, and everything else the chain covers, a larger
// raster among it, is rendered by Quick Look with the very invocation the Lua side runs, qlmanage -t
// at imageEdge, so the two panes are handed the same pixels.
//
// A plugin never holds a picture, docs/DESIGN-APP.md, so what this answers is a path, the file
// itself or the render, and the core reads, decodes and scales it off the main thread. Nothing here
// decodes an image. The in process generator reads only the file's header, to say no preview for a
// file the system cannot read, as hs.image answering nil does on the Lua side.
//
// THE RENDERS HAVE ONE OWNER EACH, rule 1 of the plan. The app keeps its own under
// `~/.olm/cache/filesearch/previews-app`, named and swept as the Lua side names and sweeps its own,
// and only reads the Lua side's directory, the preview block's cacheDir, so a file already rendered
// there costs no second render while both sides run. The app never writes, renames or sweeps there,
// since the Lua side's scratch directory for a render is named after the render, and a second
// writer running the same render would rename it out from under the first.
//
// A render runs off every thread the app cares about, a process of its own, bounded by
// renderSeconds, and two asks for one file join one render, as the Lua side's inflight does. It is
// ended when the last row waiting on it is left, so skimming past a folder of documents does not
// leave a queue of renders nobody will see, and a render ended that way is not remembered as a
// failure. A render that fails is, for the open, as the Lua pane's images memo holds false.

import CryptoKit
import Foundation
import ImageIO

/// What the picture of one row is, as the chain answers it.
public enum PictureState: Equatable, Sendable {
  /// A picture file to draw, the source file or its render.
  case ready(String)
  /// Quick Look is rendering it, and the pane says so until it lands.
  case rendering
  /// Nothing could draw it.
  case failed
}

/// One file the pane asks a picture of, thumbs.lua's spec with what the file was.
public struct ThumbSpec: Equatable, Sendable {
  public var path: String
  public var ext: String
  /// The stat the preview's read made, nil for a path that is gone.
  public var size: Int?
  public var modification: Int?

  public init(path: String, ext: String, size: Int?, modification: Int?) {
    self.path = path
    self.ext = ext
    self.size = size
    self.modification = modification
  }
}

public enum ThumbChain {
  /// thumbs.lua's NATIVE_EXT, what the system decodes from the file itself.
  public static let nativeExtensions: Set<String> = [
    "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "webp", "icns", "ico",
  ]

  /// thumbs.lua's QL_EXT, what Quick Look is asked for. It also takes the native types, as the
  /// backstop for a raster the in process generator steps aside from.
  public static let quickLookExtensions: Set<String> = [
    "pdf", "svg", "eps", "ai", "psd",
    "mp4", "mov", "m4v", "mkv", "avi", "webm",
    "doc", "docx", "pages", "rtf", "odt", "epub",
    "xls", "xlsx", "numbers", "csv",
    "ppt", "pptx", "key",
    "app",
  ]

  /// thumbs.handles, every type some generator covers.
  public static let extensions = nativeExtensions.union(quickLookExtensions)

  public enum Generator: Equatable, Sendable {
    case native, quickLook
  }

  /// The first generator that covers the type and takes this file. The in process one takes a file
  /// no larger than nativeMaxBytes, or one whose size is not known, as nativeGen's accepts.
  public static func generator(for spec: ThumbSpec, nativeMaxBytes: Int) -> Generator? {
    if nativeExtensions.contains(spec.ext), (spec.size ?? 0) <= nativeMaxBytes { return .native }
    if quickLookExtensions.contains(spec.ext) || nativeExtensions.contains(spec.ext) { return .quickLook }
    return nil
  }

  /// thumbs.lua's cacheName, the MD5 of the path, the size and the modification time, Lua's tostring
  /// of each, so the two sides name one version of one file alike.
  public static func cacheName(_ spec: ThumbSpec) -> String {
    let key = "\(spec.path)|\(spec.size.map(String.init) ?? "nil")|\(spec.modification.map(String.init) ?? "nil")"
    return Insecure.MD5.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".png"
  }

  /// Quick Look, at the fixed path a system binary lives at, declared in the Lua manifest's
  /// needs.tools as the system kind.
  public static let qlmanage = "/usr/bin/qlmanage"

  /// qlGen's arguments, a thumbnail whose larger edge is edge pixels, written into scratch.
  public static func quickLookArguments(edge: Int, scratch: String, path: String) -> [String] {
    ["-t", "-s", String(edge), "-o", scratch, path]
  }

  /// The longest a render may run before it is ended and the row says no preview. The Lua side has
  /// no bound, and a render measured on 2026-11-08 took under a second.
  public static let renderSeconds = 20.0

  /// Whether the system can read the file as a picture, from its header alone, the in process
  /// generator's answer short of decoding it.
  static func readable(_ path: String) -> Bool {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
      CGImageSourceGetCount(source) > 0,
      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let w = props[kCGImagePropertyPixelWidth] as? NSNumber, w.intValue > 0 else { return false }
    return true
  }
}

/// The chain over one cache directory of the app's own, one per file search source.
public actor Thumbs {
  private let dir: URL
  private final class Render {
    var task: Task<String?, Never>?
    var process: Job?
    // The rows waiting on it, and how many of them have since moved on.
    var waiters = 0
    var left = 0
    var ended = false
  }
  // A render's process, handed to the thread that runs it and ended from here, before or after it
  // starts, since a process may only be ended once it runs.
  private final class Job: @unchecked Sendable {
    let process = Process()
    private let lock = NSLock()
    private var started = false
    private var stopped = false

    func start() -> Bool {
      lock.withLock {
        guard !stopped, (try? process.run()) != nil else { return false }
        started = true
        return true
      }
    }

    func stop() {
      lock.withLock {
        stopped = true
        if started, process.isRunning { process.terminate() }
      }
    }
  }
  // The renders running, by destination.
  private var inflight: [String: Render] = [:]
  // The renders that failed this open, by name.
  private var failed: Set<String> = []
  private var swept = false

  /// dir is where the app keeps its renders, made the first time one is needed.
  public init(dir: URL) {
    self.dir = dir
  }

  /// A new open, which tries a render that failed in the last one again.
  public func forget() {
    failed = []
  }

  /// What the chain answers at once for a file, the source file, a render already made on either
  /// side, or rendering when a render has been started. shared is the Lua side's directory, read
  /// only.
  public func picture(_ spec: ThumbSpec, limits: PreviewLimits) -> PictureState {
    switch ThumbChain.generator(for: spec, nativeMaxBytes: limits.nativeMaxBytes) {
    case nil:
      return .failed
    case .native:
      return ThumbChain.readable(spec.path) ? .ready(spec.path) : .failed
    case .quickLook:
      let name = ThumbChain.cacheName(spec)
      if failed.contains(name) { return .failed }
      let dest = dir.appendingPathComponent(name).path
      if FileManager.default.fileExists(atPath: dest) { return .ready(dest) }
      if let shared = limits.cacheDir {
        let theirs = (shared as NSString).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: theirs) { return .ready(theirs) }
      }
      start(spec, dest: dest, limits: limits)
      return .rendering
    }
  }

  /// What a render picture answered rendering for comes to, waited for. A wait cancelled by the
  /// highlight moving on answers rendering, and ends the render when no other row waits on it.
  public func landed(_ spec: ThumbSpec, limits: PreviewLimits) async -> PictureState {
    let name = ThumbChain.cacheName(spec)
    let dest = dir.appendingPathComponent(name).path
    if failed.contains(name) { return .failed }
    guard let render = inflight[dest], let task = render.task else {
      return FileManager.default.fileExists(atPath: dest) ? .ready(dest) : .failed
    }
    render.waiters += 1
    let made = await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      Task { await self.leave(dest) }
    }
    if Task.isCancelled { return .rendering }
    return made.map { .ready($0) } ?? (render.ended ? .rendering : .failed)
  }

  // A row stopped waiting, and the render ends when it was the last.
  private func leave(_ dest: String) {
    guard let render = inflight[dest], !render.ended else { return }
    render.left += 1
    guard render.left >= render.waiters else { return }
    render.ended = true
    render.process?.stop()
  }

  private func start(_ spec: ThumbSpec, dest: String, limits: PreviewLimits) {
    guard inflight[dest] == nil else { return }
    let dir = self.dir
    let render = Render()
    inflight[dest] = render
    let job = Job()
    let process = job.process
    process.executableURL = URL(fileURLWithPath: ThumbChain.qlmanage)
    // Its own scratch directory per render, so the name qlmanage writes need only be found, and
    // nothing half written is ever at the destination the next ask looks at.
    let scratch = String(dest.dropLast(4)) + ".d"
    process.arguments = ThumbChain.quickLookArguments(edge: limits.imageEdge, scratch: scratch, path: spec.path)
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    render.process = job
    let sweep = !swept
    swept = true
    let keep = limits.cacheFiles
    let name = (dest as NSString).lastPathComponent
    render.task = Task {
      // On a dispatch thread rather than the cooperative pool, since the render waits on a process.
      let made = await withCheckedContinuation { (done: CheckedContinuation<String?, Never>) in
        DispatchQueue.global(qos: .userInitiated).async {
          let made = Self.render(job, dir: dir, scratch: scratch, dest: dest)
          if sweep { Self.sweep(dir, keep: keep) }
          done.resume(returning: made)
        }
      }
      self.finished(dest, name: name, made: made)
      return made
    }
  }

  private func finished(_ dest: String, name: String, made: String?) {
    if made == nil, inflight[dest]?.ended != true { failed.insert(name) }
    inflight[dest] = nil
  }

  // The render itself, on a thread of its own, answering the destination once the render is there.
  private static func render(_ job: Job, dir: URL, scratch: String, dest: String) -> String? {
    let process = job.process
    let fm = FileManager.default
    defer { try? fm.removeItem(atPath: scratch) }
    do {
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      try fm.createDirectory(atPath: scratch, withIntermediateDirectories: true)
    } catch {
      return nil
    }
    let done = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in done.signal() }
    guard job.start() else { return nil }
    if done.wait(timeout: .now() + ThumbChain.renderSeconds) == .timedOut {
      job.stop()
      done.wait()
      return nil
    }
    guard process.terminationReason == .exit,
      let produced = (try? fm.contentsOfDirectory(atPath: scratch))?.first(where: { $0.hasSuffix(".png") })
    else { return nil }
    // Moved into place, within one directory so the rename is atomic, which is what makes a cache
    // entry appear whole.
    let from = (scratch as NSString).appendingPathComponent(produced)
    if rename(from, dest) == 0 { return dest }
    return nil
  }

  // thumbs.lua's sweep, the oldest renders past cacheFiles removed, once per run of the app.
  private static func sweep(_ dir: URL, keep: Int) {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
    var files: [(path: String, at: Date)] = []
    for name in names where name.hasSuffix(".png") {
      let path = dir.appendingPathComponent(name).path
      let at = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
      files.append((path, at))
    }
    let excess = files.count - keep
    guard excess > 0 else { return }
    for file in files.sorted(by: { $0.at < $1.at }).prefix(excess) { try? fm.removeItem(atPath: file.path) }
  }
}
