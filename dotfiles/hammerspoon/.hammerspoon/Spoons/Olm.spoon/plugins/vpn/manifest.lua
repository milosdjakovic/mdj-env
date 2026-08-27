-- Vpn, what it declares about itself.
--
-- One backend, Mullvad, plus the shared lift to front ordering service borrowed from lib so
-- the location list opens already sorted by what was used last. When Mullvad is absent the
-- list still opens, to one row naming the missing tool, so this plugin is safe to wire on
-- any machine.
--
-- Migrated onto the shared stage, phase three of the chooser stage build, the proving
-- consumer docs/BRIEF-HANDOFF.md decision eight names, chosen for being an ordinary shape,
-- a five function surface, one recency order, one async status refresh, no companion pane,
-- no private eventtap. It owns no chooser of its own any more and builds no window, its
-- presentation block below is the whole of what used to be a Chooser.new call and a hand
-- built surface adapter.
return {
  needs = {
    -- Remembering the last used city, so the list opens already ordered by that. This
    -- said optional once, which promised the panel would still open and still connect
    -- with the resting order lost. The plugin's own configure does not honour that
    -- promise, it hard errors when opts.recency is nil, by its own comment's account
    -- deliberately, "rejected loudly rather than quietly ordering nothing." The code and
    -- its own stated intent agree with each other and disagree with this manifest, so the
    -- manifest is the one that was wrong. Required.
    lib = {
      recency = { from = "recency", policy = "required" },
    },
    tools = {
      { name = "mullvad", kind = "path", policy = "optional", unit = "mullvad",
        reason = "the relay CLI behind every VPN control and location",
        origin = { cask = "mullvad-vpn" } },
    },

    -- Two root computed words, phase three, both published for every presenting plugin to
    -- share under the same names rather than invented here, so declaring them is asking for
    -- vocabulary the root already speaks rather than proposing a word of this plugin's own.
    -- Neither breaks anything structural when absent, both degrade to a key or a status
    -- change that quietly does nothing, which is why both are optional.
    data = {
      stagePresent = { source = "root", policy = "optional",
        breaks = "this plugin's own leader key opens nothing, since M.show has no other way to reach the shared stage" },
      redrawPresented = { source = "root", policy = "optional",
        breaks = "the list stays on its last read status and location until the field is touched, since the daemon changing state no longer redraws whatever is on screen" },
    },
  },

  -- configure alone leaves this plugin with no engine. start resolves the tool's
  -- availability and wires the engine when it is present, so it is a real step beyond
  -- configure rather than an empty lifecycle method.
  wiring = {
    { method = "start" },
  },

  -- Scoped by the launcher, typing the alias and a space lists the same controls and
  -- locations the presentation does and choosing one does the same thing.
  provides = {
    rows = "rows",
    select = "select",
  },

  defaults = {
    leader = "app",
    key = "P",
    description = "VPN",
    glyph = "🌐",
    aliases = { "v", "vpn" },
  },

  -- One flat list, the controls on top and every city below, so it takes the shared
  -- navigation with nothing beyond the primary key. Unchanged by the migration, this block
  -- is what plan.contexts["vpn"] is still built from, presentation below only changes what
  -- object answers isShowing and where the rows themselves come from.
  surface = {
    context = "vpn",
    primary = { action = "insertSelected", description = "Confirm" },
  },

  -- The presentation contract, BRIEF-STAGE.md version one, docs/BRIEF-HANDOFF.md decision
  -- three. rows and select are this plugin's own M.rows and M.select, the identical members
  -- provides above already names, since the merged control and location list the old
  -- Chooser.new block read from is exactly what the stage wants too, there was never a
  -- second list to build. placeholder resolves once, at register time, to whatever M's own
  -- placeholder member currently answers, which depends on the availability this plugin's
  -- own start already resolved by then. onPresent, added in the phase three review's own
  -- second finding, names M.onPresent, the fetch M.show used to start directly before this
  -- plugin owned no window to reveal, now run whenever the stage makes this presentation
  -- current through either door rather than only the hotkey one. Every member here is dot
  -- called, like every function this plugin exposes, and every one is checked to actually
  -- resolve on this plugin's own module at register, lib/registrar.lua's own new refusal,
  -- so a typo here would keep this whole tool out of the catalogue rather than open to a
  -- silently empty list.
  presentation = {
    rows = { member = "rows", call = "dot" },
    select = { member = "select", call = "dot" },
    placeholder = { member = "placeholder", call = "dot" },
    onPresent = { member = "onPresent", call = "dot" },
  },

  -- show, and every scope action below, are plain dot called functions on this plugin's own
  -- root, never colon methods, so every one of them says call = dot rather than taking the
  -- default. scopeRows is the one member this plugin's own module did not use to expose. It
  -- joins M.prepare and M.rows exactly the way M.show already does either side of revealing
  -- its own list, and it takes a second argument, redraw, since a scope has no chooser of
  -- its own to refresh once the fetch answers. Olm hands that callback over so this plugin
  -- still never learns a launcher exists, closing the one real cross plugin coupling the
  -- retired root's own registration carried, spoon.Vpn's scope calling spoon.Launcher:refresh()
  -- directly. This whole block is unchanged by the migration, decision eight, its scope stays
  -- exactly as is.
  --
  -- surface, no longer declared. It used to be true, the plugin root itself, since M carried
  -- isShowing, selectNext, selectPrev, insertSelected, and hide directly. All five are gone
  -- now, deleted along with the Chooser.new block that gave them something to answer for, so
  -- there is nothing left here for a caller to find. The composition root routes a presenting
  -- plugin's own navigation through the shared stage instead, once presentation above exists
  -- for it to ask for, so this field would be dead weight rather than a second answer.
  registry = {
    row = { category = "Network" },
    open = { member = "show", call = "dot" },
    hosted = true,
    shortcut = "leader",
    scope = {
      rows = { member = "scopeRows", call = "dot" },
      run = { member = "select", call = "dot" },
    },
  },
}
