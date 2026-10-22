-- A pedal on F13 and Caps Lock pinned to F19, proved offline.
--
-- test/keys.sh --fixture keymap-fixture-heldkeys records what the binder bound with this table as
-- cfg.keymap. A foot pedal sends F13 from its own firmware, and Olm hears it as it is, so the
-- remap line names HYPER and not PEDAL, a key that needs no remap is no row. Hyper is pinned
-- with remapTo to F19 in place of its F18, which the line cannot show, since it names the leaders
-- remapped and not the function key each goes to. test/keyremap.lua pins the command that carries
-- the key, and this fixture pins which leaders reach it.
--
--   pedal takes the clipboard on P, so the pedal is in use beside Hyper and Meta, which still hold
--   every app, list and window key they always had. The remap line reads HYPER and META and never
--   PEDAL.
return {
  keys = {
    ["pedal+P"] = "clipboard.open",
  },
  leaders = {
    pedal = { key = "f13" },
    hyper = { key = "capsLock", remapTo = "f19" },
  },
}
