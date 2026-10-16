-- WindowCheatSheet, what it declares about itself.
--
-- A content builder only, triggered by holding the window leader, so it has no chooser, no
-- key, and no alias of its own. The one real capability is the shared overlay renderer every
-- cheat sheet draws through, which is why this host is nearly, but not entirely, empty.
--
-- It is a host rather than a plugin since phase two of the core split. Its rows are not any
-- one plugin's data, they are every binding any plugin declared on the window leader, which
-- the root collects by walking the plan, so they earn a root word rather than a sibling need.
-- Naming windowmanager here was considered and set aside twice. It was a sibling first and a
-- stamped list second, and both said this file depends on one plugin, when it depends on
-- whichever plugins declare leader = "window".
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Window Cheat Sheet",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  needs = {
    -- Drawing is delegated entirely to the shared grid renderer, this spoon only builds the
    -- row model handed to it. Required, because unlike Eyedropper's compiler, which still
    -- leaves a key worth pressing and answers a failed build with an alert, this spoon is
    -- only a front end onto the renderer and has nothing to draw without it, so a missing
    -- one should refuse to wire rather than sit there silently doing nothing on every hold.
    lib = {
      cheatSheet = { from = "cheatsheet", policy = "required" },
    },

    data = {
      -- Every binding declared on the window leader by any plugin, in plan order and then in
      -- each plugin's own order, stamped with the resolved window leader keycode. The root
      -- builds it once and the launcher's window rows read the same list, so the key a row
      -- names and the key the overlay shows come from one answer. Root computed, required,
      -- since an absent list leaves the row model empty for every leader.
      windowBindings = { source = "root", policy = "required",
        breaks = "holding a leader shows nothing at all, since the row model built from an empty list has no group for any leader to show" },
      -- Section titles keyed by leader keycode, read as the overlay heading over that
      -- leader's rows. Root computed, optional, since a missing title only blanks the
      -- heading rather than the rows under it.
      leaders = { source = "root", policy = "optional",
        breaks = "the overlay still shows every row for the leader that is held, but its heading reads blank rather than naming what the leader does" },
      -- The shared predicate registry, gating the display switch rows on multipleDisplays.
      -- Root computed, optional, since an absent or unknown name is treated as active by
      -- this plugin's own fallback, the same rule the key dispatch already applies.
      predicates = { source = "root", policy = "optional",
        breaks = "previousDisplay and nextDisplay show on the overlay even on a single display, instead of being hidden the way the live key dispatch already hides them" },
    },
  },
}
