-- Arithmetic, what it declares about itself.
--
-- A launcher query row source rather than a picker of its own, so it owns no chooser, no
-- key, and no alias. It evaluates arithmetic with native Lua alone, so it needs nothing
-- from outside Hammerspoon and declares no tool, which is the whole point of keeping it
-- apart from conversion. Being a computed row rather than a bound shortcut also means
-- neither discoverability mandate applies to it, it is found only by typing an expression.
return {
  -- What the launcher may reach for a typed expression. Named queryRows rather than rows,
  -- because rows and select together mean a scopable tool, one whose whole list a typed
  -- alias can hand the launcher, and arithmetic is the opposite of that, it computes at most
  -- one row from what was typed and claims nothing else. The two roles need two names or a
  -- calculator answering the scope query would read as a browsable list and swallow the
  -- launcher catalog. There is no select to expose either way, a chosen row's value goes
  -- straight to the launcher's own injected copy action, since arithmetic has nothing
  -- further to do with a result once it is shown.
  provides = {
    queryRows = "rows",
  },

  -- The glyph and the subtitle wording this plugin proposes for its own row, read by
  -- whatever presents it. Neither is a key or an alias, since a computed row has none.
  defaults = {
    glyph = "🧮",
    category = "Arithmetic",

    -- Short lines for the launcher's empty field, a list rather than the one line this used
    -- to be, proposed here rather than written into the launcher, since a list of what the
    -- computed sources can do, kept anywhere but beside the source itself, is a roster that
    -- goes stale the day one of them changes. Each is a whole sentence rather than only the
    -- expression, for the same reason category is a whole word here, this plugin owns its
    -- own wording and whoever shows it decides nothing about how it reads. Short enough for
    -- the field, which holds about twenty eight characters. Both lines were checked against
    -- this plugin's own grammar and whitelist above before they shipped, a plain product and
    -- an exponent, so the field never invites a person to type something this parser refuses.
    example = { "Try 128 * 4", "Try 2^10" },
  },
}
