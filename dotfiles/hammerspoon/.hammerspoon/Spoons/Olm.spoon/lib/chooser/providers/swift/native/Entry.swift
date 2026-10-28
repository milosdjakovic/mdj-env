// The Lua face of the native chooser. luaopen_olm_swiftchooser is what package.loadlib calls, and
// it answers a table of plain functions, one per thing the Lua adapter asks of the panel. The
// spike holds one panel, which is all a single chooser on screen needs.
//
// A Swift image is never unloaded, so this file outlives every Hammerspoon reload while the Lua
// state it talks to does not. Each reload calls luaopen again in a fresh state, so luaopen drops
// the panel and the callback reference the old state left behind before answering anything.

import Cocoa

// Lua's state arrives as a typed pointer here, since LuaSkin's headers make its struct complete.
public typealias LuaState = UnsafeMutablePointer<lua_State>

private var panel: ChooserPanel?
private var callbackRef: Int32 = olm_noRef()

private func current() -> ChooserPanel {
  if let existing = panel { return existing }
  let made = ChooserPanel(onEvent: emit)
  panel = made
  return made
}

// Calls the Lua callback on the main Lua state, the one LuaSkin says every callback belongs on,
// with an event name and one payload, a string, a row number or nothing.
private func emit(_ event: String, _ payload: Any?) {
  guard callbackRef != olm_noRef(), let L = LuaSkin.mainLuaState else { return }
  let skin = LuaSkin.shared(with: L) as! LuaSkin
  _ = lua_rawgeti(L, olm_registryIndex(), lua_Integer(callbackRef))
  lua_pushstring(L, event)
  switch payload {
  case let text as String: lua_pushstring(L, text)
  case let number as Int: lua_pushinteger(L, lua_Integer(number))
  default: lua_pushnil(L)
  }
  _ = skin.protectedCallAndError("olm swift chooser callback", nargs: 2, nresults: 0)
}

private func argString(_ L: LuaState?, _ idx: Int32) -> String {
  guard let raw = olm_toString(L, idx) else { return "" }
  return String(cString: raw)
}

private let setCallback: lua_CFunction = { L in
  if callbackRef != olm_noRef() { luaL_unref(L, olm_registryIndex(), callbackRef) }
  callbackRef = olm_noRef()
  if olm_isFunction(L, 1) != 0 {
    lua_pushvalue(L, 1)
    callbackRef = luaL_ref(L, olm_registryIndex())
  }
  return 0
}

private let show: lua_CFunction = { L in
  current().present(activate: lua_toboolean(L, 1) != 0)
  return 0
}

private let hide: lua_CFunction = { _ in
  panel?.dismiss(notify: false)
  return 0
}

private let isShowing: lua_CFunction = { L in
  lua_pushboolean(L, (panel?.isShowing ?? false) ? 1 : 0)
  return 1
}

private let isKey: lua_CFunction = { L in
  lua_pushboolean(L, (panel?.isKey ?? false) ? 1 : 0)
  return 1
}

private let setRows: lua_CFunction = { L in
  var rows: [String] = []
  if olm_isTable(L, 1) != 0 {
    let count = lua_rawlen(L, 1)
    if count > 0 {
      for i in 1...count {
        _ = lua_rawgeti(L, 1, lua_Integer(i))
        rows.append(argString(L, -1))
        olm_pop(L, 1)
      }
    }
  }
  current().setRows(rows)
  return 0
}

private let setQuery: lua_CFunction = { L in
  current().query = argString(L, 1)
  return 0
}

private let query: lua_CFunction = { L in
  lua_pushstring(L, current().query)
  return 1
}

private let setPlaceholder: lua_CFunction = { L in
  current().placeholder = argString(L, 1)
  return 0
}

private let selectedRow: lua_CFunction = { L in
  lua_pushinteger(L, lua_Integer(current().selectedRow))
  return 1
}

// Which surface the panel was built on, glass where the running macOS has it and the older
// visual effect view where it does not, so a probe can say what it is looking at.
private let surface: lua_CFunction = { L in
  lua_pushstring(L, current().surfaceName)
  return 1
}

@_cdecl("luaopen_olm_swiftchooser")
public func luaopen_olm_swiftchooser(_ L: LuaState?) -> Int32 {
  panel?.dismiss(notify: false)
  panel = nil
  callbackRef = olm_noRef()

  olm_newTable(L)
  olm_setFunction(L, "setCallback", setCallback)
  olm_setFunction(L, "show", show)
  olm_setFunction(L, "hide", hide)
  olm_setFunction(L, "isShowing", isShowing)
  olm_setFunction(L, "isKey", isKey)
  olm_setFunction(L, "setRows", setRows)
  olm_setFunction(L, "setQuery", setQuery)
  olm_setFunction(L, "query", query)
  olm_setFunction(L, "setPlaceholder", setPlaceholder)
  olm_setFunction(L, "selectedRow", selectedRow)
  olm_setFunction(L, "surface", surface)
  return 1
}
