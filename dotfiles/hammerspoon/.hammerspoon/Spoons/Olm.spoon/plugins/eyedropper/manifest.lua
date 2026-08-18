-- Eyedropper, what it declares about itself.
--
-- A lone mechanism rather than a list tool, so it does not ride the shared Chooser atom and
-- carries no surface block. The one thing it needs from outside Hammerspoon is a Swift
-- compiler to build its native sampler helper, declared in the needs table below since
-- init.lua is the only file here that runs it. Optional, because a failed build is
-- answered with an alert and a console line rather than a refusal to wire, the choice
-- this whole config makes about what
-- the user sees rather than about how badly a spoon wants its tool. swiftc is not on a fresh
-- install until the command line tools go on, so its origin names that install step rather
-- than claiming the compiler ships with the system.
return {
  -- The registry and the launcher's registered tool row know this plugin as colorPicker,
  -- while the directory beside this file is eyedropper.
  name = "colorPicker",

  needs = {
    tools = {
      { name = "swiftc", kind = "system", locator = "/usr/bin/swiftc", policy = "optional",
        reason = "compiles the native colour sampler helper",
        origin = { ["xcode-clt"] = "xcode-select --install" } },
    },

    data = {
      -- Show the sampled colour. What a pick looks like and where it appears is the root's own
      -- business, since it draws on the shared overlay surface, on whichever display the overlay
      -- policy picked, so this reads as part of the same interface as the cheat sheet rather than
      -- as a stray alert. This plugin only ever says which colour was picked.
      --
      -- Optional, and the sentence says what that costs honestly. The hex still reaches the
      -- clipboard, which is the point of the tool, so what is lost is the confirmation that
      -- anything happened at all.
      showColor = { source = "root", policy = "optional",
        breaks = "a picked colour is copied with nothing shown, so a pick and a missed pick "
          .. "look exactly the same" },
    },
  },

  -- What this plugin proposes for its own key. No glyph and no aliases, since it is reached
  -- as a base Hyper binding and, separately, as a launcher row through the registered tool
  -- dispatcher, rather than through a scope that would draw the glyph a second time.
  defaults = {
    leader = "app",
    key = "2",
    description = "Color picker",
  },

  -- pick is a colon method, obj:pick(), so open takes the default call rather than stating
  -- one. No surface, since this is a lone mechanism rather than a list, matching the surface
  -- block's own absence above.
  registry = {
    row = { category = "Tools", glyph = "🎨" },
    open = "pick",
    shortcut = "leader",
  },
}
