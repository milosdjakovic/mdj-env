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

return {
  feature = "Convert",

  scenarios = {
    {
      scenario = "a unit conversion typed into the launcher computes",
      expect = function(w)
        local convert = w.module("convert")
        if not convert then
          return false, "the convert plugin is not loaded, so its tool is missing or it was blocked"
        end
        if type(convert.queryRows) ~= "function" then
          return false, "it exposes no queryRows, so the launcher can never reach it"
        end
        local ok, rows = pcall(convert.queryRows, convert, "10 km in miles")
        if not ok then
          -- Dot called rather than colon is a real possibility and a real defect, so the
          -- second attempt is made and the answer says which convention worked, since a
          -- reader chasing this needs to know which one the plugin actually uses.
          local ok2, rows2 = pcall(convert.queryRows, "10 km in miles")
          if not ok2 then return false, "asking it to convert raised, " .. tostring(rows) end
          rows = rows2
        end
        if type(rows) ~= "table" or #rows == 0 then
          return false, "it answered nothing for a conversion it should understand"
        end
        local text = tostring(rows[1].text or rows[1].title or "")
        if not text:find("%d") then
          return false, "its answer carries no number, it reads '" .. text .. "'"
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
