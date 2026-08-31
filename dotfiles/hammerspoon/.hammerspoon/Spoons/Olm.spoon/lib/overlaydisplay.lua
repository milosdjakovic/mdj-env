-- The overlay display policy resolver.
--
-- This is a lib factory rather than a plugin because two shared atoms, the Chooser
-- and the CanvasPanel, each need a screen function before any plugin has loaded,
-- and a plugin only exists once the wiring stages run. So the composition root
-- builds one instance of this module first, wires self.screen into both atoms as a
-- closure that calls through the instance, and only then starts the plugin
-- pipeline.
--
-- Strategy is the shape of the resolver. A small table maps a mode name to a
-- function returning an hs.screen, opts.mode names the seed choice, and the OLM
-- settings plugin can move the live choice from whichever mode was seeded to the
-- other one with no reload. Neither atom, and nothing that calls self.screen,
-- needs to know the caller is a chooser or a canvas panel, only that a screen
-- comes back.
--
-- Two modes only, activeWindow and cursor. The OLM settings plugin is the one
-- place a person sees or changes this choice, reading and writing it through
-- self.mode and self.setMode, so this file stays the one place that ever calls
-- hs.settings for the policy itself.

local M = {}

local log = hs.logger.new("OverlayDisplay", "info")

-- The mode names, exposed on the module table so a caller building the seed opts
-- for configure names a mode once and a typo becomes a nil reference here rather
-- than a silently wrong string carried all the way to the resolver table.
local MODE_ACTIVE_WINDOW = "activeWindow"
local MODE_CURSOR = "cursor"
M.modes = {
  activeWindow = MODE_ACTIVE_WINDOW,
  cursor = MODE_CURSOR,
}

--- M.new() returns instance.
--- Takes no deps. The picker this module once carried needed a canvas panel, a
--- displayplacer path, the active display arrangement, and a way to pop the shared
--- stage, and all four left with the picker, so there is nothing left here to
--- inject.
function M.new()
  local self = {}

  -- The runtime store key, kept local rather than read from a config table, since
  -- a fresh install needs somewhere for a choice to persist before any config file
  -- exists to name one, and nothing outside this file ever reads it. A stored
  -- table may still carry a leftover fixed key from a machine that had a pin
  -- before this file was slimmed to two modes. Nothing here reads that key any
  -- more, and it is deliberately not scrubbed, since a dead key with no reader
  -- costs nothing and a migration step for it would be ceremony over a value
  -- nobody will ever see again.
  local STORE_KEY = "overlayDisplayPolicy" -- { mode }

  -- The seed policy handed to configure, config/settings.lua's own overlayDisplay
  -- block. Defaulted here so self.screen answers something sane even the moment
  -- this instance is built, before configure has run at all.
  local seed = { mode = MODE_ACTIVE_WINDOW }

  local function activeWindowScreen()
    local w = hs.window.focusedWindow()
    return (w and w:screen()) or hs.screen.mainScreen() or hs.screen.primaryScreen()
  end
  local function cursorScreen()
    return hs.mouse.getCurrentScreen() or hs.screen.primaryScreen()
  end

  -- The persisted choice, layered over the seed. The OLM settings plugin writes
  -- here, under one hs.settings key, so the choice survives a reload and a reboot
  -- the same way the launcher's own remembered order does. effectiveMode reads the
  -- stored value first and falls back to the seed, so a choice made in the settings
  -- plugin takes effect on the next screen resolve with no reload, and an unset key
  -- still honours whatever configure was seeded with.
  local function storeValue()
    return hs.settings.get(STORE_KEY) or {}
  end
  -- Clamps to cursor when the stored or seeded mode is not one of the two this file
  -- still knows. This is the whole migration a machine whose stored policy still
  -- names fixed needs, since that old choice is no longer a member of M.modes and
  -- would otherwise resolve to nothing, and cursor is the sane place to land such a
  -- machine rather than leaving it to fail the strategy lookup below.
  local function effectiveMode()
    local mode = storeValue().mode or seed.mode
    if mode ~= MODE_ACTIVE_WINDOW and mode ~= MODE_CURSOR then return MODE_CURSOR end
    return mode
  end

  -- Keyed by the same mode constants exported above, so the valid mode names live
  -- in one place and self.screen cannot drift from the one write path that sets
  -- them.
  local strategies = {
    [MODE_ACTIVE_WINDOW] = activeWindowScreen,
    [MODE_CURSOR] = cursorScreen,
  }

  --- self.screen()
  --- The injected contract every atom reads. Resolves the effective mode fresh on
  --- every call, the persisted choice when there is one, else the seed, so a mode
  --- switch takes effect on the next overlay with no reload. Tolerates being
  --- called before configure has run, since the seed default above already
  --- answers activeWindow, and falls back to the primary screen when a resolver
  --- still comes back with nothing.
  function self.screen()
    local fn = strategies[effectiveMode()] or activeWindowScreen
    return fn() or hs.screen.primaryScreen()
  end

  --- self.mode() -> string
  --- The effective placement mode right now, one of M.modes, the persisted choice
  --- when there is one, else the seed. Public so the OLM settings plugin can
  --- describe the live choice in words without keeping a second read of
  --- effectiveMode.
  function self.mode()
    return effectiveMode()
  end

  --- self.setMode(mode) -> bool
  --- Writes the placement mode through the one write path this file keeps, read
  --- the stored table, set mode, write it back. A mode not among M.modes is
  --- refused with a log line and leaves the stored choice untouched, since
  --- writing an unrecognised name here would silently hand the resolver a
  --- strategy table lookup that answers nothing.
  function self.setMode(mode)
    local known = false
    for _, m in pairs(M.modes) do
      if m == mode then known = true end
    end
    if not known then
      log.w(string.format("setMode refused '%s', not one of the modes this resolver knows", tostring(mode)))
      return false
    end
    local s = storeValue()
    s.mode = mode
    hs.settings.set(STORE_KEY, s)
    return true
  end

  --- self.configure(opts)
  --- opts.mode  the seed mode, one of the M.modes values, defaulting to
  ---            activeWindow. Seeds the fallback policy. Safe to call again.
  function self.configure(opts)
    opts = opts or {}
    seed.mode = opts.mode or MODE_ACTIVE_WINDOW
    return self
  end

  return self
end

return M
