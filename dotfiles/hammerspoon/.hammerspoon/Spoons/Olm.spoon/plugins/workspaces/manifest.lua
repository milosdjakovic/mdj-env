-- Workspaces, what it declares about itself.
--
-- Pure data, loading with nothing required and touching no hs, the same rule every manifest
-- in this tree answers to.
--
-- No needs.tools at all, and that is a real answer rather than an omission. This plugin
-- shells out to nothing. It reads screens, watches windows, and writes one JSON file, all of
-- it through Hammerspoon itself, so there is no external binary or bundle for the layer above
-- to guarantee. The one program it could be said to configure is the window server, which is
-- not a thing a package manager installs.
--
-- No provides and no registry.scope either, so no alias, and that is a decision worth stating
-- rather than a field forgotten. An alias only becomes a typed word through a scope, and a
-- scope row completes rather than pushing a level, since QueryScope discards whatever run
-- answers. Every row this tool has at its top level means go into this configuration and look
-- at it, which is a push, so there is no honest thing a scope row could complete with here.
-- An alias declared without a scope behind it is a word that resolves to nothing, which is the
-- class of declaration this contract exists to refuse, so it is left out.
return {
  -- The identity is exactly the directory, one lowercase word, so no name field. That is
  -- load bearing rather than incidental, since the root hands storePath per declaring plugin
  -- as the config directory plus this identity plus .json. Renaming the identity renames the
  -- file and orphans whatever is already remembered in it.

  needs = {
    data = {
      -- The one file this plugin owns, supplied by the root because only it knows where a
      -- person's own editable data lives. The session layer is untouched by its absence, which
      -- is why this is optional rather than required, docking and undocking within one login
      -- still work with nothing on disk.
      storePath = { source = "root", policy = "optional",
        breaks = "nothing is remembered across a restart, so the memory degrades to the "
          .. "session layer alone and a reboot lands every window wherever macOS puts it" },

      -- The stage seam. This plugin holds no chooser of its own, so the four things a chooser
      -- owner used to do directly arrive as words the composition root publishes.
      -- stagePresent is the door the launcher row opens through. stagePop is what every Back
      -- row, and every successful rename, delete, and forget, leaves a level through, the one
      -- thing a child pushed from select cannot express on its own. redrawPresented is the
      -- async seam, the engine asking for the active marker to be corrected once a
      -- configuration change lands while this list, and no other, is what the stage is showing.
      -- stageSelectedRow is the gate on that redraw, since the marker moving also reorders the
      -- list and a correction landing while somebody is part way down it has to defer rather
      -- than shuffle rows under a hand, which is the discipline the authoring guide states and
      -- the menu search cache already keeps.
      -- All four optional, all four degrading to an inert press or a skipped redraw rather
      -- than a crash, since a plugin asking before the stage's own configure has run is a
      -- wiring defect and not a state a key press should swallow loudly.
      stagePresent = { source = "root", policy = "optional",
        breaks = "the launcher row opens nothing, since the chooser has no other way to reach the shared stage" },
      stagePop = { source = "root", policy = "optional",
        breaks = "every Back row, and a successful rename, delete, or forget, all stand on the level they meant to leave rather than returning to its parent" },
      redrawPresented = { source = "root", policy = "optional",
        breaks = "the active marker stays stale when the display configuration changes while the list is open, since the engine has no other way to reach whatever is on screen" },
      stageSelectedRow = { source = "root", policy = "optional",
        breaks = "a correction landing while the list is open can no longer tell whether somebody is part way down it, so it redraws every time and a reorder may move rows under a hand" },
    },
  },

  -- Opened from the launcher only, so it proposes no key at all. Nothing about window layout
  -- memory is urgent enough to spend a chord on, the engine does its work unasked and this
  -- surface exists to inspect and prune what it remembered.
  defaults = {
    description = "Workspaces",
    launcherRow = true,
  },

  -- A nested menu you navigate, so the primary verb is insertSelected, the atom's real
  -- completion path, which every level's own intercept is asked ahead of. No pane, no level
  -- here reserves a companion, and matcher is false because each level's own supplier either
  -- filters the list itself or morphs its rows from the query, which is what a rename field
  -- is, so the shared strategy would be filtering a list that is already the answer.
  surface = {
    context = "workspaces",
    primary = { action = "insertSelected", description = "Select" },
  },

  -- rows, select, and placeholder are plain closures on the chooser submodule, dot called
  -- every one, so each says call = dot outright rather than taking the bare string shorthand.
  -- A presentation member is the one place this contract refuses a call kind left to default,
  -- since a wrong guess binds the module table where the query belonged and the list quietly
  -- answers nothing forever.
  presentation = {
    rows = { member = "chooser.rows", call = "dot" },
    select = { member = "chooser.select", call = "dot" },
    placeholder = { member = "chooser.placeholder", call = "dot" },
    matcher = false,
  },

  -- THIS BLOCK IS WHY THIS PLUGIN RUNS AT ALL, and it is the exact field whose absence killed
  -- the two plugins this one replaces. Configure alone leaves the engine built and watching
  -- nothing. start is what subscribes the window filter, the screen watcher, and the wake
  -- watcher, and runs the first restore pass. The chooser step hands the submodule the same
  -- options table, which is where its three stage words arrive, on top of the api the plugin's
  -- own configure already gave it. There is no chooser start step, the chooser owns no live
  -- resource and an empty start would be ceremony.
  wiring = {
    { method = "start" },
    { target = "chooser", method = "configure" },
  },

  -- show is a plain dot called function on the chooser submodule, function M.show(), never a
  -- colon method, so open says so. No surface member is declared, host/stage's own surfaceFor
  -- answers the five generic nav verbs once the presentation above exists and this tool binds
  -- nothing past them.
  registry = {
    row = { category = "Displays", detail = "window layouts remembered per display configuration",
      glyph = "🪟", keywords = "workspace workspaces layout window windows remember restore" },
    open = { member = "chooser.show", call = "dot" },
  },
}
