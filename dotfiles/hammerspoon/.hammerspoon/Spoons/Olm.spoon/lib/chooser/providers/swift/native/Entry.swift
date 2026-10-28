// The Lua face of the native chooser. luaopen_olm_swiftchooser is what package.loadlib calls, and
// it answers a table of plain functions, each taking a panel's id first, one per thing the Lua
// view asks of its panel. new makes a panel and answers its id, so every picker instance the
// engine builds has a panel of its own.
//
// The docked pane lives here too, in the same image, so the chooser panel and the panes beside it
// are torn down together. paneNew makes one and answers its id, and the pane functions take that
// id first the same way. A pane never calls back into Lua, it only draws what it is handed, so it
// needs no callback and none can reach a closed state through it.
//
// Every event goes back through the one callback setCallback registers, called as
// callback(id, event, ...) on the main Lua state, the state LuaSkin says every callback belongs
// on. Its first result is read as a boolean, which is how yields and listKey answer whether the
// engine claimed a key before the field edits.
//
// A Swift image is never unloaded, so this file outlives every Hammerspoon reload while the Lua
// state it talks to does not, and a reload may never call luaopen of this image again, when the
// provider is switched off, when a source edit names a new image, or when the build is pending.
// So the state a panel belongs to is told to this file by the state itself. The module table
// holds a sentinel userdata whose __gc runs when that state closes, which LuaSkin's
// destroyLuaState does with lua_close on every reload, and it stops and hides every panel,
// removes every monitor and forgets the callback reference. A callback is also refused whenever
// the main Lua state is not the one it was registered on, so an integer reference is never read
// out of another state's registry. luaopen still clears whatever is left before answering, and
// each luaopen starts a new generation, so a sentinel from an older load never clears a newer one.

import Cocoa

private var panels: [Int: ChooserPanel] = [:]
private var panes: [Int: PanePanel] = [:]
private var nextID = 1
private var callbackRef: Int32 = olm_noRef()
private var callbackState: LuaState?
private var generation = 0

private let sentinelType = "olm.swiftchooser.sentinel"

// Stops, hides and forgets every panel and the callback, the one cleanup both a closing state's
// sentinel and a fresh luaopen run, the docked panes with them. The reference belongs to a state
// that is going or gone, so it is dropped rather than released.
private func closeAll() {
  for pane in panes.values { pane.close() }
  panes = [:]
  for panel in panels.values {
    panel.stop()
    panel.hide()
  }
  panels = [:]
  callbackRef = olm_noRef()
  callbackState = nil
}

// The main thread of the state L belongs to, the state a callback registered from a coroutine
// still runs on.
private func mainThread(of L: LuaState?) -> LuaState? {
  _ = lua_rawgeti(L, olm_registryIndex(), lua_Integer(LUA_RIDX_MAINTHREAD))
  defer { olm_pop(L, 1) }
  return lua_tothread(L, -1)
}

private func callLua(_ id: Int, _ event: String, _ args: [LuaValue]) -> Bool {
  guard callbackRef != olm_noRef(), let L = LuaSkin.mainLuaState, L == callbackState else { return false }
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
  let state = mainThread(of: L)
  if callbackRef != olm_noRef(), callbackState == state { luaL_unref(L, olm_registryIndex(), callbackRef) }
  callbackRef = olm_noRef()
  callbackState = nil
  if olm_isFunction(L, 1) != 0 {
    lua_pushvalue(L, 1)
    callbackRef = luaL_ref(L, olm_registryIndex())
    callbackState = state
  }
  return 0
}

// The sentinel's __gc, run when the state holding the module table closes. It clears only the
// generation it was made for.
private let sentinelGC: lua_CFunction = { L in
  if let raw = lua_touserdata(L, 1), raw.load(as: Int.self) == generation { closeAll() }
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

// The field's Control keys, { control = { key codes }, backspace = { key codes } }.
private let setFieldKeys: lua_CFunction = { L in
  let reader = LuaReader(L)
  var control: Set<UInt16> = []
  var backspace: Set<UInt16> = []
  reader.each(2, "control") { e in if let code = reader.integer(at: e) { control.insert(UInt16(code)) } }
  reader.each(2, "backspace") { e in if let code = reader.integer(at: e) { backspace.insert(UInt16(code)) } }
  panelAt(L)?.setFieldKeys(control: control, backspace: backspace)
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

// MARK: The docked pane

// The pane named by the id in the first argument, or nil for an id this image never made.
private func paneAt(_ L: LuaState?) -> PanePanel? {
  guard let id = LuaReader(L).integer(at: 1) else { return nil }
  return panes[id]
}

// THE SEAM between a docked pane and the chooser it is drawn into, the one place either knows of
// the other. A pane knows no chooser, so it is matched here on the companion rect a visible
// chooser panel last reported, and drawn into that panel's window. Nil when no visible swift
// chooser owns the rect, and the pane then stands in a window of its own.
private func chooserHosting(_ rect: NSRect) -> ChooserPanel? {
  panels.values.first { $0.hostsPane(at: rect) }
}

private let paneNew: lua_CFunction = { L in
  let id = nextID
  nextID += 1
  panes[id] = PanePanel(findHost: chooserHosting)
  lua_pushinteger(L, lua_Integer(id))
  return 1
}

// The companion rect, { x, y, w, h } in Hammerspoon's screen space.
private let panePlace: lua_CFunction = { L in
  let reader = LuaReader(L)
  guard reader.isTable(2), let x = reader.number(2, "x"), let y = reader.number(2, "y"),
    let w = reader.number(2, "w"), let h = reader.number(2, "h")
  else { return 0 }
  paneAt(L)?.place(NSRect(x: x, y: y, width: w, height: h))
  return 0
}

// paneDraw(id, radius, elements, scroll) draws the elements on glass of that corner radius and
// answers an array naming each thing in them that was not drawn, empty when everything was.
// scroll is { height, reset, thumb }, the content's full height, whether the view goes back to
// the top, and whether it shows an overlay scroller, lib/dockedpane.lua's native scroll. Without
// it the content is the pane's own height and the view keeps where it is.
private let paneDraw: lua_CFunction = { L in
  olm_newTable(L)
  guard let pane = paneAt(L), let L else { return 1 }
  let reader = LuaReader(L)
  let skin = LuaSkin.shared(with: L) as! LuaSkin
  let radius = CGFloat(reader.number(at: 2) ?? 0)
  let (elements, unsupported) = PaneReader(r: reader, skin: skin, size: pane.size).elements(at: 3)
  var scroll = PaneScroll(height: pane.size.height, reset: false, thumb: false)
  if reader.isTable(4) {
    scroll = PaneScroll(height: reader.number(4, "height") ?? pane.size.height,
      reset: reader.bool(4, "reset") ?? false, thumb: reader.bool(4, "thumb") ?? false)
  }
  pane.draw(elements, radius: radius, scroll: scroll)
  for (i, name) in unsupported.enumerated() {
    _ = lua_pushstring(L, name)
    lua_rawseti(L, -2, lua_Integer(i + 1))
  }
  return 1
}

// paneScrollBy(id, points) scrolls the pane's view further down by points, clamped to its
// content, and answers whether it moved.
private let paneScrollBy: lua_CFunction = { L in
  let moved = paneAt(L)?.scrollBy(CGFloat(LuaReader(L).number(at: 2) ?? 0)) ?? false
  lua_pushboolean(L, moved ? 1 : 0)
  return 1
}

// hostsPane(id) answers whether that chooser panel's window holds a shown docked pane, which then
// scrolls natively under the pointer. The Lua view's scroll tap asks it before claiming a scroll
// over the companion, see View colon _onScroll in view.lua.
private let hostsPane: lua_CFunction = { L in
  lua_pushboolean(L, (panelAt(L)?.hostsShownPane ?? false) ? 1 : 0)
  return 1
}

private let paneShow: lua_CFunction = { L in
  paneAt(L)?.show()
  return 0
}

private let paneHide: lua_CFunction = { L in
  paneAt(L)?.hide()
  return 0
}

// Out of whichever window held it and forgotten, its own window released with it.
private let paneDelete: lua_CFunction = { L in
  guard let id = LuaReader(L).integer(at: 1), let pane = panes[id] else { return 0 }
  pane.close()
  panes[id] = nil
  return 0
}

@_cdecl("luaopen_olm_swiftchooser")
public func luaopen_olm_swiftchooser(_ L: LuaState?) -> Int32 {
  closeAll()
  generation += 1

  olm_newTable(L)
  // The sentinel, a userdata holding this load's generation, with __gc on its metatable.
  if let raw = lua_newuserdatauv(L, MemoryLayout<Int>.size, 0) {
    raw.storeBytes(of: generation, as: Int.self)
  }
  _ = luaL_newmetatable(L, sentinelType)
  olm_setFunction(L, "__gc", sentinelGC)
  lua_setmetatable(L, -2)
  lua_setfield(L, -2, "_sentinel")
  olm_setFunction(L, "setCallback", setCallback)
  olm_setFunction(L, "new", new)
  olm_setFunction(L, "style", style)
  olm_setFunction(L, "place", place)
  olm_setFunction(L, "setRows", setRows)
  olm_setFunction(L, "update", update)
  olm_setFunction(L, "text", text)
  olm_setFunction(L, "setText", setText)
  olm_setFunction(L, "feedKey", feedKey)
  olm_setFunction(L, "setFieldKeys", setFieldKeys)
  olm_setFunction(L, "show", show)
  olm_setFunction(L, "hide", hide)
  olm_setFunction(L, "isVisible", isVisible)
  olm_setFunction(L, "start", start)
  olm_setFunction(L, "stop", stop)
  olm_setFunction(L, "refocus", refocus)
  olm_setFunction(L, "surface", surface)
  olm_setFunction(L, "paneNew", paneNew)
  olm_setFunction(L, "panePlace", panePlace)
  olm_setFunction(L, "paneDraw", paneDraw)
  olm_setFunction(L, "paneScrollBy", paneScrollBy)
  olm_setFunction(L, "hostsPane", hostsPane)
  olm_setFunction(L, "paneShow", paneShow)
  olm_setFunction(L, "paneHide", paneHide)
  olm_setFunction(L, "paneDelete", paneDelete)
  return 1
}
