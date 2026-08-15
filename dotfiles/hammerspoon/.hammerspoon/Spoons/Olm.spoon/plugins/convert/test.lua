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
      -- The query form is the tool's own grammar and not a guess. "10 km in miles" answers
      -- nothing while "10km to miles" answers a row, which a first version of this got wrong and
      -- reported as a broken plugin on a configuration where it works.
      -- The answer arrives from a process rather than in the call, so the row is asked for and
      -- then asked for again a beat later, the same shape the launcher itself uses when a late
      -- answer lands. Asking once and judging would fail on a correct conversion.
      steps = {
        { fn = function(w) w._convert = w.role("convert") w._rows = nil end, wait = 0.1 },
        -- One ask per STEP rather than a loop inside one, because the answer arrives on the
        -- main thread and a loop that sleeps between asks blocks the very callback it is
        -- waiting for. That mistake was made twice in this suite, once in the input helpers and
        -- once here, which is why it is written down in both places.
        { fn = function(w)
            local c = w._convert
            if not c or w._rows then return end
            local ok, rows = pcall(function() return c:rows("10km to miles") end)
            if ok and type(rows) == "table" and rows[1] then
              local text = tostring(rows[1].text or rows[1].title or "")
              if text:find("%d") then w._rows = rows end
            end
          end, wait = 0.5 },
        -- One ask per STEP rather than a loop inside one, because the answer arrives on the
        -- main thread and a loop that sleeps between asks blocks the very callback it is
        -- waiting for. That mistake was made twice in this suite, once in the input helpers and
        -- once here, which is why it is written down in both places.
        { fn = function(w)
            local c = w._convert
            if not c or w._rows then return end
            local ok, rows = pcall(function() return c:rows("10km to miles") end)
            if ok and type(rows) == "table" and rows[1] then
              local text = tostring(rows[1].text or rows[1].title or "")
              if text:find("%d") then w._rows = rows end
            end
          end, wait = 0.5 },
        -- One ask per STEP rather than a loop inside one, because the answer arrives on the
        -- main thread and a loop that sleeps between asks blocks the very callback it is
        -- waiting for. That mistake was made twice in this suite, once in the input helpers and
        -- once here, which is why it is written down in both places.
        { fn = function(w)
            local c = w._convert
            if not c or w._rows then return end
            local ok, rows = pcall(function() return c:rows("10km to miles") end)
            if ok and type(rows) == "table" and rows[1] then
              local text = tostring(rows[1].text or rows[1].title or "")
              if text:find("%d") then w._rows = rows end
            end
          end, wait = 0.5 },
        -- One ask per STEP rather than a loop inside one, because the answer arrives on the
        -- main thread and a loop that sleeps between asks blocks the very callback it is
        -- waiting for. That mistake was made twice in this suite, once in the input helpers and
        -- once here, which is why it is written down in both places.
        { fn = function(w)
            local c = w._convert
            if not c or w._rows then return end
            local ok, rows = pcall(function() return c:rows("10km to miles") end)
            if ok and type(rows) == "table" and rows[1] then
              local text = tostring(rows[1].text or rows[1].title or "")
              if text:find("%d") then w._rows = rows end
            end
          end, wait = 0.5 },
        -- One ask per STEP rather than a loop inside one, because the answer arrives on the
        -- main thread and a loop that sleeps between asks blocks the very callback it is
        -- waiting for. That mistake was made twice in this suite, once in the input helpers and
        -- once here, which is why it is written down in both places.
        { fn = function(w)
            local c = w._convert
            if not c or w._rows then return end
            local ok, rows = pcall(function() return c:rows("10km to miles") end)
            if ok and type(rows) == "table" and rows[1] then
              local text = tostring(rows[1].text or rows[1].title or "")
              if text:find("%d") then w._rows = rows end
            end
          end, wait = 0.5 },
        -- One ask per STEP rather than a loop inside one, because the answer arrives on the
        -- main thread and a loop that sleeps between asks blocks the very callback it is
        -- waiting for. That mistake was made twice in this suite, once in the input helpers and
        -- once here, which is why it is written down in both places.
        { fn = function(w)
            local c = w._convert
            if not c or w._rows then return end
            local ok, rows = pcall(function() return c:rows("10km to miles") end)
            if ok and type(rows) == "table" and rows[1] then
              local text = tostring(rows[1].text or rows[1].title or "")
              if text:find("%d") then w._rows = rows end
            end
          end, wait = 0.5 },
        -- One ask per STEP rather than a loop inside one, because the answer arrives on the
        -- main thread and a loop that sleeps between asks blocks the very callback it is
        -- waiting for. That mistake was made twice in this suite, once in the input helpers and
        -- once here, which is why it is written down in both places.
        { fn = function(w)
            local c = w._convert
            if not c or w._rows then return end
            local ok, rows = pcall(function() return c:rows("10km to miles") end)
            if ok and type(rows) == "table" and rows[1] then
              local text = tostring(rows[1].text or rows[1].title or "")
              if text:find("%d") then w._rows = rows end
            end
          end, wait = 0.5 },
        -- One ask per STEP rather than a loop inside one, because the answer arrives on the
        -- main thread and a loop that sleeps between asks blocks the very callback it is
        -- waiting for. That mistake was made twice in this suite, once in the input helpers and
        -- once here, which is why it is written down in both places.
        { fn = function(w)
            local c = w._convert
            if not c or w._rows then return end
            local ok, rows = pcall(function() return c:rows("10km to miles") end)
            if ok and type(rows) == "table" and rows[1] then
              local text = tostring(rows[1].text or rows[1].title or "")
              if text:find("%d") then w._rows = rows end
            end
          end, wait = 0.5 },
      },
      expect = function(w)
        if not w._convert then
          return false, "the convert plugin is not loaded, so its tool is missing or it was blocked"
        end
        if type(w._convert.rows) ~= "function" then
          return false, "it exposes no rows, so the launcher can never reach it"
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
