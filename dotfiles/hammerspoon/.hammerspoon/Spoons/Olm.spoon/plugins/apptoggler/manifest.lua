-- AppToggler, what it declares about itself.
--
-- A general toggle mechanism serving every app in config/apps.lua, so it owns no single key of
-- its own. It answers one action per app in that catalog, apptoggler.Safari, which focuses the
-- app or cycles its windows, and one per named variant in its own data, apptoggler.GhosttyPlaced,
-- for an app that needs more than that. Which key reaches which action is the person's choice in
-- config/keymap.lua, which this plugin never reads, and Olm binds every one of them, so the plugin
-- binds nothing and learns no chord. Which apps exist and how a variant behaves stays this
-- plugin's data, in config/apps.lua and in its own entry in config/plugins.lua.
--
-- Finder is not personal, though. It ships on every Mac with a fixed bundle id, and the owner
-- asked for it as a default toggle, so a fresh install gets one working toggle out of the box
-- rather than an empty list with nothing to press. It is the one suggested key below. The
-- person's own catalog and variants merge over these defaults, the same override rules every
-- default already follows.
--
-- A variant names its `app` and may ask for more. `hides` swaps the default focus or cycle
-- behaviour for show and hide, a second press on an already frontmost app hiding it instead of
-- walking its windows. `description` labels the action wherever Olm lists it, worth stating on a
-- variant especially, since two actions for one app would otherwise read the same. `placement`
-- centers and sizes the window once the press actually showed, launched, or focused the app, a
-- table of width, height, padding, and a fractional anchor, or a function answering a frame
-- outright, both documented in this plugin's own README rather than here, since this file states
-- what the plugin needs, not how it behaves.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "App Toggler",
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
      -- The named variants, each an app and the behaviour it needs beyond focus or cycle, hides,
      -- placement and a description, reaching this plugin as `data.variants` in the same entry.
      -- They are the person's per app choices and this door already carries those.
      variants = { source = "user", policy = "optional",
                   breaks = "no variant action exists, so an app has only its plain focus or cycle" },
    },
  },

  -- What this plugin can run, one descriptor per app and per variant, built in configure from its
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
    variants = {},
    -- The one suggested key, Finder on the app leader, exactly what a fresh install with nothing
    -- else configured is meant to demonstrate. Every other key is the person's.
    bindings = {
      { action = "Finder", key = "F" },
    },
  },
}
