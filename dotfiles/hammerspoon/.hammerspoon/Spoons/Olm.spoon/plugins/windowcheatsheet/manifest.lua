-- WindowCheatSheet, what it declares about itself.
--
-- A content builder only, triggered by holding a window leader, so it has no chooser, no
-- key, and no alias of its own. The one real capability is the shared overlay renderer
-- every cheat sheet draws through, which is why this plugin is nearly, but not entirely,
-- empty.
--
-- The windowManagement list, the per leader section title, and the predicate table are all
-- root policy, so they earn needs.data rather than needs.siblings. A sibling need naming
-- windowmanager was considered first and set aside. WindowManager exposes no member that IS
-- this list, bindToLeader receives it as a plain wiring argument rather than storing it on
-- itself, so there is nothing on the real module for a sibling to point at. Naming the module
-- itself, with no member, would say this plugin calls something on WindowManager, and it
-- never does, it only needs to be handed the same table.
return {
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
      -- The composition root builds this once, WindowManager's own windowManagement default
      -- merged with the user's override and stamped with the resolved window leader keycode,
      -- and hands the identical table to WindowManager's bindToLeader and to this plugin's
      -- configure. Root computed, required, since an absent list leaves the row model empty
      -- for every leader.
      --
      -- What this field cannot say is the one fact that actually matters, that WindowManager
      -- and this plugin must receive the SAME table rather than two copies that happen to
      -- agree today. needs.data only proves a value arrived, never that it is the identical
      -- object a sibling was also handed, and nothing else in this schema says it either.
      windowManagement = { source = "root", policy = "required",
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
