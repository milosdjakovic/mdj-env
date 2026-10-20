-- LeaderSheet, what it declares about itself.
--
-- A content builder only, triggered by holding a leader, so it has no chooser, no key, and no
-- alias of its own. The one real capability is the shared overlay renderer every cheat sheet
-- draws through, which is why this host is nearly, but not entirely, empty.
--
-- It is one host for every held leader since phase 4 of the keymap plan, where there used to be
-- one for the Hyper leader and one for the window leader. What it draws for a leader is not any
-- plugin's data. It is the rows the keymap holds on that leader, each filed under the group its
-- action's descriptor names, which the root assembles, so the host names no leader and no plugin,
-- and a leader gets a sheet by stating one in its policy. Since phase 6 no plugin supplies a
-- section of its own, the app toggler's running and not running split being two groups its
-- descriptors answer.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Leader Sheet",
    author = "Milos Djakovic",
    version = "1.0",
    license = "MIT",
  },

  needs = {
    -- Drawing is delegated entirely to the shared grid renderer, this host only builds the row
    -- model. Required, since this host is only a front end onto the renderer and has nothing to
    -- draw without it, so a missing one should refuse to wire rather than sit there silently
    -- doing nothing on every hold.
    lib = {
      cheatSheet = { from = "cheatsheet", policy = "required" },
    },

    data = {
      -- The leaders that show a sheet, each with its keycode, its layout from the leader's
      -- policy and the ordered entries for it, which are the leader's rows from the keymap in
      -- blocks placed by each owner's cheatSheetOrder. Root computed, since only the root knows
      -- what it bound and what each leader's policy says. Delivered in the
      -- root's second configure, once the keymap exists. Required, since an absent list leaves
      -- the host with no sheet for any leader.
      sheets = { source = "root", policy = "required",
        breaks = "holding a leader shows nothing at all, since the host has no sheet for any leader" },
      -- The shared predicate registry, gating a row on a live condition such as more than one
      -- display. Root computed, optional, since an absent or unknown name is treated as active
      -- by this host's own fallback, the same rule the key dispatch already applies.
      predicates = { source = "root", policy = "optional",
        breaks = "a row gated on a condition shows on the sheet even while its key is gated off, instead of being hidden the way the live key dispatch already hides it" },
    },
  },

  defaults = {
    -- Where the rows of a plugin that states no cheatSheetOrder sit on a leader's sheet, a number
    -- compared with each plugin's own cheatSheetOrder. Fifty follows the app toggles at ten, the
    -- order the Hyper sheet has always had.
    cheatSheetOrder = 50,
  },
}
