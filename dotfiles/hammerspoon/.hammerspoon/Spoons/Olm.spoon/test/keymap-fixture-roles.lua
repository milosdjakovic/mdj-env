-- The window role moved to Super and nothing else, proved offline.
--
-- test/keys.sh --fixture keymap-fixture-roles records what the binder bound with this table as
-- cfg.keymap. Every window binding sits on Super and no row uses Meta, so the remap line names
-- HYPER and SUPER and not META, which is Right Option freed and Right Command claimed.
return {
  roles = {
    window = "super",
  },
}
