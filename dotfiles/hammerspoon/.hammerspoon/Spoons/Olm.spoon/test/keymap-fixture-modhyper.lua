-- Hyper as the four real modifiers, proved offline.
--
-- test/keys.sh --fixture keymap-fixture-modhyper records what the binder bound with this table as
-- cfg.keymap, and test/views.sh --fixture keymap-fixture-modhyper the launcher rows and sheets. This
-- is the Karabiner case, Hyper made by something outside Olm and arriving as Shift, Control, Option
-- and Command together, so the leader is a set of modifiers and Caps Lock is left alone.
--
-- Every app toggle and every other Hyper row is bound through hs.hotkey on the four modifiers
-- and the key, so the golden shows each of them. Every list key rides Hyper as a default, and since
-- Hyper holds no physical key here each is a field key of the open list, written as a field line
-- with the whole combination it is pressed with, the launcher's close on Space among them. Meta stays on
-- Right Option, remapped to F16, and no row uses Caps Lock, so the remap line names META alone.
-- The behaviour Hyper ships, ranking and a sheet, stays on the leader, and the sheet is not drawn
-- yet for a leader of modifiers.
--
-- The keys section is empty here, so the toggles config/keymap.lua holds are absent, the same as
-- in keymap-fixture.lua.
return {
  leaders = {
    hyper = { mods = { "shift", "ctrl", "alt", "cmd" } },
  },
}
