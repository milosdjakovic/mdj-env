-- Workspaces, what it declares about itself.
--
-- Pure data, loading with nothing required and touching no hs, the same rule every manifest
-- in this tree answers to.
--
-- No needs.tools at all, and that is a real answer rather than an omission. This plugin
-- shells out to nothing. It reads screens and windows and writes one JSON file, all of it
-- through Hammerspoon itself, so there is no external binary or bundle for the layer above to
-- guarantee.
--
-- No provides and no registry.scope either, so no alias, and that is a decision worth stating
-- rather than a field forgotten. An alias only becomes a typed word through a scope, and a
-- scope row completes rather than pushing a level, since QueryScope discards whatever run
-- answers. Every row this tool has at its top level means go into this layout and look at it,
-- which is a push, so there is no honest thing a scope row could complete with here. An alias
-- declared without a scope behind it is a word that resolves to nothing, which is the class of
-- declaration this contract exists to refuse, so it is left out.
return {
  -- The identity is exactly the directory, one lowercase word, so no name field.

  needs = {
    -- Where the layouts live. lib/storage.lua's own dataDir, the durable root under the home
    -- directory every plugin's own data goes to, speedtest's history being the settled example,
    -- rather than a file inside the config tree. A layout is this machine's own record of its
    -- desk and its apps, so it belongs beside the clipboard history and the speed test runs,
    -- never in git. Required, since every environment this config runs in configures storage
    -- at start and a list with nowhere to write would be a list that lies.
    lib = {
      storage = { from = "storage", policy = "required" },
    },

    data = {
      -- How an apply says what it did. A list of apps with their icons and one phrase each,
      -- drawn by the root on the shared overlay, since a plugin never builds a window of its
      -- own and the root decides how a message is drawn and where it lands. Optional, because
      -- the windows are placed either way and the console carries the same lines.
      report = { source = "root", policy = "optional",
        breaks = "an apply places the windows and says nothing on screen, the console alone carries what happened to each app" },

      -- The stage seam. This plugin holds no chooser of its own, so the two things a chooser
      -- owner used to do directly arrive as words the composition root publishes. stagePresent
      -- is the door the launcher row opens through. stagePop is what every Back row, a saved
      -- snapshot, and every successful rename, delete, remove, and include leaves a level
      -- through, the one thing a child pushed from select cannot express on its own. Both
      -- optional, both degrading to an inert press rather than a crash, since a plugin asking
      -- before the stage's own configure has run is a wiring defect and not a state a key
      -- press should swallow loudly.
      stagePresent = { source = "root", policy = "optional",
        breaks = "the launcher row opens nothing, since the chooser has no other way to reach the shared stage" },
      stagePop = { source = "root", policy = "optional",
        breaks = "every Back row, and every successful rename, delete, remove, and include, all stand on the level they meant to leave rather than returning to its parent" },
    },
  },

  -- Opened from the launcher only, so it proposes no key at all. Taking or applying a layout
  -- is a deliberate act a few times a day, not something worth a chord.
  defaults = {
    description = "Workspaces",
    launcherRow = true,
  },

  -- A nested menu you navigate, so the primary verb is insertSelected, the atom's real
  -- completion path, which every level's own intercept is asked ahead of. No pane, no level
  -- here reserves a companion, and matcher is false because each level's own supplier either
  -- filters the list itself or morphs its rows from the query, which is what a name field is,
  -- so the shared strategy would be filtering a list that is already the answer.
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

  -- The plugin root's own configure runs by default and builds the store and the api. The one
  -- declared step hands the chooser submodule the same options table, which is where its stage
  -- words arrive, on top of the api the root already gave it. No start step, since nothing here
  -- watches anything. The earlier plugin in this directory lived or died by a start step that
  -- subscribed its watchers, and this one deliberately has none to subscribe.
  wiring = {
    { target = "chooser", method = "configure" },
  },

  -- show is a plain dot called function on the chooser submodule, function M.show(), never a
  -- colon method, so open says so. No surface member is declared, host/stage's own surfaceFor
  -- answers the five generic nav verbs once the presentation above exists and this tool binds
  -- nothing past them.
  registry = {
    row = { category = "Displays", detail = "window layouts you snapshot and put back",
      glyph = "🪟", keywords = "workspace workspaces layout layouts window windows snapshot arrange" },
    open = { member = "chooser.show", call = "dot" },
  },
}
