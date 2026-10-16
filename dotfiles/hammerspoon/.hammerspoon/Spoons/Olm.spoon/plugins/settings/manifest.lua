-- OLM settings, what it declares about itself.
--
-- A friendly front end onto policy that already lives elsewhere, two pages today, where the
-- OLM launcher appears, over lib/overlaydisplay.lua's own two modes, and the colour theme,
-- over lib/ui/themes.lua. It owns no data of its own, it only reads and writes the live
-- choices through the root words below, so the one place that ever calls hs.settings for
-- each policy stays the lib that owns it.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "OLM Settings",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  -- The row icons. The two option rows carry only a circle each, never a checkmark, the one
  -- marker convention this codebase uses for which of these is current right now. Green marks
  -- whichever option is current and red marks the other one.
  icons = {
    placement = { emoji = "🖥️", sf = "desktopcomputer" },
    theme = { emoji = "🎨", sf = "paintpalette" },
    back = { emoji = "⬅️", sf = "chevron.left" },
    selected = { emoji = "🟢", sf = "circle.fill" },
    notSelected = { emoji = "🔴", sf = "circle" },
    settings = { emoji = "🎛️", sf = "slider.horizontal.3" },
  },

  -- No moving parts, so no engine and contract ceremony, one module. The directory is
  -- settings, one lowercase word, and it needs no different spelling, so no name field.

  needs = {
    data = {
      -- The reader, a function of no arguments answering the resolver's own effective mode
      -- as a string, one of lib/overlaydisplay.lua's M.modes. Required, since a page whose
      -- whole reason is showing which choice is live has nothing honest left to show
      -- without it.
      overlayPlacementMode = { source = "root", policy = "required",
        breaks = "the Where the OLM launcher appears page cannot say which choice is live, "
          .. "or mark either option as current, since the resolver's own mode has no other "
          .. "door out" },
      -- The writer, a function of one mode string, validated against M.modes and persisted
      -- through the resolver's own existing write path. Required for the identical reason,
      -- a page whose whole reason is changing this choice has nothing to do without it.
      setOverlayPlacementMode = { source = "root", policy = "required",
        breaks = "choosing either option in the Where the OLM launcher appears page changes "
          .. "nothing, since the resolver's own persisted choice has no other way in from "
          .. "this plugin" },

      -- The theme switcher's three words, published by the root over lib/ui/themes.lua. The
      -- reader answers the live theme's name, the lister the sorted names of every theme file
      -- found, and the writer takes a name, applies that theme at once and persists it. All
      -- three are required, since a Theme page that cannot name the live theme, list the
      -- choices or change one has nothing honest left to show.
      themeName = { source = "root", policy = "required",
        breaks = "the Theme row on the OLM settings page cannot say which theme is live, "
          .. "and the page cannot mark the live one, since the store of themes has no other "
          .. "door out" },
      themeNames = { source = "root", policy = "required",
        breaks = "the Theme page lists no themes, since the files under config/themes are "
          .. "known only to the store the root built" },
      setTheme = { source = "root", policy = "required",
        breaks = "choosing a theme on the Theme page changes nothing, since applying and "
          .. "persisting a theme has no other way in from this plugin" },

      -- The plugins page's four words over the one switch, published by the root over
      -- lib/pluginswitch.lua. Optional, since no page reads them yet and every other page
      -- here works without them. The catalog lists the plugins under plugins with their
      -- about block and needs, the set answers which are switched off, the cascade answers
      -- what else goes off or comes back with one, and the setter saves a switch and
      -- schedules the one reload that applies it.
      pluginCatalog = { source = "root", policy = "optional",
        breaks = "a plugins page has nothing to list, since which plugins exist and what each "
          .. "needs is known only to the root that read the manifests" },
      disabledPlugins = { source = "root", policy = "optional",
        breaks = "a plugins page cannot say which plugins are switched off" },
      pluginCascade = { source = "root", policy = "optional",
        breaks = "a plugins page cannot say what else goes off with a plugin before it is "
          .. "switched off, or what comes back with it" },
      setPluginDisabled = { source = "root", policy = "optional",
        breaks = "switching a plugin on or off from a plugins page changes nothing, since the "
          .. "saved set and the reload have no other way in from this plugin" },

      -- Two of the trickle migration's own words, the hotkey door and the child leaving
      -- door, optional and degrading to an inert press rather than a crash, since asking
      -- either before the stage's own configure has run is a wiring defect rather than a
      -- state a key press should silently swallow.
      stagePresent = { source = "root", policy = "optional",
        breaks = "the OLM settings launcher row opens nothing, since M.show has no other way to reach the shared stage" },
      stagePop = { source = "root", policy = "optional",
        breaks = "the Where the OLM launcher appears page's own Back row stands on the "
          .. "level it meant to leave rather than returning to OLM settings" },
    },
  },

  -- Opened from the launcher only, so it proposes no key and no shortcut field at all.
  defaults = {
    description = "OLM settings",
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
    row = { category = "System", icon = "settings",
      detail = "where the OLM launcher appears, the colour theme and other preferences",
      keywords = "olm settings preferences options window placement theme colour colors appearance" },
    open = { member = "show", call = "dot" },
  },
}
