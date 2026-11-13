// A JSON value that can cross from the listener's queue to an actor, since what JSONSerialization
// answers is not Sendable. Only the bridge reads it, docs/PROTOCOL-BRIDGE.md.

import Foundation

public enum JSON: Sendable, Equatable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSON])
  case object([String: JSON])

  public init(_ any: Any?) {
    switch any {
    case nil, is NSNull: self = .null
    case let n as NSNumber:
      self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
    case let s as String: self = .string(s)
    case let a as [Any]: self = .array(a.map { JSON($0) })
    case let d as [String: Any]: self = .object(d.mapValues { JSON($0) })
    default: self = .null
    }
  }

  public static func decode(_ data: Data) -> JSON? {
    guard let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
    return JSON(any)
  }

  public var any: Any {
    switch self {
    case .null: return NSNull()
    case .bool(let b): return b
    case .number(let n): return n.rounded() == n && abs(n) < 9e15 ? Int(n) as Any : n as Any
    case .string(let s): return s
    case .array(let a): return a.map(\.any)
    case .object(let o): return o.mapValues(\.any)
    }
  }

  public func encoded() -> Data? {
    try? JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed])
  }

  public subscript(_ key: String) -> JSON {
    if case .object(let o) = self { return o[key] ?? .null }
    return .null
  }

  public var string: String? { if case .string(let s) = self { return s }; return nil }
  public var number: Double? { if case .number(let n) = self { return n }; return nil }
  public var int: Int? { number.flatMap { $0.rounded() == $0 && abs($0) < 9e15 ? Int($0) : nil } }
  public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
  /// An array, and an empty object as an empty array, since Lua writes an empty list as either.
  public var array: [JSON]? {
    switch self {
    case .array(let a): return a
    case .object(let o) where o.isEmpty: return []
    default: return nil
    }
  }
  public var object: [String: JSON]? { if case .object(let o) = self { return o }; return nil }
  public var isNull: Bool { self == .null }
}
