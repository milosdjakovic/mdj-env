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
local worldLib = load("test/world.lua")
local behaviours = load("test/behaviours.lua")

-- How long to wait after asking a surface to open before believing its answer. Generous on
-- purpose. A suite that is flaky under load teaches people to ignore it, which costs more
-- than the seconds it saves.
local SETTLE = 0.45

--------------------------------------------------------------------------------
-- The world a scenario is handed
--------------------------------------------------------------------------------

-- The world moved into test/world.lua once it had to serve two configurations. What stays here
-- is only the extra reading the DERIVED checks need, which exists on the restructured config
-- alone, so a run against the retired root simply derives nothing and tests behaviour instead.
local function buildWorld(olm)
  local w = worldLib.new()
  local composed = (olm and olm._composed) or {}
  w.olm = olm
  w.plan = composed.plan
  w.manifests = composed.manifests or {}
  w.close = function(name)
    local entry = w.registry and w.registry.get(name)
    if not entry or type(entry.surface) ~= "function" then return end
    local ok, adapter = pcall(entry.surface)
    if ok and adapter and adapter.hide then pcall(adapter.hide) end
  end
  function w.module(name) return w.role(name) end
  function w.present(tool)
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
  function w.canDispatch(action) return (composed.dispatch or {})[action] ~= nil end
  function w.hasPredicate(name) return (composed.predicates or {})[name] ~= nil end
  function w.suppliedData(plugin, field) return ((composed.data or {})[plugin] or {})[field] end
  function w.pasteboard(text) hs.pasteboard.setContents(text) end
  return w
end

--------------------------------------------------------------------------------
-- Running
--------------------------------------------------------------------------------

local function verdictOf(scenario, world)
  if type(scenario.expect) ~= "function" then
    return "fail", "the scenario claims something and then checks nothing"
  end
  local ok, answer, why = pcall(scenario.expect, world)
  if not ok then return "fail", "it raised, " .. tostring(answer) end
  if answer == true then return "pass", nil end
  return "fail", why or "it did not hold, and said nothing about what it saw instead"
end

-- Walks one scenario and hands its verdict to `done`. Asynchronous on purpose. An input
-- scenario posts key events, and those are delivered on the main thread, so the gap between
-- posting and looking has to be a real timer rather than a sleep. Sleeping guarantees the
-- events can never be processed, which is precisely what made an entire calibration run report
-- failures on a configuration whose keys work perfectly by hand.
local function judge(scenario, world, hold, done)
  if scenario.manual then
    return done("manual", scenario.manual == true and "needs a person to look" or tostring(scenario.manual))
  end

  if type(scenario.given) == "function" then
    local ok, err = pcall(scenario.given, world)
    if not ok then return done("fail", "its Given raised, " .. tostring(err)) end
  end

  local steps = scenario.steps
  if type(steps) ~= "table" or #steps == 0 then
    if type(scenario.when) == "function" then
      local ok, err = pcall(scenario.when, world)
      if not ok then return done("fail", "its When raised, " .. tostring(err)) end
      world.settle()
    end
    local v, why = verdictOf(scenario, world)
    return done(v, why)
  end

  local i = 0
  local function nextStep()
    i = i + 1
    local step = steps[i]
    if not step then
      local v, why = verdictOf(scenario, world)
      return done(v, why)
    end
    local ok, err = pcall(step.fn or step[1], world)
    if not ok then
      return done("fail", "step " .. i .. " raised, " .. tostring(err))
    end
    hold(hs.timer.doAfter(step.wait or step[2] or 0.4, nextStep))
  end
  nextStep()
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
  for _, scenario in ipairs(behaviours) do
    queue[#queue + 1] = { feature = "What this config promises a person", scenario = scenario }
  end
  if world.plan then
    for _, scenario in ipairs(specLib.derive(world)) do
      queue[#queue + 1] = { feature = "Derived from what each plugin declares", scenario = scenario }
    end
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

  local function hold(timer) timers[#timers + 1] = timer end

  local function step()
    index = index + 1
    local item = queue[index]
    if not item then return report() end

    local scenario = item.scenario
    local tier = scenario.tier or "behaviour"

    local function finish(verdict, why)
      counts[verdict] = counts[verdict] + 1
      results[#results + 1] = {
        feature = item.feature, scenario = scenario.scenario, verdict = verdict, why = why,
      }
      -- A failed scenario may have left a surface up or a leader down, so the screen and the
      -- keyboard are both put back before the next one starts from a state it did not choose.
      if verdict == "fail" then
        pcall(world.closeAll)
        for _, leader in ipairs({ "hyper", "meta", "super" }) do pcall(world.up, leader) end
      end
      local pause = (tier == "surface" or tier == "input") and 0.3 or 0.01
      hold(hs.timer.doAfter(pause, step))
    end

    if wanted and not wanted[tier] then
      return finish("skipped", "not in the tiers this run asked for")
    end
    judge(scenario, world, hold, finish)
  end

  timers[#timers + 1] = hs.timer.doAfter(0.2, step)
  return #queue
end

return obj
