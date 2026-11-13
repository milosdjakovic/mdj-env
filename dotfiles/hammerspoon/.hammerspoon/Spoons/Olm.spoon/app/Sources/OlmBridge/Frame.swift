// The bridge's framing, docs/PROTOCOL-BRIDGE.md, chosen by step 2.1's probe. A message is its length
// in bytes as decimal digits, one newline, then exactly that many bytes of JSON, at most 8 MiB. The
// twin of host/bridge/frame.lua.

import Foundation

public enum Frame {
  public static let max = 8 * 1024 * 1024

  /// One message as it goes on the connection.
  public static func encode(_ body: Data) -> Data {
    Data("\(body.count)\n".utf8) + body
  }

  public enum Failure: Error, Equatable {
    /// A length line that is not digits, or longer than any allowed length could be.
    case badLength
    /// A length past the limit.
    case tooLong(Int)
  }

  /// Takes bytes as they arrive and answers every message they complete, in order.
  public struct Reader {
    private var buffer = Data()
    private var want: Int? = nil

    public init() {}

    public mutating func feed(_ bytes: Data) throws -> [Data] {
      buffer.append(bytes)
      var out: [Data] = []
      while true {
        if want == nil {
          guard let nl = buffer.firstIndex(of: 0x0A) else {
            // Eight digits and the newline cover the limit, so a longer line is no length at all.
            if buffer.count > 9 { throw Failure.badLength }
            return out
          }
          let line = buffer[buffer.startIndex..<nl]
          guard !line.isEmpty, line.count <= 8, line.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
            let n = Int(String(decoding: line, as: UTF8.self)) else { throw Failure.badLength }
          if n > Frame.max { throw Failure.tooLong(n) }
          want = n
          buffer = Data(buffer[(nl + 1)...])
        }
        guard let n = want, buffer.count >= n else { return out }
        out.append(Data(buffer.prefix(n)))
        buffer = Data(buffer.dropFirst(n))
        want = nil
      }
    }
  }
}
