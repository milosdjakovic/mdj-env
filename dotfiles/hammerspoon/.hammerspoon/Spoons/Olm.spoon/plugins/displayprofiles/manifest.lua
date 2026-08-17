-- DisplayProfiles, what it declares about itself.
--
-- The one external tool is the arrangement engine itself, displayplacer, resolved
-- once and handed to engine.lua, which never probes for it on its own. Without it
-- the spoon still starts, it simply manages nothing and says why.
return {
  -- The directory is displayprofiles, one word, while the identity everywhere
  -- outside this folder, config/keys.lua, the registry, the launcher row, is
  -- displayProfiles.
  name = "displayProfiles",

  needs = {
    tools = {
      { name = "displayplacer", kind = "path", policy = "optional",
        reason = "reading and applying display arrangements",
        origin = { brew = "displayplacer" } },
    },
    -- Everything below is a fact about this machine or this person's own monitors,
    -- and none of it can be shipped as a working default on a fresh install.
    data = {
      -- Keyed by host, the whole profiles table out of config/displays.lua rather than one
      -- machine's slice of it. This plugin takes its own slice, using the host below, so a
      -- person's own file stays one plain table and nothing in between has to know its shape.
      profiles = { source = "user", policy = "optional",
        breaks = "no curated arrangement exists for this host, so the tool manages "
          .. "nothing here until one is added to config/displays.lua or captured "
          .. "from the chooser" },
      host = { source = "root", policy = "optional",
        breaks = "no curated arrangement can be found, since they are keyed by host, and the "
          .. "captured store has no key to save under either, so it is disabled and the "
          .. "chooser is empty" },
      storePath = { source = "root", policy = "optional",
        breaks = "the captured profile store has no file to read or write, so it "
          .. "is disabled and the chooser shows only the curated profiles" },
      settleDelay = { source = "user", policy = "optional",
        breaks = "a burst of screen events is coalesced with the built in one and a "
          .. "half second window rather than one tuned for this setup" },
    },
  },

  -- No provides. This tool has no alias in config/keys.lua, so it is reached only by
  -- opening the picker itself, never by a typed scope.

  -- Opened from the launcher only, so it proposes no key at all.
  defaults = {
    description = "Display Profiles",
    launcherRow = true,
  },

  -- A nested menu you navigate, enter rather than the shared insertSelected, since
  -- selecting through the native chooser would close it and force a re show. No
  -- matcher and no pane, this plugin's own Chooser instance hardcodes matcher false
  -- itself regardless of anything injected, since its supplier morphs the rows from
  -- the query rather than filtering a fixed list, and it reserves no companion pane.
  surface = {
    context = "displayProfiles",
    primary = { action = "enter", description = "Select" },
  },

  -- Configure alone leaves this plugin half wired. Start begins the screen watcher
  -- and its first reconcile, and the inspect and manage picker lives on the chooser
  -- submodule, which needs its own configure, for the view deps this root injects
  -- on top of the api this plugin's own configure already hands it, and its own
  -- start before it can be shown at all.
  wiring = {
    { method = "start" },
    { target = "chooser", method = "configure" },
    { target = "chooser", method = "start" },
  },

  -- show lives on the chooser submodule as a plain dot called function, function M.show(),
  -- never a colon method, so open says so, and the chooser is the surface too, a table
  -- rather than a function, so it needs no call convention of its own.
  registry = {
    row = { category = "Displays", detail = "inspect and manage arrangements", glyph = "🖥️" },
    open = { member = "chooser.show", call = "dot" },
    surface = "chooser",
  },
}
