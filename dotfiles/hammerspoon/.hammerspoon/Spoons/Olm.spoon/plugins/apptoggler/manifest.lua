-- AppToggler, what it declares about itself.
--
-- A general toggle mechanism serving every app in config/keys.lua's appToggles, so it owns
-- no single key of its own. Most entries are keys on the app leader, but an entry may opt out
-- of the leader entirely by stating its own `modifiers`, which asks for a literal global combo
-- instead, live all the time rather than only while Hyper is held. Olm binds every one of them
-- from the rows this plugin answers through provides.bindings, so the plugin binds nothing. Which apps
-- beyond the one below, which key each one answers to, and whether an entry hides, cycles,
-- or places itself on show, stays the person's own choice in config/apps.lua and
-- config/keys.lua, the same reasoning windowmanager's much larger binding table gets for
-- everything that is NOT personal.
--
-- Finder is not personal, though. It ships on every Mac with a fixed bundle id, and the
-- owner asked for it as a default toggle, so a fresh install gets one working toggle out of
-- the box rather than an empty list with nothing to press. The person's own richer list
-- merges over apps and replaces toggles wholesale, the same override rules every default
-- already follows.
--
-- Every entry beyond `app` and `key` is optional, and each is read straight off the entry
-- table by init.lua rather than named again here, since a manifest that restated every
-- field a config table may carry would drift from the code the moment either one changed
-- alone. `modifiers` asks for the literal combo above. `hides` swaps the default
-- focus-or-cycle behaviour for show and hide, a second press on an already frontmost app
-- hiding it instead of walking its windows. `description` labels the launcher's row for the app,
-- worth stating on a literal combo entry especially, since such an entry never reaches the
-- Hyper cheat sheet and the launcher row is its only discoverability surface. `placement` centers
-- and sizes the window once the press actually showed, launched, or focused the app, a
-- table of width, height, padding, and a fractional anchor, or a function answering a frame
-- outright, both documented in this plugin's own README rather than here, since this file
-- states what the plugin needs, not how it behaves.
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
      -- Bringing the app forward, focus or cycle and toggle by url, the core lib the launcher's
      -- app rows share. Required, since the ordinary toggle and the url form both call it, and
      -- a core lib is always present, so requiring it costs nothing on any install.
      appFocus = { from = "appfocus", policy = "required" },
    },

    -- One toggle form opens a URL rather than an application, for a pane scheme such as the
    -- one System Settings answers to. That form and the ordinary focus or cycle both live in
    -- lib/appfocus.lua since phase three of the core split, which is also what the launcher's
    -- app rows call, so the launcher binary the url form runs is declared by the root rather
    -- than here, and this plugin runs no tool of its own any more.

    -- Both fields now have a working shipped default below, so neither blocks a fresh
    -- install, but both are still worth declaring, since the person's own fuller list is the
    -- entire point of this plugin and its absence is a real, if contained, loss.
    data = {
      -- config/apps.lua, the bundle id every toggle resolves its app name through. Reaches this
      -- plugin as `data.apps` in its own apptoggler entry in config/plugins.lua.
      apps = { source = "user", policy = "optional",
               breaks = "only Finder resolves, every other toggle logs Unknown app and does nothing" },
      -- config/keys.lua's appToggles, the list the binding rows are built from, reaching this
      -- plugin as `data.toggles` in the same entry. Each entry's own
      -- optional fields, modifiers, hides, description, and placement, live inside this
      -- same list rather than as separate declarations, since they are the person's
      -- per app choices and this door already carries those.
      toggles = { source = "user", policy = "optional",
                  breaks = "only the shipped Finder toggle exists, none of the person's own apps get a key" },
    },
  },

  -- The keys are the rows bindings answers, one complete row per toggle whose app resolves, each
  -- with its key, the app role or its own modifiers, its description and the function it calls.
  -- They are built in configure from this plugin's own effective toggles, already merged with
  -- whatever the person's own file overrides, and Olm binds them. It is a bridge, since these
  -- keys are still the person's data rather than actions, and a later phase of the keymap plan
  -- replaces it with one action per app.
  --
  -- The Hyper cheat sheet lists the toggles because this plugin says it supplies sections for
  -- a leader's sheet, never because the sheet knows it exists. cheatSheetSections answers the
  -- running and dormant split of every toggle that is a key on the app leader, asked on every
  -- show since which apps are running changes while Hammerspoon runs. Switched off, the sheet
  -- simply has no app section.
  --
  -- The launcher's app rows show each bound app's chord because this plugin says it supplies
  -- details for them, never because the launcher reads the toggles. launcherAppDetails answers
  -- every app that has a row, keyed by bundle id, with its chord, its description and its url.
  -- Switched off, an app row simply carries no chord.
  provides = {
    bindings = "bindings",
    cheatSheetSections = "cheatSheetSections",
    launcherAppDetails = "launcherAppDetails",
  },

  defaults = {
    -- The leader whose sheet lists the toggles, the one an entry with no `modifiers` binds on.
    -- An entry with its own `modifiers` is a global combo on no leader and is never listed.
    leader = "app",
    -- Where the app sections sit on that sheet, compared with the sheet's own block of bound
    -- chords at fifty. Ten keeps the apps first, where they have always been.
    cheatSheetOrder = 10,
    apps = {
      Finder = "com.apple.finder",
    },
    toggles = {
      -- No modifiers, meaning a key on the app leader, exactly what a fresh install with
      -- nothing else configured is meant to demonstrate.
      { app = "Finder", key = "f" },
    },
  },
}
