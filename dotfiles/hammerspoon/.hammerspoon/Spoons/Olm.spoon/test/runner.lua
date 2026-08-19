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
  --- Close one surface, through the registry when it holds one and through the module itself
  --- when it does not. The fallback is not a nicety. The launcher is a host rather than a
  --- registered tool, so the registry path finds nothing for it, and a check that opened it and
  --- then asked whether closing worked was asking about something it had never closed.
  w.close = function(name)
    local entry = w.registry and w.registry.get(name)
    if entry and type(entry.surface) == "function" then
      local ok, adapter = pcall(entry.surface)
      if ok and adapter and adapter.hide then
        if pcall(adapter.hide) then return end
      end
    end
    w.hideThrough(w.role(name))
  end
  function w.module(name) return w.role(name) end
  --- Whether one declared tool is present, asked of the dependency door the config configured
  --- rather than probed here. This used to be a third copy of the same probe, which meant a
  --- scenario could pass while the running config had concluded the opposite, and checking what
  --- the config concluded is the only version of this question worth asking. A run against a
  --- root that records no door answers nil, so such a scenario reports needing a person instead
  --- of quietly passing on an answer nobody gave.
  function w.present(tool)
    local door = composed.tools
    if not door then return nil end
    if tool.kind == "package" then return true end
    return door.have(tool.name)
  end
  function w.canDispatch(action) return (composed.dispatch or {})[action] ~= nil end
  function w.hasPredicate(name) return (composed.predicates or {})[name] ~= nil end

  --- What a context gating predicate answers RIGHT NOW, or nil when there is no such
  --- predicate. The three answers are distinct on purpose. nil means nobody can answer the
  --- question, false means the answer is no, and only true means a chord gated on it will fire.
  --- Collapsing nil into false is what let five pickers pass every check while every key inside
  --- them was dead.
  --- Which of a list's own bound verbs its live surface can actually answer, asked of the very
  --- adapters lib/nav.lua consults and in the same order, so this is the real question rather
  --- than a paraphrase of it. Answers a list of the names that resolve to nothing, empty when
  --- every one of them resolves.
  ---
  --- Must be asked WHILE the list is open, because the surface is chosen by whichever one says
  --- it is showing, exactly as routing chooses it.
  function w.unanswered(actions)
    local surface = nil
    for _, s in ipairs(composed.surfaces or {}) do
      local ok, showing = pcall(function() return s.isShowing and s.isShowing() end)
      if ok and showing then surface = s break end
    end
    if not surface then return nil end
    -- Resolved exactly the way routing resolves it. An action may name a method spelled
    -- differently, closeChooser reaching hide being the real case, and an action may be
    -- answered by a root built closure rather than by any surface, which openActionPanel is. A
    -- check that knew neither reported all twelve lists broken when only three keys were.
    local methodFor = composed.navMethodFor or {}
    local exceptions = composed.navExceptions or {}
    local missing = {}
    for _, action in ipairs(actions or {}) do
      if not exceptions[action] then
        local method = methodFor[action] or action
        if type(surface[method]) ~= "function" then missing[#missing + 1] = action end
      end
    end
    return missing
  end

  --- Every action name one context binds, read off the plan rather than listed here, so a
  --- context that gains a key is checked for it without anybody remembering to add it.
  function w.boundActions(contextName)
    local block = ((w.plan or {}).contexts or {})[contextName]
    local names = {}
    for _, b in ipairs((block or {}).bindings or {}) do
      if b.action then names[#names + 1] = b.action end
    end
    return names
  end

  function w.hasContext(name)
    local fn = (composed.predicates or {})[name]
    if type(fn) ~= "function" then return nil end
    local ok, answer = pcall(fn)
    if not ok then return nil end
    return answer == true
  end
  function w.suppliedData(plugin, field) return ((composed.data or {})[plugin] or {})[field] end
  -- Every name anything was configured for, so a name that belongs to no plugin can be found.
  -- Answered as a fresh table rather than the record's own, since a caller iterating it while
  -- the suite adds scenarios keyed off it should not be able to touch what it is reading.
  function w.suppliedFor()
    local names = {}
    for name in pairs(composed.data or {}) do names[name] = true end
    return names
  end
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
  -- nil is not false. An Expect answering nil could not reach the question at all, which is a
  -- different thing from reaching it and finding the answer no, and reporting the two the same
  -- way makes an unanswerable check read as a defect that exists.
  -- And it has to SAY it could not reach the question. An Expect that simply falls off its own
  -- end also answers nil while saying nothing, and that is a defective check rather than an
  -- unanswerable one, so it keeps failing the way it always did.
  if answer == nil and why ~= nil then
    return "manual", why
  end
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
      -- A real timer, never a sleep. What a When usually does is ask something to happen, and
      -- whatever it asked for arrives on this thread, so blocking here would be waiting for a
      -- message this very wait is preventing from being delivered. See test/world.lua for the
      -- long version and for the three tools this cost.
      return hold(hs.timer.doAfter(SETTLE, function()
        local v, why = verdictOf(scenario, world)
        done(v, why)
      end))
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
    -- A polling step asks its own question over and over and moves on the moment the answer is
    -- yes. A fixed row of looks cannot serve both ends of this. It has to be long enough for the
    -- slowest tool, and then every quick one pays that length on every run, which is the trade
    -- the surface scenarios used to be stuck with.
    --
    -- The moment that breaks it is the first run after a relaunch, when no picker has been built
    -- yet and the first build of one is the slowest thing that will happen all session. A cold
    -- surface run reported thirteen failures in alphabetical order on 2026-08-18, every one
    -- saying the tool was asked to open and never showed, when the tools were fine and simply
    -- had not finished being built inside the window. Waiting only while the answer is still no
    -- gets both halves, a quick run once things are warm and patience when nothing is.
    if type(step.poll) == "function" then
      local every = step.every or 0.25
      local left = step.upTo or 3
      local function tick()
        local ok, answer = pcall(step.poll, world)
        if not ok then
          return done("fail", "step " .. i .. " raised, " .. tostring(answer))
        end
        -- Running out of budget carries on to the next step rather than deciding anything here,
        -- so a surface that really is dead still reaches its own expect and fails in that
        -- scenario's own words instead of stalling the queue or inventing a reason.
        if answer or left <= 0 then return nextStep() end
        left = left - every
        hold(hs.timer.doAfter(every, tick))
      end
      return tick()
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
      -- The screen and the keyboard are put back after EVERY scenario, not only after a failed
      -- one, which is what this used to do. A scenario that passes can still leave something
      -- up, and one that closes with a posted Escape can have that Escape land nowhere, so
      -- "it passed" was never the same as "it left nothing behind". What that cost was a
      -- launcher left open at the end of one run and still open at the start of the next,
      -- reported there as already open before the test began, and then a cascade of failures
      -- underneath it on a configuration where every one of them works.
      pcall(world.closeAll)
      for _, leader in ipairs({ "hyper", "meta", "super" }) do pcall(world.up, leader) end
      -- A longer beat after anything that took over the screen, because closing a picker also
      -- moves the keyboard focus, and the next tool to open may care which application is
      -- frontmost at the instant it is asked. Menu search is the real case, it captures the
      -- front application, walks its menus asynchronously, and abandons the open outright if
      -- focus moved while it was walking, which is right for a person and a race for a suite
      -- opening pickers back to back.
      local pause = (tier == "surface" or tier == "input") and 0.6 or 0.01
      hold(hs.timer.doAfter(pause, step))
    end

    if wanted and not wanted[tier] then
      return finish("skipped", "not in the tiers this run asked for")
    end

    -- A locked screen cannot be tested against and must never be reported as a broken config.
    -- Behind the lock screen the frontmost application is loginwindow, so a posted key reaches
    -- that and not the picker it was meant for, and a tool that captures the front application
    -- before it opens captures the wrong one. Both come back as a tool that would not appear,
    -- which is indistinguishable in a report from a tool that is genuinely dead.
    --
    -- This is not hypothetical. A long run locked the machine partway through and the two
    -- scenarios that happened to land after that reported a perfectly good launcher and menu
    -- search as broken, on the very suite written because structural checks had reported a
    -- broken config as fine. Answering "I could not see" is the only honest verdict here, and
    -- it is what skipped means.
    if tier == "surface" or tier == "input" then
      local session = hs.caffeinate.sessionProperties() or {}
      if session.CGSSessionScreenIsLocked == 1 or session.CGSSessionScreenIsLocked == true then
        return finish("skipped", "the screen was locked, so nothing could be seen or typed at")
      end
    end
    judge(scenario, world, hold, finish)
  end

  -- Nothing is judged until the screen and the keyboard are known to be clear. A previous run,
  -- or a person testing by hand a minute ago, can leave a picker up or a leader down, and the
  -- first scenario would then be measuring that rather than anything this run did. The gap
  -- after it is real time for whatever was closed to actually go away.
  timers[#timers + 1] = hs.timer.doAfter(0.1, function()
    pcall(world.closeAll)
    for _, leader in ipairs({ "hyper", "meta", "super" }) do pcall(world.up, leader) end
    timers[#timers + 1] = hs.timer.doAfter(0.8, step)
  end)
  return #queue
end

return obj
