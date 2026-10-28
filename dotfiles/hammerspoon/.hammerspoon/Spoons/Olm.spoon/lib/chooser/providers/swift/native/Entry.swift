// The Lua face of the native chooser. luaopen_olm_swiftchooser is what package.loadlib calls, and
// it answers a table of plain functions, each taking a panel's id first, one per thing the Lua
// view asks of its panel. new makes a panel and answers its id, so every picker instance the
// engine builds has a panel of its own.
//
// Every event goes back through the one callback setCallback registers, called as
// callback(id, event, ...) on the main Lua state, the state LuaSkin says every callback belongs
// on. Its first result is read as a boolean, which is how yields and listKey answer whether the
// engine claimed a key before the field edits.
//
// A Swift image is never unloaded, so this file outlives every Hammerspoon reload while the Lua
// state it talks to does not. Each reload calls luaopen again in a fresh state, so luaopen hides
// every panel the old state left behind, stops their monitors, and forgets them and the callback
// reference before answering anything. The old reference belongs to a state that is gone, so it
// is dropped rather than released.

import Cocoa

private var panels: [Int: ChooserPanel] = [:]
private var nextID = 1
private var callbackRef: Int32 = olm_noRef()

private func callLua(_ id: Int, _ event: String, _ args: [LuaValue]) -> Bool {
  guard callbackRef != olm_noRef(), let L = LuaSkin.mainLuaState else { return false }
  let skin = LuaSkin.shared(with: L) as! LuaSkin
  _ = lua_rawgeti(L, olm_registryIndex(), lua_Integer(callbackRef))
  lua_pushinteger(L, lua_Integer(id))
  _ = lua_pushstring(L, event)
  for arg in args { pushValue(L, arg) }
  guard skin.protectedCallAndError("olm swift chooser, " + event, nargs: Int32(2 + args.count), nresults: 1)
  else { return false }
  let answer = lua_toboolean(L, -1) != 0
  olm_pop(L, 1)
  return answer
}

// The panel named by the id in the first argument, or nil for an id this image never made.
private func panelAt(_ L: LuaState?) -> ChooserPanel? {
  guard let id = LuaReader(L).integer(at: 1) else { return nil }
  return panels[id]
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

private let new: lua_CFunction = { L in
  let id = nextID
  nextID += 1
  panels[id] = ChooserPanel(ask: { event, args in callLua(id, event, args) })
  lua_pushinteger(L, lua_Integer(id))
  return 1
}

private let style: lua_CFunction = { L in
  let reader = LuaReader(L)
  if reader.isTable(2) { panelAt(L)?.applyStyle(Style(reader, 2)) }
  return 0
}

private let place: lua_CFunction = { L in
  let reader = LuaReader(L)
  if reader.isTable(2) { panelAt(L)?.place(Placement(reader, 2)) }
  return 0
}

private let setRows: lua_CFunction = { L in
  let reader = LuaReader(L)
  var rows: [Row] = []
  if reader.isTable(2) {
    let count = lua_rawlen(L, 2)
    if count > 0 {
      for i in 1...count {
        _ = lua_rawgeti(L, 2, lua_Integer(i))
        if reader.isTable(-1) { rows.append(Row(reader, reader.absolute(-1))) }
        olm_pop(L, 1)
      }
    }
  }
  panelAt(L)?.setRows(rows)
  return 0
}

private let update: lua_CFunction = { L in
  let reader = LuaReader(L)
  if reader.isTable(2) { panelAt(L)?.update(ViewState(reader, 2)) }
  return 0
}

private let text: lua_CFunction = { L in
  _ = lua_pushstring(L, panelAt(L)?.text ?? "")
  return 1
}

private let setText: lua_CFunction = { L in
  panelAt(L)?.setText(LuaReader(L).string(at: 2) ?? "")
  return 0
}

// The bytes of an hs.eventtap.event, its asData, turned back into the event it was.
private let feedKey: lua_CFunction = { L in
  guard let data = LuaReader(L).bytes(at: 2), let cg = CGEvent(withDataAllocator: nil, data: data as CFData),
    let event = NSEvent(cgEvent: cg)
  else { return 0 }
  panelAt(L)?.feed(event)
  return 0
}

private let show: lua_CFunction = { L in
  panelAt(L)?.show()
  return 0
}

private let hide: lua_CFunction = { L in
  panelAt(L)?.hide()
  return 0
}

private let isVisible: lua_CFunction = { L in
  lua_pushboolean(L, (panelAt(L)?.isVisible ?? false) ? 1 : 0)
  return 1
}

private let start: lua_CFunction = { L in
  panelAt(L)?.start()
  return 0
}

private let stop: lua_CFunction = { L in
  panelAt(L)?.stop()
  return 0
}

private let refocus: lua_CFunction = { L in
  panelAt(L)?.refocus()
  return 0
}

// Which surface a panel was built on, glass where the running macOS has it and the older visual
// effect view where it does not, so a probe can say what it is looking at.
private let surface: lua_CFunction = { L in
  _ = lua_pushstring(L, panelAt(L)?.surfaceName ?? "")
  return 1
}

@_cdecl("luaopen_olm_swiftchooser")
public func luaopen_olm_swiftchooser(_ L: LuaState?) -> Int32 {
  for panel in panels.values {
    panel.stop()
    panel.hide()
  }
  panels = [:]
  callbackRef = olm_noRef()

  olm_newTable(L)
  olm_setFunction(L, "setCallback", setCallback)
  olm_setFunction(L, "new", new)
  olm_setFunction(L, "style", style)
  olm_setFunction(L, "place", place)
  olm_setFunction(L, "setRows", setRows)
  olm_setFunction(L, "update", update)
  olm_setFunction(L, "text", text)
  olm_setFunction(L, "setText", setText)
  olm_setFunction(L, "feedKey", feedKey)
  olm_setFunction(L, "show", show)
  olm_setFunction(L, "hide", hide)
  olm_setFunction(L, "isVisible", isVisible)
  olm_setFunction(L, "start", start)
  olm_setFunction(L, "stop", stop)
  olm_setFunction(L, "refocus", refocus)
  olm_setFunction(L, "surface", surface)
  return 1
}
