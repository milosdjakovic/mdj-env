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
--- surface, the tool's manifest and the shared search's two files, which it loads to rank the
--- rows the way the stage does.
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

-- The shared search, loaded from the spoon this harness ships in, the same two files the stage
-- ranks every list through. Loaded once, on the first ask, since a load costs a parse and the
-- harness asks for rows on every poll of a round.
local olmPath = spoonPath .. "../../../"
local shared
local function sharedSearch()
  if shared then return shared end
  local rank = assert(loadfile(olmPath .. "lib/chooser/rank.lua"))()
  local match = assert(loadfile(olmPath .. "lib/chooser/match.lua"))()
  -- The presentation's own searchText and rowLimit, read from the manifest beside the tool, so a
  -- ranking here keeps exactly the rows the stage would. A searchText is a member spec, resolved
  -- against the live plugin the way the registrar resolves it, a dotted path called with a dot.
  local manifest = assert(loadfile(spoonPath .. "../manifest.lua"))()
  local p = manifest.presentation or {}
  local search = { rowLimit = p.rowLimit }
  if type(p.searchText) == "table" and type(p.searchText.member) == "string" then
    search.searchText = function(raw)
      local fn = spoon.BrowserTabs
      for part in p.searchText.member:gmatch("[^.]+") do fn = fn and fn[part] end
      return fn(raw)
    end
  end
  shared = { rank = rank, matcher = match.fuzzy, search = search }
  return shared
end

-- The rows the chooser would show for a query, top first. The runner checks that the tab it
-- means to open is the top row before it presses Return, because the top row is what Return
-- takes. It deliberately does not require the query to match one row only, since a fuzzy match
-- over a hundred tabs always matches more than one and an earlier version of this harness
-- aborted every round for that reason.
--
-- The supplier hands every row over in its resting order and reads no query since phase three of
-- the unified search on 2026-10-17, so the ranking is done here exactly as the chooser does it,
-- the presentation's own rows, the settings door included, through rank.apply with the shared
-- fuzzy matcher and the presentation's search. Reading the supplier alone would answer the
-- resting order, so every typed round would find the wrong top row and a case asking for exactly
-- one row would always skip.
local function topRows(query, n)
  local ui = spoon.BrowserTabs and spoon.BrowserTabs.chooser
  if not ui then return nil end
  local s = sharedSearch()
  local supplied = (ui.rows or ui.tabRows)(query or "")
  local ranked = s.rank.apply(supplied, query or "", s.matcher, s.search)
  local out = {}
  for i, r in ipairs(ranked) do
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
  local ui = spoon.BrowserTabs and spoon.BrowserTabs.chooser
  done({
    ok = true,
    config = hs.configdir,
    leaderWired = ui ~= nil and ui.leaderWired ~= nil and ui.leaderWired() == true,
  })
end

-- The chord answers only once the leader is believed released. The leader's key up can be lost,
-- which ChordKey releases by its watchdog only after thirty seconds, and a token typed while the
-- leader is believed held runs as Hyper chords whose last letter closes the list. So after the key
-- up this polls the tool's own word for the leader every twenty milliseconds for three hundred, and
-- posts the key up again with the same stamp when it is still held, at most three times. The reply
-- says how long the release took and how many key ups it needed, which is the measurement as well
-- as the guard.
local RELEASE_POLL = 0.02
local RELEASE_WINDOW_MS = 300
local RELEASE_RETRIES = 3

local function leaderWired()
  local ui = spoon.BrowserTabs and spoon.BrowserTabs.chooser
  return ui ~= nil and ui.leaderWired ~= nil and ui.leaderWired() == true
end

local function leaderHeld()
  local ui = spoon.BrowserTabs and spoon.BrowserTabs.chooser
  return ui ~= nil and ui.leaderHeld ~= nil and ui.leaderHeld() == true
end

function commands.chord(p, done)
  local leader = p.leader or "f18"
  chord(leader, p.key or "w", tonumber(p.hold) or 0.12, function()
    local started = hs.timer.secondsSinceEpoch()
    local reposted = 0
    local function elapsed() return math.floor((hs.timer.secondsSinceEpoch() - started) * 1000) end
    local function poll(since)
      if not leaderHeld() then
        done({ ok = true, releasedAfter = elapsed(), reposted = reposted, wired = leaderWired() })
        return
      end
      if elapsed() - since >= RELEASE_WINDOW_MS then
        if reposted >= RELEASE_RETRIES then
          done({
            ok = false,
            err = "the leader is still believed held after " .. reposted .. " repeated key ups",
            reposted = reposted,
            wired = leaderWired(),
          })
          return
        end
        reposted = reposted + 1
        postKey(leader, false)
        since = elapsed()
      end
      after(RELEASE_POLL, function() poll(since) end)
    end
    poll(0)
  end)
end

-- Typing is posted untargeted, the same route Return takes. It was posted at the Hammerspoon process
-- by name while every command arrived by opening a URL, since opening one took key focus off the
-- native list and freely posted characters then landed in the application underneath. That stopped
-- reaching anything on 2026-10-14, when the default chooser became a canvas, at commit 476cb47,
-- that never holds key focus and whose field reads keys only through a session level event tap. A
-- keystroke posted at a process goes to that process directly and never passes a session tap, which
-- was measured on 2026-10-19, so the field saw none of the query and every Safari round and most
-- Chrome rounds took the top row of an unfiltered list. Untargeted is right now because the field's
-- own tap claims the characters while the list is up, so they land in the list and never in the app
-- underneath, the way Return already arrives.
--
-- It refuses unless the tab list is showing, so a token is never typed into a browser page when the
-- list closed between the runner's showing check and this command. Characters posted untargeted go
-- to whatever holds the keyboard when nothing claims them.
function commands.type(p, done)
  local ui = spoon.BrowserTabs and spoon.BrowserTabs.chooser
  if not (ui and ui.isShowing()) then
    done({ ok = false, err = "the tab list is not showing, so nothing was typed" })
    return
  end
  if leaderHeld() then
    done({ ok = false, err = "the leader is still believed held" })
    return
  end
  hs.eventtap.keyStrokes(p.text or "")
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

-- What the live list holds right now, read from the stage rather than recomputed. The field text
-- and the highlighted row come from the default chooser provider's own state, which is live, so
-- this is what a Return pressed this instant would take. It is the only reading here that sees a
-- query that never landed, since `rows` ranks the plugin's rows for a query it is handed and would
-- say the right tab is on top over a list that was never filtered. The stage is reached through
-- the two root words the tool's surface is handed, never by opening the spoon, which the plugin
-- boundary check forbids.
function commands.live(_, done)
  local ui = spoon.BrowserTabs and spoon.BrowserTabs.chooser
  if not (ui and ui.isShowing()) then
    done({ ok = false, err = "no list is showing" })
    return
  end
  local live = ui.live()
  local item = live.item
  done({
    ok = true,
    query = live.query or "",
    leaderHeld = live.leaderHeld == true,
    url = item and item.tab and item.tab.url or nil,
    kind = item and item.kind or nil,
  })
end

-- The trace. `watch` starts a timer sampling every twenty milliseconds for the given seconds, six
-- by default, and records a compact line only when the leader held state, the showing flag, the field
-- text or the frontmost application differs from the sample before, plus the first one. It also runs
-- a passive key down tap that records each event's keycode, source stamp, characters and leader
-- state, and swallows nothing. `watched` stops both and answers the lines, with the closing
-- handler's own time relative to the watch start when it falls inside the window, and its traceback.
-- Everything lives on the module, since a timer or a tap nothing refers to is collected and the
-- buffer is read from a later command. The point is to learn what closed the list when a round's
-- typed token fails to land.
local WATCH_POLL = 0.02
local WATCH_SECONDS = 6

local function stopWatch()
  if M.watcher then
    M.watcher:stop()
    M.watcher = nil
  end
  if M.keyTap then
    M.keyTap:stop()
    M.keyTap = nil
  end
end

function commands.watch(p, done)
  stopWatch()
  M.samples = {}
  local seconds = tonumber(p.seconds) or WATCH_SECONDS
  local started = hs.timer.secondsSinceEpoch()
  M.watchStarted = started
  local function stamp() return math.floor((hs.timer.secondsSinceEpoch() - started) * 1000) end
  local lastHeld, lastShowing, lastField, lastFront
  M.watcher = hs.timer.new(WATCH_POLL, function()
    local elapsed = hs.timer.secondsSinceEpoch() - started
    if elapsed > seconds then
      stopWatch()
      return
    end
    local ui = spoon.BrowserTabs and spoon.BrowserTabs.chooser
    local held = leaderHeld()
    local showing = ui ~= nil and ui.isShowing() == true
    local live = ui ~= nil and ui.live and ui.live() or nil
    local field = live and live.query or ""
    local app = hs.application.frontmostApplication()
    local front = app and app:bundleID() or ""
    local ms = stamp()
    if lastHeld == nil or held ~= lastHeld or showing ~= lastShowing then
      M.samples[#M.samples + 1] = string.format("%dms held=%s showing=%s", ms, tostring(held), tostring(showing))
      lastHeld, lastShowing = held, showing
    end
    if lastField == nil or field ~= lastField then
      M.samples[#M.samples + 1] = string.format("%dms field=%s", ms, field)
      lastField = field
    end
    if lastFront == nil or front ~= lastFront then
      M.samples[#M.samples + 1] = string.format("%dms front=%s", ms, front)
      lastFront = front
    end
  end)
  M.watcher:start()
  local props = hs.eventtap.event.properties
  M.keyTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(ev)
    M.samples[#M.samples + 1] = string.format("key %dms code=%s source=%s chars=%s held=%s",
      stamp(),
      tostring(ev:getKeyCode()),
      tostring(ev:getProperty(props.eventSourceStateID)),
      tostring(ev:getCharacters()),
      tostring(leaderHeld()))
    return false
  end)
  M.keyTap:start()
  done({ ok = true })
end

function commands.watched(_, done)
  stopWatch()
  local ui = spoon.BrowserTabs and spoon.BrowserTabs.chooser
  local last = ui and ui.lastClose or nil
  local closedAt, trace
  if last and M.watchStarted and last.at >= M.watchStarted then
    closedAt = math.floor((last.at - M.watchStarted) * 1000)
    trace = last.trace
  end
  done({ ok = true, samples = M.samples or {}, closedAt = closedAt, trace = trace })
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
