// The Lua face of the native chooser. luaopen_olm_swiftchooser is what package.loadlib calls, and
// it answers a table of plain functions, each taking a panel's id first, one per thing the Lua
// view asks of its panel. new makes a panel and answers its id, so every picker instance the
// engine builds has a panel of its own.
//
// The docked pane lives here too, in the same image, so the chooser panel and the panes beside it
// are torn down together. paneNew makes one and answers its id, and the pane functions take that
// id first the same way. A pane never calls back into Lua, it only draws what it is handed, so it
// needs no callback and none can reach a closed state through it. A CanvasPanel is drawn by the
// same functions, made by paneNew with an options table, and one whose content takes a click hands
// a function there, which this file holds by reference for that panel alone. It is called with the
// clicked element's id on the main Lua state, refused unless that is the state it was registered
// on, released when the panel is deleted and dropped by the same cleanup that drops the callback.
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
// A CanvasPanel's click handler by pane id, the reference and the state it belongs to.
private var paneClicks: [Int: (ref: Int32, state: LuaState?)] = [:]
private var nextID = 1
private var callbackRef: Int32 = olm_noRef()
private var callbackState: LuaState?
private var generation = 0

private let sentinelType = "olm.swiftchooser.sentinel"

// Stops, hides and forgets every panel and the callback, the one cleanup both a closing state's
// sentinel and a fresh luaopen run, the docked panes with them. The reference belongs to a state
// that is going or gone, so it is dropped rather than released.
private func closeAll() {
  Perf.stop()
  for pane in panes.values { pane.close() }
  panes = [:]
  paneClicks = [:]
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

// A probe of the main thread, off until perfStart. A timer in the common modes, which run during a
// scroll's tracking too, notes every gap between its ticks long enough to drop frames, and every
// call into Lua is timed, so a stall shows what held the thread or that Lua was not it. perfRead
// answers the notes since the last read.
enum Perf {
  static var on = false
  static var notes: [String] = []
  private static var timer: Timer?
  private static var last: CFTimeInterval = 0
  private static var origin: CFTimeInterval = 0

  static func start() {
    stop()
    on = true
    notes = []
    origin = CACurrentMediaTime()
    last = origin
    let t = Timer(timeInterval: 1.0 / 120, repeats: true) { _ in
      let now = CACurrentMediaTime()
      let gap = (now - last) * 1000
      if gap > 25 { note(String(format: "stall %.0f ms", gap), at: last) }
      last = now
    }
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  static func stop() {
    timer?.invalidate()
    timer = nil
    on = false
  }

  static func note(_ text: String, at time: CFTimeInterval = CACurrentMediaTime()) {
    guard on else { return }
    notes.append(String(format: "%7.0f ms  ", (time - origin) * 1000) + text)
    if notes.count > 400 { notes.removeFirst(notes.count - 400) }
  }
}

private func timedCallLua(_ id: Int, _ event: String, _ args: [LuaValue]) -> Bool {
  guard Perf.on else { return callLua(id, event, args) }
  let start = CACurrentMediaTime()
  let answer = callLua(id, event, args)
  let took = (CACurrentMediaTime() - start) * 1000
  if took > 2 { Perf.note(String(format: "lua %@ %.1f ms", event, took), at: start) }
  return answer
}

private let perfStart: lua_CFunction = { _ in
  Perf.start()
  return 0
}

private let perfRead: lua_CFunction = { L in
  _ = lua_pushstring(L, Perf.notes.joined(separator: "\n"))
  Perf.notes = []
  return 1
}

private let perfStop: lua_CFunction = { _ in
  Perf.stop()
  return 0
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
  panels[id] = ChooserPanel(ask: { event, args in timedCallLua(id, event, args) })
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

// A list of { index, image } pairs, one based, for rows that gained their icon after they were sent.
private let setImages: lua_CFunction = { L in
  let reader = LuaReader(L)
  var images: [(Int, NSImage)] = []
  if reader.isTable(2) {
    let count = lua_rawlen(L, 2)
    if count > 0 {
      for i in 1...count {
        _ = lua_rawgeti(L, 2, lua_Integer(i))
        let t = reader.absolute(-1)
        if reader.isTable(t), let index = reader.integer(t, "index"), let image = reader.image(t, "image") {
          images.append((index - 1, image))
        }
        olm_pop(L, 1)
      }
    }
  }
  panelAt(L)?.setImages(images)
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

// A CanvasPanel's click, handed to the function its paneNew registered, on the state it belongs to.
private func paneClicked(_ id: Int, _ element: String) {
  guard let entry = paneClicks[id], let L = LuaSkin.mainLuaState, L == entry.state else { return }
  let skin = LuaSkin.shared(with: L) as! LuaSkin
  _ = lua_rawgeti(L, olm_registryIndex(), lua_Integer(entry.ref))
  _ = lua_pushstring(L, element)
  _ = skin.protectedCallAndError("olm swift panel, click", nargs: 1, nresults: 0)
}

// paneNew() makes a docked pane. paneNew({ panel = true, level, onClick }) makes a CanvasPanel's
// window instead, at that hs.canvas window level, never drawn into a chooser's window, click
// through unless onClick is a function, which is then told the id of each clicked element.
private let paneNew: lua_CFunction = { L in
  let id = nextID
  nextID += 1
  let reader = LuaReader(L)
  var config = PaneConfig()
  if reader.isTable(1), reader.bool(1, "panel") == true {
    config.panel = true
    config.level = NSWindow.Level(rawValue: reader.integer(1, "level") ?? NSWindow.Level.popUpMenu.rawValue)
    _ = lua_getfield(L, 1, "onClick")
    if olm_isFunction(L, -1) != 0 {
      paneClicks[id] = (ref: luaL_ref(L, olm_registryIndex()), state: mainThread(of: L))
      config.onClick = { element in paneClicked(id, element) }
    } else {
      olm_pop(L, 1)
    }
  }
  panes[id] = PanePanel(findHost: chooserHosting, config: config)
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
  let (elements, targets, unsupported) = PaneReader(r: reader, skin: skin, size: pane.size).elements(at: 3)
  var scroll = PaneScroll(height: pane.size.height, reset: false, thumb: false)
  if reader.isTable(4) {
    scroll = PaneScroll(height: reader.number(4, "height") ?? pane.size.height,
      reset: reader.bool(4, "reset") ?? false, thumb: reader.bool(4, "thumb") ?? false)
  }
  pane.draw(elements, targets: targets, radius: radius, scroll: scroll)
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

// paneDebug(id) answers, read only, where a pane is and what it holds, for a live look through
// hs. hosting is chooser, own or none, windowVisible and hidden say whether it can be seen,
// scrollFrame and superviewFrame are in their window's coordinates, AppKit's with y up,
// autoresizes is whether the scroll view is placed by its autoresizing mask, documentFrame and
// documentFlipped are the drawn view's, clipBounds is the visible part of it, and elements is
// how many elements the last draw handed it. panel says it is a CanvasPanel's window, level is
// its window level, clickThrough whether it ignores the mouse, and targets how many elements a
// click can land on. Nil for an id this image never made. With no id it
// answers every pane this image holds, keyed by id, since a pane's id lives inside its backend.
private func pushPaneDebug(_ L: LuaState?, _ pane: PanePanel) {
  let d = pane.debug
  func setRect(_ name: String, _ rect: NSRect?) {
    guard let rect else { return }
    olm_newTable(L)
    for (key, value) in [("x", rect.minX), ("y", rect.minY), ("w", rect.width), ("h", rect.height)] {
      lua_pushnumber(L, Double(value))
      lua_setfield(L, -2, key)
    }
    lua_setfield(L, -2, name)
  }
  func set(_ name: String, _ value: LuaValue) {
    pushValue(L, value)
    lua_setfield(L, -2, name)
  }
  olm_newTable(L)
  set("hosting", .string(d.hosting))
  set("windowVisible", .bool(d.windowVisible))
  set("hidden", .bool(d.hidden))
  setRect("scrollFrame", d.scroll)
  setRect("superviewFrame", d.superview)
  set("autoresizes", .bool(d.autoresizes))
  setRect("documentFrame", d.document)
  set("documentFlipped", .bool(d.documentFlipped))
  setRect("clipBounds", d.clipBounds)
  set("elements", .int(d.elements))
  set("panel", .bool(d.panel))
  set("level", .int(d.level))
  set("clickThrough", .bool(d.clickThrough))
  set("targets", .int(d.targets))
}

private let paneDebug: lua_CFunction = { L in
  if LuaReader(L).integer(at: 1) == nil {
    olm_newTable(L)
    for (id, pane) in panes {
      pushPaneDebug(L, pane)
      lua_rawseti(L, -2, lua_Integer(id))
    }
    return 1
  }
  guard let pane = paneAt(L) else {
    lua_pushnil(L)
    return 1
  }
  pushPaneDebug(L, pane)
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

// paneIsVisible(id) answers whether the pane or panel can be seen, which CanvasPanel's isShowing
// reads.
private let paneIsVisible: lua_CFunction = { L in
  lua_pushboolean(L, (paneAt(L)?.isVisible ?? false) ? 1 : 0)
  return 1
}

// Out of whichever window held it and forgotten, its own window released with it.
private let paneDelete: lua_CFunction = { L in
  guard let id = LuaReader(L).integer(at: 1), let pane = panes[id] else { return 0 }
  pane.close()
  panes[id] = nil
  if let entry = paneClicks.removeValue(forKey: id), entry.state == mainThread(of: L) {
    luaL_unref(L, olm_registryIndex(), entry.ref)
  }
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
  olm_setFunction(L, "setImages", setImages)
  olm_setFunction(L, "perfStart", perfStart)
  olm_setFunction(L, "perfRead", perfRead)
  olm_setFunction(L, "perfStop", perfStop)
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
  olm_setFunction(L, "paneDebug", paneDebug)
  olm_setFunction(L, "hostsPane", hostsPane)
  olm_setFunction(L, "paneShow", paneShow)
  olm_setFunction(L, "paneHide", paneHide)
  olm_setFunction(L, "paneIsVisible", paneIsVisible)
  olm_setFunction(L, "paneDelete", paneDelete)
  return 1
}
