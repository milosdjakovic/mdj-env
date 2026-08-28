-- Caffeinate, what it declares about itself.
--
-- Native Lua over the built in hs.caffeinate api, so it names no external tool and
-- declares no tools anywhere in this plugin. Its chooser and its theme are the same
-- story, both ambient once a surface is declared, so a present manifest field for either
-- would only be restating global policy.
return {
  needs = {
    -- Two root computed words, the trickle migration onto the shared stage. stagePresent
    -- is the hotkey door, reached through this plugin's own M.show. redrawPresented is the
    -- async status seam, this plugin's own onChange asking to be redrawn once a timed
    -- session ends while its own presentation, and no other, is what the stage is actually
    -- showing. Both optional, both degrade to an inert press or a silently skipped redraw,
    -- never a crash, since a plugin asking before the stage's own configure has run is a
    -- wiring defect rather than a state a key press should silently swallow.
    data = {
      stagePresent = { source = "root", policy = "optional",
        breaks = "this plugin's own leader key opens nothing, since M.show has no other way to reach the shared stage" },
      redrawPresented = { source = "root", policy = "optional",
        breaks = "the primary row keeps reading whatever it last showed once a timed session ends, since onChange has no other way to reach whatever is on screen" },
    },
  },

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

  -- The presentation contract, contract v2, docs/BRIEF-CONTRACT-V2.md. rows and select are
  -- this plugin's own plain dot called functions, M.rows and M.select, so every field below
  -- says call = dot, stated outright, never the bare string shorthand this contract allows
  -- everywhere else a member is not a presentation's own. placeholder resolves once, at
  -- register, to the static field wording.
  --
  -- rowCount is the row count exerciser named in the stage design brief itself, the one
  -- consumer in the whole tree that differs from the atom's own default of ten. A window
  -- built for some other presentation's ten rows is hidden, rebuilt at two, and reshown the
  -- moment this presentation becomes current, the one resize path that exists, and the same
  -- happens in reverse the moment anything else is shown next, both blinks host/stage's own
  -- _applyRowCount pays rather than this plugin.
  --
  -- matcher is a real false, unchanged by the migration. The field is not a filter over a
  -- list, it is a value being typed, so the supplier re-parses the query each keystroke and
  -- returns the one morphing row, and letting the shared matcher filter that row would drop
  -- it whenever the parsed value did not fuzzy-match its own label.
  presentation = {
    rows = { member = "rows", call = "dot" },
    select = { member = "select", call = "dot" },
    placeholder = { member = "placeholder", call = "dot" },
    rowCount = 2,
    matcher = false,
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
  --
  -- surface is no longer declared, host/stage's own surfaceFor answering the five generic
  -- nav verbs now that presentation above exists, and this plugin binds no verb beyond
  -- them, its own retired three function surface, isShowing, hide, and insertSelected,
  -- having never carried anything past those five in the first place.
  registry = {
    row = { category = "System" },
    open = { member = "show", call = "dot" },
    hosted = true,
    shortcut = "leader",
    scope = {
      matcher = false,
      rows = { member = "rows", call = "dot" },
      run = { member = "select", call = "dot" },
    },
  },
}
