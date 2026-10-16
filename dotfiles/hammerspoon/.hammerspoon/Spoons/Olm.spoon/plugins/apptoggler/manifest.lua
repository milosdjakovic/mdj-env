-- AppToggler, what it declares about itself.
--
-- A general toggle mechanism serving every app in config/keys.lua's appToggles, so it owns
-- no single key of its own. Most entries fire within the app leader modal, but an entry may
-- opt out of the modal entirely by stating its own `modifiers`, which asks for a literal
-- global combo instead, live all the time rather than only while Hyper is held. Which apps
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
    -- Toggles fire while the physical Hyper key is held, through the shared hold engine
    -- HyperKey wraps, so a modal entry reads as a modal chord rather than a literal
    -- modifier combination. Optional, because AppToggler already falls back to binding the
    -- literal HYPER combo when HyperKey is not wired, so losing it costs a nicer chord
    -- rather than the feature itself, and an entry that stated its own `modifiers` never
    -- reaches this at all, either way.
    lib = {
      hyperKey = { from = "hyperkey", policy = "optional" },
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
      -- config/apps.lua, the bundle id every toggle resolves its app name through.
      apps = { source = "user", policy = "optional",
               breaks = "only Finder resolves, every other toggle logs Unknown app and does nothing" },
      -- config/keys.lua's appToggles, the list bindHotkeys walks below. Each entry's own
      -- optional fields, modifiers, hides, description, and placement, live inside this
      -- same list rather than as separate declarations, since they are the person's
      -- per app choices and this door already carries those.
      toggles = { source = "user", policy = "optional",
                  breaks = "only the shipped Finder toggle exists, none of the person's own apps get a key" },
    },
  },

  -- bindHotkeys is a second call this plugin exposes beyond configure, so it belongs in
  -- wiring rather than being folded into opts. It takes the toggle list positionally rather
  -- than the whole options table, the same reason any step that is not configure(opts) needs args at all. self is
  -- right rather than root now, toggles is this plugin's own effective declaration below,
  -- already merged with whatever the person's own file overrides.
  wiring = {
    { method = "bindHotkeys", args = { "self.toggles" } },
  },

  -- The Hyper cheat sheet lists the toggles because this plugin says it supplies sections for
  -- a leader's sheet, never because the sheet knows it exists. cheatSheetSections answers the
  -- running and dormant split of every toggle this plugin bound into the Hyper modal, asked on
  -- every show since which apps are running changes while Hammerspoon runs. Switched off, the
  -- sheet simply has no app section.
  --
  -- The launcher's app rows show each bound app's chord because this plugin says it supplies
  -- details for them, never because the launcher reads the toggles. launcherAppDetails answers
  -- every app bindHotkeys bound, keyed by bundle id, with its chord, its description and its
  -- url. Switched off, an app row simply carries no chord.
  provides = {
    cheatSheetSections = "cheatSheetSections",
    launcherAppDetails = "launcherAppDetails",
  },

  defaults = {
    -- The leader whose sheet lists the toggles, the one a modal entry binds on through
    -- needs.lib.hyperKey. An entry with its own `modifiers` is a global combo on no leader and
    -- is never listed.
    leader = "app",
    -- Where the app sections sit on that sheet, compared with the sheet's own block of bound
    -- chords at fifty. Ten keeps the apps first, where they have always been.
    cheatSheetOrder = 10,
    apps = {
      Finder = "com.apple.finder",
    },
    toggles = {
      -- No modifiers, meaning the Hyper modal, exactly what a fresh install with nothing
      -- else configured is meant to demonstrate.
      { app = "Finder", key = "f" },
    },
  },
}
