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
  fixed = "fixed",
}

return {
  overlayModes = overlayModes,

  -- Stage Manager margin (pixels to offset from left when active)
  stageManagerMargin = 66,

  -- Gap around and between managed windows, in pixels. One value drives both the
  -- outer inset (the margins in init.lua) and the gutter between tiled halves, so
  -- the spacing stays uniform. Set to 0 to disable gaps entirely (windows go
  -- flush to the screen edges and to each other). The Stage Manager margin above
  -- is respected independently of this.
  gap = 0,

  -- Window animation (0 = instant)
  windowAnimationDuration = 0,

  -- Terminal handler timing
  terminal = {
    initialDelay = 0.1,       -- Wait before checking if app is ready
    checkInterval = 0.25,     -- How often to poll for readiness
    maxAttempts = 20,         -- Maximum polls before giving up
    preferredTerminal = "Ghostty",  -- App name from config/apps.lua
    size = { width = 2400, height = 1350 },
    minPadding = { x = 40, y = 20 },
  },

  -- Workspace timing
  workspace = {
    checkInterval = 0.5,      -- How often to poll for app readiness
    timeout = 30,             -- Max seconds to wait per app
  },

  -- The shared canvas surface. One source for how every canvas panel looks in
  -- light and dark, the docked shortcut bars, the cheat sheet, the colour toast,
  -- and the clipboard preview pane. Background, border, border width, corner
  -- radius. The CanvasPanel atom is configured with this once in init.lua and owns
  -- the look from there, so editing a value here restyles every surface at once.
  -- Only the surface itself lives here; the chooser preview text colours stay in
  -- chooserTheme below.
  surface = {
    cornerRadius = 0,    -- square, the look we have; raise it to round every surface at once
    borderWidth = 1,
    dark  = { bg = "#29292e", border = "#59575C" },
    light = { bg = "#cecace", border = "#A09F9F" },
  },

  -- Cheat-sheet overlay content (the Hyper and SUPER modals). One place for the
  -- grid content styling; the shared CheatSheet renderer applies it to every
  -- overlay. Per-overlay layout (column count, icons) stays in the spoons. The
  -- panel surface itself (fill, border, corners) is NOT here; the cheat sheet
  -- draws through the shared CanvasPanel atom, so it shares the one surface above.
  -- Omit any field to keep the default.
  cheatSheet = {
    badgeRadius = 5,   -- key-badge roundness, matching the hint bar chips
    fontSize = 16,
    padding = 20,      -- inner panel padding (CanvasPanel padX/padY)
  },

  -- Chooser theme. One source for how the searchable chooser and its docked
  -- preview look in light and dark. The clipboard reads it today; a future
  -- chooser based tool (and later the cheat sheets) can read the same source, so
  -- one edit restyles them all. The active side is picked per open from the live
  -- system appearance, so it tracks the automatic light and dark switch. Each
  -- side names the chooser background flag, the two row text colours (styledtext
  -- white values, since a styled row must restate its colour), and the preview
  -- webview colours (CSS hex). Omit the light block to fall back to dark.
  chooserTheme = {
    -- preview holds only the text colours of the clipboard preview pane. That pane's
    -- background and border come from the shared surface block above, drawn through
    -- the CanvasPanel atom, so it reads as one surface with the docked shortcut panel.
    dark = {
      bgDark = true,
      titleColor = { white = 0.92 },
      subColor = { white = 0.55 },
      preview = { fg = "#dcdcdc", meta = "#8a8a8a", path = "#7a7a7a", note = "#c8a86a" },
    },
    light = {
      bgDark = false,
      titleColor = { white = 0.15 },
      subColor = { white = 0.42 },
      preview = { fg = "#1c1c1e", meta = "#6b6b70", path = "#88888d", note = "#8a5a12" },
    },
  },

  -- Overlay display policy. Decides which display every transient overlay appears
  -- on, the five choosers (clipboard, VPN, menu search, launcher, keep awake), their
  -- docked shortcut panels, both cheat sheets, and the colour toast. init.lua reads
  -- this into a small strategy registry and injects the chosen resolver into the
  -- Chooser atom and the CanvasPanel, so one choice moves every overlay together.
  -- Three modes:
  --   "activeWindow" the display holding the focused window (today's behaviour).
  --   "cursor"       the display the mouse pointer is on.
  --   "fixed"        a chosen display per display arrangement, see fixed below.
  -- fixed is read only in fixed mode. Its keys are the profile names from
  -- config/displays.lua (whichever one is currently matched, resolved through
  -- DisplayProfiles:current), and its values are displayplacer serial ids, the same
  -- portable ids those profiles already use, so no second identity scheme is needed.
  -- An arrangement with no entry, or a serial that does not resolve, falls back to
  -- the activeWindow behaviour.
  --
  -- This block is now only the DEFAULT SEED. The live choice is set at runtime from
  -- the "Overlay Display" launcher row and persisted under the hs.settings key
  -- overlayDisplayPolicy, which overrides these values; init.lua reads them through
  -- effectiveMode/effectiveFixed, seed-then-persisted. So edit here to change the
  -- fresh-machine default, and use the launcher picker for day to day switching.
  overlayDisplay = {
    -- overlayModes.activeWindow | overlayModes.cursor | overlayModes.fixed
    mode = overlayModes.activeWindow,
    fixed = {
      -- ["home-office"] = "s810891350",
      -- ["vicert office, built in and two Dell P2318HC"] = "s826888524",
    },
  },

  -- Shortcut hint panel. The docked panel that spells out the Hyper navigation
  -- shortcuts under a native chooser (the clipboard, menu search, VPN, keep awake,
  -- launcher). delayMs is the idle delay
  -- before it appears: the panel stays hidden while the field is being used, and only
  -- after this many milliseconds with no keypress does it reveal, staying up until the
  -- chooser closes. One source, so editing it applies to every chooser that docks the
  -- panel. Set delayMs to nil (or 0) to show it instantly on open.
  shortcutsPanel = {
    delayMs = 3000,
  },

  -- Window sizing defaults
  windowSizing = {
    maxWidth = 2400,
    maxHeight = 1350,
    fullHeightMaxWidth = 2400,
    movePixels = 20,
    resizePixels = 50,
    screenRecording = { width = 2400, height = 1350 },
    smallSize = { width = 700, height = 800 },
  },
}
