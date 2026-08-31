-- Settings, what it declares about itself.
--
-- A friendly front end onto a policy that already lives elsewhere, one page today, window
-- placement, over lib/overlaydisplay.lua's own three modes. It owns no data of its own, it
-- only reads and writes the resolver's live choice through the two root words below, so the
-- one place that ever calls hs.settings for this policy stays lib/overlaydisplay.lua.
return {
  -- No moving parts, so no engine and contract ceremony, one module. The directory is
  -- settings, one lowercase word, and it needs no different spelling, so no name field.

  needs = {
    data = {
      -- The reader, a function of no arguments answering the resolver's own effective mode
      -- as a string, one of lib/overlaydisplay.lua's M.modes. Required, since a page whose
      -- whole reason is showing which choice is live has nothing honest left to show
      -- without it.
      overlayPlacementMode = { source = "root", policy = "required",
        breaks = "the window placement page cannot say which choice is live, or mark either "
          .. "option as current, since the resolver's own mode has no other door out" },
      -- The writer, a function of one mode string, validated against M.modes and persisted
      -- through the resolver's own existing write path. Required for the identical reason,
      -- a page whose whole reason is changing this choice has nothing to do without it.
      setOverlayPlacementMode = { source = "root", policy = "required",
        breaks = "choosing either option in the window placement page changes nothing, "
          .. "since the resolver's own persisted choice has no other way in from this plugin" },

      -- Two of the trickle migration's own words, the hotkey door and the child leaving
      -- door, optional and degrading to an inert press rather than a crash, since asking
      -- either before the stage's own configure has run is a wiring defect rather than a
      -- state a key press should silently swallow.
      stagePresent = { source = "root", policy = "optional",
        breaks = "the Settings launcher row opens nothing, since M.show has no other way to reach the shared stage" },
      stagePop = { source = "root", policy = "optional",
        breaks = "the window placement page's own Back row stands on the level it meant to leave rather than returning to Settings" },
    },
  },

  -- Opened from the launcher only, so it proposes no key and no shortcut field at all.
  defaults = {
    description = "Settings",
  },

  surface = {
    context = "settings",
    primary = { action = "insertSelected", description = "Choose" },
  },

  -- The presentation contract, docs/PLUGIN-CONTRACT.md. rows and select are this plugin's
  -- own module functions, dot called since neither is a colon method. No matcher declared,
  -- the shared default fuzzy strategy is more than enough over one top level row, and no
  -- pane, this page describes no companion content.
  presentation = {
    rows = { member = "rows", call = "dot" },
    select = { member = "select", call = "dot" },
    placeholder = { member = "placeholder", call = "dot" },
  },

  -- open is the kept fallback door the registry's own run path reaches for only when a
  -- tool's own presentation answers nothing, unreachable here since this plugin declares
  -- one and every choose already goes through it. DisplayProfiles carries the identical
  -- kept pair for the identical reason, and it stays because losing it to save three lines
  -- buys nothing. M.show asks cfg.stagePresent for the shared stage the identical way
  -- DisplayProfiles' own launcher only entry does.
  registry = {
    row = { category = "System", glyph = "🎛️", detail = "window placement and other preferences",
      keywords = "settings preferences options window placement" },
    open = { member = "show", call = "dot" },
  },
}
