-- Convert, the behaviour no declaration implies.
--
-- This plugin is here as the first hand written spec for a reason worth recording. It was
-- silently dead for as long as the composition root existed, because the root probed for its
-- required tool without a login shell, so qalc read as absent on a machine where it is
-- installed and the whole plugin was refused before it ever loaded. Nothing said so anywhere.
--
-- The derived checks would have caught it, since a required tool that is missing is now stated
-- rather than left to be inferred from a plugin's absence. The scenario below is the second
-- half of that lesson, which is that a tool being present is not the same as it answering.

-- One ask, run again and again until an answer with a number in it lands. Written once and
-- used by every polling step below rather than copied per step, since the reason there are
-- several steps has nothing to do with them differing.
--
-- Why one ask per STEP rather than a loop inside one step. The answer comes back from a
-- process, and its completion callback is delivered on the MAIN THREAD, so a loop that waited
-- between asks would be blocking the very thread the answer needs in order to arrive. Only the
-- runner may wait, between steps, where a real timer lets the run loop turn. That mistake has
-- been made twice in this suite and is written down at test/world.lua as well as here.
local function ask(w)
  local c = w._convert
  if not c or w._rows then return end
  local ok, rows = pcall(function() return c:rows("10km to miles") end)
  if not ok or type(rows) ~= "table" or not rows[1] then return end
  local text = tostring(rows[1].text or rows[1].title or "")
  -- The placeholder row says Converting and carries no digit, so a row with a number in it is
  -- the answer having actually landed rather than merely the row having appeared.
  if text:find("%d") then w._rows = rows end
end

-- The first step names the plugin and clears anything a previous run left. Every step after it
-- is one ask. Four seconds of polling is far longer than the quarter second debounce plus the
-- two processes a mixed unit answer costs, and being generous here is cheap while a flaky
-- suite is not.
local steps = { { fn = function(w) w._convert = w.role("convert") w._rows = nil end, wait = 0.1 } }
for _ = 1, 8 do steps[#steps + 1] = { fn = ask, wait = 0.5 } end

return {
  feature = "Convert",

  scenarios = {
    {
      scenario = "a unit conversion typed into the launcher computes",
      -- The query form is the tool's own grammar and not a guess. "10 km in miles" answers
      -- nothing while "10km to miles" answers a row, which a first version of this got wrong
      -- and reported as a broken plugin on a configuration where it works.
      steps = steps,
      expect = function(w)
        local c = w._convert
        if not c then
          return false, "the convert plugin is not loaded, so its tool is missing or it was blocked"
        end
        if type(c.rows) ~= "function" then
          return false, "it exposes no rows, so the launcher can never reach it"
        end
        -- Separated from the silence below on purpose. A plugin with no path was never given
        -- its tool by the root, which is a wiring answer, while a plugin with a path that
        -- stays quiet is the tool itself not coming back, which is a different repair.
        if not c._path then
          return false, "it holds no path to its tool, so the root resolved qalc to nothing "
            .. "and every ask returns an empty list before anything runs"
        end
        if not w._rows then
          return false, "it never answered with a number, it stayed on its Converting row, "
            .. "so the process behind it either never ran or never came back"
        end
        return true
      end,
    },

    {
      scenario = "a currency conversion reaches the network and answers late",
      manual = "type 100 usd in eur into the launcher and watch the row fill in a moment later",
    },
  },
}
