-- AppToggler, what it declares about itself.
--
-- A general toggle mechanism serving every app in config/apps.lua, so it owns no single key of
-- its own. It answers one action per app in that catalog, apptoggler.Safari, which focuses the
-- app or cycles its windows, unless its toggles list gives that app a named style, a behaviour
-- described once and shared by every app that takes it, which changes what the app's own action
-- does and mints no second action. Which key reaches which action is the person's choice in
-- config/keymap.lua, which this plugin never reads, and Olm binds every one of them, so the plugin
-- binds nothing and learns no chord. Which apps exist and how each behaves stays this plugin's
-- data, config/apps.lua and config/toggles.lua, handed over by its entry in config/plugins.lua.
--
-- Finder is not personal, though. It ships on every Mac with a fixed bundle id, and the owner
-- asked for it as a default toggle, so a fresh install gets one working toggle out of the box
-- rather than an empty list with nothing to press. It is the one suggested key below. The
-- person's own catalog, styles and toggles merge over these defaults, the same override rules
-- every default already follows.
--
-- A style is `hides`, `placement` or both, and a toggles entry names its `app` and the `style` it
-- takes and may override either field or add a `description`, all documented in this plugin's own
-- README rather than here, since this file states what the plugin needs, not how it behaves.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "App Toggler",
    description = "Bring an app forward with its key, cycling its windows when it is already in front.",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  needs = {
    lib = {
      -- Bringing the app forward, focus or cycle, the core lib the launcher's app rows share.
      -- Required, since every plain app action calls it, and a core lib is always present, so
      -- requiring it costs nothing on any install.
      appFocus = { from = "appfocus", policy = "required" },
    },

    -- A toggle that opened a url, which is how Hyper and comma reached the General pane, went in
    -- phase 6 of the keymap plan. A pane is System Settings' own action now, so this plugin runs
    -- no tool of its own.

    -- Both fields now have a working shipped default below, so neither blocks a fresh
    -- install, but both are still worth declaring, since the person's own fuller list is the
    -- entire point of this plugin and its absence is a real, if contained, loss.
    data = {
      -- config/apps.lua, the bundle id catalog, one action per entry. Reaches this plugin as
      -- `data.apps` in its own apptoggler entry in config/plugins.lua.
      apps = { source = "user", policy = "optional",
               breaks = "only Finder has an action, so a keymap entry naming any other app is a problem line and binds nothing" },
      -- The named styles, each a behaviour beyond focus or cycle, hides and placement, reaching
      -- this plugin as `data.styles` in the same entry, from config/toggles.lua.
      styles = { source = "user", policy = "optional",
                 breaks = "no style exists, so a toggles entry naming one is logged and its app keeps its plain focus or cycle" },
      -- The list saying which app takes which style, reaching this plugin as `data.toggles`.
      toggles = { source = "user", policy = "optional",
                  breaks = "every app keeps its plain focus or cycle" },
    },
  },

  -- What this plugin can run, one descriptor per app, built in configure from its
  -- own effective data, already merged with whatever the person's own file overrides. Each names
  -- its app, so the launcher shows the action's chord on that app's own row rather than listing
  -- it twice, and a group function answering RUNNING or DORMANT, asked at every show of a sheet,
  -- so the Hyper sheet splits the apps by whether they run with no section of this plugin's own.
  -- Switched off, no app has an action of this plugin's, the sheet has no app section, and an
  -- app row shows a chord only where another plugin's action names that app.
  provides = {
    actions = "actions",
  },

  defaults = {
    -- The role the suggested key below lands on, the app leader.
    leader = "app",
    -- Where this plugin's rows sit on whichever leader's sheet holds their keys, compared with
    -- the sheet's own number for every other row, fifty. Ten keeps the apps first, where they
    -- have always been.
    cheatSheetOrder = 10,
    apps = {
      Finder = "com.apple.finder",
    },
    styles = {},
    toggles = {},
    -- The one suggested key, Finder on the app leader, exactly what a fresh install with nothing
    -- else configured is meant to demonstrate. Every other key is the person's.
    bindings = {
      { action = "Finder", key = "F" },
    },
  },
}
