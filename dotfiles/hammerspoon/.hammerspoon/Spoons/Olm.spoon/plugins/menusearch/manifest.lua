-- MenuSearch, what it declares about itself.
--
-- Pure composition root policy over the shared Chooser atom and the Accessibility api
-- hs.application already exposes, so it names no external tool and declares no tools. There
-- is no needs.tools table here at all, since a present field is a claim and this plugin has
-- nothing to claim.
--
-- Migrated onto host/stage, phase five of the chooser stage build, docs/PLAN-CHOOSER-STAGE.md,
-- promoted ahead of the remaining plugins because the slow hyper e open was the original
-- complaint and does not need any of them. This file owns no chooser of its own any more and
-- builds no window, its presentation block below is the whole of what used to be a Chooser.new
-- call and a hand rolled surface adapter and panel wiring, following VPN's own migration, the
-- proving consumer, exactly. Its own leader key still opens it, through cfg.stagePresent, the
-- root published word every presenting plugin's own hotkey door shares.
--
-- Its two collaborators from the launcher are unchanged by this migration. coveredApp and
-- refreshLauncher are declared and ordering false for the identical reason the note that used
-- to sit here explained. Each arrives as a closure called when a person types rather than
-- while anything is being wired, and this plugin is deliberately configured BEFORE the
-- launcher, so an eager edge would invert that order for no reason.
--
-- Three more collaborators join for the snapshot cache, docs/BRIEF-MENUSEARCH-CACHE.md. storage
-- is lib/storage.lua itself, asked for under a field name other than the module's own so the
-- generic needs.lib grant hands over the raw module rather than the one fixed instance
-- services.perPlugin automatically builds for a plugin that declares needs.lib.recency, since
-- this plugin wants one recency instance per bundle id rather than one for the whole plugin,
-- decision three of the cache brief, and only a raw module can build more than one of anything.
-- stagePresent, redrawPresented, and stageSelectedRow are three root published words under one
-- name apiece, the last one added by this migration for a background correction to ask whether
-- the highlight has moved off row one before it is safe to redraw in place.
return {
  -- The registry and every sibling lookup know this plugin as menuSearch, camel
  -- cased, while the directory beside this file is menusearch, lowercase.
  name = "menuSearch",

  needs = {
    siblings = {
      -- Which application the launcher opened over, which is the whole subject of this
      -- plugin, since the menus it searches belong to that app and not to the launcher.
      coveredApp = { plugin = "launcher", member = "coveredApp", call = "method",
        policy = "required", ordering = false },
      -- Poking the launcher to draw again once this plugin's own scope read lands, the same
      -- late answer shape the browser tab and relay lists take.
      refreshLauncher = { plugin = "launcher", member = "refresh", call = "method",
        policy = "optional", ordering = false },
    },

    lib = {
      -- Declared under "recencyLib" rather than "recency" on purpose. The key "recency" is
      -- what lib/services.lua's own perPlugin function watches for to auto build ONE instance
      -- keyed to this plugin's own name, the right shape for almost every scoped tool and the
      -- wrong one here, since one instance shared across every app would prune one app's dead
      -- menu paths using a different app's fresh read's path set. A different field name still
      -- resolves the same module, lib/recency.lua, through the ordinary generic grant, but
      -- hands over the module itself, the thing with a new function on it, so this plugin can
      -- build as many instances as it opens apps, one per bundle id, lazily, each keyed to its
      -- own settings slot.
      recencyLib = { from = "recency", policy = "optional" },
      -- The path mechanism every snapshot is written under, lib/storage.lua's own cacheDir,
      -- required because the whole point of this migration, an open that never waits on the
      -- accessibility walk, has nothing to draw from instantly without it. Every environment
      -- this config runs in configures storage at start, so this is never genuinely absent,
      -- and the guard would rather be structural than trust that forever.
      storage = { from = "storage", policy = "required" },
    },

    data = {
      stagePresent = { source = "root", policy = "optional",
        breaks = "this plugin's own leader key opens nothing, since the hotkey has no other way to reach the shared stage" },
      redrawPresented = { source = "root", policy = "optional",
        breaks = "a background correction that lands while this plugin's own presentation is showing never reaches the screen until the next open" },
      stageSelectedRow = { source = "root", policy = "optional",
        breaks = "a background correction can no longer tell whether the highlight has moved off row one, so it always redraws in place at once rather than deferring while a considered row is on screen" },
    },
  },

  -- Scoped by the launcher, the alias lists the frontmost app's menus the same way
  -- the picker does and choosing one runs the same item. It is a discovery opener,
  -- so it has no launcher row of its own, the aliases are found in the alias
  -- directory instead.
  provides = {
    rows = "rows",
    select = "select",
  },

  defaults = {
    leader = "app",
    key = "e",
    description = "Menu search",
    glyph = "📋",
    aliases = { "m", "menu" },
  },

  -- Unchanged by the migration, decision eight of the handoff brief kept for every presenting
  -- plugin since VPN. context, primary, and nav are still what plan.contexts is built from and
  -- what the navigation bind loop still binds this plugin's own keys against, only who answers
  -- for them once fired now differs. panelAs is gone, the docked shortcut panel is atom level
  -- policy host/stage owns for the life of its one instance rather than something a presenting
  -- plugin's own configure reads any more.
  --
  -- This plugin still earns the docked panel triple regardless, review finding L7, since
  -- lib/services.lua builds it for any plugin with a surface and a context that resolves, with
  -- no way to ask for a surface's own navigation wiring without it. VPN carries the identical
  -- residue for the identical reason. Both are deliberate, three unread fields on opts rather
  -- than a special case in a shared function for the one or two plugins that no longer read
  -- them.
  surface = {
    context = "menuSearch",
    primary = { action = "insertSelected", description = "Run" },
  },

  -- The presentation contract, BRIEF-STAGE.md version one plus its own PLUGIN-CONTRACT.md
  -- paragraph. rows and select are this plugin's own self.rows and self.select, assigned as
  -- plain closures inside configure exactly the way self.open and the two scope functions
  -- already are, so every member here says call = dot, stated outright, never the bare string
  -- shorthand this contract allows everywhere else a member is not a presentation's own. Every
  -- one of these is also resolved fresh against the real module every time it runs rather than
  -- once here, the same laziness a plugin building its own surface inside configure already
  -- relies on, which is exactly this plugin's own shape. placeholder alone resolves once, at
  -- register, since the contract wants a presentation to carry a plain string rather than a
  -- function to call again. onPresent is where the target app is captured and the background
  -- read for it begins, the identical seam VPN's own onPresent starts its fetch from, never
  -- blocking the swap that is about to happen, since the read this plugin starts here runs off
  -- the main thread and the instant snapshot the open already drew from is what the window
  -- shows the moment it appears. onClose, review finding M3, is told once whenever the
  -- stage hides entirely, never on a swap, and is what clears the highlight gate's own per
  -- entry bookkeeping, so a correction that lands after a genuine close is judged on its own
  -- terms rather than held back by a row number a hidden hs.chooser instance is still sitting
  -- on from before the hide.
  presentation = {
    rows = { member = "rows", call = "dot" },
    select = { member = "select", call = "dot" },
    placeholder = { member = "placeholder", call = "dot" },
    onPresent = { member = "onPresent", call = "dot" },
    onClose = { member = "onClose", call = "dot" },
  },

  -- open, scopeRows and scopeRun are all assigned as plain closures inside this plugin's own
  -- configure, self.open, self.scopeRows, self.scopeRun, so none of them expects a receiver,
  -- and every one below says dot rather than taking the default. No row, since this tool is a
  -- discovery opener reached through the alias directory rather than a launcher row of its own.
  -- No registry.surface, a presenting plugin declares none, PLUGIN-CONTRACT.md's own rule,
  -- since host/stage's own surfaceFor answers isShowing, selectNext, selectPrev,
  -- insertSelected and hide for this plugin's own identity once registry.presentationFor
  -- answers something for it, and a surface entry here would be a second answer nobody reads.
  registry = {
    open = { member = "open", call = "dot" },
    shortcut = "leader",
    scope = {
      rows = { member = "scopeRows", call = "dot" },
      run = { member = "scopeRun", call = "dot" },
    },
  },
}
