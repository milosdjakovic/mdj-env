-- Launcher, what it declares about itself.
--
-- The largest host, and the one that shows why hosts needed a declaration kind of their own.
-- It receives sixteen fields today, and almost none of them are a named sibling. They are
-- either a question about the whole plugin set, a plain mechanism from lib, or user data.
return {
  needs = {
    -- Three questions about the set, none of which names a plugin.
    --
    -- `surfaces` is what the root currently keeps as a hand written list of twelve, used to
    -- decide which chooser is open so navigation can be routed to it. Any plugin declaring a
    -- surface belongs in it, so the list is an answer rather than a fact and should be
    -- computed. A hand kept copy is one plugin behind from the day someone forgets.
    --
    -- `queryRows` is the computed row sources, the ones that turn a typed query into rows and
    -- claim nothing, which is arithmetic and unit conversion today. They are separated from
    -- scopes because claiming the query is exactly the difference, and folding the two
    -- together would let a calculator swallow the catalog.
    --
    -- The loader excludes this plugin's own name from its own answer to `surfaces` before that
    -- answer becomes a wiring edge, since this plugin's manifest declares a surface too and
    -- would otherwise be a dependency of itself. That exclusion lives in the loader, once,
    -- rather than as a rule this manifest has to know about itself.
    set = {
      surfaces  = { has = "surface" },
      scopes    = { provides = { "rows", "select" } },
      queryRows = { provides = { "queryRows" } },
      -- A plugin whose own keyed actions each deserve a row in this list, rather than one row
      -- for the plugin as a whole. Capture is the case and may stay the only one. Asking the
      -- set is what keeps the four screenshot rows built from that plugin's own bindings, so
      -- moving one of its keys moves the row with it instead of leaving a copy here to drift.
      actionRows = { provides = { "actionRows" } },
    },

    lib = {
      -- The tool registry, phase seven of the build plan. The real code disagrees with the
      -- policy this used to say. host/launcher/init.lua's own comment states it outright, "a
      -- launcher configured without one dispatches a special row through actions.special
      -- alone... since a host that hard requires one cannot be tested without one", and
      -- configure never asserts on it, it only reads `opts.registry` with no guard. Corrected
      -- from required to optional to match what the code actually does.
      registry  = { from = "registry", policy = "optional" },
      glyphIcon = { from = "glyphicon", policy = "optional" },
      -- The shared chord glyph renderer, dot called. Read by `_chordLabel` to print a chord as
      -- words, "Hyper ⌘4", rather than as a bare key. Optional, since configure already falls
      -- back to `tostring(key)` with no glyph styling.
      --
      -- The comment said dot called for a long time while the declaration did not, and saying
      -- it is not the same as declaring it. Bound as a method instead, every call arrived with
      -- the cheat sheet module in the key parameter and the real key in the mods parameter, so
      -- every chord printed in a launcher subtitle was drawn from the wrong two arguments.
      glyphFor  = { from = "cheatsheet", member = "glyphFor", call = "dot", policy = "optional" },
    },

    -- A sibling naming clipboard.setContents used to sit here for actions.copy. It named a
    -- capability that does not exist. Asked against the real, loaded clipboard module, it has
    -- no setContents, its own manager comment says the outward pasteText and copySelection
    -- wrappers it used to carry are gone, and the real code confirms it, host/launcher's own
    -- actions.copy is `function(value) hs.pasteboard.setContents(value) end`, a plain call
    -- with nothing behind it from any plugin. So the line is removed rather than repaired
    -- into the new table form, since converting the shape of a need that names nothing real
    -- would only carry the same defect forward in a tidier spelling.
    --
    -- windowActions is real and was undeclared. `spoon.WindowManager:actions()` is a genuine
    -- sibling capability, a colon method answering the action name to handler map the window
    -- rows in this catalog dispatch through. Optional, since an absent map only drops those
    -- rows one at a time, `if self._windowActions[b.action] then add(...) end`, rather than
    -- failing anything.
    -- Every leaf a chosen row dispatches to. This catalogue owns the kind switch and nothing
    -- else, so each leaf is a capability declared here and injected, which is what lets the
    -- file itself name no plugin at all. The composition root used to hold these as closures
    -- and could not honestly resolve them without naming a plugin, so it left them unset and
    -- said so, which meant choosing an app row, a capture action or a settings pane did
    -- nothing at all with no error anywhere.
    --
    -- Every one is optional, because a row of a kind nothing provides is simply never built,
    -- and every one is ordering false, because a leaf is called when a person picks a row
    -- rather than while anything is being wired, so needing it says nothing about who goes
    -- first. Making them ordering true would add edges that mean nothing and could only
    -- constrain the plan for no reason.
    siblings = {
      windowActions = { plugin = "windowmanager", member = "actions", call = "method", policy = "optional" },
      appFocus = { plugin = "apptoggler", member = "focusOrCycle", call = "method",
        policy = "optional", ordering = false },
      appToggleURL = { plugin = "apptoggler", member = "toggleURL", call = "method",
        policy = "optional", ordering = false },
      runCapture = { plugin = "capture", member = "capture", call = "method",
        policy = "optional", ordering = false },
      -- The function rather than its answer, since rows reads what that plugin's own configure
      -- set and asking it before that has happened answers an empty list, which is how the
      -- launcher lost every System Settings pane once already.
      settingsPaneRows = { plugin = "systemsettings", member = "rows", call = "method",
        policy = "optional", ordering = false },
      openSettingsPane = { plugin = "systemsettings", member = "open", call = "method",
        policy = "optional", ordering = false },
      focusSettingsSearch = { plugin = "systemsettings", member = "focusSearch", call = "method",
        policy = "optional", ordering = false },
    },

    -- Everything below is root or user data configure reads that this plugin cannot derive
    -- and that had no declaration anywhere. All eight are optional, because every one of them
    -- has a working, if diminished, absence already built into configure, none of them make
    -- this plugin refuse to wire.
    data = {
      -- The per app toggle list, the same value the app toggler and the Hyper cheat sheet both
      -- declare under this name, so one answer reaches all three and none of them is named by
      -- the person's own file.
      --
      -- This used to ask for the whole key catalog and reach inside it for this one field,
      -- which made the person hand over everything to supply one thing and made this host know
      -- a field name inside somebody else's data. Every other use of that catalog here is gone,
      -- the curated rows became shipped declarations and the per tool chords now come off each
      -- tool's own registration, so the catalog itself is no longer wanted.
      toggles = { source = "user", policy = "optional",
        breaks = "no application toggle appears in the catalogue, so an app bound to a Hyper letter can be launched by that letter but never found by searching for it here" },
      -- config/apps.lua, the bundle id registry. Only used here to label an app row's own
      -- Hyper shortcut, the app rows themselves come from a real disk scan and need no
      -- registry to exist at all.
      apps = { source = "user", policy = "optional",
        breaks = "every app row loses its Hyper shortcut subtitle, since nothing maps a toggle's app name to the bundle id a scanned app row is keyed by" },
      -- `spoon.SystemSettings:rows()`, called once by the root and handed in as a plain list.
      -- Root computed rather than a sibling here, since what this plugin wants is the
      -- concrete list a method call produced, not the method itself. The set query above
      -- already makes systemsettings an ordering edge ahead of this plugin whenever it
      -- provides rows and select, so the sequencing this value depends on is covered there.
      settingsPanes = { source = "root", policy = "optional",
        breaks = "no System Settings pane is ever listed as a row, since nothing hands over the descriptors SystemSettings itself already assembled" },
      -- The shared predicate registry, gating a row's `when` the same way a Hyper context
      -- binding does.
      predicates = { source = "root", policy = "optional",
        breaks = "every row gated on a when name, previousDisplay and nextDisplay among them, disappears from the catalog instead of showing conditionally, since an unmatched name reads here as hide rather than as always active" },
      -- The one opaque field this schema cannot see into. `actions` is a nested table of
      -- closures, app, capture, settingsPane, rowIntercept, scope, scopePeek, scopeCanPeek,
      -- and a `special` map of bare commands, and six of those close over other plugins or
      -- hosts, WindowManager, AppToggler, Capture, SystemSettings, and QueryScope among them.
      -- needs.data can say this plugin needs SOME table here, it cannot say which capabilities
      -- live inside it, since the category is built for a plain value and this is a bundle of
      -- behaviour naming several other parts of the configuration at once.
      actions = { source = "root", policy = "optional",
        breaks = "choosing almost any row does nothing at all, an app opens nothing, a capture command runs nothing, a settings pane opens nothing, and every special command from lock to the alias directory is silent, since the one dispatcher this plugin calls has nothing to call" },
      -- What a row says about being reachable by a typed word, asked once per row while the
      -- action rows are built. Root computed, since it depends on aliases resolved after
      -- several other plugins have configured.
      aliasHint = { source = "root", policy = "optional",
        breaks = "no row ever states the word that would scope the launcher onto it, so a tool's alias still works when typed but is never discovered by reading its row" },
      -- The one spelling of a chord, shared with the docked hint bar so a row and a hint can
      -- never print two different words for the same key. Root computed, since the leader
      -- catalog and the glyph renderer both live there.
      chordLabel = { source = "root", policy = "optional",
        breaks = "every row that would name a keyboard shortcut shows its bare category instead" },
      -- The ordered query row sources, QueryScope plus whichever of arithmetic and convert
      -- are present. Root assembled from the `queryRows` set answer above plus QueryScope
      -- itself, which does not appear in that answer since it claims rather than provides.
      queryProviders = { source = "root", policy = "optional",
        breaks = "no typed calculation, unit conversion, or scoped alias ever appears in the list, since nothing supplies the sources that turn what was typed into rows" },
    },
  },

  -- Hyper and Space, and it is the one tool exempt from its own rule about every command
  -- being findable as a launcher row, since listing the finder inside the finder earns
  -- nothing.
  defaults = {
    leader = "app",
    key = "space",
    description = "Launcher",
    glyph = "🚀",

    -- Three scopes that narrow this host's OWN catalog rather than reaching any tool, so they
    -- have no plugin to be declared on and belong here, on the host whose rows they filter.
    -- Each names a kind of row this catalog already builds and the word that selects it.
    --
    -- They ship rather than being asked of the person because none of the three is a personal
    -- choice. That applications, window actions and System Settings panes are the three groups
    -- worth a word of their own follows from this catalog holding exactly those groups, and an
    -- install with no window manager simply builds no window rows, so the scope answers an
    -- empty list rather than needing to be removed. Losing them cost nothing visibly, which is
    -- why they went missing quietly, they are advertised only in the alias directory and each
    -- is reachable by typing a word nothing tells you about anywhere else.
    -- Rows for the handful of actions that answer to no registration. Each is a bare command
    -- with nothing behind it that a descriptor could describe, so each is stated here as plain
    -- data rather than written into the row builder, which is what keeps that builder naming
    -- nothing. lock and sleep are system calls, searchSettings focuses a field inside a pane
    -- and belongs to no plugin, overlayDisplay is a picker the composition root itself owns,
    -- and aliasDirectory is a scope about scopes.
    --
    -- A key here is a default this person may move. Where one is given the subtitle names the
    -- chord, and where none is the subtitle says what the row is for instead, which is right
    -- for the three that open from this list and nowhere else.
    specialRows = {
      { name = "searchSettings", description = "Search Settings",
        subTitle = "System · opens the System Settings search field", glyph = "🔍" },
      { name = "overlayDisplay", description = "Overlay Display",
        subTitle = "Displays · where panels and choosers appear", glyph = "🖥️" },
      { name = "aliasDirectory", description = "Aliases",
        subTitle = "Tools · every word that scopes this list", glyph = "🏷️",
        keywords = "alias aliases scope scopes shortcut words prefix" },
      { name = "lock", description = "Lock Screen", category = "System", key = "§", glyph = "🔒" },
      { name = "sleep", description = "Sleep", category = "System", key = "escape", glyph = "🌙" },
    },

    catalogScopes = {
      { name = "apps", kind = "app",
        description = "Applications", glyph = "🚀", aliases = { "a", "app" } },
      { name = "windowActions", kind = "window",
        description = "Window actions", glyph = "🪟", aliases = { "w", "window" } },
      { name = "settingsPanes", kind = "settingsPane",
        description = "System Settings", glyph = "⚙️", aliases = { "s", "system" } },
    },
  },

  -- Corrected against config/keys.lua's real launcher block rather than left as first
  -- written. The primary verb reads "Run" there, not "Open", the composition root only
  -- relabels it to "Open" live while the highlight sits on an application. The close key is
  -- "space" rather than the shared default "x", since space is also this plugin's own open
  -- key, which is the exact case lib/surface.lua's own top comment names as the reason a
  -- `close` override exists at all. And the gated "go back" row, listed rather than bound
  -- while a hosted list is showing, was missing entirely.
  surface = {
    context = "launcher",
    -- Where the object that answers the navigation verbs actually lives. This host builds a
    -- dot called adapter over its own Chooser instance in configure, and that adapter's own
    -- comment says the root is meant to drive it the way it drives every other picker. Nothing
    -- did, because every other tool is found through its registry entry and this one has no
    -- registry entry at all, being a host rather than a launcher row. So the most used list in
    -- the config was the one list where holding the leader and pressing j reached nothing.
    member = "_surface",
    -- This plugin's configure reads the docked panel's three callbacks nested under one
    -- field rather than as three flat ones, so the shape is named here. Four plugins
    -- disagree about this and the disagreement lives in their own configure contracts,
    -- so it has to be declared. Assuming the flat form silently removed the panel from
    -- every one of them while handing each three fields it never reads.
    panelAs = "shortcutPanel",
    primary = { action = "insertSelected", description = "Run" },
    close = { key = "space" },
    extra = {
      { key = "delete", action = "leavePage", when = "launcherHostingList", chord = false,
        description = "Go back" },
    },
  },
}
