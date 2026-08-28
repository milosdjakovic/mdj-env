-- DisplayProfiles, what it declares about itself.
--
-- The one external tool is the arrangement engine itself, displayplacer, resolved
-- once and handed to engine.lua, which never probes for it on its own. Without it
-- the spoon still starts, it simply manages nothing and says why.
return {
  -- The directory is displayprofiles, one word, while the identity everywhere
  -- outside this folder, config/keys.lua, the registry, the launcher row, is
  -- displayProfiles.
  name = "displayProfiles",

  needs = {
    tools = {
      { name = "displayplacer", kind = "path", policy = "optional", unit = "engine",
        reason = "reading and applying display arrangements",
        origin = { brew = "displayplacer" } },
    },
    -- Everything below is a fact about this machine or this person's own monitors,
    -- and none of it can be shipped as a working default on a fresh install.
    data = {
      -- Keyed by host, the whole profiles table out of config/displays.lua rather than one
      -- machine's slice of it. This plugin takes its own slice, using the host below, so a
      -- person's own file stays one plain table and nothing in between has to know its shape.
      profiles = { source = "user", policy = "optional",
        breaks = "no curated arrangement exists for this host, so the tool manages "
          .. "nothing here until one is added to config/displays.lua or captured "
          .. "from the chooser" },
      host = { source = "root", policy = "optional",
        breaks = "no curated arrangement can be found, since they are keyed by host, and the "
          .. "captured store has no key to save under either, so it is disabled and the "
          .. "chooser is empty" },
      storePath = { source = "root", policy = "optional",
        breaks = "the captured profile store has no file to read or write, so it "
          .. "is disabled and the chooser shows only the curated profiles" },
      settleDelay = { source = "user", policy = "optional",
        breaks = "a burst of screen events is coalesced with the built in one and a "
          .. "half second window rather than one tuned for this setup" },

      -- Three root computed words, the trickle migration onto the shared stage. stagePresent
      -- is the hotkey door, reached through this plugin's own M.show, and through the
      -- registered special row dispatch, this tool proposing no key of its own. redrawPresented
      -- is the async status seam, the engine's own screen watcher asking to be redrawn once
      -- the active profile changes while this presentation, and no other, is what the stage
      -- is actually showing. stagePop, contract v3's own addition, docs/BRIEF-CONTRACT-V3.md,
      -- is what every child level's own Back row, and every successful rename, delete, and
      -- capture, leaves a level through, the one thing a child pushed from select cannot
      -- express on its own. All three optional, all three degrading to an inert press or a
      -- silently skipped redraw, never a crash, since a plugin asking before the stage's own
      -- configure has run is a wiring defect rather than a state a key press should silently
      -- swallow.
      stagePresent = { source = "root", policy = "optional",
        breaks = "this plugin's own launcher row opens nothing, since M.show has no other way to reach the shared stage" },
      redrawPresented = { source = "root", policy = "optional",
        breaks = "the active marker stays stale after a screen change lands while the tool is open, since M.refresh has no other way to reach whatever is on screen" },
      stagePop = { source = "root", policy = "optional",
        breaks = "every child level's own Back row, and a successful rename, delete, or capture, all stand on the level they meant to leave rather than returning to its parent" },
    },
  },

  -- No provides. This tool has no alias in config/keys.lua, so it is reached only by
  -- opening the picker itself, never by a typed scope.

  -- Opened from the launcher only, so it proposes no key at all.
  defaults = {
    description = "Display Profiles",
    launcherRow = true,
  },

  -- A nested menu you navigate, insertSelected now rather than the retired enter. The
  -- rename costs nothing behaviourally, this level's own drill down and its Back row both
  -- go through host/stage's own intercept, the atom's real completion path, asked before
  -- Return, insertSelected, or a click alike are ever let through, so nothing here needs a
  -- private mechanism to keep the window open through a step any more. No pane, this
  -- plugin's own levels reserve no companion pane, and matcher stays false through
  -- presentation.matcher below and every child's own field, since each level's own supplier
  -- morphs its rows from the query rather than filtering a fixed list.
  surface = {
    context = "displayProfiles",
    primary = { action = "insertSelected", description = "Select" },
  },

  -- The presentation contract, contract v3, docs/BRIEF-CONTRACT-V3.md. rows and select are
  -- this plugin's own chooser.rows and chooser.select, plain closures assigned or defined on
  -- the chooser submodule exactly the way its show, placeholder, and every other public
  -- member already are, so every field below says call = dot, stated outright, never the
  -- bare string shorthand this contract allows everywhere else a member is not a
  -- presentation's own. placeholder resolves once, at register, to the top level's own
  -- static wording, every child level below it carrying its own instead, a plain field on a
  -- table built at runtime rather than something the registrar ever resolves. matcher is a
  -- real false, unchanged by the migration, since the top level's own supplier already
  -- filters the profile list itself rather than leaving that to the shared strategy.
  presentation = {
    rows = { member = "chooser.rows", call = "dot" },
    select = { member = "chooser.select", call = "dot" },
    placeholder = { member = "chooser.placeholder", call = "dot" },
    matcher = false,
  },

  -- Configure alone leaves this plugin half wired. Start begins the screen watcher
  -- and its first reconcile, and the inspect and manage picker lives on the chooser
  -- submodule, which needs its own configure, for the view deps this root injects
  -- on top of the api this plugin's own configure already hands it, and its own
  -- start before it can be shown at all.
  wiring = {
    { method = "start" },
    { target = "chooser", method = "configure" },
    { target = "chooser", method = "start" },
  },

  -- show lives on the chooser submodule as a plain dot called function, function M.show(),
  -- never a colon method, so open says so. surface is no longer declared, host/stage's own
  -- surfaceFor answering the five generic nav verbs now that presentation above exists, and
  -- M.refresh, this plugin's only other public member, was never routed through the nav
  -- registry to begin with, called only from this plugin's own screen watcher.
  registry = {
    row = { category = "Displays", detail = "inspect and manage arrangements", glyph = "🖥️" },
    open = { member = "chooser.show", call = "dot" },
  },
}
