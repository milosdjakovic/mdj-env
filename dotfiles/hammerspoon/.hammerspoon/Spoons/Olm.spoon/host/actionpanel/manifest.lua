-- ActionPanel, what it declares about itself.
--
-- A host, and a decorator rather than a coordinator. It is installed once at the chooser
-- atom's decorate seam, so every list gains it without any of the twelve places a chooser is
-- built learning it exists. That is why it declares no surface of its own despite being a
-- list, the list it shows is always somebody else's, borrowed for as long as the panel is up.
--
-- The single most load bearing fact about how this plugin is actually wired has nowhere to go
-- in this file. Configure succeeding proves nothing on its own, decorate must ALSO be
-- installed at the shared Chooser atom's own configure call, as its decorate hook, before the
-- first list anywhere is built, or every instance keeps its own rows and this plugin decorates
-- nothing. That is a fact about being installed into ANOTHER module's configuration, not about
-- a sibling plugin or a lib capability this plugin receives, and neither needs nor wiring has
-- a field for it. A wiring step can only call a method on this plugin's own root or its own
-- submodule, never on a shared lib atom, and a needs entry can only ask for something handed
-- TO this plugin, never state that this plugin must be handed to someone else first. So this
-- stays true only because the composition root remembers to do it in the right order, exactly
-- the risk already named as this plugin's biggest one.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Action Panel",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  -- The one icon the panel states for itself, the Back row it puts first. The verbs below it
  -- name the icons of the plugin that owns their context and never this one.
  icons = {
    back = { emoji = "⬅️", sf = "chevron.left" },
  },

  needs = {
    -- What it shows is every VERB the live context carries, and never the shared navigation.
    -- Classifying an action as one or the other is policy that spans every context, so the
    -- root owns it and hands it in as plain data this plugin cannot derive for itself.
    --
    -- This used to be a needs.root category naming kindOf, rowsFor, and run. Nothing in the
    -- loader ever reads needs.root, tools, siblings, lib, data, and set are the only
    -- categories read, so it was documentation with no enforcement path, silently unchecked
    -- on every load. Moved to needs.data, source root, the category this schema already has
    -- for a value Olm's own composition computes and owes itself.
    data = {
      kindOf = { source = "root", policy = "required",
        breaks = "configure refuses to run, since the panel would have nothing telling a verb from navigation and could not honour the one promise it makes" },
      rowsFor = { source = "root", policy = "required",
        breaks = "configure refuses to run, since the panel would have no ordered rows to build for any context it borrows" },
      run = { source = "root", policy = "required",
        breaks = "configure refuses to run, since a chosen verb would have nowhere to go once the row it acted on was restored" },
      -- The one rank engine, lib/chooser/rank.lua, and the strategy it filters the panel's own
      -- rows with when the presentation under the panel owns its filtering. Both handed over by
      -- the root, so this host keeps no filter loop of its own, docs/PLAN-UNIFIED-SEARCH.md, and
      -- the choice of strategy stays where every other one is made.
      rank = { source = "root", policy = "optional",
        breaks = "typing while the panel is open over a list that owns its own filtering narrows nothing, every verb stays listed" },
      ownRowsMatcher = { source = "root", policy = "optional",
        breaks = "typing while the panel is open over a list that owns its own filtering narrows nothing, every verb stays listed" },
    },
  },

  -- Its own chord is o, and it is deliberately classified as navigation rather than a verb so
  -- the panel can never list its own way in among the verbs it offers.
  --
  -- The key is NOT declared here, and neither is a leader. lib/surface.lua appends the binding
  -- to every context it builds, which is what makes a thirteenth context carry it for free, and
  -- the chord only exists inside an open list. A leader and key declared here would make the
  -- plan treat o as a key held on the app leader, and the Hyper cheat sheet reads exactly that
  -- to draw its rows, so it listed a key nothing binds there. A sheet lists only what its
  -- leader binds, so this plugin states a description and nothing that places it on a leader.
  defaults = {
    description = "Actions",
  },
}
