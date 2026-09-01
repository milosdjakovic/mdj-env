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

return {
  overlayModes = overlayModes,

  -- Gap around and between managed windows, in pixels. One value drives both the
  -- outer inset (the margins in init.lua) and the gutter between tiled halves, so
  -- the spacing stays uniform. Set to 0 to disable gaps entirely (windows go
  -- flush to the screen edges and to each other).
  gap = 0,

  -- Window animation (0 = instant)
  windowAnimationDuration = 0,

  -- A terminal block used to sit here, the timing and the size and padding the retired
  -- TerminalHandler spoon read. AppToggler owns the behaviour now, through the placement
  -- field the Ghostty entry in config/keys.lua's appToggles carries, and the timing that
  -- block held is internal to that plugin, nobody has ever tuned it.

  -- A windowMemory block used to sit here, holding the pixel tolerance for the retired
  -- WindowMemory plugin. Nothing ever passed it through, so it was already dead, and the
  -- plugin it named is gone. Workspaces owns that behaviour now and carries its own tuning
  -- inside its engine, which is where a constant nobody has ever wanted to change belongs.

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
  -- on, every chooser, its docked shortcut panel, both cheat sheets, and the colour
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

  -- Shortcut hint panel. The docked bar that spells out the Hyper navigation shortcuts
  -- under a list, the clipboard, menu search, VPN, keep awake, the launcher and every
  -- plugin that earns one.
  --
  -- delayMs is an IDLE delay, not a delay from opening. The bar stays hidden while the
  -- field is being used, the countdown restarts on every keypress, and only after this
  -- many milliseconds with no key does it reveal, staying up until the list closes. Zero
  -- draws it instantly on open.
  --
  -- Olm ships three seconds, so this is an OVERRIDE POINT and is deliberately absent
  -- rather than empty. The number used to live here and nowhere else, this comment used to
  -- call itself the one source for every chooser that docks the panel, and init.lua never
  -- forwarded the field into Olm's policy, so nothing ever read it and every bar drew
  -- instantly. Restating the shipped number here would put it back in two places, which is
  -- how that drift started.
  --
  -- Absent rather than an empty table on purpose, and this is not a style choice.
  -- lib/defaults.lua's own merge treats a table with no keys as a LIST, and a list REPLACES
  -- the default instead of merging into it, so writing `shortcutsPanel = {}` here would wipe
  -- the shipped three seconds and put every bar back to drawing instantly, with the config
  -- still looking like it said nothing at all. To differ from what Olm ships, uncomment the
  -- whole block below with a real value in it.
  --
  -- shortcutsPanel = { delayMs = 3000 },

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
