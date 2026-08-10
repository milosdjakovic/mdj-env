--- The native Quick Look panel, one of the two preview providers.
---
--- The same window Finder shows on the space bar, over the picker rather than beside it, drawn
--- by whatever generator the system has for that file. So it renders things this config has
--- never heard of, at full size and full fidelity, which is the entire reason to want it.
---
--- IT IS ASKED FOR RATHER THAN FOLLOWED, and that is a property of the provider rather than a
--- limitation to be worked around later. A canvas beside the list can track the highlight for
--- nothing, because redrawing it is free and it is already on screen. A window cannot. Tracking
--- would mean killing one process and launching another on every arrow key, and a large window
--- reopening over the list every time you pause is worse than no preview at all. So this one
--- declares that it does not follow the highlight, and the surface wires a key to it instead of
--- the poll. That is why `followsHighlight` is in the contract at all.
---
--- It reserves no room. With this provider the picker is the list and nothing else, which is
--- the other half of the trade, a compact picker and a full size preview on demand against a
--- permanent summary in the corner of your eye.
---
--- THE PANEL IS BUILT BY A SWIFT HELPER RATHER THAN BY THE COMMAND LINE TOOL, and that was
--- measured rather than assumed. `qlmanage -p` starts, registers as a running application and
--- spawns the system preview extension, and then owns zero windows, checked on this macOS both
--- as a child of Hammerspoon and straight from a shell. Hammerspoon has no binding for Quick
--- Look either, so the only route to a real panel is AppKit, and quicklook.swift beside this
--- file is the smallest program that opens one. That is the same shape Eyedropper already uses
--- for NSColorSampler, compiled once into a cache outside the watched config tree so building it
--- never triggers a reload.
---
--- A panel is a child process, which is what makes closing it clean, since the helper lives for
--- exactly as long as its window and terminating it takes the window with it. The handle is held
--- for that reason, and holding it also keeps the task from being collected mid flight.

-- A viewer sits one directory below the spoon root, so its siblings are one level up.
local viewerPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(viewerPath .. "../util.lua")()

local M = {}

--- The Swift compiler, at the fixed absolute path a system binary lives at. Declared in
--- quicklook.dependencies as the system kind, which is what allows the literal here, the same
--- as /bin/ls in sources/walk.lua and /usr/bin/open in chooser.lua. Nothing is injected because
--- nothing can move it.
local SWIFTC = "/usr/bin/swiftc"

--- The helper, its source beside this file and its binary in a cache under HOME. Outside the
--- config tree on purpose, since Hammerspoon watches this tree and a compile landing in it would
--- reload the config every time the helper is built.
local SOURCE = viewerPath .. "quicklook.swift"
local CACHE_DIR = os.getenv("HOME") .. "/Library/Caches/Hammerspoon-FileSearch"
local BINARY = CACHE_DIR .. "/quicklook"

--- viewer.name - for the console line when a provider steps aside.
M.name = "quicklook"

--- viewer.followsHighlight - false, see the header. The surface reads this to decide whether to
--- run a highlight poll at all, so choosing this provider also costs no timer.
M.followsHighlight = false

local cfg = {
  log = nil,
}

-- The panel currently up, as the task that owns it. One at a time, because a second panel over
-- the first is not something anyone asked for and the newer file is always the wanted one.
local task = nil

-- What that panel is showing, so asking again for the same file can mean close rather than
-- redraw. Kept beside the task because the two have exactly one lifetime between them.
local shownPath = nil

-- Escape, watched only while a panel is up. The panel is deliberately never the key window, which
-- is what keeps the picker alive underneath it, and the price of that is that it cannot receive a
-- key press of its own. So the dismissal has to be caught out here instead. Consuming the press is
-- the whole point, since Escape reaching the list behind would close the list as well, and closing
-- the preview should leave you where you were.
local escTap = nil

-- The deferred teardown that Escape schedules, held so it is not collected before it fires. It
-- exists because stopping a tap from inside that tap's own handler drops the last reference to it
-- mid call, so the work is moved to the next turn of the loop instead.
local escSoon = nil

-- Whether the helper is being compiled right now, so two quick presses queue behind one build
-- rather than starting two.
local building = false

local function stop()
  if escSoon then
    escSoon:stop()
    escSoon = nil
  end
  if escTap then
    escTap:stop()
    escTap = nil
  end
  shownPath = nil
  if not task then return end
  pcall(function() task:terminate() end)
  task = nil
end

local function note(message)
  if cfg.log then cfg.log.i("quicklook: " .. message) end
end

--------------------------------------------------------------------------------
-- Building the helper
--------------------------------------------------------------------------------

-- Whether the cached binary is present and no older than the Swift source, so an edit to the
-- helper forces a rebuild and an unchanged one is reused instantly.
local function binaryFresh()
  local bin = hs.fs.attributes(BINARY, "modification")
  if not bin then return false end
  local src = hs.fs.attributes(SOURCE, "modification")
  return src == nil or bin >= src
end

local function compilerPresent()
  return hs.fs.attributes(SWIFTC, "mode") == "file"
end

-- Ensure the binary exists and is current, then call done(ok). A fresh one is reused at once,
-- otherwise the source is compiled into the cache and done is called when that finishes. The
-- compile runs off the main thread, so the first preview after an edit is slow rather than
-- blocking, and Hammerspoon keeps answering every other key while it happens.
local function ensureBinary(done)
  if binaryFresh() then done(true) return end
  if not compilerPresent() then
    note("no Swift compiler at " .. SWIFTC .. ", the panel cannot be built")
    done(false)
    return
  end
  if building then done(false) return end
  building = true
  hs.fs.mkdir(CACHE_DIR)
  local build = hs.task.new(SWIFTC, function(code, _, err)
    building = false
    if code ~= 0 then
      note("compiling the helper failed (" .. tostring(code) .. "), " .. tostring(err))
    end
    done(code == 0)
  end, { "-O", SOURCE, "-o", BINARY })
  build:start()
end

--------------------------------------------------------------------------------
-- The viewer contract
--------------------------------------------------------------------------------

--- viewer.configure(opts) - the logger, and nothing else. This provider has no policy to take,
--- since the system owns the size, the placement and the rendering of its own window.
---
--- The build is warmed here, which is the one wiring point this provider has, so the first
--- preview of the session is instant rather than paying for a compile. It never blocks and it is
--- a no op once the binary is current, which it is on every run after the first.
function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  ensureBinary(function() end)
  return M
end

--- viewer.available() -> bool, reason
---
--- True when a panel can actually be opened, which means either the helper is already built or
--- the compiler that builds it is present. Answering this honestly is what the availability
--- mechanism is for, because the alternative is a provider you can select that quietly shows
--- nothing, and a missing preview is silent by nature.
function M.available()
  if binaryFresh() then return true end
  if compilerPresent() then return true end
  return false, "no helper binary and no Swift compiler at " .. SWIFTC
end

--- viewer.companionWidth(policy) -> 0
--- No room beside the list. The panel is its own window and lands on top, so reserving anything
--- would leave a permanent empty strip next to the picker.
function M.companionWidth()
  return 0
end

--- viewer.dock(frame) - nothing to dock. Present so the surface can call the same verbs on
--- either provider without asking which one it has.
function M.dock() end

--- viewer.scrollBy(points) - nothing to scroll. The panel scrolls itself under the pointer, and
--- the two scroll keys are not even bound with this provider chosen, since they declare that
--- they need a preview this config scrolls on your behalf.
function M.scrollBy() end

--- viewer.show(row, chooserFrame), put this file in the panel, or take the panel down.
---
--- ASKING FOR THE FILE ALREADY ON SCREEN MEANS CLOSE, which is what makes the key a toggle the way
--- the space bar is one in Finder. Asking for a DIFFERENT file replaces what is up rather than
--- closing it, because the alternative is pressing the key twice to move a preview one row, and
--- because a preview that follows what you asked for is the whole point. The same key therefore
--- reads as show me this, and, when this is already what you are looking at, as put it away.
---
--- A row with no path is a status row and simply closes what is there.
---
--- chooserFrame is the picker's own absolute frame, x, y, w, h, forwarded to the helper as four
--- extra string arguments so it can pick the screen the picker is actually on rather than the
--- screen the pointer happens to be resting on. Optional, since a caller with no frame to hand
--- over still gets a panel, on whatever screen the helper falls back to.
function M.show(row, chooserFrame)
  if not (row and row.path) then stop() return end
  -- Expanded at the boundary as well as at the source, and that is not belt and braces. This is
  -- the point where a path leaves Hammerspoon for another process, and the reason the bug it
  -- guards against was invisible is that hs.fs.attributes expands a tilde while an external
  -- program does not, so the existence check below cannot catch one on its own.
  local path = util.expandHome(row.path)
  -- Compared after expansion, since the same file can arrive as a tilde path from the back row and
  -- as a full one from a search, and those are the same file to everyone but a string compare.
  if task and shownPath == path then
    stop()
    return
  end
  stop()
  if hs.fs.attributes(path) == nil then
    note("nothing at " .. tostring(path))
    return
  end
  ensureBinary(function(ok)
    if not ok then return end
    -- Checked again rather than assumed, since the build is async and the highlight may have
    -- moved on or the picker may have closed while it ran.
    stop()
    -- The handle is captured so the exit callback can ask whether it is still the current one,
    -- and that identity check is not defensive dressing. Replacing a panel terminates the old
    -- helper and starts a new one in the same breath, but the old one's exit arrives LATER, so a
    -- callback that cleared the field unconditionally would erase the handle to the panel that
    -- is actually on screen. Closing the picker then terminated nothing and left a window
    -- floating over nothing, which is exactly what happened before this check existed.
    --
    -- The frame rides along as four more strings on the same argument list, since hs.task hands
    -- a process plain command line arguments and a rect is not one of those on its own. Left off
    -- entirely when there is no frame to give, rather than sent as empty strings, so the helper
    -- can tell a caller with nothing to offer apart from one that sent four numbers it failed to
    -- parse.
    local args = { path }
    if chooserFrame then
      args[#args + 1] = tostring(chooserFrame.x)
      args[#args + 1] = tostring(chooserFrame.y)
      args[#args + 1] = tostring(chooserFrame.w)
      args[#args + 1] = tostring(chooserFrame.h)
    end
    local handle
    handle = hs.task.new(BINARY, function()
      -- Cleared on the panel's own exit too, since closing it by hand is the ordinary way it
      -- ends and a stale handle would make the next show terminate something already gone.
      if task ~= handle then return end
      task = nil
      -- And the Escape watcher goes with it, which matters more than it reads. Clicking the
      -- panel's own close button ends the process without anyone here asking, so a teardown that
      -- only ran on our own paths would leave a tap swallowing Escape for a panel that is not
      -- there, and Escape would stop closing the list. With the handle already nil this
      -- terminates nothing and only forgets.
      stop()
    end, args)
    task = handle
    if handle then
      handle:start()
      shownPath = path
      -- Watched only for as long as there is something to dismiss, so nothing here touches Escape
      -- when no panel is up and the key means what it always meant.
      escTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
        if e:getKeyCode() ~= hs.keycodes.map.escape then return false end
        escSoon = hs.timer.doAfter(0, stop)
        return true
      end)
      escTap:start()
    else
      note("could not start " .. BINARY)
    end
  end)
end

--- viewer.clear() - take the panel down.
function M.clear()
  stop()
end

--- viewer.close() - the picker is gone, so the panel goes with it. Dismissing the list must not
--- leave a preview of one of its rows floating on the screen.
function M.close()
  stop()
end

return M
