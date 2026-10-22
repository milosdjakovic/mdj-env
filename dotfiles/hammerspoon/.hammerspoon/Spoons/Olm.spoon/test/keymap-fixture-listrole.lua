-- The list role moved to Meta and nothing else, proved offline.
--
-- test/keys.sh --fixture keymap-fixture-listrole records what the binder bound with this table as
-- cfg.keymap. Every default list key, Olm's own all layer and every manifest's surface keys, rides
-- the list role, so each one sits on Meta while its list is open, and no list key is left on Hyper.
-- The global keys stay where they were, Hyper still holds the app role and Meta the window role,
-- so the remap line still names HYPER and META. A list key on Meta beside a window key on the same
-- chord, Meta and A in the clipboard beside Meta and A for a window move, is the shadowing a list
-- key may do on purpose, so neither is a collision.
return {
  roles = {
    list = "meta",
  },
}
