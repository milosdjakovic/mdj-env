-- BrowserTabs, what it declares about itself.
--
-- The third of the prototype three because it fails differently again. It has providers
-- the root names, persisted per machine state, a nested settings level, and it opts out of
-- the shared matcher, so it exercises the parts of the manifest the other two do not.
return {
  -- The directory is browsertabs, one word, while the identity everywhere outside this
  -- folder, config/keys.lua, the registry, the launcher row, is browserTabs.
  name = "browserTabs",

  needs = {
    -- Ordering the list by what you looked at last. A plain reusable mechanism, so it
    -- comes from lib rather than from a sibling plugin. Optional, and without it the
    -- resting order simply stands.
    lib = {
      -- limit is a cap on how many remembered tabs are kept, and it is declared rather than
      -- left off because a browser session is the one list here big enough for unbounded to
      -- mean something. The retired root passed two thousand and nothing carried it over, so
      -- the remembered order was left to grow with no ceiling at all.
      recency = { from = "recency", policy = "optional", limit = 2000 },
    },
    tools = {
      { name = "osascript", kind = "system", locator = "/usr/bin/osascript", policy = "optional", unit = "jxa",
        reason = "runs the JXA that asks each browser for its open tabs",
        origin = { macos = "ships with the system" } },
      -- swiftc is absent on a fresh install until the command line tools go on, so this is not
      -- a macos origin the way the sibling lines above and below are, it is a thing to install
      -- rather than a thing already present, and the origin has to say so honestly.
      { name = "swiftc", kind = "system", locator = "/usr/bin/swiftc", policy = "optional", unit = "permissions",
        reason = "builds the helper that asks for automation permission per browser",
        origin = { ["xcode-clt"] = "xcode-select --install" } },
      -- Runtime, and separate from the test stage line below that happens to name the same
      -- binary. The permission surface opens the Automation pane by URL, which is the only
      -- route left once a browser has been refused, and that is a running feature rather than
      -- part of the harness.
      { name = "open", kind = "system", locator = "/usr/bin/open", policy = "optional", unit = "permissions",
        reason = "opening the Automation pane, the only way to undo a refused browser",
        origin = { macos = "ships with the system" } },
      -- Test only, so none of the four below ever reach an install proposal for someone who
      -- just wants the tool. Same separation the emoji dataset builders use. All four came from
      -- the integration harness's own beside file declaration rather than being invented here,
      -- and all four name that file as their unit.
      { name = "jq", kind = "path", policy = "optional", stage = "test", unit = "test/harness",
        reason = "reads every answer the integration harness gets back from the browsers",
        origin = { brew = "jq" } },
      -- The harness runs the browser adapters and the accessibility witness through osascript
      -- itself, in six of its own files, so it declares the tool rather than leaning on the jxa
      -- provider's runtime line above happening to name it. The tool would have been installed
      -- either way, since two other units declare it, and what was missing is the harness's own
      -- claim on it, which is what a person reads to know why it is needed.
      { name = "osascript", kind = "system", locator = "/usr/bin/osascript", policy = "optional",
        stage = "test", unit = "test/harness",
        reason = "runs the browser adapters and the accessibility witness that judges each round",
        origin = { macos = "ships with the system" } },
      -- The harness once carried each command to the agent as a URL and declared open for it. It
      -- does not any more, and lib/hs.sh says at length why, opening a URL goes through Launch
      -- Services, which takes focus, and focus is the very thing most of these rounds measure. The
      -- channel is files on both sides now and nothing in the harness activates anything. The
      -- declaration outlived the mechanism, which is what a declaration does when nothing checks
      -- it against the code, so it is gone rather than carried forward.
      { name = "ioreg", kind = "system", locator = "/usr/sbin/ioreg", policy = "optional", stage = "test", unit = "test/harness",
        reason = "asks the window server whether the screen is locked, which the accessibility layer cannot be trusted to report about itself",
        origin = { macos = "ships with the system" } },
      { name = "caffeinate", kind = "system", locator = "/usr/bin/caffeinate", policy = "optional", stage = "test", unit = "test/harness",
        reason = "holds the display awake for a run, since a suite drives the machine with synthesised events and the idle timer does not count those",
        origin = { macos = "ships with the system" } },
    },
    -- Safari and Arc each carry their own bundle id inside their own provider file, so
    -- neither needs anything handed in. Chrome is different, the Chromium provider is a
    -- factory shared by five applications, so it is the one browser whose identity this
    -- plugin cannot know on its own.
    data = {
      -- Optional, and the breaks sentence below is the proof. It describes ONE browser
      -- dropping out, not the tool failing, and Safari is the default this ships enabled
      -- precisely because macOS guarantees it. Required would have blocked the whole plugin
      -- on a fresh install and taken Safari's tabs down with it, over an application that
      -- may well not be installed. The policy has to agree with the sentence.
      chromeBundleID = { source = "user", policy = "optional",
        breaks = "Chrome never joins the provider list, since the shared Chromium factory "
          .. "refuses to build without a bundle id, so no Chrome tab is ever listed no "
          .. "matter how the browser is switched on" },
    },
  },

  provides = {
    rows = "rows",
    select = "select",
  },

  -- W reads as web, since B is the Books toggle and T the Stickies one.
  --
  -- `enabled` is the fresh install answer, and it is one browser rather than all of them
  -- on purpose. Safari is the only one macOS guarantees is there, so a new machine
  -- scripts exactly one browser and raises exactly one Automation prompt, and the rest
  -- are switched on deliberately by whoever wants them.
  --
  -- `providers` is the shipped browser order, by name, and it belongs here rather than in the
  -- needs above because nothing outside this plugin has to know anything for it to work. The
  -- names are resolved against the providers directory by this plugin's own configure, so a
  -- person reordering the list, or dropping a browser they do not use, edits one line and needs
  -- no bundle id and no knowledge of which file answers to which word. Chrome sits between the
  -- other two because it is the one that only appears when its bundle id was supplied.
  --
  -- The order is not cosmetic. It is where each browser's tabs rest in the list before this tool
  -- has ever opened one, so it is the answer to what you see first on a fresh machine.
  defaults = {
    leader = "app",
    key = "W",
    description = "Browser tabs",
    glyph = "📑",
    aliases = { "t", "tabs" },
    providers = { "safari", "chrome", "arc" },
    enabled = { "safari" },
  },

  surface = {
    context = "browserTabs",
    -- `enter` rather than the shared insertSelected, because this is a menu with a
    -- settings level behind its last row and stepping into it must not close and re show.
    primary = { action = "enter", description = "Select" },
    -- No matcher line, and its absence is the correct statement rather than an omission.
    -- This plugin scores its own rows, because a uniform filter would rank away the Back row
    -- and pull the Settings row into the tab ranking, and it opts its own Chooser instance out
    -- in its own code at chooser.lua line 341. That opt out is an internal decision and the
    -- manifest has no business restating it. What the manifest would be saying with a value
    -- here is which STRATEGY to inject, and this plugin wants the shared default, which
    -- bestFieldScore at chooser.lua line 291 then uses to rank the tabs. Writing false here
    -- injected nothing and quietly degraded ranked tabs to unranked order.
  },

  -- Configure alone leaves this plugin half wired. Start warms the permission probe so
  -- the first settings open is instant, and the picker itself lives on the chooser
  -- submodule, which needs its own configure and its own start before a tab can show.
  wiring = {
    { method = "start" },
    { target = "chooser", method = "configure" },
    { target = "chooser", method = "start" },
  },

  -- show is a colon method on this plugin's own root, obj:show(), so open takes the default
  -- call, and the chooser submodule is the surface. scopeRows and activate both live on that
  -- same submodule as plain dot called functions, so the scope below says dot rather than
  -- taking the default. scopeRows is the one member the chooser did not use to expose. It
  -- joins M.prepare and M.tabRows exactly the way M.show already does through M.reload, and
  -- it takes a second argument, redraw, since a scope has no chooser of its own to refresh
  -- once the fetch answers. Olm hands that callback over so this plugin still never learns a
  -- launcher exists, closing the one real cross plugin coupling the retired root's own
  -- registration carried, spoon.BrowserTabs's scope calling spoon.Launcher:refresh() directly.
  -- matcher is false for the same reason the surface block above states one nowhere, this
  -- plugin scores its own rows and a second, uniform pass would rank the Back row away.
  registry = {
    row = { category = "Tools" },
    open = "show",
    surface = "chooser",
    hosted = true,
    shortcut = "leader",
    scope = {
      matcher = false,
      rows = { member = "chooser.scopeRows", call = "dot" },
      run = { member = "chooser.activate", call = "dot" },
    },
  },
}
