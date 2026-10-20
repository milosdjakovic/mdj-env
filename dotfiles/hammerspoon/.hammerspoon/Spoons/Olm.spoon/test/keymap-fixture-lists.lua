-- A person's lists section, the keys live while a list is open, proved offline.
--
-- test/keys.sh --fixture keymap-fixture-lists hands this table to Olm as cfg.keymap in place of
-- config/keymap.lua and records what the binder bound, diffed against the golden beside this file.
-- config/keymap.lua itself ships no lists entry, since this machine moves no list key, so this is
-- where the layer is shown working through the real root. What it proves, read off the golden.
--
--   all moves selectNext from Hyper and J to Hyper and N in every list that moves at all, so no
--   list binds a bare J any more, while the clipboard's and file search's Command and J stay.
--   The clipboard's own table moves Delete from D to E, a chord the global layer gives menu
--   search, which a list key may shadow while its list is open, and puts selectPrev on A, which
--   takes the slot from Append to batch, so A is the clipboard's still and K is free there.
--   File search frees Y, so Copy path has no key and keeps its row in the action panel only
--   where a key reaches it, which is nowhere.
--   The launcher's close moves from Space to C by the shared verb's name, close.
--
-- The keys section is empty here, so the toggles config/keymap.lua holds are absent, the same as
-- in keymap-fixture.lua.
return {
  lists = {
    all = {
      ["hyper+n"] = "selectNext",
    },
    clipboard = {
      ["hyper+e"] = "deleteSelected",
      ["hyper+a"] = "selectPrev",
    },
    fileSearch = {
      ["hyper+y"] = false,
    },
    launcher = {
      ["hyper+c"] = "close",
    },
  },
}
