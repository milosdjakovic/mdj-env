--- === BrowserTabs.test.agent ===
---
--- The inside half of the integration harness. It exists so a shell runner can drive the real
--- tool the way a person does, through the real leader chord, the real chooser and a real
--- Return, rather than by calling the engine directly. Calling the engine directly was tried
--- first and it hides the faults that matter, because three of the four defects this suite
--- exists to guard against lived between the chooser and the window server rather than inside
--- the engine at all.
---
--- It loads only when the marker file beside it is present, which the runner writes at the
--- start of a suite and removes at the end, so a normal machine never has this in its config.
--- Nothing in the spoon depends on it and it depends on nothing but the chooser's public
--- surface.
---
--- Commands arrive as a URL rather than through hs.ipc. The reason is measured. The CLI stalls
--- while asynchronous work is in flight, which this tool always has, and killing a stalled call
--- leaves the channel unusable for the rest of the session. A URL is one way and cannot stall,
--- so every answer comes back through a reply file instead.

local M = {}

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

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

--- M.start() - bind the command handler. Called by the spoon only when the marker is present.
function M.start()
  hs.urlevent.bind("bttest", function(_, params)
    params = params or {}
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
  end)
  hs.printf("BrowserTabs test agent listening, loaded from %s", spoonPath)
  return M
end

return M
