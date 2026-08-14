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

  -- Gap around and between managed windows, in pixels. One value drives both the
  -- outer inset (the margins in init.lua) and the gutter between tiled halves, so
  -- the spacing stays uniform. Set to 0 to disable gaps entirely (windows go
  -- flush to the screen edges and to each other).
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

  -- Window layout memory. Records every standard window's frame per display
  -- configuration and restores it automatically on docking, undocking, and waking.
  -- tolerance is the pixel slack for the compare and skip guard, so a one or two pixel
  -- nudge from an app snapping a window is not mistaken for a real move. The settle
  -- timing is shared with DisplayProfiles (displays.settleDelay), so both coalesce the
  -- same screen event burst, and the spoon adds its own small margin so frames are
  -- restored only after the display geometry has been reapplied.
  windowMemory = {
    tolerance = 5,
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

  -- What physically means Hyper. Pure data, and the one place a person whose keyboard is not
  -- this one says so. Two shapes, and they are genuinely different inputs rather than two
  -- spellings of one, so each is named by a kind and the mechanism behind it is not decided
  -- here at all.
  --
  -- { kind = "leader" } is a single physical key held down, which is what this machine uses.
  -- The key itself is deliberately not named here, it is the appLeader row of the catalog in
  -- config/keys.lua, remapped at the HID level, and only the composition root reads that
  -- catalog. Hold it and press a letter to fire a binding, tap it alone to toggle real Caps
  -- Lock, hold it alone to reveal the cheat sheet.
  --
  -- { kind = "chord", mods = { "shift", "ctrl", "alt", "cmd" } } is a modifier chord held
  -- together, any subset of those four and at least one of them. Every binding declared
  -- against Hyper is claimed on the chord plus whatever sub modifiers that binding already
  -- declared, and holding the chord alone still reveals the cheat sheet after the same delay.
  --
  -- FOUR WAYS THE CHORD SHAPE IS NOT THE LEADER SHAPE, worth reading before choosing it, since
  -- none of them is a defect waiting to be fixed. They all follow from a chord being a flag on
  -- somebody else's event where a key is an event of its own.
  --
  -- A binding declaring sub modifiers does work, because the chord is taken back out of what
  -- is held before any binding is matched, so a second tier key means the same thing under
  -- either shape. But a binding whose sub modifiers overlap the chord does not work at all. It
  -- collapses onto the base combination, the two become one physical thing to press, and the
  -- plain binding is the one that answers. Nothing can repair that, so it is named in the
  -- console once at load, and leaving shift out of the chord is how you keep a shift tier.
  --
  -- A combination that IS bound is claimed machine wide, so it is swallowed even at a moment
  -- when every binding on it is gated shut by live state. The leader shape leaks such a combo
  -- downstream to other apps instead. A combination nothing binds is left alone either way,
  -- and under the chord shape it also runs no code here at all, so it cannot end a hold.
  --
  -- There is no tap, since a chord has no bare press and release to measure, so real Caps Lock
  -- stays whatever the system makes of it.
  --
  -- The root reads this block and hands the hyperkey lib a finished descriptor, and that lib
  -- owns one strategy per kind. So a third shape would be a strategy there plus a kind here,
  -- and nothing in between would move. A kind nothing answers to, or a chord naming no
  -- modifiers at all, falls back to the leader shape and says so in the console rather than
  -- claiming the whole keyboard.
  hyperTrigger = {
    kind = "leader",
    -- kind = "chord", mods = { "shift", "ctrl", "alt", "cmd" },
  },

  -- The default activation list for the tool registry, phase seven of the build plan.
  -- Every tool named here is what the composition root registers and, absent an
  -- override, activates, so this file is what keeps a fresh machine's behaviour
  -- identical to before the registry existed. The hs.settings key registryActivation
  -- overrides this list when it holds one, and is the door a future roster will write
  -- through, nothing writes it yet. menuSearch joined the other eleven in phase seven's
  -- fourth packet, the twelfth tool the registry knows and the one step easiest to miss
  -- when folding a new tool in, since a registered tool absent from this list is
  -- inactive, and an inactive tool answers nil to surfaceFor, rowFor, and scopeFor alike
  -- with nothing failing loudly.
  toolActivation = {
    "clipboard", "caffeinate", "vpn", "colorPicker", "emoji", "dockAutoHide",
    "displayProfiles", "textCase", "browserTabs", "processes", "fileSearch", "menuSearch",
    "tmuxSessions",
  },

  -- Screen capture priority. An ordered list of Capture provider names, tried front
  -- to back, so the first one that supports the action and is usable right now handles
  -- it. This is the whole of the chain order, pure data, and the composition root is
  -- still the only place a name becomes a concrete provider, the same shape the overlay
  -- display modes and the tool roster above already use. So reordering the chain, or
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
  -- regenerable data, safe to delete since it only costs a rebuild. olmRoot
  -- holds durable data, visible in the home directory since deleting it
  -- loses something. Changing either is one line here, since the root is
  -- the only place either name is written.
  paths = {
    cacheRoot = "~/.cache/hammerspoon",
    olmRoot = "~/Olm",
  },
}
