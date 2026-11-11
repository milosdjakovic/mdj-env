// Files iCloud holds only as placeholders, step 1.4i, docs/DESIGN-APP-DOWNLOAD.md. Three questions
// and nothing else, whether a path is a placeholder, asking iCloud for one, and how far a download
// has come, each a closure so a check stands in for all three, since no check can make iCloud evict
// a file. The source keeps which paths it asked for, so this holds no state of its own.

import Foundation

public struct CloudFiles: Sendable {
  /// Whether the file's contents are not on this Mac, the stat flag 1.4b reads, which never fetches.
  public let isPlaceholder: @Sendable (String) -> Bool
  /// Asks iCloud for the file and returns at once, false where no iCloud container claims the path.
  public let download: @Sendable (String) -> Bool
  /// Starts following how many bytes of the file have come down, read from what it answers until
  /// it is stopped.
  public let watch: @Sendable (String) -> CloudProgress

  public init(isPlaceholder: @escaping @Sendable (String) -> Bool,
              download: @escaping @Sendable (String) -> Bool,
              watch: @escaping @Sendable (String) -> CloudProgress = { _ in CloudProgress() }) {
    self.isPlaceholder = isPlaceholder
    self.download = download
    self.watch = watch
  }

  /// The real ones, the stat flag, the system's own request, and the progress the system publishes
  /// for a file on its way, the one Finder draws its pie from, measured on 2026-11-11 to answer a
  /// few times a second with no entitlement.
  public static let system = CloudFiles(
    isPlaceholder: { Peek.attributes($0)?.dataless ?? false },
    download: { path in
      (try? FileManager.default.startDownloadingUbiquitousItem(at: URL(fileURLWithPath: path))) != nil
    },
    watch: { path in
      let progress = CloudProgress()
      // The subscriber is answered on the main run loop, which a source's actor does not have.
      DispatchQueue.main.async { progress.subscribe(URL(fileURLWithPath: path)) }
      return progress
    })
}

extension CloudFiles {
  /// A stand in for looking at the meter, OLM_DEMO_DOWNLOAD in main.swift. Every placeholder is
  /// one as the stat says, Download asks iCloud nothing, and the download stands still at fraction
  /// of the file's size, so the pane holds the meter there for as long as the row is highlighted.
  public static func demo(fraction: Double) -> CloudFiles {
    CloudFiles(isPlaceholder: system.isPlaceholder, download: { _ in true }, watch: { path in
      let progress = CloudProgress()
      let size = Int64(Peek.attributes(path)?.attrs.size ?? 0)
      progress.set(done: Int64(Double(size) * min(1, max(0, fraction))), total: size)
      return progress
    })
  }
}

/// How far one download has come, written from the system's thread and read from the source's.
public final class CloudProgress: @unchecked Sendable {
  private let lock = NSLock()
  private var done: Int64 = 0
  private var total: Int64 = 0
  private var subscriber: Any?
  private var observation: NSKeyValueObservation?
  private var stopped = false

  public init() {}

  /// The bytes come down and the whole, nil until the system has said how big the whole is.
  public var bytes: (done: Int64, total: Int64)? {
    lock.withLock { total > 0 ? (done, total) : nil }
  }

  /// Written by the system's subscriber, and by a check standing in for it.
  public func set(done: Int64, total: Int64) {
    lock.withLock {
      self.done = done
      self.total = total
    }
  }

  /// Stops following, the subscriber removed on the main thread where it was made.
  public func stop() {
    let held: Any? = lock.withLock {
      stopped = true
      let held = subscriber
      subscriber = nil
      observation = nil
      return held
    }
    guard let held else { return }
    nonisolated(unsafe) let token = held
    DispatchQueue.main.async { Progress.removeSubscriber(token) }
  }

  fileprivate func subscribe(_ url: URL) {
    if lock.withLock({ stopped }) { return }
    let made = Progress.addSubscriber(forFileURL: url) { [weak self] published in
      guard let self else { return nil }
      self.set(done: published.completedUnitCount, total: published.totalUnitCount)
      let seen = published.observe(\.completedUnitCount) { [weak self] p, _ in
        self?.set(done: p.completedUnitCount, total: p.totalUnitCount)
      }
      self.lock.withLock { self.observation = seen }
      return { [weak self] in
        guard let self else { return }
        self.lock.withLock { self.observation = nil }
      }
    }
    lock.withLock { subscriber = made }
  }
}
