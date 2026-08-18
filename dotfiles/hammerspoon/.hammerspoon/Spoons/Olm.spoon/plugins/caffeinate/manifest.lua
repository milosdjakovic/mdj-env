-- Caffeinate, what it declares about itself.
--
-- Native Lua over the built in hs.caffeinate api, so it names no external tool and
-- declares no tools anywhere in this plugin. There is no needs table here at
-- all, since a present field is a claim and this plugin has nothing to claim. Its
-- chooser and its theme are the same story, both ambient once a surface is declared,
-- so a present manifest field for either would only be restating global policy.
return {
  -- Scoped by the launcher, typing the alias and a space lists the same field this
  -- picker shows and choosing an entry does the same thing.
  provides = {
    rows = "rows",
    select = "select",
  },

  defaults = {
    leader = "app",
    key = "K",
    description = "Keep awake",
    glyph = "☕",
    aliases = { "k", "awake" },
  },

  -- One morphing row rather than a list, a typed clock or duration, so the context
  -- binds only the commit and the close. There is no highlight to move, so j and k
  -- are absent rather than shared, and there is nothing beyond the primary key. nav
  -- is stated as false rather than left to say so only in this comment, since the
  -- shared surface wiring adds both move keys to every context unless told not to.
  surface = {
    context = "caffeinate",
    primary = { action = "insertSelected", description = "Confirm" },
    nav = false,
  },

  -- configure alone leaves this plugin with no engine and no chooser, both of which
  -- start builds. A real step beyond configure, so it is named rather than left for
  -- someone to notice the key does nothing.
  wiring = {
    { method = "start" },
  },

  -- show is a plain dot called function on this plugin's own root, function M.show(), never
  -- a colon method, so open says so, and rows and select are the same, both assigned onto the
  -- module from plain locals rather than written as methods.
  --
  -- The scope is what the launcher shows when a typed duration is being turned into a list of
  -- morphing suggestion rows, and it is the same two functions the tool's own picker already
  -- uses, reached by name rather than by a closure so nothing here captures anything at
  -- declare time. matcher is a real false rather than an absent field, because the rows morph
  -- as the query is typed and a second scoring pass over them would fight the wording they
  -- already chose for themselves, which is the tool's own reason its own chooser stands the
  -- shared matcher down too.
  registry = {
    row = { category = "System" },
    open = { member = "show", call = "dot" },
    surface = true,
    hosted = true,
    shortcut = "leader",
    scope = {
      matcher = false,
      rows = { member = "rows", call = "dot" },
      run = { member = "select", call = "dot" },
    },
  },
}
