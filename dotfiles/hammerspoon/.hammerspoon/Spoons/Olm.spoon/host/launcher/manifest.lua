-- Launcher, what it declares about itself.
--
-- The largest host, and the one that shows why hosts needed a declaration kind of their own.
-- It receives many fields, and since phase three of the core split none of them is a named
-- sibling. Each is a question about the whole plugin set, a plain mechanism from lib, root
-- data, or user data, so this host names no plugin.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Launcher",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  -- The icons the launcher states for the rows it owns, the catalog scopes and its own special
  -- rows, in the emoji set and the SF Symbol set. A tool's own row, and every row a plugin
  -- contributes, reads its own plugin's icons and never these. The search icon left with the
  -- System Settings search row and the window rows wear the window manager's own copy of
  -- windows, both since phase three of the core split, and windows stays here for the window
  -- catalog scope's own row. The System Settings scope's icon is settingsPanes, named for the
  -- scope it marks, since a key spelled settings is also a plugin's identity and core must not
  -- write a plugin's name.
  icons = {
    launcher = { emoji = "🚀", sf = "paperplane" },
    apps = { emoji = "🚀", sf = "square.grid.2x2" },
    windows = { emoji = "🪟", sf = "macwindow" },
    settingsPanes = { emoji = "⚙️", sf = "gearshape" },
    aliases = { emoji = "🏷️", sf = "tag" },
    lock = { emoji = "🔒", sf = "lock" },
    sleep = { emoji = "🌙", sf = "zzz" },
  },

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
      -- Every plugin that adds rows to this catalog, and every plugin that runs a row it owns.
      -- A contributor answers plain row descriptors from its own launcherRows member, built
      -- from its own bindings or its own data, so moving one of its keys moves the row with
      -- it instead of leaving a copy here to drift. A runner answers launcherRun, handed the
      -- chosen row's item. The two are separate questions because a query row source may own
      -- the rows it computes and run them without adding anything to the catalog. Asking the
      -- set is what lets this host list window actions, screenshots and System Settings panes
      -- while naming none of the plugins behind them.
      launcherRows = { provides = { "launcherRows" } },
      launcherRun = { provides = { "launcherRun" } },
      -- Every plugin that knows something about an installed app's row, the chord that brings
      -- the app forward and the url the row opens, keyed by bundle id. The app rows themselves
      -- come from this host's own disk scan, which is the catalog it searches and is launcher
      -- policy, so a supplier only adds to a row and never adds one.
      launcherAppDetails = { provides = { "launcherAppDetails" } },
    },

    lib = {
      -- The tool registry, phase seven of the build plan. The real code disagrees with the
      -- policy this used to say. host/launcher/init.lua's own comment states it outright, "a
      -- launcher configured without one dispatches a special row through actions.special
      -- alone... since a host that hard requires one cannot be tested without one", and
      -- configure never asserts on it, it only reads `opts.registry` with no guard. Corrected
      -- from required to optional to match what the code actually does.
      registry  = { from = "registry", policy = "optional" },
      -- The shared chord glyph renderer, dot called. Read by `_chordLabel` to print a chord as
      -- words, "Hyper ⌘4", rather than as a bare key. Optional, since configure already falls
      -- back to `tostring(key)` with no glyph styling.
      --
      -- The comment said dot called for a long time while the declaration did not, and saying
      -- it is not the same as declaring it. Bound as a method instead, every call arrived with
      -- the cheat sheet module in the key parameter and the real key in the mods parameter, so
      -- every chord printed in a launcher subtitle was drawn from the wrong two arguments.
      glyphFor  = { from = "cheatsheet", member = "glyphFor", call = "dot", policy = "optional" },
      -- What was picked the last time a query was typed, which is what orders this list once
      -- something has been typed into it. The raw module rather than a built instance, since
      -- lib/services.lua builds one only for a field literally named recency, and configure
      -- calls new itself against the two numbers under `ranking` below. Optional, because
      -- without it the list simply orders on the match alone, which is what it did before.
      queryassoc = { from = "queryassoc", policy = "optional" },
    },

    -- No siblings, since phase three of the core split. Seven used to sit here, the window
    -- manager's action map, the app toggler's focus or cycle and toggle by url, capture's run,
    -- and System Settings' rows, open and search focus, every one a leaf this catalog's
    -- dispatcher reached by naming a plugin. The rows and the runs now arrive through the two
    -- set questions above and the root data below, keyed by whoever owns a row, and bringing
    -- an application forward is core, lib/appfocus.lua, reached through actions.app. A host
    -- that names no plugin keeps working with any of them switched off.

    -- Everything below is root or user data configure reads that this plugin cannot derive
    -- and that had no declaration anywhere. Every one is optional, because every one of them
    -- has a working, if diminished, absence already built into configure, none of them make
    -- this plugin refuse to wire.
    data = {
      -- The stage, host/stage, the one host owning the live chooser instance this plugin
      -- presents into since the chooser stage build, phase two. Root computed, since the stage
      -- is one of the host modules the composition root alone is allowed to name, the same
      -- exception this manifest's own sibling table already used for the domain spoons this
      -- plugin's leaf actions call into.
      stage = { source = "root", policy = "optional",
        breaks = "this plugin builds no presentation and no navigation surface, so its list never opens at all, no window, no rows, and no way for the shared list keys to reach it" },
      -- One function answering every launcherAppDetails supplier above merged into one table
      -- keyed by bundle id, asked whenever the app rows are built. Root assembled because only
      -- the root may resolve a member on another plugin's module. This replaced the person's
      -- toggles and app registry, which this host read itself to put a chord on an app row,
      -- the same leak phase four of the core split removed from the Hyper sheet. The app rows
      -- need neither, they come from a disk scan.
      appDetails = { source = "root", policy = "optional",
        breaks = "no app row names the chord that brings its app forward, and an app row a toggle points at a pane opens the app instead" },
      -- One supplier per plugin answering the launcherRows set above, in the set's order, each
      -- a function answering that plugin's rows with the plugin's identity already stamped as
      -- the owner on every item. Root assembled because only the root may resolve a member on
      -- another plugin's module, and stamped there so a plugin never has to know its own
      -- identity for the routing to work.
      rowSuppliers = { source = "root", policy = "optional",
        breaks = "no screenshot, window action, System Settings pane or settings search row is listed, since nothing hands over the rows those plugins contribute" },
      -- Owner identity to a function running that owner's chosen row, one per plugin answering
      -- the launcherRun set above. Root assembled for the same reason.
      runners = { source = "root", policy = "optional",
        breaks = "choosing a contributed row, a screenshot, a window action, a typed window size or a System Settings pane, does nothing at all" },
      -- The shared predicate registry, gating a row's `when` the same way a Hyper context
      -- binding does.
      predicates = { source = "root", policy = "optional",
        breaks = "every row gated on a when name, previousDisplay and nextDisplay among them, disappears from the catalog instead of showing conditionally, since an unmatched name reads here as hide rather than as always active" },
      -- The one opaque field this schema cannot see into. `actions` is a nested table of
      -- closures, app, copy, rowIntercept, scope, scopePeek, scopeCanPeek, and a `special`
      -- map of bare commands, and every one closes over core alone, the app focus lib and the
      -- query scope and stage hosts among them, never a plugin. needs.data can say this
      -- plugin needs SOME table here, it cannot say which capabilities live inside it, since
      -- the category is built for a plain value and this is a bundle of behaviour.
      actions = { source = "root", policy = "optional",
        breaks = "choosing an app row opens nothing, a computed result copies nothing, and every special command from lock to the alias directory is silent, since the one dispatcher this plugin calls has nothing to call" },
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
      -- One example field hint per computed row source that proposes one, assembled by the
      -- root on the same walk that assembles the sources themselves. This host writes none of
      -- them, which is the whole point, a list of what the computed sources can do kept here
      -- would be a roster of other plugins' capabilities and would go stale the day one of
      -- them changed. Root computed, since only the root may read another plugin's own
      -- effective defaults.
      placeholderExamples = { source = "root", policy = "optional",
        breaks = "the empty field only ever says it searches apps and commands, so a person is never told that a typed sum or a unit conversion is answered here at all" },
      -- The one rank engine, lib/chooser/rank.lua, the same module both chooser providers rank
      -- through. This host scores and orders its catalog through it, putting only its learned
      -- query memory ahead, so it keeps no scoring loop of its own, docs/PLAN-UNIFIED-SEARCH.md.
      rank = { source = "root", policy = "optional",
        breaks = "typing filters nothing, the whole catalog stays listed in its resting order, since the engine that scores rows against what was typed is never handed in" },
    },
  },

  -- configure alone leaves this host with no app watcher, no app directory watchers, and no
  -- persisted recency loaded, none of which a table of options can start on its own, each is
  -- live state a real step has to begin owning. A real step beyond configure, so it is named
  -- here rather than left for the running set to never track the machine and the last pick to
  -- never float to the top, host/launcher/init.lua's own start doing nothing at all until
  -- something calls it.
  wiring = {
    { method = "start" },
  },

  -- Hyper and Space, and it is the one tool exempt from its own rule about every command
  -- being findable as a launcher row, since listing the finder inside the finder earns
  -- nothing.
  defaults = {
    leader = "app",
    key = "space",
    description = "Launcher",
    icon = "launcher",

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
    -- Rows for the handful of actions that answer to no registration and belong to no plugin.
    -- Each is a bare command with nothing behind it that a descriptor could describe, so each
    -- is stated here as plain data rather than written into the row builder, which is what
    -- keeps that builder naming nothing. lock and sleep are system calls and aliasDirectory is
    -- a scope about scopes. The System Settings search row sat here too until phase three of
    -- the core split, and it is that plugin's own now, since it calls that plugin's method.
    --
    -- A key here is a default this person may move. Where one is given the subtitle names the
    -- chord, and where none is the subtitle says what the row is for instead, which is right
    -- for the two that open from this list and nowhere else.
    -- How this list learns from what is picked in it. Both are plain numbers because both
    -- mean something arguable rather than naming a behaviour from a set, and both were
    -- chosen against a measurement rather than by feel.
    --
    -- `decay` is how much every remembered score under one query shrinks per pick of
    -- anything under that same query, and the only thing it really sets is how many
    -- consecutive picks overturn a settled favourite, ln(0.5)/ln(decay), which is 3.11 here
    -- so the fourth pick takes the top row. That number is the same however long the
    -- favourite has held, which is the whole reason a decaying score is used rather than a
    -- count. Lower it to about 0.79 to overturn on the third. A value whose answer lands
    -- exactly on a whole number is worth avoiding, since the two scores then meet within
    -- floating point noise on that pick.
    --
    -- `margin` is how far a challenger must exceed the current leader rather than merely
    -- beat it. It costs nothing in speed, the overturn stays on the fourth pick, and it
    -- roughly halves how often the top row changes where two rows are used about equally.
    -- Set it to zero for a bare comparison.
    --
    -- `nearness` is how close to the best match a row must score before any of this is
    -- allowed to decide it, as a proportion of that best score rather than a number of
    -- points, since the score grows with every character typed. It is what stops a pick made
    -- at a short spelling from outranking a name spelled out in full, and it is the one of
    -- the three that is a correctness guard rather than a preference. Raising it toward one
    -- makes the memory apply only to near ties, lowering it lets it reach further, and zero
    -- removes the guard entirely and is very unlikely to be what anyone wants.
    -- Where this host's own special rows, the alias directory, lock and sleep, sit among the rows
    -- other plugins contribute, a number compared with each contributor's own launcherOrder.
    -- Thirty puts them after the screenshot actions and the settings search and before the
    -- window actions, where they have always been. docs/PLUGIN-CONTRACT.md lists every
    -- shipped number.
    launcherOrder = 30,

    ranking = {
      decay = 0.80,
      margin = 0.6,
      nearness = 0.9,
    },

    specialRows = {
      { name = "aliasDirectory", description = "Aliases",
        subTitle = "Tools · every word that scopes this list", icon = "aliases",
        keywords = "alias, scope, shortcut, prefix" },
      { name = "lock", description = "Lock Screen", category = "System", key = "§", icon = "lock" },
      { name = "sleep", description = "Sleep", category = "System", key = "escape", icon = "sleep" },
    },

    catalogScopes = {
      { name = "apps", kind = "app",
        description = "Applications", icon = "apps", aliases = { "a", "app" } },
      { name = "windowActions", kind = "window",
        description = "Window actions", icon = "windows", aliases = { "w", "window" } },
      { name = "settingsPanes", kind = "settingsPane",
        description = "System Settings", icon = "settingsPanes", aliases = { "s", "system" } },
    },
  },

  -- Corrected against the launcher's real block rather than left as first
  -- written. The primary verb reads "Run" there, not "Open", the composition root only
  -- relabels it to "Open" live while the highlight sits on an application. The close key is
  -- "space" rather than the shared default "x", since space is also this plugin's own open
  -- key, which is the exact case lib/surface.lua's own top comment names as the reason a
  -- `close` override exists at all. And the gated "go back" row, listed rather than bound
  -- while a hosted list is showing, was missing entirely.
  surface = {
    context = "launcher",
    -- Where the object that answers the navigation verbs actually lives. Originally this host
    -- built its own dot called adapter over its own Chooser instance in configure. Since the
    -- chooser stage build's phase two it builds no instance at all, and _surface is instead a
    -- plain assignment of the stage's own shared nav adapter, host/stage's own surface field.
    -- The reason this is still declared here rather than being assumed is the one that made it
    -- necessary in the first place, every other tool is found through its registry entry and
    -- this one has no registry entry at all, being a host rather than a launcher row, so
    -- nothing else tells the root where to look.
    member = "_surface",
    -- No panelAs line, and unlike every other plugin that omits one, the absence here is not
    -- about this plugin's own configure contract at all, since the chooser stage build's
    -- phase two left this plugin reading no docked panel callback in any shape, flat or
    -- nested. It matters to a different reader. lib/services.lua's own perPlugin writes the
    -- three callbacks onto perPluginData under this manifest's own name either way, nested
    -- under a panelAs word when one is declared or flat when none is, and root/compose.lua's
    -- own THE SEAM comment beside its stage wiring reads them flat now, straight off
    -- perPluginData, with no nested field name for that file to carry by heart any more. So
    -- this plugin's own configure still receives whichever shape arrives, flat fields now
    -- rather than one nested table, on its ordinary call, and drops every one of them on the
    -- floor on purpose either way, findings seven and eight of the phase two adversarial
    -- review closed together by removing the line rather than by explaining it.
    primary = { action = "insertSelected", description = "Run" },
    close = { key = "space" },
    extra = {
      { key = "delete", action = "leavePage", when = "launcherHostingList", chord = false,
        description = "Go back" },
    },
  },
}
