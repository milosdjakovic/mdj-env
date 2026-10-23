-- Global settings
-- All configurable values in one place

-- Overlay display modes, named constants rather than bare strings, so the config
-- below names a symbol (overlayModes.activeWindow) and a typo is a nil reference here
-- rather than a silently wrong string down the line. Exposed on the returned table so
-- init.lua's strategy registry keys off these same values, one source of truth for the
-- valid mode names.
local overlayModes = {
  activeWindow = "activeWindow",
  cursor = "cursor",
}

-- Picker provider names, the same keys the Chooser facade's providers table uses, named
-- constants for the same reason as overlayModes.
local chooserProviders = {
  default = "default",
  legacy = "legacy",
}

return {
  overlayModes = overlayModes,
  chooserProviders = chooserProviders,

  -- Which picker draws every chooser. default is the hand drawn picker on the shared panel
  -- chrome, with its own field, list and mouse handling. legacy is the
  -- built in hs.chooser window, DEPRECATED since 2026-10-14, kept only as a fallback for now
  -- and warned about in the console on every load that picks it. chooserProviders.default | chooserProviders.legacy
  chooser = {
    provider = chooserProviders.default,
  },

  -- Gap around and between managed windows, in pixels. One value drives both the
  -- outer inset (the margins in init.lua) and the gutter between tiled halves, so
  -- the spacing stays uniform. Set to 0 to disable gaps entirely (windows go
  -- flush to the screen edges and to each other).
  gap = 0,

  -- Window animation (0 = instant)
  windowAnimationDuration = 0,

  -- A terminal block used to sit here, the timing and the size and padding the retired
  -- TerminalHandler spoon read. AppToggler owns the behaviour now, through the placement
  -- field its GhosttyPlaced variant in config/plugins.lua carries, and the timing that
  -- block held is internal to that plugin, nobody has ever tuned it.

  -- A windowMemory block used to sit here, holding the pixel tolerance for the retired
  -- WindowMemory plugin. Nothing ever passed it through, so it was already dead, and the
  -- plugin it named is gone. Workspaces owns that behaviour now and carries its own tuning
  -- inside its engine, which is where a constant nobody has ever wanted to change belongs.

  -- The shared canvas surface. One source for how every canvas panel looks in
  -- light and dark, the docked shortcut bars, the cheat sheet, the colour toast,
  -- and the clipboard preview pane. Only the shape lives here, the border width and the
  -- corner radius. The colours of the surface and of everything drawn on it come from the
  -- theme files under config/themes, one file per theme, chosen on the OLM settings page.
  surface = {
    cornerRadius = 0,    -- square surfaces, 20 is the macOS window corner, rounding every surface at once
    borderWidth = 1,
  },

  -- Cheat-sheet overlay content (the Hyper and SUPER modals). One place for the
  -- grid content styling; the shared CheatSheet renderer applies it to every
  -- overlay. Per-overlay layout (column count, icons) stays in the spoons. The
  -- panel surface itself (fill, border, corners) is NOT here; the cheat sheet
  -- draws through the shared CanvasPanel atom, so it shares the one surface above.
  -- The badge radius is not a setting any more. Every panel pads by the kit's one inset on
  -- all four sides, the cheat sheet by twice it, and every chip's corner is the surface
  -- radius less its panel's padding, so it follows surface.cornerRadius above.
  cheatSheet = {
    -- padding = 28,   -- an override of twice the kit inset, the badge corner follows it
  },

  -- Overlay display policy. Decides which display every transient overlay appears
  -- on, every chooser, its docked shortcut panel, every cheat sheet, and the colour
  -- toast. init.lua reads this into a small strategy registry and injects the chosen
  -- resolver into the Chooser atom and the CanvasPanel, so one choice moves every
  -- overlay together. Two modes.
  --   "activeWindow" the display holding the focused window.
  --   "cursor"       the display the mouse pointer is on, the default, since the launcher
  --                  should land where the eyes already are.
  --
  -- This block is now only the DEFAULT SEED. The live choice is set at runtime from
  -- the OLM settings tool in the launcher and persisted under the hs.settings key
  -- overlayDisplayPolicy, which overrides this value. init.lua reads it through
  -- effectiveMode, seeded then persisted. So edit here to change the default for a
  -- fresh machine, and use the OLM settings tool for day to day switching.
  overlayDisplay = {
    -- overlayModes.activeWindow | overlayModes.cursor
    mode = overlayModes.cursor,
  },

  -- Window sizing defaults. A move or resize key travels one of two amounts and never anything
  -- in between. stepPixels is what a press on its own does, kept small because a press is how
  -- a window is placed by eye, and heldPixels is what each repeat of a held key does, which is
  -- where the speed of a hold comes from, since the rate itself is the machine's and stays
  -- steady. holdGrace is how many presses still count as a press before the held amount takes
  -- over, so 1 means the very first repeat already cruises.
  --
  -- Resizing carries its own pair, and a larger one, because the two keys do not cover the
  -- same apparent ground with the same number. A move slides the whole window one distance,
  -- where a resize moves an edge and spends its step across two axes at once.
  --
  -- A resize number is what the canvas's LONG edge grows by, and the short edge takes its
  -- proportional share, so a window grows in the shape of the screen it is growing inside
  -- instead of reaching the top and bottom of an ultrawide long before the sides. The long
  -- edge is the reference rather than the width so that a rotated, portrait screen behaves the
  -- same way, one press always growing the long edge by the number written here whichever way
  -- the screen is turned.
  --
  -- The held amount over the repeat interval is the hold's speed, so on a stock keyboard, at
  -- twelve repeats a second, a move holds about 480 pixels a second and a resize grows its
  -- long edge by about 600. Raise the Held numbers to cross a screen quicker and nothing about
  -- a single press changes.
  --
  -- minWidth and minHeight are the floor a shrink stops at, since growing has the screen edge
  -- to stop at and shrinking has nothing, and a held shrink key with no floor walks a window
  -- down to a sliver.
  windowSizing = {
    maxWidth = 2400,
    maxHeight = 1350,
    fullHeightMaxWidth = 2400,
    movePixels = 20,
    movePixelsHeld = 40,
    resizePixels = 30,
    resizePixelsHeld = 50,
    holdGrace = 1,
    minWidth = 400,
    minHeight = 300,
    screenRecording = { width = 2400, height = 1350 },
    smallSize = { width = 700, height = 800 },
  },

  -- How OFTEN a held key repeats, which is empty on purpose. Both beats are read off this
  -- machine, the Delay Until Repeat and Key Repeat sliders in System Settings under Keyboard,
  -- so a held leader key waits and then runs exactly like a held key in any text field and
  -- follows whatever is set there. The long first beat is what keeps one deliberate press to
  -- one press, and the steady rate after it never changes under the finger, so where a window
  -- ends up does not depend on the exact moment it is released.
  --
  -- Naming either number here overrides the machine for the leader keys alone, which is worth
  -- doing only to make them differ from every other held key on purpose. How FAR each of
  -- those repeats moves a window is the windowSizing block above, and that is the knob to
  -- reach for, since one is a property of the keyboard and the other of the action.
  keyRepeat = {
    -- delay = 0.5,
    -- interval = 0.08,
  },

  -- Screen capture priority. An ordered list of Capture provider names, tried front
  -- to back, so the first one that supports the action and is usable right now handles
  -- it. This is the whole of the chain order, pure data, and the composition root is
  -- still the only place a name becomes a concrete provider, the same shape the overlay
  -- display modes already use. So reordering the chain, or
  -- dropping a backend to stay off it, is one edit here.
  --
  -- macshot leads because its capture is the one wanted for screenshots and recording,
  -- and it stands aside on its own whenever it is not installed, does not own its URL
  -- scheme, or is simply not running. native is the macOS shortcuts and is always
  -- available, so it belongs last of the two and is what answers while macshot is down.
  -- macocr is the only backend for the OCR action, so nothing competes with it and its
  -- position does not matter, but removing it removes OCR entirely.
  --
  -- A name nothing answers to is named in the console and skipped, and a list that
  -- resolves to no provider at all leaves Capture on its own built in order rather than
  -- on an empty chain.
  capture = {
    providers = { "macshot", "native", "macocr" },
  },

  -- The two storage roots every plugin's data lives under, pure data with the
  -- join done elsewhere, in Olm.spoon's storage module. cacheRoot holds
  -- regenerable data, safe to delete since it only costs a rebuild, compiled
  -- helpers, menu snapshots, preview renders. olmRoot holds durable data,
  -- clipboard history, layouts, speed test runs. Both sit under one hidden
  -- directory so everything Olm writes on this machine is in one place and
  -- none of it is in the config tree or in git. Changing either is one line
  -- here, since the root is the only place either name is written.
  paths = {
    cacheRoot = "~/.olm/cache",
    olmRoot = "~/.olm/data",
    -- The directory of colour theme files, found from this file's own location so it is the
    -- one beside this config wherever the config is loaded from. Tracked, unlike the two above.
    themes = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or (hs.configdir .. "/config")) .. "/themes",
    -- The typography file, fonts and sizes of the five type roles, beside this config.
    typography = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or (hs.configdir .. "/config")) .. "/typography.toml",
    -- The icons file, which icon set draws every row icon and which one backs it up.
    icons = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or (hs.configdir .. "/config")) .. "/icons.toml",
  },
}
