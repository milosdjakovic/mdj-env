-- Takes keyboard focus for a list opened over a password field, and gives it back.
--
-- Why this exists. The default chooser is a canvas that never takes focus and reads keys
-- through an event tap. While a password field has focus macOS secure input hides every key
-- from every tap, so a list opened then is drawn but deaf. Measured live on 2026-10-22 over a
-- Safari password field. hs.focus() did nothing and Safari kept focus. A borderless hs.webview
-- with text entry allowed, focused through hs.window focus, could not take focus either. A native
-- hs.chooser is a real window that becomes key, it took focus, secure input went off within a
-- tenth of a second, and hiding it then activating the previous application returned both the
-- focus and secure input. So a native chooser is the only mechanism proven, and this file is
-- the one place that knows it. Nothing else in the spoon names hs.chooser for this purpose.
--
-- The chooser shows with no rows and is moved off screen at once, so nothing of it is seen
-- beyond a brief flash before the move. It exists only to be the key window.
--
-- Chrome does not let go. Measured 2026-10-27, Chrome keeps secure input on for as long as its
-- password field has focus inside its own window, whichever application is active, so the tap
-- stays deaf with this chooser key and Hammerspoon in front. The keys still arrive, at this
-- chooser, the way a key window always gets them, and hs.hotkey still fires, the route Hyper's
-- keys take there. So while secure input stays on, the hold relays both into the list. The
-- chooser's typed text goes to the sink's text, and the keys a list reads that are not typing,
-- the arrows, Return, Escape, the Command chords and Backspace on an empty field, are claimed
-- through hs.hotkey and handed to the sink's key as key events, so they take the list's own path.
-- The relay follows secure input, polled, and is off whenever it is off, since a tap that hears
-- a key and a hotkey that fires on it would act twice.
--
-- The security trade off, stated plainly. While a list is open over a password field secure
-- input is off, so any event tap on the machine could read what is typed into that list. That
-- is the price of a list that hears keys there. It lasts only while the list is open, and the
-- release function puts secure input back by returning focus to the password field. Over Chrome
-- secure input stays on and nothing changes about who can read keys.
--
-- Text the list puts in its own field, a scope's word or a seeded query, never passes through the
-- chooser, so the hold answers a mirror beside the release, which writes it into the chooser with
-- the caret after it. Without it the next letter typed there would replace the list's text with
-- that letter alone.
--
-- hold(sink, opts) answers nil when secure input is off, so every ordinary open is untouched. When
-- it is on, hold answers a release function, safe to call more than once, and a mirror
-- function(text). sink is optional, and carries key(event) and text(string). opts.keys is a list of
-- { mods, key } relayed beside the fixed set, the list keys a person binds with no leader, a key
-- the fixed set already claims skipped.

local M = {}

-- Far enough above every display that the window is never on any of them.
local OFF_SCREEN_Y = -10000

-- How often the relay checks whether secure input is still on.
local POLL_SECONDS = 0.1

-- The keys a list reads that are not typing, each a modifier set and a key name, and whether a
-- held key repeats. Backspace is apart, claimed only while the typed text is empty, since the
-- chooser's own field deletes a character otherwise.
local RELAYED = {
  { {}, "up", true }, { {}, "down", true },
  { {}, "return" }, { {}, "padenter" }, { {}, "escape" },
  { { "cmd" }, "return" }, { { "cmd" }, "padenter" },
  { { "cmd" }, "/" }, { { "cmd", "shift" }, "/" },
}
for digit = 1, 9 do RELAYED[#RELAYED + 1] = { { "cmd" }, tostring(digit) } end

local function comboId(mods, key)
  local sorted = {}
  for _, m in ipairs(mods) do sorted[#sorted + 1] = m end
  table.sort(sorted)
  -- A key by name and the same key by code are one combination.
  local code = type(key) == "string" and hs.keycodes.map[key] or key
  return table.concat(sorted, "+") .. ":" .. tostring(code)
end

local function relayed(sink, mods, key)
  return function()
    if not sink.key then return end
    local ok, err = pcall(sink.key, hs.eventtap.event.newKeyEvent(mods, key, true))
    if not ok then print("Olm secure focus, a relayed key failed, " .. tostring(err)) end
  end
end

-- Builds the hotkeys disabled, enabled and disabled as secure input comes and goes.
local function buildRelay(sink, extra)
  local relay = { keys = {}, on = false, text = "" }
  local seen = {}
  local function claim(mods, key, repeats)
    local id = comboId(mods, key)
    if seen[id] then return end
    seen[id] = true
    local fn = relayed(sink, mods, key)
    local ok, hotkey = pcall(hs.hotkey.new, mods, key, fn, nil, repeats and fn or nil)
    if ok and hotkey then
      relay.keys[#relay.keys + 1] = hotkey
    else
      print("Olm secure focus, " .. id .. " could not be relayed, " .. tostring(hotkey))
    end
  end
  for _, spec in ipairs(RELAYED) do claim(spec[1], spec[2], spec[3]) end
  for _, spec in ipairs(extra or {}) do claim(spec[1] or {}, spec[2]) end
  relay.backspace = hs.hotkey.new({}, "delete", relayed(sink, {}, "delete"))

  function relay.sync()
    local want = hs.eventtap.isSecureInputEnabled()
    if want ~= relay.on then
      relay.on = want
      for _, k in ipairs(relay.keys) do if want then k:enable() else k:disable() end end
    end
    if relay.on and relay.text == "" then relay.backspace:enable() else relay.backspace:disable() end
  end

  function relay.stop()
    if relay.timer then relay.timer:stop(); relay.timer = nil end
    for _, k in ipairs(relay.keys) do k:delete() end
    relay.backspace:delete()
    relay.keys = {}
  end

  return relay
end

-- Puts the caret after the chooser's text, which hs.chooser:query leaves selected. There is no
-- caret api, so the field is reached through the accessibility tree, as the legacy chooser does.
local function caretToEnd(window)
  local element = window and hs.axuielement.windowElement(window)
  if not element then return end
  local function find(e, depth)
    if depth > 6 then return nil end
    for _, kid in ipairs(e:attributeValue("AXChildren") or {}) do
      local role = kid:attributeValue("AXRole")
      if role == "AXTextField" or role == "AXComboBox" then return kid end
      local found = find(kid, depth + 1)
      if found then return found end
    end
    return nil
  end
  local field = find(element, 0)
  if not field then return end
  local n = field:attributeValue("AXNumberOfCharacters")
  if type(n) ~= "number" then
    local value = field:attributeValue("AXValue") or ""
    n = utf8.len(value) or #value
  end
  field:setAttributeValue("AXSelectedTextRange", { location = n, length = 0 })
end

function M.hold(sink, opts)
  if not hs.eventtap.isSecureInputEnabled() then return nil end
  sink = sink or {}
  opts = opts or {}

  local previous = hs.application.frontmostApplication()
  local picker = hs.chooser.new(function() end)
  picker:choices({})
  picker:rows(0)

  local relay = buildRelay(sink, opts.keys)
  picker:queryChangedCallback(function(text)
    text = text or ""
    if text == relay.text then return end
    relay.text = text
    relay.sync()
    -- Only while the tap is deaf. With secure input off the tap claims every key and this
    -- chooser hears none, so a change here then is not one the person typed.
    if relay.on and sink.text then
      local ok, err = pcall(sink.text, text)
      if not ok then print("Olm secure focus, relaying typed text failed, " .. tostring(err)) end
    end
  end)
  picker:show()

  -- The chooser's window is the focused one only once it is key, and only then is it ours.
  local window = hs.window.focusedWindow()
  local owner = window and window:application()
  if window and owner and owner:name() == "Hammerspoon" then
    local f = window:frame()
    window:setFrame({ x = f.x, y = OFF_SCREEN_Y, w = f.w, h = f.h }, 0)
  end

  relay.sync()
  relay.timer = hs.timer.doEvery(POLL_SECONDS, relay.sync)

  local released = false
  local function release()
    if released then return end
    released = true
    relay.stop()
    picker:hide()
    picker:delete()
    if previous then previous:activate() end
  end
  local function mirror(text)
    text = text or ""
    if released or text == relay.text then return end
    relay.text = text
    picker:query(text)
    if text ~= "" then pcall(caretToEnd, window) end
    relay.sync()
  end
  return release, mirror
end

return M
