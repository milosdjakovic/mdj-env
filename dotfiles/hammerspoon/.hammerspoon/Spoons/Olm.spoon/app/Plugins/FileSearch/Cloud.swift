// Files iCloud holds only as placeholders, step 1.4i, docs/DESIGN-APP-DOWNLOAD.md. Two questions
// and nothing else, whether a path is a placeholder and asking iCloud for one, each a closure so a
// check stands in for both, since no check can make iCloud evict a file. The source keeps which
// paths it asked for, so this holds no state.

import Foundation

public struct CloudFiles: Sendable {
  /// Whether the file's contents are not on this Mac, the stat flag 1.4b reads, which never fetches.
  public let isPlaceholder: @Sendable (String) -> Bool
  /// Asks iCloud for the file and returns at once, false where no iCloud container claims the path.
  public let download: @Sendable (String) -> Bool

  public init(isPlaceholder: @escaping @Sendable (String) -> Bool,
              download: @escaping @Sendable (String) -> Bool) {
    self.isPlaceholder = isPlaceholder
    self.download = download
  }

  /// The real ones, the stat flag and the system's own request.
  public static let system = CloudFiles(
    isPlaceholder: { Peek.attributes($0)?.dataless ?? false },
    download: { path in
      (try? FileManager.default.startDownloadingUbiquitousItem(at: URL(fileURLWithPath: path))) != nil
    })
}
