-- A person's keymap, the case the keymap plan was written for, proved offline.
--
-- test/keys.sh --fixture keymap-fixture hands this table to Olm as cfg.keymap in place of
-- config/keymap.lua and records what the binder bound, and views.sh --fixture keymap-fixture
-- writes the launcher rows and the sheets it leads to. Each is diffed against its committed
-- golden beside this file. What it proves, read off those goldens.
--
--   vpn leaves Hyper and P for Meta and E, and the clipboard leaves Hyper and X for Meta and Y,
--   each keeping every gate and label it had.
--   A leader named from Shift and Control takes Tmux Manager on T, claimed as that combination.
--   Hyper and 3 is freed, so OCR keeps its launcher row and loses its chord.
--   The window role moves to Super, so every window binding sits on Super and the window sheet is
--   Super's. Meta stays remapped, since Meta and E and Meta and Y still use it, which
--   keymap-fixture-roles.lua, the roles alone, shows freeing it.
--   The VPN's aliases are the three words below in place of its own.
return {
  keys = {
    ["meta+E"] = "vpn.open",
    ["meta+Y"] = "clipboard.open",
    ["nav+T"] = "tmuxSessions.open",
    ["hyper+3"] = false,
  },
  leaders = {
    nav = { "shift", "ctrl" },
  },
  roles = {
    window = "super",
  },
  aliases = {
    vpn = { "v", "vpn", "tunnel" },
  },
}
