// olm://ping?nonce=N, the test step 1.1 of docs/PLAN-STANDALONE.md names. It writes N to
// ~/.olm/run/ping so a test can tell this app answered it.

import Foundation

enum Ping {
  /// The nonce a ping carries, or nil when the URL is not a well formed ping. A nonce is what a
  /// test wrote, so it is short and plain, and anything else is refused rather than written.
  static func nonce(_ url: URL) -> String? {
    guard url.scheme == "olm", url.host == "ping",
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
      let nonce = items.first(where: { $0.name == "nonce" })?.value,
      !nonce.isEmpty, nonce.count <= 64,
      nonce.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
    else { return nil }
    return nonce
  }

  /// Writes the nonce through a temporary file and a rename, so a reader never sees half of it.
  static func answer(_ nonce: String, in dir: URL) {
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let tmp = dir.appendingPathComponent("ping.tmp")
      try (nonce + "\n").write(to: tmp, atomically: false, encoding: .utf8)
      _ = try FileManager.default.replaceItemAt(dir.appendingPathComponent("ping"), withItemAt: tmp)
    } catch {
      NSLog("Olm: could not answer a ping, %@", "\(error)")
    }
  }
}
