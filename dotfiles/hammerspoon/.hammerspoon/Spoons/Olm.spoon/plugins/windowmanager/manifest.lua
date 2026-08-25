-- WindowManager, what it declares about itself.
--
-- Window positioning and sizing operations only, taking its margins and its settings block
-- as plain policy data through configure, so neither is a declared need.
--
-- Its sixteen bindings hang off the WINDOW leader rather than the app leader, and every one
-- of them, resize, move, center, maximize, and the display switch pair, depends on nothing
-- local, they behave identically on every Mac. That is the test a default has to pass, and
-- it is why they belong here even though AppToggler's per app toggles do not, those need to
-- know which apps are installed and these need nothing. The order below is copied exactly
-- as config/keys.lua has it, since it matches the cheat sheet grid, two switch display rows
-- gated on multiple displays, then resize, then move and center, then hide all last.
return {
  needs = {
    -- bindToLeader hands this plugin a WindowLeader instance directly as an argument,
    -- outside configure, so this coupling would otherwise never appear in a manifest built
    -- only from configure calls. It is declared anyway, because the wiring order is
    -- computed off needs.siblings regardless of which method delivers the collaborator, and
    -- an undeclared one here would let the loader configure WindowManager before
    -- WindowLeader exists with nothing to warn about it. Required, since none of the
    -- sixteen bindings above bind to anything without a leader to bind into.
    --
    -- No member. bindToLeader calls windowLeader:bind(...) on the collaborator itself, the
    -- WindowLeader MODULE, never one method pulled off it in isolation, so leader must
    -- resolve to the module or it resolves to the bare colon method with no self bound,
    -- which fails on arity rather than failing cleanly the moment a key is pressed.
    siblings = {
      leader = { plugin = "windowleader", policy = "required" },
    },

    -- bindToLeader's own second and third arguments, just as load bearing as the leader
    -- itself, and configure's own two fields. None of the four has anywhere else to live.
    data = {
      -- The stamped windowManagement list, the sixteen entries above merged with any user
      -- override and stamped with the resolved window leader keycode by the composition
      -- root. Root computed, and the exact same stamped table WindowCheatSheet must also
      -- receive, though nothing here, or in WindowCheatSheet's own manifest, can assert
      -- that the two consumers are handed the identical table rather than two separately
      -- stamped copies that happen to agree today.
      mapping = { source = "root", policy = "required",
                  breaks = "bindToLeader runs over an empty list, so not one of the sixteen window actions binds to any key, holding the window leader does nothing at all" },
      -- The shared when name to predicate function table, gating previousDisplay and
      -- nextDisplay on multipleDisplays. Root computed. Optional, since an absent or
      -- unknown name is treated as always active by bindToLeader's own fallback, the same
      -- rule the overlay applies, so the gate is lost rather than the binding.
      predicates = { source = "root", policy = "optional",
                     breaks = "previousDisplay and nextDisplay bind unconditionally instead of hiding on a single screen, so a lone display still shows two display switch keys that do nothing useful" },
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
  -- Every one of the three positional values, the sibling and the two data entries above, is
  -- something the composition root resolved rather than something declared on this plugin's
  -- own defaults, so all three read from the root namespace.
  wiring = {
    { method = "bindToLeader", args = { "root.leader", "root.mapping", "root.predicates" } },
  },

  -- The launcher narrows its own catalog into a window actions group by asking this plugin
  -- for its action map directly, rather than keeping a second copy of it.
  provides = {
    actions = "actions",
  },

  defaults = {
    leader = "window",
    windowManagement = {
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
