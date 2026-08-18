--- === Olm test world ===
---
--- Everything a scenario may do, and the reason this file exists rather than scenarios reaching
--- for `hs` themselves.
---
--- It must work against TWO configurations. The retired root exposes each tool as a global
--- spoon, and the restructured one exposes them through `Olm:module`. A suite that only ran
--- against one of them could never say whether a failure was a regression or a broken test,
--- which is exactly the position this work started from. So role resolution is the one adapter
--- here, every scenario names a stable role, and this file finds it whichever way the live
--- config keeps it.
---
--- The input half is the part worth reading before changing anything.
---
--- A posted key event is IGNORED by the leader engine on purpose. lib/chordkey.lua drops any
--- event whose source is not the HID system, so a tool's own synthesized paste cannot be
--- misread as a chord while the leader is held. That guard is correct and load bearing, and a
--- test declares its way through it by setting the source to 1, which is honest precisely
--- because the guard exists to catch a tool pasting, not a harness pressing.
---
--- Two timings are not adjustable taste. A leader must be held longer than the engine's hold
--- delay before a key is tapped, or the press reads as a tap rather than a chord and nothing
--- happens. And a hold with NO key is what reveals a cheat sheet, so that path holds past the
--- same threshold and presses nothing at all.
---
--- One thing is impossible rather than merely hard. `hs.hotkey` bindings are registered with
--- the system and never see a posted event, so anything bound that way cannot be driven here.
--- Everything through the shared event tap can.

local obj = {}

-- Long enough that a chooser has really appeared before anything asks. Generous on purpose,
-- since a suite that is flaky under load teaches people to ignore it.
local SETTLE = 0.45
-- Comfortably past the 0.6 second hold delay the shared chord engine ships.
local HOLD = 1.0

--- The stable name a scenario uses, mapped to how each configuration keeps it. The left column
--- is the plugin directory the restructured config uses, the right is the global the retired
--- root exposes, and this table is the ONLY place either spelling appears.
local ROLES = {
  launcher        = "Launcher",
  hypercheatsheet = "HyperCheatSheet",
  windowcheatsheet = "WindowCheatSheet",
  apptoggler      = "AppToggler",
  windowmanager   = "WindowManager",
  clipboard       = "ClipboardHistory",
  terminalhandler = "TerminalHandler",
  queryscope      = "QueryScope",
}

function obj.new()
  local w = {}

  w.stamp = tostring(math.floor(hs.timer.secondsSinceEpoch())):sub(-6)
  w.registry = spoon.Olm and spoon.Olm.registry

  --- The one adapter. A role resolves through Olm's own module door when the live config has
  --- one, and through the global spoon otherwise, so every scenario below is written once.
  function w.role(name)
    local viaOlm = spoon.Olm and type(spoon.Olm.module) == "function"
      and spoon.Olm:module(name)
    if viaOlm then return viaOlm end
    local global = ROLES[name]
    if global and spoon[global] then return spoon[global] end
    -- Not in the map is not the same as not present. A directory name capitalised is what the
    -- retired root calls most tools, so try that before answering nothing, since reporting a
    -- tool absent when it is merely unlisted is a test defect wearing a finding's clothes.
    local camel = name:sub(1, 1):upper() .. name:sub(2)
    return spoon[camel] or spoon[name] or nil
  end

  --- There is deliberately NO settle helper here any more, and its absence is the point.
  ---
  --- It used to block the main thread with usleep, which reads as waiting and is the exact
  --- opposite. Every answer this suite waits for, a posted key reaching the event tap, an
  --- accessibility walk finishing, a shelled out process returning, arrives on that same main
  --- thread, so a scenario that blocks it is guaranteeing the thing it is waiting for can never
  --- happen. It cost three tools a false failure and a whole calibration run before that, which
  --- is twice for one mistake.
  ---
  --- Waiting is the RUNNER'S job and nobody else's. A scenario says what it wants to happen and
  --- how long to leave between one step and the next, and the runner leaves that gap with a real
  --- timer, which is the only kind of waiting that lets the run loop turn.

  ------------------------------------------------------------------------------
  -- Input
  ------------------------------------------------------------------------------

  local props = hs.eventtap.event.properties

  -- Claiming the physical keyboard, which is what gets past the engine's own guard. See the
  -- note at the top for why that is honest here and nowhere else.
  local function post(mods, key, isDown)
    local ev = hs.eventtap.event.newKeyEvent(mods or {}, key, isDown)
    ev:setProperty(props.eventSourceStateID, 1)
    ev:post()
  end

  local LEADERS = { hyper = "f18", meta = "f16", super = "f17" }

  --- INPUT IS ASYNCHRONOUS AND CANNOT BE OTHERWISE, which cost a whole calibration run to see.
  --- A posted key event is delivered to the event tap on the MAIN THREAD, so a scenario that
  --- sleeps between posting and looking is guaranteeing the events it just posted can never be
  --- processed. Every input helper below therefore only POSTS, and the waiting is done by the
  --- runner between steps, where a real timer lets the run loop turn.
  ---
  --- The standalone probes that proved all of this worked chained timers and passed. The first
  --- suite slept and failed every one of them, on a configuration where the same keys work by
  --- hand, which is exactly the ambiguity calibrating against a known good config exists to
  --- resolve.

  function w.down(leader)
    local fkey = LEADERS[leader] or leader
    local code = hs.keycodes.map[fkey]
    if not code then return false end
    post({}, code, true)
    return true
  end

  function w.up(leader)
    local fkey = LEADERS[leader] or leader
    local code = hs.keycodes.map[fkey]
    if not code then return false end
    post({}, code, false)
    return true
  end

  function w.press(key, mods)
    post(mods, key, true)
    post(mods, key, false)
  end

  ------------------------------------------------------------------------------
  -- Observing
  ------------------------------------------------------------------------------

  --- Whether a role's surface is on screen. Asked of the role first, since a picker and a cheat
  --- sheet both answer isShowing themselves, and of the registry's navigation adapter otherwise,
  --- which is the generic door every registered tool exposes.
  function w.showing(name)
    local module = w.role(name)
    -- Some tools keep their picker on a submodule rather than on their own root, which is where
    -- the clipboard keeps its manager, so the holder is looked for rather than assumed.
    if module and type(module.isShowing) ~= "function" then
      module = module.manager or module.chooser or module
    end
    if module and type(module.isShowing) == "function" then
      local ok, answer = pcall(function() return module:isShowing() end)
      if ok then return answer == true end
      local ok2, answer2 = pcall(module.isShowing)
      if ok2 then return answer2 == true end
    end
    local entry = w.registry and w.registry.get(name)
    if entry and type(entry.surface) == "function" then
      local ok, adapter = pcall(entry.surface)
      if ok and adapter and type(adapter.isShowing) == "function" then
        local ok2, answer = pcall(adapter.isShowing)
        return ok2 and answer == true
      end
    end
    return false
  end

  function w.open(name)
    if w.registry and w.registry.get(name) then
      local ok = pcall(w.registry.run, name)
      if ok then return true end
    end
    local module = w.role(name)
    if module and type(module.show) == "function" then
      pcall(function() module:show() end)
      return true
    end
    return false
  end

  --- Close whatever is on screen the way a person would, with Escape, so the closing path is
  --- exercised too rather than a method nobody presses.
  function w.escape()
    w.press("escape")
  end

  --- Put the screen back, whatever is on it. Asked of every registered tool through the
  --- surface the registry holds, and then of the three that answer to no registry entry.
  ---
  --- The three are tried through several holders rather than one, because a tool does not
  --- necessarily keep its hide where it keeps its isShowing. The launcher is the case that
  --- proved it. It answers isShowing on its own root and keeps hide on the picker instance
  --- underneath, so asking the root alone found nothing, closed nothing, and said nothing.
  --- A launcher left open at the end of one run was still open at the start of the next,
  --- which the run after reported as already open before the test began and then failed
  --- everything underneath, on a configuration where all of it works.
  -- Exposed on the world, not kept private, because closing one named surface needs the same
  -- several holder walk that closing everything does, and two versions of this would drift.
  function w.hideThrough(module)
    if type(module) ~= "table" then return end
    for _, holder in ipairs({ module, module._instance, module.manager, module.chooser }) do
      if type(holder) == "table" and type(holder.hide) == "function" then
        -- Both conventions tried, since these submodules disagree about which they use and a
        -- harness putting the screen back is the wrong place to care which.
        if pcall(function() holder:hide() end) then return end
        if pcall(holder.hide) then return end
      end
    end
  end

  function w.closeAll()
    for _, entry in ipairs((w.registry and w.registry.all()) or {}) do
      if w.showing(entry.name) then
        local e = w.registry.get(entry.name)
        local ok, adapter = pcall(e.surface)
        if ok and adapter and adapter.hide then pcall(adapter.hide) end
      end
    end
    for _, role in ipairs({ "launcher", "hypercheatsheet", "windowcheatsheet" }) do
      w.hideThrough(w.role(role))
    end
  end

  --- The person's own key catalog, read from the live config directory so it is whichever one
  --- is running. Both configurations keep it in the same place, which is what lets an input
  --- scenario ask what key a tool is on rather than hardcoding one that a rebind would break.
  local keysCache = nil
  function w.keyFor(name)
    if keysCache == nil then
      local ok, answer = pcall(dofile, hs.configdir .. "/config/keys.lua")
      keysCache = ok and answer or false
    end
    local entry = keysCache and keysCache[name]
    return entry and entry.key or nil
  end

  function w.frontmostBundle()
    local app = hs.application.frontmostApplication()
    return app and app:bundleID() or nil
  end

  function w.rows(name, query)
    local scope = w.registry and w.registry.scopeFor(name)
    if scope and type(scope.rows) == "function" then
      local ok, answer = pcall(scope.rows, query or "")
      if ok and type(answer) == "table" then return answer end
    end
    -- No scope is ordinary rather than a fault. A tool may be reachable only by its own key,
    -- which the clipboard is on the retired root, so its own rows are asked for directly.
    local module = w.role(name)
    for _, holder in ipairs({ module, module and module.manager, module and module.chooser }) do
      if holder and type(holder.rows) == "function" then
        local ok, answer = pcall(holder.rows, query or "")
        if ok and type(answer) == "table" then return answer end
      end
    end
    return nil
  end

  return w
end

return obj
