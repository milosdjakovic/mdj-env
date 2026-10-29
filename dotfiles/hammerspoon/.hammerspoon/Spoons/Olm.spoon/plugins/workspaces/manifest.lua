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
-- A scope, so the alias and a space lists the layouts in the launcher and choosing one applies
-- it. The earlier plugin here declared none, since every one of its top level rows was a push
-- into a configuration and a scope row completes rather than pushes. This one has an honest
-- completion, apply, which is also the thing a layout is for, so the typed word is the fast
-- path and the launcher row still opens the manager for taking, pruning, and the rest.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Workspaces",
    description = "Snapshot where your windows sit and put them back later.",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  -- The identity is exactly the directory, one lowercase word, so no name field.

  -- The row icons, named by the rows and drawn by Olm. The Apps list carries each
  -- app's own picture instead, and app is only the mark for an app with none.
  icons = {
    available = { emoji = "🟢", sf = "circle.fill" },
    unavailable = { emoji = "⚪", sf = "circle" },
    new = { emoji = "📸", sf = "camera" },
    apply = { emoji = "🪟", sf = "macwindow" },
    apps = { emoji = "📦", sf = "shippingbox" },
    app = { emoji = "🪟", sf = "macwindow" },
    update = { emoji = "🔄", sf = "arrow.triangle.2.circlepath" },
    rename = { emoji = "✏️", sf = "pencil" },
    delete = { emoji = "🗑️", sf = "trash" },
    remove = { emoji = "🚫", sf = "nosign" },
    include = { emoji = "✅", sf = "checkmark.circle" },
    save = { emoji = "💾", sf = "square.and.arrow.down" },
    no = { emoji = "↩️", sf = "arrow.uturn.backward" },
    back = { emoji = "⬅️", sf = "chevron.left" },
    hint = { emoji = "⌨️", sf = "keyboard" },
    warn = { emoji = "⚠️", sf = "exclamationmark.triangle" },
    workspaces = { emoji = "🪟", sf = "rectangle.3.group" },
  },

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
      stagePush = { source = "root", policy = "optional",
        breaks = "Apps and Rename in the action panel open nothing, since a verb has no other way to open a level" },
      stageSelectedItem = { source = "root", policy = "optional",
        breaks = "every verb of the action panel finds no layout to act on and does nothing" },
      redrawPresented = { source = "root", policy = "optional",
        breaks = "an update or a delete from the action panel leaves the list showing what it showed until it is reopened" },
      stagePop = { source = "root", policy = "optional",
        breaks = "every Back row, and every successful rename, delete, remove, and include, all stand on the level they meant to leave rather than returning to its parent" },
    },
  },

  -- What enrols this plugin in the launcher's scope set. The queryscope host asks which
  -- plugins provide both rows and select, never a roster, and registry.scope below is what
  -- the typed word then actually runs. Both name the scope's own members, since the scope
  -- lists layouts to apply and the presentation's own top level is the manager.
  provides = {
    rows = "chooser.scopeRows",
    select = "chooser.applyScoped",
  },

  -- Opened from the launcher only, so it proposes no key at all. Taking or applying a layout
  -- is a deliberate act a few times a day, not something worth a chord. The aliases are the
  -- typed word that scopes the launcher to the layouts.
  defaults = {
    description = "Workspaces",
    launcherRow = true,
    aliases = { "ws", "layout" },
  },

  -- A nested menu you navigate, so the primary verb is insertSelected, the atom's real
  -- completion path, which every level's own intercept is asked ahead of. No pane, no level
  -- here reserves a companion, and no matcher is declared at the top, so the layouts are
  -- searched by the shared strategy. Only the levels whose field is a typed name or a confirm
  -- set matcher false themselves.
  -- Return applies the highlighted layout, and what else a layout offers is a verb of the action
  -- panel alone, no key, gated by isLayout so the New snapshot row offers none of them,
  -- docs/PLAN-ACTION-PANEL.md. Delete asks first through the panel's own confirm.
  surface = {
    context = "workspaces",
    primary = { action = "insertSelected", description = "Apply", icon = "apply" },
    extra = {
      { action = "updateLayout", description = "Update snapshot", icon = "update",
        section = "Layout", applies = "isLayout" },
      { action = "editApps", description = "Apps", icon = "apps", section = "Layout", applies = "isLayout" },
      { action = "renameLayout", description = "Rename", icon = "rename", section = "Manage", applies = "isLayout" },
      { action = "deleteLayout", description = "Delete", icon = "delete", section = "Manage",
        applies = "isLayout", confirm = "Delete this layout" },
    },
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
  --
  -- The scope's two members live on the chooser submodule, reached through it by the dotted
  -- name, since a bare name is walked against the plugin root and answers nil in silence.
  -- No matcher, so the shared one filters the rows scopeRows returns by the typed rest.
  registry = {
    row = { category = "Displays", detail = "window layouts you snapshot and put back",
      icon = "workspaces", keywords = "layout, snapshot, arrange windows, restore windows" },
    open = { member = "chooser.show", call = "dot" },
    -- The submodule the action panel's verbs, isLayout and the four on a layout, are answered by.
    surface = "chooser",
    scope = {
      rows = { member = "chooser.scopeRows", call = "dot" },
      run = { member = "chooser.applyScoped", call = "dot" },
    },
  },
}
