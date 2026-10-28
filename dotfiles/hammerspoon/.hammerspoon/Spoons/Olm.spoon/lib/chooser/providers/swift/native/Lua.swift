// Reading Lua values into Swift and pushing Swift values back, the plumbing every other file here
// leans on. It knows the Lua stack and nothing about a chooser, so the panel's files read a table
// field by name and never touch an index by hand.

import Cocoa

// Lua's state arrives as a typed pointer here, since LuaSkin's headers make its struct complete.
public typealias LuaState = UnsafeMutablePointer<lua_State>

// One argument of an event Swift sends to Lua.
enum LuaValue {
  case string(String)
  case bytes(Data)
  case int(Int)
  case number(Double)
  case bool(Bool)
  case none
}

func pushValue(_ L: LuaState?, _ value: LuaValue) {
  switch value {
  case .string(let text): _ = lua_pushstring(L, text)
  case .bytes(let data): data.withUnsafeBytes { raw in olm_pushBytes(L, raw.baseAddress, raw.count) }
  case .int(let number): lua_pushinteger(L, lua_Integer(number))
  case .number(let number): lua_pushnumber(L, number)
  case .bool(let flag): lua_pushboolean(L, flag ? 1 : 0)
  case .none: lua_pushnil(L)
  }
}

// Reads values off the stack and fields off tables, every answer nil when the value is missing
// or of another type, so a caller writes one fallback rather than a type check.
struct LuaReader {
  let L: LuaState?

  init(_ L: LuaState?) { self.L = L }

  func absolute(_ index: Int32) -> Int32 { lua_absindex(L, index) }

  func isTable(_ index: Int32) -> Bool { lua_type(L, index) == LUA_TTABLE }

  func string(at index: Int32) -> String? {
    guard lua_type(L, index) == LUA_TSTRING else { return nil }
    var length = 0
    guard let raw = lua_tolstring(L, index, &length) else { return nil }
    return String(decoding: UnsafeRawBufferPointer(start: raw, count: length), as: UTF8.self)
  }

  func bytes(at index: Int32) -> Data? {
    guard lua_type(L, index) == LUA_TSTRING else { return nil }
    var length = 0
    guard let raw = lua_tolstring(L, index, &length) else { return nil }
    return Data(bytes: raw, count: length)
  }

  func number(at index: Int32) -> Double? {
    lua_type(L, index) == LUA_TNUMBER ? olm_toNumber(L, index) : nil
  }

  func integer(at index: Int32) -> Int? {
    lua_type(L, index) == LUA_TNUMBER ? Int(olm_toInteger(L, index)) : nil
  }

  // Pushes table[name], runs read on it, and pops it again whatever read answered.
  func field<T>(_ table: Int32, _ name: String, _ read: (Int32) -> T?) -> T? {
    guard isTable(table) else { return nil }
    _ = lua_getfield(L, table, name)
    defer { olm_pop(L, 1) }
    return read(lua_gettop(L))
  }

  func string(_ table: Int32, _ name: String) -> String? { field(table, name) { string(at: $0) } }

  func number(_ table: Int32, _ name: String) -> CGFloat? {
    field(table, name) { number(at: $0).map { CGFloat($0) } }
  }

  func integer(_ table: Int32, _ name: String) -> Int? { field(table, name) { integer(at: $0) } }

  func bool(_ table: Int32, _ name: String) -> Bool? {
    field(table, name) { lua_type(L, $0) == LUA_TBOOLEAN ? lua_toboolean(L, $0) != 0 : nil }
  }

  // A colour table as the UI kit writes one, red, green, blue and alpha between zero and one.
  func color(_ table: Int32, _ name: String) -> NSColor? {
    field(table, name) { index in
      guard isTable(index), let r = number(index, "red"), let g = number(index, "green"),
        let b = number(index, "blue")
      else { return nil }
      return NSColor(srgbRed: r, green: g, blue: b, alpha: number(index, "alpha") ?? 1)
    }
  }

  // A font as a name and a size, the system font of that size when the name is not installed.
  func font(_ table: Int32, _ name: String) -> NSFont? {
    field(table, name) { index in
      guard isTable(index), let size = number(index, "size") else { return nil }
      if let face = string(index, "name"), let font = NSFont(name: face, size: size) { return font }
      return NSFont.systemFont(ofSize: size)
    }
  }

  func rect(_ table: Int32, _ name: String) -> NSRect? {
    field(table, name) { index in
      guard isTable(index), let x = number(index, "x"), let y = number(index, "y"),
        let w = number(index, "w"), let h = number(index, "h")
      else { return nil }
      return NSRect(x: x, y: y, width: w, height: h)
    }
  }

  // An hs.image, converted through the helper Hammerspoon's image module registers with LuaSkin.
  func image(_ table: Int32, _ name: String) -> NSImage? {
    field(table, name) { index in
      guard lua_type(L, index) == LUA_TUSERDATA, let L else { return nil }
      let skin = LuaSkin.shared(with: L) as! LuaSkin
      return skin.luaObject(at: index, toClass: "NSImage") as? NSImage
    }
  }

  // Calls body once per element of the array at table[name], each pushed while body runs.
  func each(_ table: Int32, _ name: String, _ body: (Int32) -> Void) {
    _ = field(table, name) { index -> Bool? in
      guard isTable(index) else { return nil }
      let count = lua_rawlen(L, index)
      guard count > 0 else { return nil }
      for i in 1...count {
        _ = lua_rawgeti(L, index, lua_Integer(i))
        body(lua_gettop(L))
        olm_pop(L, 1)
      }
      return nil
    }
  }
}
