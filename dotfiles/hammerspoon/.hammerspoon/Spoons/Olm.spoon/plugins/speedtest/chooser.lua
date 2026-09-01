--- === Speedtest.chooser ===
---
--- The list surface. Pure policy over the runner and the store, talking to both only through
--- what the composition root injected, so it knows nothing about flags, JSON, or files.
---
--- Every row carries plain scalars and nothing else. A row's payload is handed to LuaSkin on
--- its way to the widget, so a function or a userdata anywhere inside one is refused, and the
--- refusal takes the WHOLE list rather than the offending row, leaving an empty picker and a
--- reason visible only in the console. That is a defect this tree has already shipped once,
--- so rows here carry a run's timestamp and a network id and the record is looked up when
--- something is actually done with it.
---
--- The run is not owned here, deliberately. It lives on the runner and outlives this list,
--- since nobody stands in front of a picker for twenty seconds. What is owned here is the
--- ticker that redraws the elapsed row, which is only ever about what is on screen.
---
--- The pane follows the highlight, and which of its three faces to draw is decided by the row
--- itself rather than by this file knowing which level it is on. A row says pane equals
--- result, trend, or help, and the same one highlight handler serves every level.

local chooserPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(chooserPath .. "util.lua")()
local pane = loadfile(chooserPath .. "pane.lua")()

local M = { name = "Speedtest.chooser" }

local cfg = {}          -- injected by the plugin root, see M.configure
local net = nil         -- the network this open is about, read once per open
local ticker = nil      -- redraws the elapsed row while a run is in flight
local lastReason = nil  -- why the most recent run did not land, shown until the next one

local ICON_RUN = "📶"
local ICON_STOP = "🚫"
local ICON_RESULT = "📈"
local ICON_SETTINGS = "⚙️"
local ICON_NETWORKS = "🌐"
local ICON_BACK = "⬅️"
local ICON_EMPTY = "📊"
local ICON_PROBLEM = "⚠️"
local ICON_NAME = "✏️"
local ICON_CLEAR = "🗑️"
local ICON_KEEP = "↩️"

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function icon(glyph)
  if not (cfg.glyphIcon and glyph) then return nil end
  return cfg.glyphIcon.icon(glyph)
end

local function row(title, subTitle, glyph, item, enabled)
  return { title = title, subTitle = subTitle, image = icon(glyph),
           item = item, enabled = enabled ~= false }
end

local function backRow()
  return row("Back", nil, ICON_BACK, { act = "back", pane = "none" }, true)
end

local function currentNet()
  if not net then net = util.currentNetwork() end
  return net
end

local function labelFor(netId, fallback)
  return cfg.store.label(netId, fallback)
end

-- Said on the Run row and in the pane, so a person can see what a run will actually do
-- without opening the settings page to find out.
local function describeRun(settings)
  local parts = {}
  if settings.direction == "down" then
    parts[#parts + 1] = "download only"
  elseif settings.direction == "up" then
    parts[#parts + 1] = "upload only"
  else
    parts[#parts + 1] = "both directions"
  end
  if settings.sequential then parts[#parts + 1] = "one at a time" end
  if settings.protocol and settings.protocol ~= "auto" then parts[#parts + 1] = settings.protocol end
  if settings.privateRelay then parts[#parts + 1] = "private relay" end
  parts[#parts + 1] = (settings.maxSeconds or 20) .. "s"
  return table.concat(parts, ", ")
end

-- What the running row says under itself. The tool reports nothing for the first second or two
-- while it opens its flows, so there is a real moment with a run in progress and no figures in it,
-- and saying warming up is more honest than showing three zeros.
local function runningSubtitle()
  local elapsed = cfg.runner.elapsed() .. "s"
  if not cfg.runner.isLive() then
    return "running, " .. elapsed .. ", no live figures without script"
  end
  local latest = cfg.runner.latest()
  if not latest then return "warming up, " .. elapsed end
  return string.format("%.1f down, %.1f up, %.0f RPM, %s",
    latest.down, latest.up, latest.rpm or 0, elapsed)
end

-- Three figures in one row, in the order a person reads them. A direction that was not
-- measured simply has no column rather than a column saying nothing.
local function resultTitle(record)
  local parts = {}
  local down = util.rate(record.down)
  local up = util.rate(record.up)
  if down then parts[#parts + 1] = down .. " down" end
  if up then parts[#parts + 1] = up .. " up" end
  if record.rpm then parts[#parts + 1] = string.format("%.0f RPM", record.rpm) end
  if #parts == 0 then return "Nothing measured" end
  return table.concat(parts, "   ")
end

-- The one line a person pastes into a message when they are complaining to somebody.
local function summaryLine(record)
  local parts = {}
  local down = util.rate(record.down)
  local up = util.rate(record.up)
  if down then parts[#parts + 1] = down .. " Mbps down" end
  if up then parts[#parts + 1] = up .. " Mbps up" end
  if record.rpm then
    parts[#parts + 1] = string.format("%.0f RPM", record.rpm)
    local loaded = util.loadedMs(record.rpm)
    if loaded then parts[#parts + 1] = string.format("%.0f ms under load", loaded) end
  end
  parts[#parts + 1] = labelFor(record.net, record.label)
  parts[#parts + 1] = util.stamp(record.at)
  return table.concat(parts, ", ")
end

local function resultRow(record)
  local sub = util.relative(record.at) .. ", " .. labelFor(record.net, record.label)
  return row(resultTitle(record), sub, ICON_RESULT,
    { act = "result", pane = "result", rid = record.at }, true)
end

--------------------------------------------------------------------------------
-- What the pane says about a row that is not a measurement
--------------------------------------------------------------------------------

-- Every entry is whole sentences rather than lines broken to a width. The pane wraps them to
-- whatever room it actually has, so nothing here is written against a guess about the pane's size
-- and nothing gets cut off at the edge. An empty string is a paragraph break.
local HELP = {
  settings = { title = "Settings", lines = {
    "What a run does, how many readings are kept per network, and what this network is called.",
  } },
  networks = { title = "Other networks", lines = {
    "Every network this Mac has measured, each with its own history kept separately.",
    "",
    "A trend drawn across two different networks would be a number about nowhere, which is why they never share a line.",
  } },
  direction = { title = "Direction", lines = {
    "Both directions, download only, or upload only.",
    "",
    "Skipping a direction makes the run shorter and leaves that half of the trend without a point for this run.",
  } },
  measurement = { title = "Measurement", lines = {
    "Both at once loads the link in both directions together, which is what real use looks like and what responsiveness is meant to be measured under.",
    "",
    "One at a time measures each direction with the other idle, which reads higher and is closer to a capacity ceiling than to a working figure.",
  } },
  runtime = { title = "Maximum runtime", lines = {
    "How long the tool is allowed to spend measuring.",
    "",
    "Shorter is noisier. Ten seconds is enough for the figures to settle for an ordinary look, and the longer runs are there for when a number is being argued over.",
  } },
  protocol = { title = "Protocol", lines = {
    "Automatic lets the tool and the server agree, which is what ordinary traffic does.",
    "",
    "Forcing HTTP/3 or HTTP/2, or turning L4S off, is for answering a question about the path rather than for a reading you intend to compare with the others.",
  } },
  relay = { title = "iCloud Private Relay", lines = {
    "Measures through Private Relay rather than directly.",
    "",
    "Worth one run when Safari feels slow and nothing else does. Not worth leaving on, since it measures a different path from the one everything else on this Mac uses.",
  } },
  cap = { title = "Keep per network", lines = {
    "How many readings are kept for each network before the oldest is dropped.",
    "",
    "Nothing here expires by age. A reading from months ago is the most useful record in the file the day something changes.",
  } },
  name = { title = "Name this network", lines = {
    "Wi Fi network names are a location on modern macOS, so an app is only told one if it holds Location Services permission, and Hammerspoon has never asked for it. It is not refused outright either, the name simply comes back blank, which is why this shows a made up label instead.",
    "",
    "Nothing is lost by that. Readings are filed against the network profile itself, which needs no permission and does not change, so naming a network here only changes what it is called on screen. Every reading already kept stays exactly where it is.",
    "",
    "Granting Hammerspoon Location Services in System Settings would make the real names appear on their own.",
  } },
  clearOne = { title = "Clear this network", lines = {
    "Forgets every reading kept for this network.",
    "",
    "The name stays and other networks are untouched.",
  } },
  clearAll = { title = "Clear everything", lines = {
    "Forgets every reading for every network.",
    "",
    "The names stay. There is no undo, the file is rewritten immediately.",
  } },
  missing = { title = "Nothing to measure with", lines = {
    "networkQuality ships with macOS and lives in /usr/bin. This Mac answers nothing there.",
    "",
    "The history already kept still opens and still reads.",
  } },
  running = { title = "Running", lines = {
    "Closing this list does not stop the run. The reading lands in the history either way.",
  } },
}

--------------------------------------------------------------------------------
-- Running
--------------------------------------------------------------------------------

local function redraw()
  if cfg.redrawPresented then cfg.redrawPresented("speedtest", false) end
end

-- Everything the running pane draws from, gathered in one place since the highlight, the progress
-- watcher and the first paint all ask the same question.
local function runningState()
  return {
    samples = cfg.runner.samples(),
    elapsed = cfg.runner.elapsed(),
    limit = cfg.store.settings().maxSeconds,
    live = cfg.runner.isLive(),
  }
end

local function stopTicker()
  if ticker then
    ticker:stop()
    ticker = nil
  end
end

-- One tick a second while a run is in flight, purely so the elapsed row counts up. The
-- redraw is a no op whenever this presentation is not what the stage is showing, so a run
-- started and then walked away from costs a call that does nothing twenty times.
local function startTicker()
  stopTicker()
  ticker = hs.timer.doEvery(1, redraw)
end

-- Fresh figures land about four times a second. The list itself is redrawn once a second by the
-- ticker, since a row of text changing faster than that reads as flicker rather than as progress,
-- while the pane is redrawn on every one of them, since a graph is the one thing that genuinely
-- wants every point. The pane is only touched while the running row is the one under the
-- highlight, so a person reading a past reading during a run is never interrupted by it.
local function onProgress()
  local item = cfg.stageSelectedItem and cfg.stageSelectedItem()
  if not (item and item.pane == "running") then return end
  pane.refreshRunning(runningState())
end

local function startRun()
  if cfg.runner.isRunning() then return end
  lastReason = nil
  local target = currentNet()
  local started = cfg.runner.start(cfg.store.settings(), target, function(record, reason)
    stopTicker()
    if record then
      cfg.store.add(record)
    elseif reason ~= "stopped" then
      -- A stopped run is not a failure and says nothing worth keeping on screen.
      lastReason = reason
    end
    redraw()
  end, onProgress)
  if started then startTicker() end
  redraw()
end

--------------------------------------------------------------------------------
-- The settings page
--------------------------------------------------------------------------------

-- Every option row steps to the next value in a small ring rather than opening a level of
-- its own, so flipping one is a single press and the page never moves under the hand.
local function nextIn(ring, current)
  for i, value in ipairs(ring) do
    if value == current then return ring[(i % #ring) + 1] end
  end
  return ring[1]
end

local DIRECTIONS = { "both", "down", "up" }
local RUNTIMES = { 10, 20, 30 }
local PROTOCOLS = { "auto", "h3", "h2", "noL4S" }
local CAPS = { 25, 50, 200 }

local function directionWord(value)
  if value == "down" then return "Download only" end
  if value == "up" then return "Upload only" end
  return "Both directions"
end

local settingsChild, namingChild, confirmClearChild, networksChild, networkRunsChild

local function settingsRows()
  local settings = cfg.store.settings()
  local target = currentNet()
  local rows = { backRow() }

  rows[#rows + 1] = row("Direction", directionWord(settings.direction), ICON_SETTINGS,
    { act = "set", key = "direction", pane = "help", help = "direction" }, true)
  rows[#rows + 1] = row("Measurement",
    settings.sequential and "One direction at a time" or "Both at once", ICON_SETTINGS,
    { act = "set", key = "sequential", pane = "help", help = "measurement" }, true)
  rows[#rows + 1] = row("Maximum runtime", (settings.maxSeconds or 20) .. " seconds", ICON_SETTINGS,
    { act = "set", key = "maxSeconds", pane = "help", help = "runtime" }, true)
  rows[#rows + 1] = row("Protocol",
    settings.protocol == "auto" and "Automatic" or settings.protocol, ICON_SETTINGS,
    { act = "set", key = "protocol", pane = "help", help = "protocol" }, true)
  rows[#rows + 1] = row("iCloud Private Relay",
    settings.privateRelay and "Measure through the relay" or "Measure directly", ICON_SETTINGS,
    { act = "set", key = "privateRelay", pane = "help", help = "relay" }, true)
  rows[#rows + 1] = row("Keep per network", settings.cap .. " runs", ICON_SETTINGS,
    { act = "set", key = "cap", pane = "help", help = "cap" }, true)

  local named = cfg.store.nameOf(target.id)
  rows[#rows + 1] = row("Name this network",
    named or (target.named and target.label or (target.label .. ", not its real name")),
    ICON_NAME, { act = "name", pane = "help", help = "name" }, true)

  rows[#rows + 1] = row("Clear this network's history",
    #cfg.store.forNetwork(target.id) .. " runs kept", ICON_CLEAR,
    { act = "clearOne", pane = "help", help = "clearOne" }, true)
  rows[#rows + 1] = row("Clear every network's history",
    #cfg.store.networks() .. " networks kept", ICON_CLEAR,
    { act = "clearAll", pane = "help", help = "clearAll" }, true)

  return rows
end

-- A step through one option's ring, written back and answered in place. Every one of these
-- mutates the list it is standing on, so every one of them answers stay and the highlight
-- never leaves the row the person is flipping.
local function stepSetting(key)
  local settings = cfg.store.settings()
  if key == "direction" then
    cfg.store.setSetting(key, nextIn(DIRECTIONS, settings.direction))
  elseif key == "sequential" then
    cfg.store.setSetting(key, not settings.sequential)
  elseif key == "maxSeconds" then
    cfg.store.setSetting(key, nextIn(RUNTIMES, settings.maxSeconds))
  elseif key == "protocol" then
    cfg.store.setSetting(key, nextIn(PROTOCOLS, settings.protocol))
  elseif key == "privateRelay" then
    cfg.store.setSetting(key, not settings.privateRelay)
  elseif key == "cap" then
    cfg.store.setSetting(key, nextIn(CAPS, settings.cap))
  end
end

-- The confirmation leads with the harmless answer, so a stray Return on this screen is never
-- the destructive one. The same rule the processes stop and the display profiles delete both
-- already keep.
function confirmClearChild(scope, netId, label)
  local child
  child = {
    placeholder = scope == "all" and "Clear every network" or ("Clear " .. label),
    rows = function()
      return {
        row("Keep them", "leave this history alone", ICON_KEEP,
          { act = "back", pane = "help", help = scope == "all" and "clearAll" or "clearOne" }, true),
        row(scope == "all" and "Clear every network" or ("Clear " .. label),
          "there is no undo", ICON_CLEAR,
          { act = "clearConfirmed", scope = scope, netId = netId, pane = "help",
            help = scope == "all" and "clearAll" or "clearOne" }, true),
      }
    end,
    onSelect = function() return nil end,
    intercept = function(item)
      if item.act == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      if item.act == "clearConfirmed" then
        cfg.store.clear(item.scope == "all" and nil or item.netId)
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      return false
    end,
  }
  return child
end

-- The one page here that reads what is typed. The widget must not filter it, since the row
-- IS the query, so this level declares matcher false and every row it builds ignores the
-- text except the one that is made out of it.
function namingChild()
  local target = currentNet()
  local child
  child = {
    placeholder = "Type a name for this network",
    matcher = false,
    rows = function(query)
      local rows = { backRow() }
      local typed = query and query:match("^%s*(.-)%s*$") or ""
      if typed ~= "" then
        rows[#rows + 1] = row("Call it " .. typed,
          "every run already kept here keeps its place", ICON_NAME,
          { act = "nameSet", name = typed, pane = "help", help = "name" }, true)
      else
        rows[#rows + 1] = row("Currently " .. labelFor(target.id, target.label),
          target.named and "this is the network's real name"
            or "macOS is not telling this Mac the real name", ICON_NAME,
          { act = "none", pane = "help", help = "name" }, false)
      end
      if cfg.store.nameOf(target.id) then
        rows[#rows + 1] = row("Remove the name", "go back to whatever macOS answers",
          ICON_CLEAR, { act = "nameClear", pane = "help", help = "name" }, true)
      end
      return rows
    end,
    onSelect = function() return nil end,
    intercept = function(item)
      if item.act == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      if item.act == "nameSet" then
        cfg.store.setName(target.id, item.name)
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      if item.act == "nameClear" then
        cfg.store.setName(target.id, nil)
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      return false
    end,
  }
  return child
end

function settingsChild()
  local child
  child = {
    placeholder = "Speedtest settings",
    rows = settingsRows,
    onSelect = function(item)
      if item.act == "name" then return namingChild() end
      if item.act == "clearOne" then
        local target = currentNet()
        return confirmClearChild("one", target.id, labelFor(target.id, target.label))
      end
      if item.act == "clearAll" then return confirmClearChild("all") end
      return nil
    end,
    intercept = function(item)
      if item.act == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      if item.act == "set" then
        stepSetting(item.key)
        return "stay"
      end
      return false
    end,
  }
  return child
end

--------------------------------------------------------------------------------
-- Other networks
--------------------------------------------------------------------------------

function networkRunsChild(netId, label)
  local child
  child = {
    placeholder = label,
    rows = function()
      local rows = { backRow() }
      local runs = cfg.store.forNetwork(netId)
      for _, record in ipairs(runs) do rows[#rows + 1] = resultRow(record) end
      if #runs == 0 then
        rows[#rows + 1] = row("Nothing kept for " .. label, nil, ICON_EMPTY,
          { act = "none", pane = "none" }, false)
      end
      return rows
    end,
    onSelect = function(item)
      if item.act == "result" then
        local record = cfg.store.byId(item.rid)
        if record then hs.pasteboard.setContents(summaryLine(record)) end
      end
      return nil
    end,
    intercept = function(item)
      if item.act == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      return false
    end,
  }
  return child
end

function networksChild()
  local child
  child = {
    placeholder = "Networks measured from this Mac",
    rows = function()
      local rows = { backRow() }
      local here = currentNet().id
      for _, entry in ipairs(cfg.store.networks()) do
        local label = labelFor(entry.id, entry.label)
        local sub = entry.count .. (entry.count == 1 and " run, " or " runs, ")
          .. util.relative(entry.latest)
        if entry.id == here then sub = sub .. ", connected now" end
        rows[#rows + 1] = row(label, sub, ICON_NETWORKS,
          { act = "network", netId = entry.id, pane = "trend" }, true)
      end
      return rows
    end,
    onSelect = function(item)
      if item.act == "network" then
        return networkRunsChild(item.netId, labelFor(item.netId, item.netId))
      end
      return nil
    end,
    intercept = function(item)
      if item.act == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      return false
    end,
  }
  return child
end

--------------------------------------------------------------------------------
-- The top level
--------------------------------------------------------------------------------

--- chooser.rows(query) - the top level list. The widget filters, so the query is not read
--- here, which is also what lets the launcher scope show exactly these rows.
function M.rows()
  local rows = {}
  local target = currentNet()
  local settings = cfg.store.settings()
  local label = labelFor(target.id, target.label)

  if not cfg.runner.isAvailable() then
    rows[#rows + 1] = row("networkQuality is not on this Mac",
      "the tool this measures with ships with macOS", ICON_PROBLEM,
      { act = "none", pane = "help", help = "missing" }, false)
  elseif cfg.runner.isRunning() then
    rows[#rows + 1] = row("Stop", runningSubtitle(), ICON_STOP,
      { act = "stop", pane = "running" }, true)
  else
    rows[#rows + 1] = row("Run test", describeRun(settings) .. ", on " .. label, ICON_RUN,
      { act = "run", pane = "trend" }, true)
  end

  if lastReason then
    rows[#rows + 1] = row("The last run did not finish", lastReason, ICON_PROBLEM,
      { act = "none", pane = "none" }, false)
  end

  local history = cfg.store.forNetwork(target.id)
  for _, record in ipairs(history) do rows[#rows + 1] = resultRow(record) end
  if #history == 0 and cfg.runner.isAvailable() then
    rows[#rows + 1] = row("No runs on " .. label .. " yet",
      "one reading says little, the second one is where this starts to be useful",
      ICON_EMPTY, { act = "none", pane = "trend" }, false)
  end

  rows[#rows + 1] = row("Settings", describeRun(settings), ICON_SETTINGS,
    { act = "settings", pane = "help", help = "settings" }, true)

  local networks = cfg.store.networks()
  if #networks > 1 then
    rows[#rows + 1] = row("Other networks", (#networks - 1) .. " more with runs kept",
      ICON_NETWORKS, { act = "networks", pane = "help", help = "networks" }, true)
  end

  return rows
end

--- chooser.select(item) - what a completed row does. A child returned from here is pushed by
--- the stage in place, so a level is a returned table rather than anything wired by hand.
function M.select(item)
  if not item then return nil end
  if item.act == "settings" then return settingsChild() end
  if item.act == "networks" then return networksChild() end
  if item.act == "result" then
    local record = cfg.store.byId(item.rid)
    if record then hs.pasteboard.setContents(summaryLine(record)) end
    return nil
  end
  return nil
end

--- chooser.intercept(item) - asked before a row completes. Both rows here mutate the list
--- they stand on rather than going anywhere, so both answer stay and the list stays open with
--- the highlight where the person left it.
function M.intercept(item)
  if not item then return false end
  if item.act == "run" then
    startRun()
    return "stay"
  end
  if item.act == "stop" then
    cfg.runner.stop()
    stopTicker()
    redraw()
    return "stay"
  end
  return false
end

--------------------------------------------------------------------------------
-- The pane, following the highlight
--------------------------------------------------------------------------------

-- Why the trend pane is headed by a made up label, shown only when it actually is, so a Mac that
-- has been granted the permission, or a network a person has already named, never sees it.
--
-- It says what happened, that nothing is broken by it, and what to do, in that order, because the
-- first version said only that the name was hidden and left every one of those three unanswered.
local function nameNote(target)
  if target.named then return nil end
  if cfg.store.nameOf(target.id) then return nil end
  return "This is a made up label. macOS treats a Wi Fi name as a location and only tells an app "
    .. "that holds Location Services, which Hammerspoon has never been granted. Readings are filed "
    .. "against the network itself rather than its name, so nothing is mixed up by it. Name it "
    .. "under Settings, or grant the permission and real names appear on their own."
end

local function describe(item)
  if not item then
    pane.clear()
    return
  end
  local face = item.pane
  if face == "result" then
    local record = cfg.store.byId(item.rid)
    if record then
      pane.showResult(record, labelFor(record.net, record.label), cfg.store.forNetwork(record.net))
    else
      pane.clear()
    end
  elseif face == "trend" then
    local netId = item.netId or currentNet().id
    local target = (netId == currentNet().id) and currentNet() or nil
    local label = labelFor(netId, target and target.label or netId)
    pane.showTrend(cfg.store.forNetwork(netId), label, target and nameNote(target) or nil)
  elseif face == "running" then
    pane.refreshRunning(runningState())
  elseif face == "help" then
    local block = HELP[item.help]
    if block then
      pane.showText(block.title, block.lines)
    else
      pane.clear()
    end
  else
    pane.clear()
  end
end

--- chooser.onHighlight(item) - the pane follows the highlight and nothing else.
function M.onHighlight(item)
  describe(item)
end

local function renderHighlighted()
  describe(cfg.stageSelectedItem and cfg.stageSelectedItem())
end

--- chooser.onPositioned(chooserFrame, companionFrame) - dock the pane where the stage put it.
--- Told both frames as nil once when a different presentation becomes current, which is the
--- signal to erase, never onClose, since that nil pair is a swap rather than a close.
function M.onPositioned(_, companionFrame)
  if companionFrame then
    pane.dock(companionFrame)
    -- The atom seeds the highlight before it positions anything, so the first onHighlight
    -- lands with nowhere to draw. This is what fills the pane on open.
    renderHighlighted()
  else
    pane.hide()
  end
end

--- chooser.onPresent() - reread which network this is, since the answer changes when a person
--- moves, and an open is the only moment worth asking.
function M.onPresent()
  net = util.currentNetwork()
end

--- chooser.onClose() - the stage hid entirely. The pane goes with it and the network is
--- forgotten so the next open asks again. The run is deliberately left alone.
function M.onClose()
  net = nil
  pane.destroy()
end

--- chooser.placeholder() - names the list, never a key.
function M.placeholder()
  return "Measure this connection"
end

--- chooser.paneWidth() - resolved once at register, by which point configure has already run,
--- so this answers the real reservation. A root that injected no surface gets the list with no
--- companion rect rather than a rect nothing can draw in.
function M.paneWidth()
  return pane.isEnabled() and true or 0
end

--- chooser.show() - the fallback door registry.open keeps, for a path that has no presentation
--- to push. Everything ordinary reaches this list through the stage instead.
function M.show()
  if cfg.stagePresent then cfg.stagePresent("speedtest") end
end

--- chooser.onScroll(points) - a trackpad scroll over the docked pane.
--- The atom watches for it over the companion rect and normalises a wheel notch against a
--- trackpad's pixels before calling this, so a pane never has an opinion about direction. A canvas
--- cannot report a scroll of its own, which is why this arrives from the atom rather than from the
--- pane noticing anything.
function M.onScroll(points)
  pane.scrollBy(points)
end

--------------------------------------------------------------------------------
-- The launcher scope
--------------------------------------------------------------------------------

--- chooser.scopeRows(query) - the rows a typed alias shows inside the launcher's own list.
---
--- Deliberately not the whole tool. The launcher's list reserves no companion pane and nothing can
--- be pushed onto it, so neither the detail pane nor the settings level can exist here, and
--- pretending otherwise is what made choosing a row from the alias close the list rather than show
--- anything. What a typed word is genuinely good for is the two things worth reaching in one
--- gesture, taking a reading and seeing what this network has done before. Everything else is one
--- row away through the door at the top.
function M.scopeRows()
  local target = currentNet()
  local settings = cfg.store.settings()
  local label = labelFor(target.id, target.label)
  local rows = {}

  rows[#rows + 1] = row("Open Speedtest", "the full tool, with the detail pane", ICON_NETWORKS,
    { act = "open" }, true)

  if not cfg.runner.isAvailable() then
    rows[#rows + 1] = row("networkQuality is not on this Mac",
      "the tool this measures with ships with macOS", ICON_PROBLEM, { act = "none" }, false)
  elseif cfg.runner.isRunning() then
    rows[#rows + 1] = row("Stop", runningSubtitle(), ICON_STOP, { act = "stop" }, true)
  else
    rows[#rows + 1] = row("Run test", describeRun(settings) .. ", on " .. label, ICON_RUN,
      { act = "run" }, true)
  end

  for _, record in ipairs(cfg.store.forNetwork(target.id)) do
    rows[#rows + 1] = resultRow(record)
  end

  return rows
end

--- chooser.scopeAct(item) - what a scope row does, in place, with the launcher's list still open.
---
--- One function for every row rather than a run and an act that could disagree, since a scope
--- declaring act has every one of its rows routed through it and run is never reached.
---
--- Starting a run from here opens the tool as well, which is not a shortcut for its own sake. A
--- scope row cannot ask the launcher to redraw it, so a run started and left in the launcher would
--- count up in a row nothing ever repaints, and the live graph is the whole point of watching one.
function M.scopeAct(item)
  if not item then return end
  if item.act == "open" then
    if cfg.stagePresent then cfg.stagePresent("speedtest") end
    return
  end
  if item.act == "run" then
    startRun()
    if cfg.stagePresent then cfg.stagePresent("speedtest") end
    return
  end
  if item.act == "stop" then
    cfg.runner.stop()
    stopTicker()
    return
  end
  if item.act == "result" then
    local record = cfg.store.byId(item.rid)
    if record then hs.pasteboard.setContents(summaryLine(record)) end
    return
  end
end

--- chooser.configure(opts) - injected by this plugin's own composition root, which is the only
--- file that names the runner, the store, and the pane.
function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  pane.configure({
    surface = cfg.surface,
    emptyState = cfg.emptyState,
    -- The atom's own light and dark resolution, reproduced here rather than reached through
    -- an instance this file does not hold, so the pane follows the system appearance switch.
    palette = function()
      local theme = cfg.theme or {}
      local dark = hs.host.interfaceStyle() == "Dark"
      local resolved = (dark and theme.dark) or theme.light or theme.dark
      return resolved and resolved.preview
    end,
  })
  return M
end

return M
