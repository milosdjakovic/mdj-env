-- AppToggler, what it declares about itself.
--
-- A general toggle mechanism serving every app in config/keys.lua's appToggles, so it owns
-- no single key of its own, only the app leader modal every one of those toggles fires
-- within. Which apps beyond the one below, and which key each one answers to, stays the
-- person's own choice in config/apps.lua and config/keys.lua, the same reasoning
-- windowmanager's much larger binding table gets for everything that is NOT personal.
--
-- Finder is not personal, though. It ships on every Mac with a fixed bundle id, and the
-- owner asked for it as a default toggle, so a fresh install gets one working toggle out of
-- the box rather than an empty list with nothing to press. The person's own richer list
-- merges over apps and replaces toggles wholesale, the same override rules every default
-- already follows.
return {
  needs = {
    -- Toggles fire while the physical Hyper key is held, through the shared hold engine
    -- HyperKey wraps, so a toggle reads as a modal chord rather than a literal modifier
    -- combination. Optional, because AppToggler already falls back to binding the literal
    -- HYPER combo when HyperKey is not wired, so losing it costs a nicer chord rather than
    -- the feature itself.
    lib = {
      hyperKey = { from = "hyperkey", policy = "optional" },
    },

    -- One toggle form opens a URL rather than an application, for a pane scheme such as the
    -- one System Settings answers to, and hs.urlevent.openURL refuses those since they carry
    -- a single colon instead of a scheme separator. So the launcher binary is a real
    -- dependency of this plugin rather than an implementation detail, and it was invoked by
    -- name here for as long as this plugin has existed with nothing declaring it.
    --
    -- Optional, because every ordinary toggle resolves an application through the
    -- accessibility API and never reaches this, so an absent one costs the URL form alone.
    tools = {
      { name = "open", kind = "system", locator = "/usr/bin/open", policy = "optional",
        reason = "opening a pane URL for a toggle whose target is a settings pane rather " ..
                 "than an application",
        origin = { macos = "ships with the system" } },
    },

    -- Both fields now have a working shipped default below, so neither blocks a fresh
    -- install, but both are still worth declaring, since the person's own fuller list is the
    -- entire point of this plugin and its absence is a real, if contained, loss.
    data = {
      -- config/apps.lua, the bundle id every toggle resolves its app name through.
      apps = { source = "user", policy = "optional",
               breaks = "only Finder resolves, every other toggle logs Unknown app and does nothing" },
      -- config/keys.lua's appToggles, the list bindHotkeys walks below.
      toggles = { source = "user", policy = "optional",
                  breaks = "only the shipped Finder toggle exists, none of the person's own apps get a key" },
    },
  },

  -- bindHotkeys is a second call this plugin exposes beyond configure, so it belongs in
  -- wiring rather than being folded into opts. It takes the toggle list positionally rather
  -- than the whole options table, the same reason KeyRemap's apply needs args at all. self is
  -- right rather than root now, toggles is this plugin's own effective declaration below,
  -- already merged with whatever the person's own file overrides.
  wiring = {
    { method = "bindHotkeys", args = { "self.toggles" } },
  },

  defaults = {
    apps = {
      Finder = "com.apple.finder",
    },
    toggles = {
      { app = "Finder", key = "f", modifiers = { "shift", "ctrl", "alt", "cmd" } },
    },
  },
}
