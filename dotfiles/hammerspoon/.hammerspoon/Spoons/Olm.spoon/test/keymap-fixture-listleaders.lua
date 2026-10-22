-- List keys written on several leaders, proved offline.
--
-- test/keys.sh --fixture keymap-fixture-listleaders records what the binder bound with this table
-- as cfg.keymap. A list chord names its own leader as a global chord does, so each entry lands on
-- the leader it names and every other list key stays on the list role's leader, Hyper.
--
--   all moves selectNext from Hyper and J to Meta and N in every list whose J came from Olm's own
--   all layer, so Meta is in use for list keys alone beside its window keys.
--   The clipboard's own table puts deleteSelected on Super and E, which is the one row that puts
--   Super in use, so the remap line names SUPER as well. It also puts selectPrev on nav and K,
--   nav being Shift and Ctrl named as a leader, and the launcher's table puts selectNext on Ctrl
--   and J, a combination of modifiers alone. Neither opens with a held leader, so neither binds
--   on one. Since phase B of the list keys addendum both belong to the default chooser's own field
--   while their list is up, written as field lines with the whole combination each is pressed
--   with, and the launcher's own selectNext entry keeps all's Meta and N out of the launcher.
--   The launcher's close moves from Space to Meta and C by the shared verb's name, close.
--
-- The keys section is empty here, so the toggles config/keymap.lua holds are absent, the same as
-- in keymap-fixture.lua.
return {
  leaders = {
    nav = { "shift", "ctrl" },
  },
  lists = {
    all = {
      ["meta+n"] = "selectNext",
    },
    clipboard = {
      ["super+e"] = "deleteSelected",
      ["nav+k"] = "selectPrev",
    },
    launcher = {
      ["ctrl+j"] = "selectNext",
      ["meta+c"] = "close",
    },
  },
}
