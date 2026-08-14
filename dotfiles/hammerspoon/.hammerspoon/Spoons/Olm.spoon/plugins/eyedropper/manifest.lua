-- Eyedropper, what it declares about itself.
--
-- A lone mechanism rather than a list tool, so it does not ride the shared Chooser atom and
-- carries no surface block. The one thing it needs from outside Hammerspoon is a Swift
-- compiler to build its native sampler helper, declared beside the spoon's own root since
-- init.lua is the only file here that runs it, matching the existing dependencies file this
-- plugin already carries. Optional, because a failed build is answered with an alert and a
-- console line rather than a refusal to wire, the choice this whole config makes about what
-- the user sees rather than about how badly a spoon wants its tool.
return {
  -- The registry and the launcher's registered tool row know this plugin as colorPicker,
  -- while the directory beside this file is eyedropper.
  name = "colorPicker",

  needs = {
    tools = {
      { name = "swiftc", kind = "system", locator = "/usr/bin/swiftc", policy = "optional",
        reason = "compiles the native colour sampler helper",
        origin = { macos = "ships with the Xcode command line tools" } },
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
