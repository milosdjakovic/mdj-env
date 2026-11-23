-- WindowManager, what it declares about itself.
--
-- Window positioning and sizing operations only, taking its margins and its settings block
-- as plain policy data through configure, so neither is a declared need.
--
-- Six of the sixteen actions repeat, the four moves and the two resize steps, since each of
-- those is a STEP and a person placing a window by eye wants several of them without pressing
-- the key several times. The other ten are placements, so holding one would put the window
-- where it already is, again. That is a fact about the action, so its descriptor in init.lua
-- says it, together with the gate on the two display switches, and a binding below is only an
-- action and a key. How the repeat is timed is not decided here either, the window leader
-- answers it once for every key under it, which is why an action says only that it repeats.
--
-- Its sixteen bindings hang off the WINDOW leader rather than the app leader, and every one
-- of them, resize, move, center, maximize, and the display switch pair, depends on nothing
-- local, they behave identically on every Mac. That is the test a default has to pass, and
-- it is why they belong here even though AppToggler's per app keys do not, those need to
-- know which apps are installed and these need nothing. The order below is copied exactly
-- as the retired config/keys.lua once had it, since it matches the cheat sheet grid, two switch display rows
-- gated on multiple displays, then resize, then move and center, then hide all last, and the
-- descriptor list in init.lua keeps the same order for the launcher's rows.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Window Manager",
    description = "Move, resize and send the focused window between halves and displays.",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  -- The one icon every window action's launcher row wears, the chord in the subtitle telling
  -- the rows apart. It was the launcher's own icon while the launcher built these rows from
  -- this plugin's action map, and it moved here with the rows in phase three of the core
  -- split. Each descriptor names it, and Olm builds the row.
  icons = {
    windows = { emoji = "🪟", sf = "macwindow" },
  },

  needs = {
    data = {
      -- The when name to predicate table is not declared here any more. The window leader lib
      -- owns the gate, like Hyper, and the root hands it the table when it configures it, so
      -- this plugin only says which name a binding carries.
      -- configure's own margins, the screen insets, stated only to differ from the gap, which
      -- insets every side when none is stated.
      margins = { source = "user", policy = "optional",
                  breaks = "every side of the screen is inset by the gap in Olm Settings, as it is " ..
                           "with no margins stated" },
      -- configure's own settings block, animation duration, resize pixel step, and every
      -- named window size. The person's own tuning, and configure already treats an absent
      -- one as {}, falling back to this plugin's own hardcoded numbers.
      settings = { source = "user", policy = "optional",
                   breaks = "window animation duration, the resize step, and every named window " ..
                            "size run fine on this plugin's own shipped defaults, and only ignore " ..
                            "the person's own tuning if they set one in settings" },
      notify = { source = "root", policy = "optional",
        breaks = "a resize asked for with no window focused does nothing and says nothing, so it " ..
                 "reads as a key that is broken" },
    },
  },

  -- actions answers one descriptor per window action, and Olm binds each binding below on the
  -- window leader to the descriptor its action names, the descriptor's gate and repeat
  -- travelling with it, so this plugin binds nothing and needs no leader of its own. The window
  -- sheet reads the keymap's rows on the window leader, so it shows what is bound without ever
  -- naming this plugin, and the launcher lists every listed action as a row of its own catalog,
  -- built by Olm from the descriptor and the keymap, which its window scope narrows by kind.
  provides = {
    actions = "actions",
  },

  defaults = {
    leader = "window",
    -- Where the window action rows sit in the launcher's own catalog, a number compared with
    -- every other contributor's and with the launcher's own. Forty puts them after the
    -- launcher's own rows and before the System Settings panes, where they have always been.
    launcherOrder = 40,
    bindings = {
      -- Switch display (first row, hidden on a single display by the predicate)
      { action = "previousDisplay",      key = "," },
      { action = "nextDisplay",          key = "." },
      -- Resize (bare key)
      { action = "leftHalf",             key = "left" },
      { action = "rightHalf",            key = "right" },
      { action = "fullHeight",           key = "up" },
      { action = "reasonableSize",       key = "down" },
      { action = "maximize",             key = "return" },
      { action = "smallSize",            key = "Z" },
      { action = "increaseSize",         key = "=" },
      { action = "decreaseSize",         key = "-" },
      -- Move (WASD) and center
      { action = "moveLeft",             key = "a" },
      { action = "moveRight",            key = "d" },
      { action = "moveUp",               key = "w" },
      { action = "moveDown",             key = "s" },
      { action = "center",               key = "C" },
      -- Hide all except the focused window (kept last so it sits in the last row)
      { action = "hideAllExceptFocused", key = "H" },
    },
  },
  -- The gap, steps and sizes, Olm's own settings in Olm Settings under Window Management,
  -- docs/DESIGN-APP-SETTINGS.md S.4, and since 2026-11-23 their only home, config/settings.lua no
  -- longer stating them. Each is a path into this plugin's settings data, filled with the shipped
  -- value and a saved one laid over it before configure, so init.lua reads them with no word of its
  -- own, and the share hands them to Olm.app, step 6.3b.
  --
  -- A move or resize key travels one of two amounts. The step is a press on its own, small since a
  -- press places a window by eye, and the held step each repeat of a held key, where a hold's speed
  -- comes from since the repeat rate is the machine's. The hold grace is how many repeats still
  -- count as a press. A resize step is what the screen's long edge grows by, the short edge taking
  -- its share, so a window grows in the screen's shape and a rotated screen behaves alike. The
  -- smallest width and height are the floor a shrink stops at.
  settings = {
    { key = "gap", at = { "settings", "gap" }, section = "windows",
      title = "Gap", kind = "number", min = 0, max = 100, step = 2, unit = "pixels", shipped = 0,
      keywords = { "margin", "gutter", "spacing", "padding" } },
    { key = "movePixels", at = { "settings", "windowSizing", "movePixels" }, section = "windows",
      title = "Move step", kind = "number", min = 5, max = 200, step = 5, unit = "pixels", shipped = 20,
      keywords = { "nudge", "distance", "arrow" } },
    { key = "movePixelsHeld", at = { "settings", "windowSizing", "movePixelsHeld" }, section = "windows",
      title = "Move step while held", kind = "number", min = 5, max = 400, step = 5, unit = "pixels", shipped = 40,
      keywords = { "nudge", "repeat", "hold" } },
    { key = "resizePixels", at = { "settings", "windowSizing", "resizePixels" }, section = "windows",
      title = "Resize step", kind = "number", min = 5, max = 200, step = 5, unit = "pixels", shipped = 30,
      keywords = { "grow", "shrink", "size" } },
    { key = "resizePixelsHeld", at = { "settings", "windowSizing", "resizePixelsHeld" }, section = "windows",
      title = "Resize step while held", kind = "number", min = 5, max = 400, step = 5, unit = "pixels", shipped = 50,
      keywords = { "grow", "shrink", "repeat", "hold" } },
    { key = "minWidth", at = { "settings", "windowSizing", "minWidth" }, section = "windows",
      title = "Smallest width", kind = "number", min = 100, max = 2000, step = 10, unit = "pixels", shipped = 400,
      keywords = { "minimum", "shrink", "floor" } },
    { key = "minHeight", at = { "settings", "windowSizing", "minHeight" }, section = "windows",
      title = "Smallest height", kind = "number", min = 100, max = 2000, step = 10, unit = "pixels", shipped = 300,
      keywords = { "minimum", "shrink", "floor" } },
    { key = "maxWidth", at = { "settings", "windowSizing", "maxWidth" }, section = "windows",
      title = "Default width", kind = "number", min = 400, max = 8000, step = 50, unit = "pixels", shipped = 2400,
      keywords = { "largest", "maximum", "default size" } },
    { key = "maxHeight", at = { "settings", "windowSizing", "maxHeight" }, section = "windows",
      title = "Default height", kind = "number", min = 300, max = 5000, step = 50, unit = "pixels", shipped = 1350,
      keywords = { "largest", "maximum", "default size" } },
    { key = "fullHeightMaxWidth", at = { "settings", "windowSizing", "fullHeightMaxWidth" }, section = "windows",
      title = "Full height width", kind = "number", min = 400, max = 8000, step = 50, unit = "pixels", shipped = 2400,
      keywords = { "full height", "tall", "column" } },
    { key = "holdGrace", at = { "settings", "windowSizing", "holdGrace" }, section = "windows",
      title = "Small steps before speeding up", kind = "number", min = 1, max = 10, step = 1, unit = "times", shipped = 1,
      detail = "How many presses of a held move or resize key use the step before the held step takes over",
      keywords = { "hold", "repeat", "grace", "speed" } },
    -- The named sizes, each an action, Small and Recording shipped and kept, the rest added on the
    -- Window Management page. A size is points or a share of the screen, stood at one of nine
    -- anchors, on the screen the window is on, the built in one, the first other one or the one
    -- under the pointer. extra hands the page every action with its title, catalog().
    { key = "sizes", at = { "settings", "windowSizes" }, section = "windows", title = "Sizes", kind = "sizes",
      extra = "catalog", keywords = { "size", "preset", "recording", "small" },
      shipped = {
        { id = "small", name = "Small", width = 700, height = 800, unit = "points", anchor = "center", display = "current" },
        { id = "recording", name = "Recording", width = 2400, height = 1350, unit = "points", anchor = "center",
          display = "external" },
      } },
  },
}
