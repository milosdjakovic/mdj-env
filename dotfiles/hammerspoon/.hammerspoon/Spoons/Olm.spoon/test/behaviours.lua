--- === Olm behaviours ===
---
--- What this configuration promises a person, written as things you do rather than as things
--- that were wired. Every scenario here runs identically against the retired root and the
--- restructured one, because a suite that only runs against the thing under test cannot tell a
--- regression from a broken test.
---
--- The list started as the five failures a person found by hand in ten seconds while every
--- automated check reported no problems. That gap is the whole reason this file is shaped
--- around pressing keys and looking at the screen rather than around inspecting wiring.
---
--- Ordering matters in one direction only. Each scenario leaves the screen as it found it, so
--- they may be run in any order, and any that fails halfway is followed by a sweep that closes
--- whatever it left open.

return {

  --------------------------------------------------------------------------------
  -- The leaders, which is where every one of the reported failures lived
  --------------------------------------------------------------------------------

  {
    scenario = "holding the app leader reveals the Hyper cheat sheet, releasing hides it",
    tier = "input",
    -- Steps rather than one function, because the gap between holding a key and looking at the
    -- screen has to be a real turn of the run loop. See test/world.lua for why.
    --
    -- The first two steps are a WARM UP and nothing is judged on them. An overlay that has
    -- never been drawn on this config builds its canvas, measures its text and renders every
    -- glyph on the first hold, which can take longer than a person would ever hold a leader,
    -- and being first in the queue this scenario is the one that always pays it. A cold run
    -- failed here, left a leader down, and every scenario after it failed too, on a config
    -- that was perfect. So the first hold is spent rather than measured, and the second one,
    -- against a warm overlay, is the one the verdict comes from. Waiting longer before the
    -- run would not have helped, since what is cold is the drawing rather than the config.
    steps = {
      { fn = function(w) w.down("hyper") end, wait = 1.1 },
      { fn = function(w) w.up("hyper") end, wait = 0.8 },
      { fn = function(w) w._seen = nil w.down("hyper") end, wait = 1.1 },
      { fn = function(w) w._seen = w.showing("hypercheatsheet") w.up("hyper") end, wait = 0.6 },
    },
    expect = function(w)
      local sheet = w.role("hypercheatsheet")
      if not sheet then return false, "no Hyper cheat sheet in this config at all" end
      if type(sheet.isShowing) ~= "function" then
        return false, "it cannot be observed, so nothing can tell whether it appears"
      end
      if not w._seen then
        return false, "the leader was held past its hold delay and no sheet appeared"
      end
      if w.showing("hypercheatsheet") then
        return false, "it appeared but stayed on screen after the leader was released"
      end
      return true
    end,
  },

  {
    scenario = "holding the window leader reveals the window cheat sheet, releasing hides it",
    tier = "input",
    -- Steps rather than one function, because the gap between holding a key and looking at the
    -- screen has to be a real turn of the run loop. See test/world.lua for why.
    -- Warmed the same way and for the same reason as the Hyper sheet above, since this is a
    -- second overlay with its own canvas and its own first draw to pay for.
    steps = {
      -- A beat before the leader goes down, because the scenario before this one also held a
      -- leader and the shared engine has its own state to unwind. Two holds back to back is
      -- not something a person does, so the suite gives it the room a person would.
      { fn = function(w) w._seen = nil end, wait = 0.8 },
      { fn = function(w) w.down("meta") end, wait = 1.2 },
      { fn = function(w) w.up("meta") end, wait = 0.8 },
      { fn = function(w) w.down("meta") end, wait = 1.2 },
      { fn = function(w) w._seen = w.showing("windowcheatsheet") w.up("meta") end, wait = 0.6 },
    },
    expect = function(w)
      local sheet = w.role("windowcheatsheet")
      if not sheet then return false, "no window cheat sheet in this config at all" end
      if type(sheet.isShowing) ~= "function" then
        return false, "it cannot be observed, so nothing can tell whether it appears"
      end
      if not w._seen then
        return false, "the leader was held past its hold delay and no sheet appeared"
      end
      if w.showing("windowcheatsheet") then
        return false, "it appeared but stayed on screen after the leader was released"
      end
      return true
    end,
  },

  --------------------------------------------------------------------------------
  -- What the overlays SAY, which is a different question from whether they appear
  --------------------------------------------------------------------------------

  -- Both scenarios below exist because the two above passed on a configuration where the
  -- Hyper overlay had no applications on it at all and the window overlay's heading was
  -- blank. Every automated check said the sheets appeared, and they did. Appearing was never
  -- the promise. A cheat sheet that shows nothing is worse than one that does not open, since
  -- it answers the question wrongly instead of visibly failing to answer it.

  {
    scenario = "the Hyper overlay lists the applications its leader switches between",
    tier = "behaviour",
    expect = function(w)
      local sheet = w.role("hypercheatsheet")
      if not sheet then return false, "no Hyper cheat sheet in this config at all" end
      local n = 0
      for _ in pairs(sheet._apps or {}) do n = n + 1 end
      if n == 0 then
        return false, "it holds no application registry, so its whole app half draws empty "
          .. "however well it opens"
      end
      if #(sheet._toggles or {}) == 0 then
        return false, "it holds no toggle list, so it knows of no app to draw a row for"
      end
      return true
    end,
  },

  {
    scenario = "the Hyper overlay lists the actions bound to its leader",
    tier = "behaviour",
    expect = function(w)
      local sheet = w.role("hypercheatsheet")
      if not sheet then return false, "no Hyper cheat sheet in this config at all" end
      local rows = 0
      for _, section in ipairs(sheet._staticSections or {}) do
        rows = rows + #(section.rows or {})
      end
      if rows == 0 then
        return false, "it has no action rows, so every chord under this leader is unlisted"
      end
      -- A count rather than a list of names, since which tools a person installs is theirs to
      -- decide and this suite has no business holding a roster. What it can say honestly is
      -- that a set this small means whole sources were missed rather than merely unpopulated,
      -- which is what reading only registry tools and ignoring every plugin carrying its own
      -- bindings actually did.
      if rows < 10 then
        return false, "only " .. rows .. " action rows, which is fewer than the tools that "
          .. "carry a chord, so a whole source of bindings is being skipped"
      end
      return true
    end,
  },

  {
    scenario = "the window overlay names what its leader does",
    tier = "behaviour",
    expect = function(w)
      local sheet = w.role("windowcheatsheet")
      if not sheet then return false, "no window cheat sheet in this config at all" end
      local groups = sheet._byLeader or {}
      local found = nil
      for _, group in pairs(groups) do found = group break end
      if not found then
        return false, "it has no rows for any leader, so holding one shows an empty overlay"
      end
      if #(found.rows or {}) == 0 then
        return false, "its leader group has no rows in it"
      end
      if found.name == nil or found.name == "" then
        return false, "its rows have no heading, so the overlay draws a blank title over them"
      end
      return true
    end,
  },

  --------------------------------------------------------------------------------
  -- The launcher, and the key that reaches it
  --------------------------------------------------------------------------------

  {
    scenario = "the app leader and space opens the launcher, and escape closes it",
    tier = "input",
    steps = {
      { fn = function(w) w._before = w.showing("launcher") w.down("hyper") end, wait = 1.0 },
      { fn = function(w) w.press("space") end, wait = 0.2 },
      { fn = function(w) w.up("hyper") end, wait = 0.9 },
      { fn = function(w) w._opened = w.showing("launcher") w.escape() end, wait = 0.5 },
      -- Closing is watched rather than checked once. The claim is that escape closes the
      -- launcher, not that it closes it inside half a second, and a chooser that is still
      -- animating open when the key arrives takes a beat longer to go away. Judging on the
      -- first look failed here on runs where the same key works by hand every time.
      { fn = function(w) w._closed = not w.showing("launcher") end, wait = 0.5 },
      { fn = function(w) w._closed = w._closed or not w.showing("launcher") end, wait = 0.5 },
    },
    expect = function(w)
      if w._before then return false, "it was already open before the test began" end
      if not w._opened then
        return false, "the chord was posted and the launcher never appeared"
      end
      if not w._closed then
        return false, "it opened but escape did not close it"
      end
      return true
    end,
  },

  {
    scenario = "the launcher lists applications to switch to",
    tier = "behaviour",
    expect = function(w)
      local launcher = w.role("launcher")
      if not launcher or type(launcher.rowsOfKind) ~= "function" then
        return false, "the launcher cannot be asked for its rows"
      end
      local ok, rows = pcall(function() return launcher:rowsOfKind("app") end)
      if not ok then return false, "asking for app rows raised, " .. tostring(rows) end
      if type(rows) ~= "table" or #rows == 0 then
        return false, "it has no application rows at all, so nothing can be switched to"
      end
      return true
    end,
  },

  {
    scenario = "the launcher lists window management actions",
    tier = "behaviour",
    expect = function(w)
      local launcher = w.role("launcher")
      if not launcher or type(launcher.rowsOfKind) ~= "function" then
        return false, "the launcher cannot be asked for its rows"
      end
      local rows = launcher:rowsOfKind("window")
      if type(rows) ~= "table" or #rows == 0 then
        return false, "no window rows, so the window actions are unreachable by name"
      end
      return true
    end,
  },

  --------------------------------------------------------------------------------
  -- App switching, the leader's other half
  --------------------------------------------------------------------------------

  {
    scenario = "the app toggler knows which applications its leader switches between",
    tier = "behaviour",
    expect = function(w)
      local toggler = w.role("apptoggler")
      if not toggler then return false, "there is no app toggler in this config" end
      if type(toggler.toggle) ~= "function" then
        return false, "it exposes no toggle, so its leader has nothing to call"
      end
      return true
    end,
  },

  --------------------------------------------------------------------------------
  -- Window management, which was blocked outright at one point with nothing said
  --------------------------------------------------------------------------------

  {
    scenario = "the window manager offers the actions its leader binds",
    tier = "behaviour",
    expect = function(w)
      local wm = w.role("windowmanager")
      if not wm then return false, "there is no window manager in this config" end
      if type(wm.actions) ~= "function" then
        return false, "it exposes no action map, so its leader binds nothing"
      end
      local ok, actions = pcall(function() return wm:actions() end)
      if not ok then return false, "asking for its actions raised, " .. tostring(actions) end
      local n = 0
      for _ in pairs(actions or {}) do n = n + 1 end
      if n == 0 then return false, "its action map is empty, so every window key is dead" end
      return true
    end,
  },

  --------------------------------------------------------------------------------
  -- The tool kept deliberately outside Olm
  --------------------------------------------------------------------------------

  {
    scenario = "the terminal handler is configured and can be toggled",
    tier = "behaviour",
    expect = function(w)
      local th = w.role("terminalhandler")
      if not th then return false, "the terminal handler is not loaded at all" end
      if type(th.toggle) ~= "function" then
        return false, "it exposes no toggle, so its key has nothing to call"
      end
      return true
    end,
  },

  --------------------------------------------------------------------------------
  -- The clipboard, which a person noticed had gone back to the native one
  --------------------------------------------------------------------------------

  {
    scenario = "the clipboard key opens Olm's own history rather than the native one",
    tier = "input",
    -- This is the scenario the whole suite was rebuilt for. A person pressed this key, got the
    -- native macOS clipboard, and every automated check still reported no problems, because
    -- every check was asking whether wiring returned rather than what the key did.
    --
    -- The key is read from the live catalog rather than written here, so rebinding it moves the
    -- test with it. Its catalog name differs from its registered name, which is exactly the
    -- mismatch that cost seven tools their key once before.
    steps = {
      { fn = function(w)
          w._key = w.keyFor("clipboardHistory") or w.keyFor("clipboard")
          if w._key then w.down("hyper") end
        end, wait = 1.0 },
      { fn = function(w) if w._key then w.press(w._key) end end, wait = 0.2 },
      { fn = function(w) if w._key then w.up("hyper") end end, wait = 0.9 },
      { fn = function(w)
          w._opened = w.showing("clipboard")
          if w._opened then w.escape() end
        end, wait = 0.6 },
    },
    expect = function(w)
      if not w._key then
        return false, "no key is bound for the clipboard in the live catalog"
      end
      local manager = (w.role("clipboard") or {}).manager or w.role("clipboard")
      if not manager or type(manager.isShowing) ~= "function" then
        return false, "the clipboard exposes nothing that says whether it is showing"
      end
      if not w._opened then
        return false, "its key was pressed and Olm's own clipboard never appeared, "
          .. "so whatever answered that key was not this one"
      end
      return true
    end,
  },
}
