-- The minimal hs stub the dry gate loads a plugin module under, so check two, does a
-- declared member path resolve to a real function, can ask the question against the
-- actual module table Lua built rather than against a guess.
--
-- Nothing in test/ before this file has ever needed to stub hs, because runner.lua and
-- suite.sh both run against a LIVE Hammerspoon over its own ipc port, hs -c, and take the
-- test lock to do it. That is a different tool for a different moment, proving a plugin
-- behaves once it is actually running. This file exists because a builder agent cannot
-- start one at all, so this stub is not a copy of anything already in test/, it is new,
-- and it is deliberately permissive rather than a faithful model of Hammerspoon.
--
-- THE SHAPE. Every hs.anything, called or indexed, however deep, answers another one of
-- these same stub objects, which is itself truthy, indexable, and callable. A plugin's own
-- top level code, `local log = hs.logger.new(...)`, `hs.fs.attributes(...)`, whatever a
-- module happens to reach for while it is merely being LOADED rather than configured, gets
-- back something it can keep indexing and calling without raising. This is deliberately
-- permissive rather than a faithful model of any one hs module, because faithfulness would
-- mean maintaining twenty stubs that drift from the real API the moment Hammerspoon's own
-- surface changes, and this gate's whole job is to be cheap enough that nobody minds
-- running it constantly.
--
-- THE COST OF THAT PERMISSIVENESS, named rather than hidden. A stub answer is always
-- truthy, so `if hs.something() then ...` always takes the true branch, which the real
-- Hammerspoon would not promise. A module whose own top level code branches on a live hs
-- answer to decide which functions it defines can come out of this load with a different
-- shape than a real reload would give it. This is the reason a member path that fails to
-- resolve is a FINDING and a module that would not load, or would not configure, at all is
-- UNKNOWN rather than either PASS or FAIL for that module. An honest unknown beats a false
-- green.
--
-- WHY CONFIGURE TOO, NOT ONLY LOAD. A real tool commonly assembles the very members check
-- two goes looking for, self.rows, self.select, self.open, INSIDE its own configure, exactly
-- the discipline lib/registrar.lua's own comments describe at length and MenuSearch is the
-- concrete case, `self.open`, `self.rows`, and `self.select` all live on
-- plugins/menusearch/init.lua's own configure and nowhere else. A module checked only after
-- dofile, before configure has ever run, reports every one of those as unresolved, which is
-- not a finding, it is this gate asking the wrong question. So M.configureModule attempts
-- configure too, with a generous, entirely inert opts table, generous because getting past a
-- plugin's own early guard on a required field matters more here than the field's real
-- shape, and inert because every value in it, ambient or lib sourced, is either real plugin
-- data read straight off the manifest or another one of these same harmless stub answers, so
-- nothing a configure call does under it, bind a hotkey, start a timer, touches anything
-- real. A configure that still raises, most often a required capability this gate has no way
-- to assemble, a sibling plugin's own module or a piece of the person's own configuration,
-- degrades the whole plugin to unknown rather than reporting its unconfigured shape as a
-- false finding.
--
-- THE INSTRUCTION BUDGET. A `while hs.something() do ... end` written to run until a real
-- Hammerspoon answer eventually turns falsy never terminates against a stub that is always
-- truthy, and did, once, while this file was being built, plugins/processes/init.lua's own
-- load chain hung the shell it ran in. M.budgeted below counts VM instructions during ONE
-- attempt and raises once a generous budget is spent, which its own caller's pcall turns
-- into an ordinary failure, reported the same honest UNKNOWN as any other attempt this stub
-- cannot carry. The count resets before every attempt, so one plugin's own legitimate cost
-- can never be blamed on the budget a much heavier one ahead of it already spent.
local M = {}

local function autostub()
  local self
  self = setmetatable({}, {
    __index = function(_, _key) return autostub() end,
    __call = function(_, ...) return autostub() end,
    __tostring = function() return "<olm dry gate hs stub>" end,
  })
  return self
end

--- M.autostub()
--- One fresh permissive stand in, indexable and callable, always truthy, never the same
--- table twice. Exposed so a caller can build a plausible looking opts value, a chooser
--- factory or a theme table a plugin's own configure only ever stores or hands onward,
--- without this file needing to know that shape either.
M.autostub = autostub

--- M.install(spoonDir)
--- Installs the permissive hs and spoon globals. spoonDir is handed in so hs.configdir
--- reads the real path a plugin's own code might reasonably expect, rather than an empty
--- string. Call once per process, before the first module load.
function M.install(spoonDir)
  hs = autostub()
  hs.configdir = spoonDir
  -- lib/loader.lua's own obj.mirror writes onto a global `spoon` table when a caller asks
  -- for it, and nothing under plugins or host should read `spoon` directly by the plugin
  -- contract, but a stray reference degrading to another harmless stub is cheaper than a
  -- raise over a global this gate never otherwise needed to model.
  spoon = autostub()

  -- One targeted override, found while this file was being built. hs.fs.attributes is the
  -- ordinary Hammerspoon idiom for asking whether a path exists at all, answering nil for
  -- one that does not, and a stub table is never nil, so `hs.fs.attributes(path,
  -- "modification")` compared or arithmetic'd the way a real timestamp check does raises
  -- instead of taking the "not there yet" branch every caller already writes for it, the
  -- concrete failure plugins/eyedropper/init.lua's own binaryFresh hit. A dry gate machine
  -- genuinely has none of a plugin's own cache files, so nil is not only safe, it is the
  -- honest answer. Assigned directly onto a stable table, rather than left to the generic
  -- __index below, which manufactures a brand new answer on every single access and could
  -- never hold an override at all.
  local fsStub = autostub()
  fsStub.attributes = function() return nil end
  hs.fs = fsStub
end

-- Chosen empirically against this tree's own plugins, not derived from anything. Loading or
-- configuring any one real plugin here today costs at most a few thousand VM instructions;
-- the one module that hit an unterminated loop under the stub burned through this budget in
-- well under a second. Generous enough that a legitimately heavier attempt still finishes,
-- small enough that a hung one fails fast rather than stalling a whole gate run.
local BUDGET = 20000

--- M.budgeted(fn, ...)
--- Runs fn under the instruction budget, resetting the count first so one attempt's cost is
--- never blamed on another's. Answers fn's own pcall, ok and then either fn's results or the
--- error, exactly as a bare pcall would, so callers already know this shape.
function M.budgeted(fn, ...)
  local count = 0
  debug.sethook(function()
    count = count + 1
    if count > BUDGET then
      error("this did not finish under the stub's instruction budget, most likely a loop "
        .. "waiting on a live hs answer that never turns falsy here")
    end
  end, "", 1000)

  local results = { pcall(fn, ...) }

  debug.sethook()

  return table.unpack(results)
end

--- M.loadModule(path)
--- Loads one plugin's init.lua the identical way lib/loader.lua's own obj.modules does,
--- dofile then, when the result is a table with an init method, one colon called init, both
--- inside the same instruction budget. Answers the loaded module table on success, or nil
--- plus a reason string, which the gate reports as unknown rather than as a pass or a fail.
function M.loadModule(path)
  local ok, mod = M.budgeted(dofile, path)
  if ok and type(mod) == "table" and type(mod.init) == "function" then
    -- init is called for its side effect, wiring the module's own internal state the way
    -- lib/loader.lua's own obj.modules already does, and the module table itself, mutated
    -- in place, is what this hands back, never init's own return value, which is
    -- conventionally nothing or self and never a replacement worth trusting over the
    -- original.
    local okInit, errInit = M.budgeted(mod.init, mod)
    if not okInit then
      ok, mod = false, errInit
    end
  end

  if not ok then
    return nil, tostring(mod)
  end
  if type(mod) ~= "table" then
    return nil, "init.lua returned a " .. type(mod) .. " rather than a table"
  end
  return mod
end

--- M.configureModule(mod, opts)
--- Attempts mod:configure(opts) under the same budget, when mod declares a configure at
--- all. A module with no configure is already whole as loaded, register.lua's own comment
--- on `hasWiringSteps` names the one shape that is true for, a plugin whose entire lifecycle
--- runs through declared wiring steps instead, and answers true doing nothing. Answers true
--- on success, or false plus a reason on a raise, which the caller degrades to unknown for
--- this module rather than trusting its unconfigured shape.
function M.configureModule(mod, opts)
  if type(mod.configure) ~= "function" then return true end
  local ok, err = M.budgeted(mod.configure, mod, opts)
  if not ok then return false, tostring(err) end
  return true
end

return M
