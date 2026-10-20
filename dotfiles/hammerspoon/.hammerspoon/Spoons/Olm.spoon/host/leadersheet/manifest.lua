-- LeaderSheet, what it declares about itself.
--
-- A content builder only, triggered by holding a leader, so it has no chooser, no key, and no
-- alias of its own. The one real capability is the shared overlay renderer every cheat sheet
-- draws through, which is why this host is nearly, but not entirely, empty.
--
-- It is one host for every held leader since phase 4 of the keymap plan, where there used to be
-- one for the Hyper leader and one for the window leader. What it draws for a leader is not any
-- plugin's data. It is the rows the keymap holds on that leader and the sections plugins
-- contribute for the leader's role, both of which the root assembles, so the host names no leader
-- and no plugin, and a leader gets a sheet by stating one in its policy.
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

    -- Every plugin that adds sections to a leader's sheet. A contributor answers them from its
    -- own cheatSheetSections member, built from its own data, and states the role they belong
    -- to as defaults.leader, so only the ones on a leader's role reach that leader's sheet.
    -- Asking the set is what lets the app toggles appear on the Hyper sheet while this host
    -- names no plugin and reads no plugin's data.
    set = {
      cheatSheetSections = { provides = { "cheatSheetSections" } },
    },

    data = {
      -- The leaders that show a sheet, each with its keycode, its layout from the leader's
      -- policy and the ordered entries for it, which are the leader's own rows from the keymap
      -- and one supplier per plugin answering the set above, each placed by its cheatSheetOrder.
      -- Root computed, since only the root may resolve a member on another plugin's module and
      -- only the root knows what it bound and what each leader's policy says. Delivered in the
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
    -- Where a leader's own block, every chord bound on that leader, sits among the sections
    -- plugins contribute, a number compared with each contributor's own cheatSheetOrder. Fifty
    -- follows the app toggles at ten, the order the Hyper sheet has always had.
    cheatSheetOrder = 50,
  },
}
