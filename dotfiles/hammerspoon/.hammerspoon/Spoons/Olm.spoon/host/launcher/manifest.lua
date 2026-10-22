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
    keys = { emoji = "⌨️", sf = "keyboard" },
    back = { emoji = "⬅️", sf = "chevron.left" },
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
      -- Every plugin that adds rows to this catalog that are not actions, and every plugin that
      -- runs a row it owns. A contributor answers plain row descriptors from its own launcherRows
      -- member, built from its own data, the System Settings panes being the case today. A
      -- runner answers launcherRun, handed the chosen row's item. The two are separate questions
      -- because a query row source may own the rows it computes and run them without adding
      -- anything to the catalog. A plugin's actions are not asked for here at all. Olm builds a
      -- row from every listed action descriptor, with the chord the keymap binds it to, and runs
      -- a chosen one through that descriptor, so screenshots, window actions and the clipboard's
      -- actions are listed with no plugin building a row. Asking the set and reading the
      -- descriptors is what lets this host list all of it while naming none of the plugins.
      launcherRows = { provides = { "launcherRows" } },
      launcherRun = { provides = { "launcherRun" } },
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
    -- manager's action map, the app toggler's focus or cycle and its toggle by url, capture's run,
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
      -- One function answering, keyed by bundle id, the chord of an action whose descriptor names
      -- that app, asked whenever the app rows are built. Root assembled from the descriptors and
      -- the keymap, since only the root holds both, so no plugin answers anything for an app row.
      -- This replaced the person's toggles and app registry, which this host read itself until
      -- the core split, and a plugin's own app details, until phase 6 of the keymap plan. The app
      -- rows need neither, they come from a disk scan.
      appDetails = { source = "root", policy = "optional",
        breaks = "no app row names the chord that brings its app forward" },
      -- One supplier per plugin answering the launcherRows set above, in the set's order, then
      -- one per plugin with a listed action descriptor, in plan order, each a function answering
      -- that plugin's rows with the plugin's identity already stamped as the owner on every
      -- item. Root assembled because only the root may resolve a member on another plugin's
      -- module and only the root holds the keymap a row's chord comes from, and stamped there so
      -- a plugin never has to know its own identity for the routing to work.
      rowSuppliers = { source = "root", policy = "optional",
        breaks = "no screenshot, window action, clipboard action, System Settings pane or settings search row is listed, since nothing hands over those rows" },
      -- Owner identity to a function running that owner's chosen row, one per plugin answering
      -- the launcherRun set above or answering a listed action, which runs the descriptor. Root
      -- assembled for the same reason.
      runners = { source = "root", policy = "optional",
        breaks = "choosing a contributed row, a screenshot, a window action, a typed window size or a System Settings pane, does nothing at all" },
      -- The chord a registered tool's row names, asked by the tool's name and answered from the
      -- keymap, since a tool's open key is a keymap row rather than a field of its registry row.
      chordOf = { source = "root", policy = "optional",
        breaks = "a registered tool's row names no chord, so a key that opens it is found only on the cheat sheet" },
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

  -- What this host can run beside opening itself, its actions, the same descriptors a plugin
  -- answers. Lock and sleep are plain macOS calls, launcher.lock and launcher.sleep, so Olm binds
  -- the keys the bindings below suggest, builds their rows in this catalog from the descriptors
  -- and runs a chosen one through them, and a person moves either in config/keymap.lua like any
  -- action. Both were special rows of this manifest until phase 5 of the keymap plan, which was a
  -- second way to declare something runnable.
  provides = {
    actions = "actions",
  },

  -- Hyper and Space, and it is the one tool exempt from its own rule about every command
  -- being findable as a launcher row, since listing the finder inside the finder earns
  -- nothing.
  defaults = {
    leader = "app",
    -- The open key, a bindings row whose action is open, on the leader above, launcher.open in
    -- config/keymap.lua, and the keys of the two actions this host answers.
    bindings = {
      { action = "open", key = "space" },
      { action = "lock", key = "§" },
      { action = "sleep", key = "escape" },
    },
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
    -- Rows that are not actions and belong to no plugin, stated here as plain data rather than
    -- written into the row builder, which is what keeps that builder naming nothing. The alias
    -- directory is a scope about scopes and is the one left. The System Settings search row sat
    -- here until phase three of the core split, and lock and sleep until phase 5 of the keymap
    -- plan, when they became this host's own descriptors. A special row carries no key, a key is
    -- a bindings row, and the registrar names a key left on one as retired.
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
    -- What the memory decides is fixed by the shared search rather than by a number here. A
    -- remembered row carries a bonus, which orders only rows matching equally well, so a pick
    -- made at a short spelling never outranks a better match, docs/PLAN-UNIFIED-SEARCH.md.
    -- Where this host's own rows, the alias directory, OLM keys and then lock and sleep, sit among the rows
    -- other plugins contribute, a number compared with each contributor's own launcherOrder.
    -- Thirty puts them after the screenshot actions and the settings search and before the
    -- window actions, where they have always been. docs/PLUGIN-CONTRACT.md lists every
    -- shipped number.
    launcherOrder = 30,

    ranking = {
      decay = 0.80,
      margin = 0.6,
    },

    specialRows = {
      { name = "aliasDirectory", description = "Aliases",
        subTitle = "Tools · every word that scopes this list", icon = "aliases",
        keywords = "alias, scope, shortcut, prefix" },
      { name = "keys", description = "OLM keys",
        subTitle = "Tools · every key Olm binds", icon = "keys",
        keywords = "shortcuts, hotkeys, keybindings, chords" },
    },

    catalogScopes = {
      { name = "apps", kind = "app",
        description = "Applications", icon = "apps", aliases = { "a", "app" } },
      { name = "windowActions", kind = "window",
        description = "Window actions", icon = "windows", aliases = { "w", "window" } },
      { name = "settingsPanes", kind = "settingsPane",
        description = "System Settings", icon = "settingsPanes" },
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
