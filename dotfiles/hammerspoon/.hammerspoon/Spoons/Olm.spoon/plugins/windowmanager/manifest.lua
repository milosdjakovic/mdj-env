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
}
