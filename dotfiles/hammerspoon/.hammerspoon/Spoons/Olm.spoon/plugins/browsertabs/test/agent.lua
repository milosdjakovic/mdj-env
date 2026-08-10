--- === BrowserTabs.test.agent ===
---
--- The inside half of the integration harness. It exists so a shell runner can drive the real
--- tool the way a person does, through the real leader chord, the real chooser and a real
--- Return. Calling the engine directly was tried first and it hides the faults that matter,
--- because three of the four defects this suite exists to guard against lived between the
--- chooser and the window server rather than inside the engine at all. Skipping only the
--- keyboard, and still going through the chooser's own activate, was tried later and turned out
--- to change the result rather than shorten the path, which is recorded above `round` in run.sh.
---
--- It loads only when the marker file beside it is present, which the runner writes at the
--- start of a suite and removes at the end, so a normal machine never has this in its config.
--- Nothing in the spoon depends on it and it depends on nothing but the chooser's public
--- surface.
---
--- Commands arrive as files rather than through hs.ipc or a URL, and both exclusions are
--- measured. The CLI stalls while asynchronous work is in flight, which this tool always has,
--- and killing a stalled call leaves the channel unusable for the rest of the session. A URL
--- does not stall but it goes through Launch Services, which takes focus, and focus is what
--- most of these rounds are measuring. So the runner drops a request file and the agent polls
--- for it, and nothing in the channel activates anything.

local M = {}

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

-- Where requests arrive. Derived from HOME rather than passed in, because this file is loaded by
-- Hammerspoon and there is nobody to pass it anything. It sits under the caches directory on
-- purpose, since a file written inside the watched config tree would trigger a reload on every
-- command.
local CHANNEL = (os.getenv("HOME") or "") .. "/Library/Caches/browsertabs-test/channel"

-- The poll interval. A directory that is nearly always empty is cheap to read, so this is chosen
-- to be shorter than anything the runner can perceive rather than to save work. A path watcher
-- would do the same job with a coalescing latency that would have to be measured, and the whole
-- point of this channel is to stop paying delays nobody can see.
local POLL = 0.02

-- Every pending timer is held here until it fires. A Hammerspoon timer is userdata whose
-- finalizer stops it, so one that nothing refers to can be collected before it runs, which for
-- this file would mean a chord that silently never completes and a test that fails for a reason
-- that has nothing to do with the tool.
local pending = {}
local function after(delay, fn)
  local t
  t = hs.timer.doAfter(delay, function()
    pending[t] = nil
    fn()
  end)
  pending[t] = true
  return t
end

-- The reply goes to a temporary name and is then renamed into place, so the runner polling for
-- the file can never read half of one. Rename is atomic on the same filesystem.
local function reply(path, value)
  if not path or path == "" then return end
  local f = io.open(path .. ".part", "w")
  if not f then return end
  f:write(hs.json.encode(value or {}))
  f:close()
  os.rename(path .. ".part", path)
end

--------------------------------------------------------------------------------
-- Driving the keyboard
--------------------------------------------------------------------------------

-- The leader chord has to look like it came from the keyboard. The shared ChordKey eventtap
-- deliberately ignores any event whose source state is not the HID system's, which is what stops
-- Hammerspoon's own synthetic keys from re-entering its own leader engine. So each event is
-- stamped as if the hardware sent it. Without this stamp the chooser simply never opens, which
-- was the first thing this harness got wrong.
local HID_SYSTEM_STATE = 1

local function postKey(key, isDown)
  local e = hs.eventtap.event.newKeyEvent({}, key, isDown)
  e:setProperty(hs.eventtap.event.properties.eventSourceStateID, HID_SYSTEM_STATE)
  e:post()
end

-- Hold the leader, tap the key, release the leader, spaced the way a hand does it. The gaps are
-- not decoration. The leader engine distinguishes a hold from a tap by time, so a chord posted
-- as four events in one tick reads as a tap of the leader and nothing opens.
--
-- `hold` is how long the leader is down before the key, which is also what makes the slow press
-- case possible, since holding past the cheat sheet delay brings that panel up first and the
-- chooser then has to open over it.
local function chord(leader, key, hold, done)
  postKey(leader, true)
  after(hold, function()
    postKey(key, true)
    after(0.03, function()
      postKey(key, false)
      after(0.05, function()
        postKey(leader, false)
        after(0.05, done)
      end)
    end)
  end)
end

--------------------------------------------------------------------------------
-- Reading the tool's own state
--------------------------------------------------------------------------------

-- The rows the chooser would show for a query, top first. The runner checks that the tab it
-- means to open is the top row before it presses Return, because the top row is what Return
-- takes. It deliberately does not require the query to match one row only, since a fuzzy match
-- over a hundred tabs always matches more than one and an earlier version of this harness
-- aborted every round for that reason.
local function topRows(query, n)
  local ui = spoon.BrowserTabs and spoon.BrowserTabs.chooser
  if not ui then return nil end
  local out = {}
  for i, r in ipairs(ui.tabRows(query or "")) do
    if i > (n or 3) then break end
    local tab = r.item and r.item.tab or {}
    out[#out + 1] = {
      title = r.title,
      url = tab.url,
      bundleID = tab.bundleID,
      windowID = tab.windowID,
      tabIndex = tab.tabIndex,
    }
  end
  return out
end

--------------------------------------------------------------------------------
-- The commands
--------------------------------------------------------------------------------

-- Each command is a function of the parsed query parameters and a done callback that carries the
-- reply value. Adding one is a new entry here and a new line in the runner, which is the whole
-- reason this is a table rather than a chain of ifs.
local commands = {}

function commands.ping(_, done)
  done({ ok = true, config = hs.configdir })
end

function commands.chord(p, done)
  chord(p.leader or "f18", p.key or "w", tonumber(p.hold) or 0.12, function()
    done({ ok = true })
  end)
end

-- Typing is posted at Hammerspoon itself rather than at whatever holds focus. Every command in this
-- harness arrives by opening a URL, and opening one while the list is up is enough to take key
-- focus off it, so freely posted characters went to the app underneath while the list sat there
-- unfiltered. Return still worked throughout, because the chooser catches Return with an event tap
-- of its own rather than through focus, which is what made this look like typing working.
function commands.type(p, done)
  local hammerspoon = hs.application.get("org.hammerspoon.Hammerspoon")
  hs.eventtap.keyStrokes(p.text or "", hammerspoon)
  after(0.15, function() done({ ok = true }) end)
end

function commands.key(p, done)
  local name = p.name or "return"
  local reps = tonumber(p.reps) or 1
  local function step(i)
    if i > reps then
      after(0.05, function() done({ ok = true }) end)
      return
    end
    hs.eventtap.keyStroke({}, name, 0)
    after(0.04, function() step(i + 1) end)
  end
  step(1)
end

function commands.rows(p, done)
  done({ ok = true, rows = topRows(p.query, tonumber(p.n)) })
end

-- Which Space is current, and which Space each of a browser's windows is on. Both accessibility
-- readers can only ever see the current Space, while a browser's own dictionary answers about every
-- window wherever it is. So a window on another Space reads as no window at all, which is the same
-- reading a raise that never happened produces, and nothing else in this harness can tell the two
-- apart.
function commands.spaces(p, done)
  local out = { ok = true, focused = hs.spaces.focusedSpace(), windows = {} }
  local app = hs.application.get(p.bundleID or "")
  if app then
    for _, w in ipairs(app:allWindows()) do
      out.windows[#out.windows + 1] = { id = w:id(), spaces = hs.spaces.windowSpaces(w) }
    end
  end
  done(out)
end

function commands.showing(_, done)
  local ui = spoon.BrowserTabs and spoon.BrowserTabs.chooser
  done({ ok = true, showing = ui ~= nil and ui.isShowing() })
end

-- Force a fresh listing and answer only once it has landed, so the runner never reads rows built
-- from a listing taken before it arranged the browser.
function commands.prepare(_, done)
  local ui = spoon.BrowserTabs and spoon.BrowserTabs.chooser
  if not ui then done({ ok = false, err = "no chooser" }) return end
  ui.prepare(function()
    done({ ok = true, rows = topRows("", 1) })
  end)
end

-- The whole listing as the tool sees it, so a case can judge what is in the list rather than what
-- happens when a row is chosen. Safari's phantom window is proved absent this way, since there is
-- no round that could show it, only rows that must not exist.
function commands.listing(_, done)
  local ui = spoon.BrowserTabs and spoon.BrowserTabs.chooser
  if not ui then done({ ok = false, err = "no chooser" }) return end
  ui.prepare(function()
    done({ ok = true, rows = topRows("", 10000) })
  end)
end

-- Reading and setting which browsers are switched on. A case that turns one off has to turn it
-- back on, and the runner does that in the case's own cleanup rather than in the restore, so a
-- suite stopped halfway still leaves the setting as it found it on the next full run.
function commands.enabled(p, done)
  local bt = spoon.BrowserTabs
  if not bt then done({ ok = false, err = "no spoon" }) return end
  if p.on == "1" or p.on == "0" then bt:setEnabled(p.bundleID, p.on == "1") end
  done({ ok = true, enabled = bt:isEnabled(p.bundleID) })
end

-- Record a tab as opened through the tool, which is the only thing that writes the remembered
-- order now that nothing watches the browsers. A case needing a known tab in a known row arranges
-- it here rather than through the browser, because nothing done in the browser affects the order
-- any more, which is the entire point of the current design.
--
-- Arranging a precondition through the same call the tool makes is fair for the one case that
-- needs it, since what that case checks is that a bare Return opens the row on top, not how the
-- row got there. Anything asserting about the order itself must not use this.
--
-- This harness owns the coupling on purpose. The key pairing mirrors keyFor in the plugin's own
-- init.lua, and the byte joining the two halves is that same function's separator.
function commands.touch(p, done)
  local bt = spoon.BrowserTabs
  if not bt then done({ ok = false, err = "no spoon" }) return end
  if not bt._recency then done({ ok = false, err = "no recency instance" }) return end
  bt._recency.touch((p.bundleID or "") .. "\0" .. (p.url or ""))
  done({ ok = true })
end

-- Press a control inside an application by its accessibility name, used for the few states that
-- exist only behind a page or a panel with nothing scriptable behind it.
--
-- Chrome needs coaxing first. It keeps the contents of a web page out of the accessibility tree
-- until something claiming to be assistive technology asks for it, which is why searching for a
-- button on one of its own internal pages finds an empty tree and reports the state as
-- unreachable. Setting the enhanced interface flag makes it expose the page, and it is set back
-- afterwards, because leaving it on costs the browser memory for the rest of its life and is not
-- this harness's to decide.
local function findByName(el, want, depth)
  if depth > 14 then return nil end
  local kids = el:attributeValue("AXChildren") or {}
  for _, kid in ipairs(kids) do
    for _, attr in ipairs({ "AXTitle", "AXDescription", "AXValue" }) do
      local v = kid:attributeValue(attr)
      if type(v) == "string" and v:lower():find(want, 1, true) then return kid end
    end
    local hit = findByName(kid, want, depth + 1)
    if hit then return hit end
  end
  return nil
end

-- Look inside an application with the page exposed, and optionally press what was found. A case
-- uses the looking half to tell one reason for a state being unreachable from another, since
-- reporting that a browser would not do something is nearly useless next to reporting why.
local function withPageExposed(bundleID, settle, fn, done)
  local app = hs.application.get(bundleID or "")
  if not app then done({ ok = false, err = "not running" }) return end
  local el = hs.axuielement.applicationElement(app)
  if not el then done({ ok = false, err = "no accessibility element" }) return end

  local had = el:attributeValue("AXEnhancedUserInterface")
  el:setAttributeValue("AXEnhancedUserInterface", true)

  -- The flag takes effect asynchronously, since the browser has to rebuild its tree before
  -- anything on the page can be found.
  after(settle, function()
    local value = fn(el)
    after(1.0, function()
      if had ~= true then el:setAttributeValue("AXEnhancedUserInterface", false) end
      done(value)
    end)
  end)
end

function commands.axfind(p, done)
  withPageExposed(p.bundleID, tonumber(p.settle) or 2.5, function(el)
    return { ok = true, found = findByName(el, (p.name or ""):lower(), 0) ~= nil }
  end, done)
end

function commands.press(p, done)
  withPageExposed(p.bundleID, tonumber(p.settle) or 2.0, function(el)
    local hit = findByName(el, (p.name or ""):lower(), 0)
    local pressed = hit ~= nil and hit:performAction("AXPress") ~= nil
    return { ok = pressed, pressed = pressed }
  end, done)
end

-- What Hammerspoon believes is focused. This is the weaker of the two witnesses and is recorded
-- rather than trusted, because it reads the same accessibility layer the code under test writes
-- to. The runner's own check goes through System Events instead, from outside this process.
function commands.focused(_, done)
  local w = hs.window.focusedWindow()
  if not w then done({ ok = true, window = nil }) return end
  local f = w:frame()
  local app = w:application()
  done({ ok = true, window = {
    id = w:id(),
    title = w:title(),
    app = app and app:name(),
    bundleID = app and app:bundleID(),
    frame = { x = f.x, y = f.y, w = f.w, h = f.h },
  } })
end

--------------------------------------------------------------------------------
-- The channel
--------------------------------------------------------------------------------

local function ensureChannel()
  local acc = ""
  for seg in CHANNEL:gmatch("[^/]+") do
    acc = acc .. "/" .. seg
    if not hs.fs.attributes(acc) then hs.fs.mkdir(acc) end
  end
end

local function dispatch(params)
  local fn = commands[params.cmd or ""]
  if not fn then
    reply(params.reply, { ok = false, err = "unknown command " .. tostring(params.cmd) })
    return
  end
  local ok, err = pcall(fn, params, function(value)
    reply(params.reply, value)
  end)
  if not ok then
    reply(params.reply, { ok = false, err = tostring(err) })
  end
end

-- Every request waiting in the channel, taken in one pass. The names are collected before any of
-- them is removed, since removing entries from a directory while iterating it is not something to
-- rely on. A request is removed before it is dispatched rather than after, so a command that throws
-- cannot be picked up and run a second time on the next tick.
--
-- Only a fully renamed request is matched. The runner writes under a .part name first, so a name
-- ending in .json is one that arrived whole.
local function drain()
  if not hs.fs.attributes(CHANNEL) then return end
  local names = {}
  for name in hs.fs.dir(CHANNEL) do
    if name:match("^req%..*%.json$") then names[#names + 1] = name end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local path = CHANNEL .. "/" .. name
    local f = io.open(path, "r")
    local body = f and f:read("*a")
    if f then f:close() end
    os.remove(path)
    local ok, params = pcall(hs.json.decode, body or "")
    if ok and type(params) == "table" then dispatch(params) end
  end
end

--- M.start() - begin reading the channel. Called by the spoon only when the marker is present.
--- The timer is held on the module, since a Hammerspoon timer nothing refers to is collected and
--- stops, which here would look like the agent having gone deaf halfway through a suite.
function M.start()
  ensureChannel()
  M.reader = hs.timer.new(POLL, drain)
  M.reader:start()
  hs.printf("BrowserTabs test agent listening on %s, loaded from %s", CHANNEL, spoonPath)
  return M
end

return M
