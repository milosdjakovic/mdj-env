-- Bridge, what it declares about itself.
--
-- A host, the Lua side of Olm.app, docs/PLAN-STANDALONE.md and docs/PROTOCOL-BRIDGE.md. Today it is
-- step 1.2 alone. Where this machine's olmapp piece is on, it answers the root which tools Olm.app
-- serves, file search today, and the root hands that tool's open key to it, so the key opens the
-- app's list through an olm:// URL rather than the Lua one. The keymap is unchanged, so the key, its
-- cheat sheet row and its launcher row stay where they are, and the Lua file search is still reached
-- from the launcher. Off by the piece, it answers nothing and every key is as before.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Bridge",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  -- The trial key's action, step 3.2, bridge.launcher, which opens Olm.app's own launcher while
  -- Hyper and Space opens the Lua one. Olm builds its row and binds whatever key this machine's
  -- keys file gives it, and its when keeps both off a machine whose olmapp piece is off.
  provides = {
    actions = "actions",
  },

  icons = {
    launcher = { emoji = "🧪", sf = "flask" },
  },

  needs = {
    data = {
      -- This machine's pieces, from config/machine.lua through config/plugins.lua.
      pieces = { source = "user", policy = "optional",
        breaks = "no tool's key opens Olm.app, so every key opens the Lua list as before" },
      -- Settings the app reads, by name, each written as ~/.olm/run/<name>.json where the olmapp
      -- piece is on, so the config keeps one owner and the app a copy it never edits.
      shares = { source = "user", policy = "optional",
        breaks = "the app runs on its own defaults rather than this config's" },
      -- The tools whose answers are handed to Olm.app to answer again and compare, step 1.3e, by
      -- identity, from config/plugins.lua. Each must offer watch and held.
      shadows = { source = "user", policy = "optional",
        breaks = "no answer is compared with the app's, which changes nothing a person sees" },
      -- Whether the bridge connects to Olm.app's socket and serves the launcher read only, step 2.2,
      -- from config/plugins.lua, off by default.
      socket = { source = "user", policy = "optional",
        breaks = "nothing is served over the socket, which changes nothing a person sees" },
      -- The tools Olm.app serves, by identity, from config/plugins.lua.
      serves = { source = "user", policy = "optional",
        breaks = "no tool's key opens Olm.app, so every key opens the Lua list as before" },
    },
    tools = {
      { name = "open", kind = "system", locator = "/usr/bin/open", policy = "optional",
        reason = "opening an olm:// URL in Olm.app in the background, without which every key opens the Lua list as before",
        origin = { macos = "ships with the system" } },
    },
  },
}
