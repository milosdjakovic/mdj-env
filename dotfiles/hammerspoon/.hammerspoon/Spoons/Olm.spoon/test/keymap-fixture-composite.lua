-- Hyper and META on a held key and on modifiers at once, proved offline.
--
-- This is how both ship since phase 1 of docs/PLAN-MACHINES.md, written out in the triggers form a
-- person may use, so the golden is the shipped composite as the root builds it. goldens.sh records
-- it with DRYGATE_CLAIMS=1, and to write the golden again run
--   DRYGATE_CLAIMS=1 test/keys.sh --fixture keymap-fixture-composite --update
--
--   Every Hyper and META row is bound on its leader exactly as with one held key each, and the
--   remap line names HYPER and META, so Caps Lock and Right Option are still remapped to F18 and F16.
--   The claim lines after it are the modifier halves, one per key and combination, each Hyper key
--   claimed on shift, ctrl, alt and cmd and each META key on shift, ctrl and alt. A Hyper row asking
--   for shift or cmd beside the four is left to the held key and adds no claim of its own. Without
--   the claim lines the golden is line for line what an empty keymap binds, so nothing else moved.
--
-- The keys section is empty here, so the toggles config/keymap.lua holds are absent, the same as
-- in keymap-fixture.lua.
return {
  leaders = {
    hyper = { triggers = { { key = "capsLock" }, { mods = { "shift", "ctrl", "alt", "cmd" } } } },
    meta = { triggers = { { key = "rightOption" }, { mods = { "shift", "ctrl", "alt" } } } },
  },
}
