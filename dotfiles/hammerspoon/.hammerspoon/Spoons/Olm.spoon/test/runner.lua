--- === Olm test runner ===
---
--- Runs every scenario against the LIVE configuration and writes the result to a file.
---
--- Three facts about Hammerspoon shape this whole file, and each was learned by watching this
--- fail rather than by reading anything.
---
--- One. Opening a chooser from inside an `hs -c` call kills the ipc port, so the caller gets
--- back nothing at all and the run looks like it hung. Every scenario that touches a surface
--- therefore runs on a TIMER, after the ipc call that started the run has already returned.
--- The shell that started it polls a file instead of waiting for an answer.
---
--- Two. A timer whose handle nobody holds is garbage collected before it fires. The first
--- version of this scheduled a chain of steps, held none of them, and produced no output and
--- no error, which is the least helpful failure there is. Every timer here is retained.
---
--- Three. A scenario that raises must not take the run with it. Each one is wrapped, and a
--- raise becomes that scenario's failure message, because a suite that dies on its third
--- check tells you less than one that finishes and names three failures.
---
--- The run is a QUEUE walked one step per tick rather than a loop. That is not stylistic. A
--- chooser needs real time on the main thread to appear before anything may ask whether it is
--- showing, and a loop would ask before the window existed and score every picker as broken.

local obj = {}

local spoonDir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") .. "../"

local function load(relativePath)
  local chunk, err = loadfile(spoonDir .. relativePath)
  if not chunk then error("Olm test, failed to load " .. relativePath .. ", " .. tostring(err)) end
  return chunk()
end

local specLib = load("test/spec.lua")

-- How long to wait after asking a surface to open before believing its answer. Generous on
-- purpose. A suite that is flaky under load teaches people to ignore it, which costs more
-- than the seconds it saves.
local SETTLE = 0.45

--------------------------------------------------------------------------------
-- The world a scenario is handed
--------------------------------------------------------------------------------

-- Everything a scenario may do, in one table, so a scenario never reaches into Hammerspoon or
-- into Olm's internals directly. That keeps a test readable as a sentence, and it means a
-- change in how a surface is opened is one edit here rather than one per scenario.
local function buildWorld(olm)
  local registry = olm.registry
  local composed = olm._composed or {}
  local plan = composed.plan or {}

  local world = {
    olm = olm,
    registry = registry,
    plan = plan,
    manifests = composed.manifests or {},
    stamp = tostring(hs.timer.secondsSinceEpoch()):gsub("%.", ""),
  }

  function world.module(name) return olm:module(name) end

  function world.settle() hs.timer.usleep(math.floor(SETTLE * 1000000)) end

  -- The generic door. Every registered tool opens through its own registration and closes
  -- through the navigation adapter it already exposes, so this file names no plugin and needs
  -- no per tool knowledge of what a picker is called or how it is dismissed.
  function world.open(identity)
    local ok, err = pcall(registry.run, identity)
    if not ok then return false, tostring(err) end
    return true
  end

  local function adapterFor(identity)
    local entry = registry.get(identity)
    if not entry or type(entry.surface) ~= "function" then return nil end
    local ok, adapter = pcall(entry.surface)
    if not ok then return nil end
    return adapter
  end

  function world.showing(identity)
    local adapter = adapterFor(identity)
    if not adapter or type(adapter.isShowing) ~= "function" then return false end
    local ok, answer = pcall(adapter.isShowing)
    return ok and answer == true
  end

  function world.close(identity)
    local adapter = adapterFor(identity)
    if adapter and type(adapter.hide) == "function" then pcall(adapter.hide) end
  end

  function world.rows(identity, query)
    local scope = registry.scopeFor(identity)
    if not scope or type(scope.rows) ~= "function" then return nil end
    local ok, answer = pcall(scope.rows, query or "")
    if not ok then return nil end
    return answer
  end

  -- Whether a tool a plugin declared is actually on this machine, asked the same way the
  -- composition root asks it, so the suite and the config cannot disagree about a tool.
  function world.present(tool)
    if tool.kind == "path" then
      return hs.execute("command -v " .. tostring(tool.name) .. " >/dev/null 2>&1 && echo y", true) == "y\n"
    elseif tool.kind == "system" or tool.kind == "manual" then
      return tool.locator ~= nil and hs.fs.attributes(tool.locator) ~= nil
    elseif tool.kind == "app" then
      local path = tool.locator and hs.application.pathForBundleID(tool.locator)
      return path ~= nil and path ~= ""
    end
    return true
  end

  function world.canDispatch(action)
    local dispatch = composed.dispatch or {}
    return dispatch[action] ~= nil
  end

  function world.hasPredicate(name)
    local predicates = composed.predicates or {}
    return predicates[name] ~= nil
  end

  function world.suppliedData(plugin, field)
    local data = composed.data or {}
    return (data[plugin] or {})[field]
  end

  function world.pasteboard(text)
    hs.pasteboard.setContents(text)
  end

  -- A leader chord, posted rather than typed, which is the only way to prove the INPUT path
  -- rather than the action behind it. Held for a beat before the key, because the leader
  -- engines distinguish a hold from a tap by time and a chord posted all at once reads as a tap.
  function world.chord(leaderFkey, key, mods)
    local code = hs.keycodes.map[leaderFkey]
    if not code then return false, "no keycode for " .. tostring(leaderFkey) end
    hs.eventtap.event.newKeyEvent({}, code, true):post()
    hs.timer.usleep(350000)
    hs.eventtap.event.newKeyEvent(mods or {}, key, true):post()
    hs.timer.usleep(40000)
    hs.eventtap.event.newKeyEvent(mods or {}, key, false):post()
    hs.timer.usleep(120000)
    hs.eventtap.event.newKeyEvent({}, code, false):post()
    return true
  end

  return world
end

--------------------------------------------------------------------------------
-- Running
--------------------------------------------------------------------------------

local function judge(scenario, world)
  if scenario.manual then
    return "manual", scenario.manual == true and "needs a person to look" or tostring(scenario.manual)
  end

  if type(scenario.given) == "function" then
    local ok, err = pcall(scenario.given, world)
    if not ok then return "fail", "its Given raised, " .. tostring(err) end
  end

  if type(scenario.when) == "function" then
    local ok, err = pcall(scenario.when, world)
    if not ok then return "fail", "its When raised, " .. tostring(err) end
    world.settle()
  end

  if type(scenario.expect) ~= "function" then
    return "fail", "the scenario claims something and then checks nothing"
  end

  local ok, answer, why = pcall(scenario.expect, world)
  if not ok then return "fail", "it raised, " .. tostring(answer) end
  if answer == true then return "pass", nil end
  return "fail", why or "it did not hold, and said nothing about what it saw instead"
end

--- obj.run(olm, opts)
--- Schedules the whole suite and returns at once. opts.out is where the report is written,
--- opts.tiers is an optional set limiting which tiers run, and opts.onDone is called with the
--- summary when everything has finished.
function obj.run(olm, opts)
  opts = opts or {}
  local outPath = opts.out or (os.getenv("HOME") .. "/olm-test-report.txt")
  local wanted = opts.tiers

  local world = buildWorld(olm)

  -- Derived first, then whatever is written beside a plugin, so a report reads structure
  -- before behaviour and a broken foundation is visible before its consequences are.
  local queue = {}
  for _, scenario in ipairs(specLib.derive(world)) do
    queue[#queue + 1] = { feature = "Olm, derived from what each plugin declares", scenario = scenario }
  end

  local features = specLib.discover({ spoonDir .. "plugins", spoonDir .. "host" })
  for _, feature in ipairs(features) do
    if feature.broken then
      queue[#queue + 1] = {
        feature = feature.feature,
        scenario = { scenario = "its own test file loads", tier = "structure",
                     expect = function() return false, feature.broken end },
      }
    end
    for _, scenario in ipairs(feature.scenarios) do
      queue[#queue + 1] = { feature = feature.feature, scenario = scenario }
    end
  end

  local results, index = {}, 0
  local counts = { pass = 0, fail = 0, manual = 0, skipped = 0 }
  local timers = {}
  obj._timers = timers -- retained, see the note at the top

  local function report()
    local lines = {}
    local function say(s) lines[#lines + 1] = s end

    say("Olm test report")
    say(("%d passed, %d failed, %d need a person, %d skipped")
      :format(counts.pass, counts.fail, counts.manual, counts.skipped))
    say("")

    local currentFeature = nil
    for _, r in ipairs(results) do
      if r.feature ~= currentFeature then
        currentFeature = r.feature
        say("")
        say("Feature, " .. currentFeature)
      end
      local mark = ({ pass = "  ok  ", fail = " FAIL ", manual = " look ", skipped = " skip " })[r.verdict]
      say(mark .. r.scenario)
      if r.why then say("         " .. r.why) end
    end

    if counts.manual > 0 then
      say("")
      say("What only you can judge")
      for _, r in ipairs(results) do
        if r.verdict == "manual" then say("  [ ] " .. r.scenario .. ", " .. (r.why or "")) end
      end
    end

    say("")
    local file = io.open(outPath, "w")
    file:write(table.concat(lines, "\n") .. "\n")
    file:close()
    if opts.onDone then pcall(opts.onDone, counts) end
  end

  local function step()
    index = index + 1
    local item = queue[index]
    if not item then return report() end

    local scenario = item.scenario
    local verdict, why

    if wanted and not wanted[scenario.tier or "behaviour"] then
      verdict, why = "skipped", "not in the tiers this run asked for"
    else
      verdict, why = judge(scenario, world)
    end

    counts[verdict] = counts[verdict] + 1
    results[#results + 1] = {
      feature = item.feature, scenario = scenario.scenario, verdict = verdict, why = why,
    }

    -- A surface scenario left something open if it failed halfway, so the next one starts from
    -- a clean screen rather than inheriting a chooser nobody closed.
    if scenario.tier == "surface" and verdict == "fail" then
      for _, entry in ipairs(world.registry.all()) do
        if world.showing(entry.name) then world.close(entry.name) end
      end
    end

    timers[#timers + 1] = hs.timer.doAfter(scenario.tier == "surface" and 0.15 or 0.01, step)
  end

  timers[#timers + 1] = hs.timer.doAfter(0.2, step)
  return #queue
end

return obj
