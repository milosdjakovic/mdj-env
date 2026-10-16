-- WindowManager, what it declares about itself.
--
-- Window positioning and sizing operations only, taking its margins and its settings block
-- as plain policy data through configure, so neither is a declared need.
--
-- Six of the sixteen carry `repeats`, the four moves and the two resize steps, since each of
-- those is a STEP and a person placing a window by eye wants several of them without pressing
-- the key several times. The other ten are placements, so holding one would put the window
-- where it already is, again. How that repeat is timed is not decided here, the window leader
-- answers it once for every key under it and takes the answer off the machine, which is why an
-- entry says only that it repeats and never how often.
--
-- Its sixteen bindings hang off the WINDOW leader rather than the app leader, and every one
-- of them, resize, move, center, maximize, and the display switch pair, depends on nothing
-- local, they behave identically on every Mac. That is the test a default has to pass, and
-- it is why they belong here even though AppToggler's per app toggles do not, those need to
-- know which apps are installed and these need nothing. The order below is copied exactly
-- as config/keys.lua once had it, since it matches the cheat sheet grid, two switch display rows
-- gated on multiple displays, then resize, then move and center, then hide all last.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Window Manager",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  -- The one icon every window action's launcher row wears, the chord in the subtitle telling
  -- the rows apart. It was the launcher's own icon while the launcher built these rows from
  -- this plugin's action map, and it moved here with the rows in phase three of the core
  -- split, drawn identically in both sets, so the picture is unchanged and only the manifest
  -- it is read from differs.
  icons = {
    windows = { emoji = "🪟", sf = "macwindow" },
  },

  needs = {
    -- The window leader is core, a lib like Hyper, and a plugin that declares leader = "window"
    -- binds onto it through the grant below with no keycode in sight, the way capture binds
    -- onto Hyper. The grant is the whole module rather than one member, because bindToLeader
    -- calls windowLeader:bind(...) on it as a colon method. Required, since none of the
    -- sixteen bindings below bind to anything without a leader to bind into.
    lib = {
      windowLeader = { from = "windowleader", policy = "required" },
    },

    data = {
      -- The when name to predicate table is not declared here any more. The window leader lib
      -- owns the gate, like Hyper, and the root hands it the table when it configures it, so
      -- this plugin only says which name a binding carries.
      -- configure's own margins, config/settings.lua's gap on all four sides. The person's
      -- own preference, and configure already treats an absent one as {}, so it degrades
      -- rather than breaks.
      margins = { source = "user", policy = "optional",
                  breaks = "every window still sizes and moves the same way, sitting flush to the " ..
                           "screen edge exactly as the shipped default gap already does, and only " ..
                           "loses the person's own wider gap if they set one in settings" },
      -- configure's own settings block, animation duration, resize pixel step, and every
      -- named window size. The person's own tuning, and configure already treats an absent
      -- one as {}, falling back to this plugin's own hardcoded numbers.
      settings = { source = "user", policy = "optional",
                   breaks = "window animation duration, the resize step, and every named window " ..
                            "size run fine on this plugin's own shipped defaults, and only ignore " ..
                            "the person's own tuning if they set one in settings" },
    },
  },

  -- bindToLeader is a second call beyond configure, so it is named here rather than assumed.
  -- The leader is the lib grant above and the bindings are this plugin's own effective list,
  -- after any override, which is the same shape capture's bindHotkeys takes. A binding's
  -- `when` and `repeats` travel to the lib through its bind options. The root reads the same
  -- effective list by walking the plan for every plugin on the window leader, so the cheat
  -- sheet shows what is bound without ever naming this plugin, and launcherRows below builds
  -- the launcher's rows from the same list.
  wiring = {
    { method = "bindToLeader", args = { "self.windowLeader", "self.bindings" } },
  },

  -- actions is the action name to handler map the window leader binds from. launcherRows is
  -- one launcher row per bound action, built from the same effective bindings, and
  -- launcherRun runs a chosen row's action once the launcher has closed. The launcher asks
  -- the set for both rather than naming this plugin, and its window scope narrows its own
  -- catalog to these rows by their kind.
  provides = {
    actions = "actions",
    launcherRows = "launcherRows",
    launcherRun = "launcherRun",
  },

  defaults = {
    leader = "window",
    -- Where the window action rows sit in the launcher's own catalog, a number compared with
    -- every other contributor's and with the launcher's own. Forty puts them after the
    -- launcher's own rows and before the System Settings panes, where they have always been.
    launcherOrder = 40,
    bindings = {
      -- Switch display (first row, hidden on a single display by the predicate)
      { action = "previousDisplay",      key = ",", when = "multipleDisplays" },
      { action = "nextDisplay",          key = ".", when = "multipleDisplays" },
      -- Resize (bare key)
      { action = "leftHalf",             key = "left" },
      { action = "rightHalf",            key = "right" },
      { action = "fullHeight",           key = "up" },
      { action = "reasonableSize",       key = "down" },
      { action = "maximize",             key = "return" },
      { action = "smallSize",            key = "Z" },
      { action = "increaseSize",         key = "=", repeats = true },
      { action = "decreaseSize",         key = "-", repeats = true },
      -- Move (WASD) and center
      { action = "moveLeft",             key = "a", repeats = true },
      { action = "moveRight",            key = "d", repeats = true },
      { action = "moveUp",               key = "w", repeats = true },
      { action = "moveDown",             key = "s", repeats = true },
      { action = "center",               key = "C" },
      -- Hide all except the focused window (kept last so it sits in the last row)
      { action = "hideAllExceptFocused", key = "H" },
    },
  },
}
