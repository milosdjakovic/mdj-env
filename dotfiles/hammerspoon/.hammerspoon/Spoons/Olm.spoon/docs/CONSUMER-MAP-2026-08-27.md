# Consumer map for the chooser stage, evidence with citations

Read only sweep of `Spoons/Olm.spoon` on 2026-08-27. Every path below is relative to
`dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon`. Nothing was edited.

Terms used throughout. The **atom** is `lib/chooser/providers/native.lua`, the one wrapper
around `hs.chooser`. The **facade** is `lib/chooser/init.lua`, which every consumer calls
through. A **surface** is the dot called navigation adapter a plugin hands to the nav registry.

---

## 1. Every call site of Chooser.new

The facade is `lib/chooser/init.lua:116`, `function obj.new(config)`. It folds in two module
defaults, `config.screen` from `DEFAULT_SCREEN` at `lib/chooser/init.lua:118` and
`config.matcher` from `DEFAULT_MATCHER` at `lib/chooser/init.lua:119`, then calls
`native.new(config)` and runs the decorate hook at `lib/chooser/init.lua:121`. The three
defaults are installed once by `obj.configure` at `lib/chooser/init.lua:101` through
`lib/chooser/init.lua:105`, and the root calls that at `root/compose.lua:188` through
`root/compose.lua:204`.

The atom's own construction is `lib/chooser/providers/native.lua:1034`. It builds the
`hs.chooser` once, `lib/chooser/providers/native.lua:1059`, and reuses it across shows. Only
`fieldMode`, `matcher`, and `layout` are captured at construction,
`lib/chooser/providers/native.lua:1038` and `:1043` and `:1047`. Everything else is read live
off `self.config` on each use, which is what the decorator seam depends on,
`lib/chooser/init.lua:76` through `:85`.

The full key set the atom reads is documented at `lib/chooser/providers/native.lua:16` through
`:80` and read at these lines. `theme` at `:177`. `rows` at `:214`. `onClose` at `:268`.
`screen` at `:282`. `onPositioned` at `:352` and `:422`. `onActivity` at `:468`. `intercept`
at `:490`. `back` at `:500`. `onHighlight` at `:513` and `:763`. `pollInterval` at `:516`.
`onScroll` at `:693`. `onInput` at `:720`. `onSelect` at `:735`. `layout` at `:1038`.
`fieldMode` at `:1043`. `matcher` at `:1047`. `placeholder` at `:1063`. `onRightClick` at
`:1075`.

There are **thirteen** call sites, not twelve. The count of twelve that appears in
`lib/chooser/init.lua:75` and in `host/actionpanel/init.lua:23` and `:387` counts the twelve
tools that declare a surface. `lib/overlaydisplay.lua` is a thirteenth instance owned by the
root itself with no manifest and no surface declaration. See section nine.

### 1.1 host/launcher, built once in configure

`host/launcher/init.lua:209` through `:252`, inside `configure`, `host/launcher/init.lua:140`.

Keys passed. `theme`, `placeholder`, `rows`, `onSelect`, `intercept`, `back`, `onPositioned`,
`onActivity`, `onClose`. No `fieldMode`, so it inherits filter. No `matcher`, so it inherits
the shared default. No `layout`, so 480 wide with ten rows and no pane.

`onSelect` at `:213` promotes recency then defers the run by 0.1 seconds,
`host/launcher/init.lua:223`. `intercept` at `:239` asks `_replacementFor` and calls the
returned callable. `back` at `:248` is `leavePage`. The panel triple arrives nested and is
unpacked from `sp` at `:208`, sourced from `opts.shortcutPanel` at `:179`.

### 1.2 lib/overlaydisplay, rebuilt on every configure

`lib/overlaydisplay.lua:418` through `:432`, inside `self.configure`,
`lib/overlaydisplay.lua:401`. The previous instance is hidden first at
`lib/overlaydisplay.lua:415`, and the local is reassigned, so a second configure genuinely
builds a second `hs.chooser`.

Keys passed. `theme`, `placeholder = "Overlay display"`, `fieldMode = filter` at `:421`,
`matcher = false` at `:426`, `rows = buildRows`, `onSelect`, and the three panel callbacks read
off `deps.panel` at `:417`.

### 1.3 plugins/caffeinate, built once in start

`plugins/caffeinate/init.lua:340` through `:361`, inside `M:start()`,
`plugins/caffeinate/init.lua:337`.

Keys passed. `theme`, `placeholder = "Time or duration"`, `fieldMode = filter` at `:347`,
`matcher = false` at `:352`, `layout = { rowCount = 2 }` at `:353`, `rows`, `onSelect`, and the
three panel callbacks flat off `cfg` at `:358` through `:360`.

### 1.4 plugins/browsertabs, built once in start

`plugins/browsertabs/chooser.lua:827` through `:855`, inside `M:start()`,
`plugins/browsertabs/chooser.lua:825`.

Keys passed. `theme`, `placeholder = "Search open tabs"`, `fieldMode = filter` at `:830`,
`matcher = false` at `:836`, `rows`, `onSelect`, `onPositioned`, `onActivity`, and a composed
`onClose` at `:845` that stops its own Return tap, calls the root's `onClose`, and either
re shows on a zero timer or resets the stack.

It passes no `intercept` and no `back`. It runs its own Return swallowing eventtap instead,
`plugins/browsertabs/chooser.lua:628` through `:642`.

### 1.5 plugins/clipboard, built once at start

`plugins/clipboard/manager/ui.lua:1374` through `:1413`, inside `UI.build()`,
`plugins/clipboard/manager/ui.lua:1373`, called once from
`plugins/clipboard/manager/init.lua:462`.

The widest config in the tree. Keys passed. `theme`, `fieldMode = filter` at `:1376`,
`matcher = false` at `:1380`, `placeholder` at `:1381`, `pollInterval = cfg.previewPoll` at
`:1382`, `rows = buildChoices`, `onSelect`, `intercept` at `:1389`, `back` at `:1390`,
`onHighlight = renderPreview` at `:1391`, `onClose`, `onPositioned` at `:1393` which is a local
composing the root's own, `onActivity` flat off `cfg` at `:1394`, `onScroll` at `:1399`,
`onRightClick` at `:1400`, and a `layout` block at `:1401` through `:1412` carrying `widthPct`,
`paneMaxW`, `rowH`, `baseH`, `rowCount`, `gap`, `topFrac`, `minVPad`, `companionWidth`.

This is the only consumer of `pollInterval` and the only consumer of `onRightClick` anywhere.

### 1.6 plugins/displayprofiles, built once in start

`plugins/displayprofiles/chooser.lua:424` through `:452`, inside `M:start()`,
`plugins/displayprofiles/chooser.lua:422`.

Keys passed. `theme`, `placeholder = "Search profiles"`, `fieldMode = filter` at `:427`,
`matcher = false` at `:433`, `rows`, `onSelect`, `onPositioned`, `onActivity`, and a composed
`onClose` at `:442` identical in shape to browsertabs, including the zero timer re show at
`:447`.

No `intercept` and no `back`. It also runs its own Return tap, referenced at
`plugins/displayprofiles/chooser.lua:443`.

### 1.7 plugins/emoji, built once in the backend's configure

`plugins/emoji/providers/hammerspoon.lua:339` through `:356`, inside `obj:configure`,
`plugins/emoji/providers/hammerspoon.lua:322`.

Keys passed. `theme`, `placeholder`, `matcher = false` at `:348`, `rows`, `onSelect`, and the
three panel callbacks unpacked from the nested `sp` at `:338`. No `fieldMode`, so filter. No
`layout`.

### 1.8 plugins/filesearch, built once in configure

`plugins/filesearch/chooser.lua:547` through `:609`, inside `M:configure`,
`plugins/filesearch/chooser.lua:472`.

Keys passed. `theme`, `rows = supplier`, `matcher = false` at `:551`, `placeholder`,
`onSelect`, `intercept` at `:563` which puts the parent query in the field and stays open,
`onHighlight` conditional on the viewer following the highlight at `:572`, `onPositioned` at
`:573` which is a local composing the root's own, `onActivity` flat off `cfg` at `:574`,
`onScroll` conditional at `:578`, a composed `onClose` at `:579` that cancels in flight work
and drops three per open caches, and a `layout` block at `:598` carrying `companionWidth` from
the viewer and `titleLineBreak = "truncateMiddle"` at `:607`.

`titleLineBreak` is a real layout field, defaulted at `lib/chooser/providers/native.lua:127`
and read at `:189`. Filesearch is its only consumer.

### 1.9 plugins/menusearch, built once in configure

`plugins/menusearch/init.lua:214` through `:227`, inside `obj:configure`,
`plugins/menusearch/init.lua:206`.

Keys passed. `theme`, `placeholder = "Search menu items"`, `rows = menuSearchRows`, `onSelect`
at `:218` which defers 0.1 seconds through the injected `cfg.after` at `:221`, and the three
panel callbacks unpacked from `cfg.panel` at `:213`. No `fieldMode`, no `matcher`, no `layout`.

### 1.10 plugins/processes, built once in start

`plugins/processes/chooser.lua:545` through `:592`, inside `M:start()`,
`plugins/processes/chooser.lua:532`.

Keys passed. `theme`, `placeholder`, `fieldMode = filter` at `:548`, `matcher = cfg.matcher` at
`:555`, which is the one consumer that passes the injected strategy straight through rather
than opting out, `rows = supplier`, `onSelect`, `onHighlight` conditional on the pane at `:560`,
`onPositioned` at `:561` composing the root's own, `onActivity` flat at `:562`, a composed
`onClose` at `:576` that stops the sampler and destroys the pane, and a `layout` block at
`:586` carrying only `companionWidth`.

### 1.11 plugins/textcase, built once in configure

`plugins/textcase/init.lua:153` through `:171`, inside `obj:configure`,
`plugins/textcase/init.lua:143`.

Keys passed. `theme`, `placeholder`, `rows` which ignores the query and returns a prebuilt list
at `:159`, `onSelect`, and the three panel callbacks read individually off the nested
`self._shortcutPanel` at `:168` through `:170`. No `fieldMode`, no `matcher`, no `layout`. It is
the only picker that deliberately keeps the shared matcher, stated at
`plugins/textcase/init.lua:156` through `:158`.

### 1.12 plugins/tmuxsessions, built lazily on first show and then reused

`plugins/tmuxsessions/chooser.lua:248` through `:262`, inside `M.show()`,
`plugins/tmuxsessions/chooser.lua:234`, guarded by `if not chooser then` at `:247`. It is the
only consumer whose instance is not built during wiring.

Keys passed. `theme`, `placeholder = "Search sessions and windows"`, `fieldMode = filter` at
`:251`, `matcher = false` at `:254`, `rows`, `onSelect`, `intercept` at `:257`, `back` at
`:258`, and the three panel callbacks flat off `cfg` at `:259` through `:261`.

### 1.13 plugins/vpn, built once in start

`plugins/vpn/init.lua:439` through `:450`, inside `M:start()`, `plugins/vpn/init.lua:424`.

Keys passed. `theme`, a `placeholder` that changes with availability at `:441`,
`fieldMode = filter` at `:442`, `rows`, `onSelect`, and the three panel callbacks flat off
`cfg` at `:447` through `:449`. No `matcher`, so it inherits the shared default. No `layout`.

### 1.14 The decorator, which is a fourteenth writer of config

`host/actionpanel/init.lua:394` runs on every instance the facade builds and mutates the
consumer's own config table in place, wrapping six functions. `config.rows` at `:413`,
`config.intercept` at `:423`, `config.back` at `:435`, `config.onSelect` at `:449`,
`config.onHighlight` at `:463`, `config.onClose` at `:472`. It reads `config.matcher` once at
decoration time, `host/actionpanel/init.lua:408`, to decide whether the panel filters its own
rows. It is installed at `root/compose.lua:198`, before any manifest is read, and the reason is
stated at `root/compose.lua:191` through `:197`.

So `intercept` exists on **all thirteen** instances at runtime even though only four consumers
write one, and `back` likewise. Section eight covers what that means for the stage.

### 1.15 Summary table of config keys per consumer

| consumer | theme | placeholder | rows | onSelect | onClose | onPositioned | onActivity | onHighlight | intercept | back | onScroll | onRightClick | pollInterval | fieldMode | matcher | layout | built |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| launcher | y | y | y | y | y | y | y | . | y | y | . | . | . | inherit | inherit | . | configure |
| overlaydisplay | y | y | y | y | y | y | y | . | . | . | . | . | . | filter | false | . | configure, rebuilt |
| caffeinate | y | y | y | y | y | y | y | . | . | . | . | . | . | filter | false | rowCount | start |
| browsertabs | y | y | y | y | composed | y | y | . | . | . | . | . | . | filter | false | . | start |
| clipboard | y | y | y | y | y | composed | y | y | y | y | y | y | y | filter | false | nine fields | start |
| displayprofiles | y | y | y | y | composed | y | y | . | . | . | . | . | . | filter | false | . | start |
| emoji | y | y | y | y | y | y | y | . | . | . | . | . | . | inherit | false | . | configure |
| filesearch | y | y | y | y | composed | composed | y | conditional | y | . | conditional | . | . | inherit | false | two fields | configure |
| menusearch | y | y | y | y | y | y | y | . | . | . | . | . | . | inherit | inherit | . | configure |
| processes | y | y | y | y | composed | composed | y | conditional | . | . | . | . | . | filter | injected | one field | start |
| textcase | y | y | y | y | y | y | y | . | . | . | . | . | . | inherit | inherit | . | configure |
| tmuxsessions | y | y | y | y | y | y | y | . | y | y | . | . | . | filter | false | . | first show |
| vpn | y | y | y | y | y | y | y | . | . | . | . | . | . | filter | inherit | . | start |

Nobody passes `screen`, `onInput`, or `filterText` at the config level. `screen` is always the
injected default from `root/compose.lua:189`.

---

## 2. Surface adapters and the nav registry

### 2.1 Where the registry consumes them

`lib/nav.lua` is the consumer. `obj.activeSurface(surfaces)` at `lib/nav.lua:51` walks an
ordered list and returns the first entry whose `isShowing()` answers true, calling it with a
bare dot at `lib/nav.lua:53`. `obj.routeNav(method, surfaces, hideShortcuts)` at
`lib/nav.lua:65` builds a zero argument closure that hides the hint panel, finds the active
surface, and calls `surface[method]()` if that surface answers it, `lib/nav.lua:69` through
`:71`. A surface that does not answer a method is silently left alone, which is the whole
reason one action name can be bound in twelve contexts.

`obj.actions(plan, deps)` at `lib/nav.lua:89` builds one routed handler per distinct action
name, mapping through `deps.methodFor` at `:101`, then folds in `deps.exceptions` at `:107` and
stamps the resolved handler onto each binding as `binding.fn` at `:113`. `obj.bindOne(repeats)`
at `lib/nav.lua:130` reads `binding.fn` and never asks again.

The root supplies the list at `root/compose.lua:1301`, `surfaces = surfaceAdapters`. The
method map is `navMethodFor` at `root/compose.lua:1131`, three entries, `closeChooser` to
`hide`, `refreshList` to `refresh`, `revealInFinder` to `reveal`. The one exception is
`openActionPanel`, `root/compose.lua:1139`.

`surfaceAdapters` is built at `root/compose.lua:1186` through `:1214`, in `plan.order`, one per
context owner. Each entry is a lazy metatable proxy, `surfaceAdapterFor` at
`root/compose.lua:1165`, which on every method access resolves the holder through `surfaceOf`
at `root/compose.lua:810`, looks the method up on the declared surface first and on the plugin
root second, `root/compose.lua:1170` through `:1174`, then calls it trying colon style first and
dot style second, `root/compose.lua:1176` through `:1181`. Nothing is cached, stated at
`root/compose.lua:1162`.

Which holder to use comes from the manifest, `root/compose.lua:1209`, reading
`manifest.surface.member` first and `manifest.registry.surface` second.

`lib/registry.lua` has a second, separate door, `instance.surfaces(spec)` at
`lib/registry.lua:627`, which resolves tool names to `descriptor.surface()` results and refuses
anything with no `isShowing` at `lib/registry.lua:646`. Note that the live root does **not**
use this path for navigation, it uses `surfaceAdapters` built at `root/compose.lua:1186`. See
section nine.

### 2.2 The adapters themselves

Four consumers hand over a literal five function table.

- Launcher, `host/launcher/init.lua:257` through `:266`. **Six** functions, not five. It adds
  `peekPreview` at `:264`, which routes to `self:peekSelected()`. Reached through
  `manifest.surface.member = "_surface"`, `host/launcher/manifest.lua:226`.
- Emoji backend, `plugins/emoji/providers/hammerspoon.lua:361` through `:367`. Exactly five.
  Reached through the facade's `obj:surface()` at `plugins/emoji/init.lua:162`, which falls back
  to `NOOP_SURFACE` at `plugins/emoji/init.lua:55`, itself a five function table of no ops.
  Declared as `registry.surface = "surface"`, `plugins/emoji/manifest.lua:93`.
- MenuSearch, `plugins/menusearch/init.lua:231` through `:237`. Exactly five, assigned onto
  `self.surface` inside configure. Declared as `registry.surface = "surface"`,
  `plugins/menusearch/manifest.lua:70`.
- TextCase, `plugins/textcase/init.lua:175` through `:181`. Exactly five, on `self._surface`,
  handed out by `obj:surface()` at `plugins/textcase/init.lua:213`. Declared as
  `registry.surface = "surface"`, `plugins/textcase/manifest.lua:65`.
- OverlayDisplay, `lib/overlaydisplay.lua:242` through `:248`. Exactly five, built once and
  reading the `picker` upvalue at call time, `lib/overlaydisplay.lua:236` through `:241`.

The remaining eight do not build an adapter at all. Their surface **is** a module whose public
dot called functions happen to carry the five names.

- BrowserTabs, `registry.surface = "chooser"`, `plugins/browsertabs/manifest.lua:155`. Module
  functions `isShowing` `:771`, `refresh` `:777`, `hide` `:781`, `selectNext` `:785`,
  `selectPrev` `:789`, `enter` `:796`, `insertSelected` `:806`.
- Caffeinate, `registry.surface = true`, `plugins/caffeinate/manifest.lua:56`, so the plugin
  root itself. **Deviates.** It answers only `isShowing` `:309`, `hide` `:313`,
  `insertSelected` `:319`. No `selectNext` and no `selectPrev`, which is consistent with
  `nav = false` at `plugins/caffeinate/manifest.lua:32`.
- Clipboard, `registry.surface = "manager"`, `plugins/clipboard/manifest.lua:141`. The manager
  answers the five plus `appendSelected`, `scrollPreviewDown`, `scrollPreviewUp`,
  `deleteSelected`, `manageHistory`, `leaveManageHistory`, `isManagingHistory`,
  `plugins/clipboard/manager/init.lua:160` through `:231`.
- DisplayProfiles, `registry.surface = "chooser"`,
  `plugins/displayprofiles/manifest.lua:77`. Five plus `refresh` and `enter`,
  `plugins/displayprofiles/chooser.lua:366` through `:403`.
- FileSearch, `registry.surface = "chooser"`, `plugins/filesearch/manifest.lua:256`. Five plus
  fourteen more, `plugins/filesearch/chooser.lua:686` through `:859`, including
  `scrollPreviewDown`, `scrollPreviewUp`, `peekPreview`, `browseInto`, `browseUp`, `reveal`,
  `copyPath`.
- Processes, `registry.surface = "chooser"`, `plugins/processes/manifest.lua:160`. Five plus
  `refresh`, `sortByLoad`, `stopForced`, `plugins/processes/chooser.lua:421` through `:500`.
- TmuxSessions, `registry.surface = "chooser"`, `plugins/tmuxsessions/manifest.lua:113`. Five
  plus `enter`, `selectRow`, `selectedItem`, `setQuery`,
  `plugins/tmuxsessions/chooser.lua:169` through `:232`.
- VPN, `registry.surface = true`, `plugins/vpn/manifest.lua:68`, so the plugin root. Five,
  `plugins/vpn/init.lua:360` through `:380`.

Deviation summary. One adapter has six functions, the launcher's `peekPreview`. One surface
answers only three of the five, Caffeinate. Five surfaces are literal tables and eight are
modules. Three of the literal ones are reached through a `surface()` **member** rather than a
field, which is why `surfaceOf` has to call a function value at `root/compose.lua:820`.

---

## 3. Panel callback shapes, the panelAs field

Erratum, 2026-08-27, after the phase 2 stage build on feat/chooser-stage. The
launcher no longer declares panelAs and no longer builds a chooser, the stage
receives the triple flat off perPluginData instead, so this section's launcher
rows and its citations into host/launcher are stale on that branch. The counts
become three nested under shortcutPanel minus the launcher, and the stage is a
new flat reader. Everything here about the other consumers still holds. Phase 3
planning reads this section with that correction, see REVIEW-STAGE-PHASE2.md
finding 13.

The field is `manifest.surface.panelAs`. It is documented at
`docs/PLUGIN-CONTRACT.md:537` through `:545` and its rationale at `lib/wire.lua:41` through
`:50`.

Two writers deliver the triple, and both branch on the same field.

- `lib/services.lua:268` through `:284`, `obj.perPlugin`. Builds the panel through
  `deps.hints.shortcutPanelFor` at `:271`, then nests under `panelAs` at `:275` or writes three
  flat fields at `:278` through `:280`.
- `lib/wire.lua:178` through `:196`. Collects whatever of `PANEL_CALLBACKS` sits on the flat
  services table, `lib/wire.lua:51`, then nests at `:191` or spreads flat at `:193`.

The panel object itself is built at `lib/hints.lua:385`, `obj.shortcutPanelFor`, returning
`onPositioned` at `:397` and `onActivity` at `:398` plus an `onClose`.

The four variants observed.

**Nested under `shortcutPanel`, three plugins.**
- Launcher, `host/launcher/manifest.lua:232`, read at `host/launcher/init.lua:179` and unpacked
  at `:208`.
- Emoji, `plugins/emoji/manifest.lua:79`, read at
  `plugins/emoji/providers/hammerspoon.lua:328` and unpacked at `:338`.
- TextCase, `plugins/textcase/manifest.lua:56`, read at `plugins/textcase/init.lua:150` and
  read field by field at `:168` through `:170`.

**Nested under `panel`, one plugin.**
- MenuSearch, `plugins/menusearch/manifest.lua:59`, read at `plugins/menusearch/init.lua:213`.

**Flat, three separate fields, the rest.** No `panelAs` line at all. Caffeinate reads them off
`cfg` at `plugins/caffeinate/init.lua:358`. BrowserTabs at
`plugins/browsertabs/chooser.lua:839`. DisplayProfiles at
`plugins/displayprofiles/chooser.lua:436`. Processes at `plugins/processes/chooser.lua:562`,
partially, since its own `onPositioned` local composes `cfg.onPositioned` at `:344`. FileSearch
the same shape at `plugins/filesearch/chooser.lua:451`. TmuxSessions at
`plugins/tmuxsessions/chooser.lua:259`, with the absence stated explicitly at
`plugins/tmuxsessions/manifest.lua:72` through `:75`. VPN at `plugins/vpn/init.lua:447`.
Clipboard is flat but only takes `onActivity` from it, `plugins/clipboard/manager/ui.lua:1394`,
composing `onPositioned` inside its own local at `:1177` through `:1187`.

**A fourth variant, a nested table read positionally.** OverlayDisplay reads
`deps.panel` at `lib/overlaydisplay.lua:417` and spreads it at `:429` through `:431`. It has no
manifest at all so no `panelAs` could describe it, and nothing supplies `deps.panel` at its one
construction site, `root/compose.lua:354` through `:375`. See section nine.

There is one hard rule the stage must preserve. `obj.ambient` in `lib/services.lua` must never
carry the three callbacks, stated at `lib/services.lua:18` through `:20`, because
`lib/wire.lua`'s entitlement table would then hand them to every surfaced plugin flat and
undo the whole `panelAs` mechanism.

---

## 4. Launcher alias and scope mechanics

### 4.1 The query source contract

`host/launcher/init.lua:190` holds `self._queryProviders`, an ordered list, wired at
`root/compose.lua:1473` through `:1477`. QueryScope leads at `root/compose.lua:1474`, then every
plugin the plan's `queryRows` set names, at `:1475`.

`obj:_queryRows(query)` at `host/launcher/init.lua:639` walks them. Each source is called as
`provider:rows(query)` inside a pcall at `:643`. A source may return a second value,
`exclusive`, at `:643`. When a source claims, everything earlier is discarded at `:647` and the
loop returns immediately at `:658`. A source that raises is dropped for that keystroke with a
console line at `:645` rather than emptying the list. Each returned row is normalised at `:649`
through `:656`, with `filterText` defaulting to the raw query at `:655`.

### 4.2 How a typed alias swaps the visible list

`obj:_commandRows(query)` at `host/launcher/init.lua:677` is the whole of it. Line `:685` asks
the sources, line `:688` returns their rows alone when the claim came back true, and only then
does the catalog loop at `:690` run. The file's own comment at `:687` calls that one line the
entire extent of the launcher's knowledge of scoping.

The grammar itself lives in QueryScope and nowhere else. `obj:resolve(query)` at
`host/queryscope/init.lua:192` matches the first token plus a separator against `_byAlias` at
`:195`, returning the scope and the remainder. `obj:rows(query)` at
`host/queryscope/init.lua:268` calls resolve, returns `{}, false` when nothing claims at `:270`,
runs the scope's own rows under pcall at `:272`, filters through `obj:_filter` at `:285`, and
wraps every row at `:296` through `obj:_present` at `:237`. A claimed query stays claimed even
with zero hits, `:286` through `:295`, so the same keystroke never means two things.

`_present` at `host/queryscope/init.lua:237` does two load bearing things. It nests the scope's
own item under `{ kind = "scope", scope = name, payload = item }` at `:248`, since the native
chooser serialises rows and would drop a function, stated at `:229`. And it sets `filterText` to
the **raw query including the alias** at `:247`, so the launcher's matcher scores every scope
row identically and the ordering `_filter` decided survives, stated at `:232` through `:236`.

### 4.3 How backspace steps out

Two different mechanisms, and the distinction matters for the stage.

A **typed** alias needs no mechanism. Deleting the space is ordinary text editing and
`resolve` stops matching, stated at `host/queryscope/init.lua:7` through `:10`.

A **hosted page** needs one. `config.back` at `host/launcher/init.lua:248` calls
`obj:leavePage()` at `:874`, which clears `_page`, clears the field, and restores the
placeholder, `:876` through `:880`. It answers false when there is no page, `:875`, which is
what leaves Backspace an ordinary press. The atom only asks when the field is empty,
`lib/chooser/providers/native.lua:499` through `:508` and the comment at `:456` through `:460`.

### 4.4 The state that tracks the current scope

There is exactly one field, `obj._page`, declared at `host/launcher/init.lua:67` and described
as an opaque query prefix. Nothing else records scope.

`obj:enterPage(prefix, title)` at `host/launcher/init.lua:836` sets `_page`, clears the field,
and sets the placeholder to the title. The design note at `:825` through `:829` is the key
fact for the stage. A page is a prefix the launcher never shows, so hosting reuses the existing
query source mechanism with the prefix prepended, and needs no second row mechanism, no second
matcher, and no second definition of what choosing a row does.

`obj:seedQuery(text)` at `:813` is the other half. It leaves any page first at `:815`, then
sets the field. The reason is at `:809` through `:812`, an invisible prefix in front of seeded
text composes into a query neither half meant.

`obj:isHostingList()` at `:848` is `_page ~= nil`. `obj:currentQuery()` at `:864` answers
`_page .. typed`, the exact string `_commandRows` assembles, so a typed alias and a chosen
scope row read the same.

Every open resets. `obj:show(query)` calls `leavePage()` at `host/launcher/init.lua:1014`
before the show, stated at `:1012`.

### 4.5 Who decides a row swaps the list

`obj:_replacementFor(it)` at `host/launcher/init.lua:780` asks the injected
`self._actions.rowIntercept` at `:782` and keeps the answer only when it is a function at
`:784`. The answer is a **callable and not a boolean**, and the reason is recorded at `:765`
through `:771`, an earlier version replaced the list merely by being asked about. Every kind of
row is asked, not only a scope row, stated at `:773` through `:779`.

The root supplies `rowIntercept` at `root/compose.lua:1585` through `:1592`. It returns
`queryScopeModule:actFor(item)` when the scope declared an in place act, `:1587`, else builds a
closure calling `launcherModule:seedQuery(query)` from `redirectFor`, `:1589` through `:1591`.

The four QueryScope verbs are `run` at `host/queryscope/init.lua:316`, `peek` at `:337`,
`redirectFor` at `:360`, `actFor` at `:391`, plus `verbFor` at `:425` which also answers whether
the verb closes the list.

### 4.6 coveredApp and openId

Set in `obj:show(query)`. `self._openId = (self._openId or 0) + 1` at
`host/launcher/init.lua:997`. `self._coveredApp` at `:1009`, guarded so the launcher never
records itself at `:1008`, with the reason at `:998` through `:1006`, that two quick opens would
otherwise hand a source Hammerspoon's own menus.

Exposed together by `obj:coveredApp()` at `:1025`, returning both values.

One reader. MenuSearch, declared at `plugins/menusearch/manifest.lua:26` and called at
`plugins/menusearch/init.lua:146`. It keys its whole scope cache off the pair,
`plugins/menusearch/init.lua:143` and `:148`, and drops a late arriving accessibility read whose
pair no longer matches, `:162`.

### 4.7 refresh for late arriving rows

`obj:refresh()` at `host/launcher/init.lua:889` calls `self._instance:refresh()` when showing,
a no op otherwise. The purpose is stated at `:886` through `:888`, a query source whose answer
arrives late calls this so the row appears without further typing.

Declared as a sibling need by MenuSearch, `plugins/menusearch/manifest.lua:30`, and called at
`plugins/menusearch/init.lua:167`.

The other two async scopes take it as an injected `redraw` callback rather than through the
manifest. BrowserTabs, `M.scopeRows(rest, redraw)` at `plugins/browsertabs/chooser.lua:753`,
passing it into `M.prepare` at `:755`, with the reason at `:747` through `:752`. VPN, the same
shape at `plugins/vpn/init.lua:318` and `:320`.

Note the atom's `refresh` signature, `lib/chooser/providers/native.lua:787`,
`Chooser:refresh(resetRow)`. The launcher's refresh passes nothing, so the highlight is kept.

---

## 5. The handoff path today

### 5.1 Launcher row to registry.run

`obj:_runItem(it)` at `host/launcher/init.lua:900` is the one dispatcher, a switch on
`it.kind`. Seven kinds. `app` `:903`, `window` `:905`, `capture` `:908`, `special` `:910`,
`settingsPane` `:921`, `calc` `:923`, `scope` `:928`.

A tool is a `special` row. `local ran = self._registry.run(it.name)` at
`host/launcher/init.lua:916`, falling back to `self._actions.special[it.name]` at `:918` when
the registry does not own the name. The two sources are justified at `:911` through `:915`.

Those rows are built by `addTool` at `host/launcher/init.lua:394`, which reads
`self._registry.rowFor(name)` at `:395` and emits `{ kind = "special", name = name }` at `:419`,
looped over `self._registry.listing()` at `:431`.

`instance.run(name)` is `lib/registry.lua:515`. Four lines. It looks the name up in
`flatIndex`, checks the owning tool is active, and calls `entry.fn()` at `:518`. `entry.fn` is
`descriptor.open`, stamped at registration, `lib/registry.lua:479`.

`descriptor.open` resolves from the manifest's `registry.open` member. Examples,
`plugins/filesearch/manifest.lua:255` names `chooser.show` dot called,
`plugins/processes/manifest.lua:159` the same, `plugins/vpn/manifest.lua:67` names `show`,
`plugins/menusearch/manifest.lua:69` names `open`. So `registry.run` calls straight into a
plugin's own show, synchronously, with no knowledge of whether that opens a chooser.

### 5.2 Where the 0.1 second deferral lives

`host/launcher/init.lua:223`.

```
self._runTimer = hs.timer.doAfter(0.1, function() self:_runItem(item) end)
```

Its stated reason is at `host/launcher/init.lua:204` through `:207` and `:218` through `:222`.
The row runs after the chooser tears down and macOS restores focus to the app the launcher
covered, since a window action acts on `hs.window.focusedWindow()`. The timer is held in a field
because an unreferenced Hammerspoon timer can be collected before it fires.

**It is unconditional.** Every kind goes through it, including `special`, which is every tool.
So opening BrowserTabs from a launcher row today is close, wait 0.1 seconds, open a second
chooser. That is exactly the close and open the stage replaces.

### 5.3 Every deferred call site, with what it defers and why

| site | delay | defers | stated reason |
| --- | --- | --- | --- |
| `host/launcher/init.lua:223` | 0.1 | the whole `_runItem` switch | focus must return to the covered app before a window action reads `focusedWindow`, `:205` through `:207` |
| `plugins/menusearch/init.lua:221` | 0.1 | `app:selectMenuItem(item.path)` through the injected `cfg.after` | the chosen item acts on the captured app once focus returns, `:209` through `:212` |
| `host/actionpanel/init.lua:348` | 0 | restoring the highlight and running the chosen verb | both `intercept` and `back` call `refresh(true)` **after** the handler returns, so a synchronous restore would be undone, `:321` through `:329` |
| `plugins/browsertabs/chooser.lua:850` | 0 | a re show after a click selection | the native chooser has already closed, so the re show waits for the hide to finish, `:842` through `:844` |
| `plugins/displayprofiles/chooser.lua:447` | 0 | the same re show | `:438` through `:441` |
| `plugins/processes/chooser.lua:371` | 0 | showing the confirmation frame | the chooser already closed on the selection, `:367` through `:370` |
| `lib/overlaydisplay.lua:366` | 0.04 | a re show after a drill or a commit | `hs.chooser` dismisses on every select, `:359` through `:363` |
| `lib/chooser/providers/native.lua:335` | 0.03 | the settle correction of the real window frame | the rendered height is unknown until the window appears, `:321` through `:332` |

The generic deferral helper is `lib/services.lua:65`, the `after` service granted universally,
`lib/wire.lua:55`. MenuSearch is its only chooser related consumer.

### 5.4 Which tools open a chooser versus dispatch into the world

**Open another chooser.** BrowserTabs, Caffeinate, Clipboard, DisplayProfiles, Emoji,
FileSearch, MenuSearch, Processes, TextCase, TmuxSessions, VPN, plus the root's overlay display
picker. Twelve destinations reachable from a launcher row through `registry.run`, each of which
today closes the launcher first.

**Dispatch into the world.** These genuinely need the deferral or the covered app.
- Menu items into apps, `plugins/menusearch/init.lua:221` and the scope path at `:187`, which
  addresses the app directly and so does not depend on focus, stated at `:182` through `:184`.
- Window actions, `host/launcher/init.lua:906`, which read `hs.window.focusedWindow()`.
- Paste actions, through `lib/paste.lua`, which has its own internal delays at
  `lib/paste.lua:124` and `:551`. TextCase relies on that at `plugins/textcase/init.lua:161`
  through `:163`.
- App focus and toggle, `root/compose.lua:1568` through `:1574`.
- Capture, `root/compose.lua:1575`.
- Settings pane by url, `root/compose.lua:1576`.
- The plain pasteboard write for a computed row, `root/compose.lua:1579`.
- Lock and sleep, `root/compose.lua:1597` and `:1598`.

---

## 6. Per plugin async row handling

Six plugins hand roll this, not four. VPN and Processes have their own mechanisms too.

### 6.1 MenuSearch

Two entirely separate paths for the same accessibility read.

Its own chooser fetches per open and shows only once the rows are built,
`plugins/menusearch/init.lua:119` through `:133`. The guard is a frontmost app comparison at
`:128`, so a read that landed after focus moved is dropped. Module local `menuRows` at `:85` is
the store, and `menuSearchRows` at `:111` simply reads it.

The launcher scope path keeps a per open cache, `scopeMenu` at
`plugins/menusearch/init.lua:143`, keyed on the covered app and the open id. The cache is reset
whenever either changes, `:148` through `:155`. An in flight guard is the `reading` flag at
`:156` and `:157`. A late answer is dropped when the pair no longer matches at `:162`, otherwise
it fills the list and calls `cfg.refreshLauncher()` at `:167`. While reading, one disabled row
carrying the typed text as its `filterText` is returned at `:170` through `:178`, so the matcher
cannot rank away the only row there is. The whole design note is at `:135` through `:142`.

### 6.2 BrowserTabs

`M.prepare(onReady)` at `plugins/browsertabs/chooser.lua:700` is the single listing path. Module
state at `:39` through `:44`, `tabs`, `listSig`, `listErrors`, `loading`, `waiting`.

A second ask while one is in flight joins it rather than starting another, `:701` and `:702`,
and every waiter is called at `:715` through `:717`. What is already held is repainted at once
with the recency order reapplied, `:703`, then corrected when the answer lands.

The redraw is **skipped when nothing changed**, `:714`. `signatureOf` at `:670` folds identity,
title, group, and order into one string, and `setTabs` at `:682` keeps the list and its
signature moving together. The reason is at `:710` through `:713`, a redraw rebuilds every row
under a highlight that keeps only its number.

The scope path is `M.scopeRows(rest, redraw)` at `:753`, which joins the flight rather than
starting a new one and redraws through the caller's own hook.

### 6.3 TmuxSessions

A time based read cache on the engine rather than a per open one. `obj._read` at
`plugins/tmuxsessions/engine.lua:44` with `_readTTL = 1.0` at `:45`. `obj:_cachedSessions()` at
`:171` returns the held read within the window and otherwise re reads at `:177`.

It caches the **read** and never the ordering, `plugins/tmuxsessions/engine.lua:161` through
`:163`, because recency is applied over the result on every call.

The one second window exists specifically because the launcher's hosted list has no open and no
close to hang freshness on, stated at `:165` through `:170`. The plugin's own picker does have
those, so `M.show()` calls `cfg.api:invalidate()` at `plugins/tmuxsessions/chooser.lua:240` and
`cfg.api:pruneRecency()` at `:246`, once per open.

There is no in flight guard because the read is synchronous shell out.

### 6.4 FileSearch

The most developed mechanism, and it lives in the engine rather than the chooser.

A **generation counter**. `self._gen` incremented at `plugins/filesearch/engine.lua:465`, every
callback carries the generation it was issued under and is dropped when it no longer matches,
`:493`. The reason is at `:460` through `:463`, a task terminated a microsecond too late still
has its callback queued.

A **cancel** that is separate from the generation check, `obj:_cancelInflight()` at
`plugins/filesearch/engine.lua:453`. It deliberately leaves the recent files fetch running, and
the recorded bug at `:447` through `:452` is that cancelling it once left a pending flag set and
the picker showed a loading row for the rest of the process.

A **debounce**, `self._debounce` at `plugins/filesearch/engine.lua:100`, default `debounceMs =
70` at `:55`, armed and cancelled in `rowsFor` at `:612`, `:624`, and `:643`.

The chooser side is the redraw. `M.refresh()` at `plugins/filesearch/chooser.lua:686` calls
`picker:refresh(false)` so the highlight is preserved, then re renders the pane explicitly at
`:689`. The reason at `:681` through `:685` is exactly the stage relevant one, the atom's poll
compares the highlighted **row number**, so a result set landing under a stationary highlight
fires nothing.

Three per open caches are dropped on close. `dirFits` at `plugins/filesearch/chooser.lua:591`,
`iconMemo` at `:594`, `lastChooserFrame` at `:595`.

The scope path `M.scopeRows(rest)` at `:664` ensures a session only on an empty rest, `:665`,
with the reason at `:658` through `:663`, a scope asked on every keystroke would restart a
session forever.

### 6.5 Processes

A boolean `scanning` guard. `M.show()` returns early if already scanning,
`plugins/processes/chooser.lua:405`, sets the flag at `:410`, and shows only once the scan
returns at `:414`. The reason for showing after rather than before is at `:400` through `:403`.

`M.refresh()` at `:421` is the same guard plus a `renderHighlighted()` at `:432`, for the same
row number reason FileSearch documents.

A separate live sampler drives redraws while open. `onSample` at
`plugins/processes/chooser.lua:251` refreshes the rows and the pane on one tick, deliberately
one timer and not two, `:255` through `:258`. It stops itself after three misses,
`MISSES_BEFORE_STOP` at `:249` and the check at `:263`.

`sortByLoad` at `:448` is a one shot reorder that calls `chooser:refresh(true)` at `:466` and
then `renderHighlighted()` at `:469`.

### 6.6 VPN

`M.prepare(onReady)` at `plugins/vpn/init.lua:341`. A `fetching` flag at `:349` and `:350`, a
`pending` waiter list at `:348` drained at `:354` through `:356`. Unavailable calls back at once
at `:342` through `:345` so no caller waits on a fetch that cannot happen. The reason for
draining every waiter rather than dropping the second is at `:338` through `:340`.

Its scope path at `:318` shows a single placeholder row while the real list is in flight, with
the typed text as its `filterText` at `:325`, the identical trick MenuSearch uses.

### 6.7 Clipboard

No async row mechanism. Its rows come from a synchronous store. Its live behaviour is instead
the preview poll, `pollInterval = cfg.previewPoll` at
`plugins/clipboard/manager/ui.lua:1382`, which is 0.08 at
`plugins/clipboard/manager/init.lua:111`.

---

## 7. Field modes and layout variance

### 7.1 Field modes

**No consumer uses a non filter field mode.** Every single one of the thirteen either passes
`fieldModes.filter` explicitly or passes nothing and inherits filter through
`obj.memberFieldMode(nil)` at `lib/chooser/providers/native.lua:913`.

Explicit filter, seven. `lib/overlaydisplay.lua:421`, `plugins/caffeinate/init.lua:347`,
`plugins/browsertabs/chooser.lua:830`, `plugins/clipboard/manager/ui.lua:1376`,
`plugins/displayprofiles/chooser.lua:427`, `plugins/processes/chooser.lua:548`,
`plugins/tmuxsessions/chooser.lua:251`, `plugins/vpn/init.lua:442`.

Implicit filter, five. Launcher, Emoji, FileSearch, MenuSearch, TextCase.

`off`, `input`, and `hybrid` are declared at `lib/chooser/providers/native.lua:906` and honoured
at `:720` and `:1068`, and nothing anywhere selects them. `config.onInput` is read at
`lib/chooser/providers/native.lua:720` and passed by nobody. `Chooser:setFieldMode(mode)` at
`lib/chooser/providers/native.lua:929` is called by nobody.

The brief named arithmetic and convert as likely non filter consumers. They are not. Both are
query row sources with no chooser at all. Arithmetic states it at
`plugins/arithmetic/init.lua:3` through `:8` and provides `queryRows` at
`plugins/arithmetic/manifest.lua:18`. Convert says the same at `plugins/convert/manifest.lua:6`
and `:53`. TextCase does own a chooser but it is a plain filter picker over prebuilt rows,
`plugins/textcase/init.lua:159`, with a static row set stated at `:156` through `:158`.

Caffeinate is the closest thing to an input field, but it achieves it in filter mode by
re parsing the query on every keystroke and returning one morphing row, stated at
`plugins/caffeinate/init.lua:341` through `:344` and `:348` through `:351`. Same for the
clipboard manage history page, which reads a duration in a filter field,
`plugins/clipboard/manager/ui.lua:1338` through `:1341`.

### 7.2 Layout overrides

Defaults at `lib/chooser/providers/native.lua:104` through `:132`. `width = 480`,
`widthPct = 32`, `paneMaxW = 480`, `rowH = 42`, `baseH = 94`, `rowCount = 10`, `gap = 12`,
`topFrac = 0.06`, `minVPad = 60`, `companionWidth = 0`, `titleLineBreak = "truncateTail"`.

Four consumers pass a `layout` block. Nine pass none.

- Caffeinate, `plugins/caffeinate/init.lua:353`, `{ rowCount = 2 }`. The reason is at `:342`
  through `:344`, the larger row font clips a single row so the extra height gives it room.
- Clipboard, `plugins/clipboard/manager/ui.lua:1401` through `:1412`, nine fields.
- FileSearch, `plugins/filesearch/chooser.lua:598` through `:608`, `companionWidth` from the
  viewer at `:601` and `titleLineBreak = "truncateMiddle"` at `:607`, with a filename specific
  reason at `:602` through `:606`.
- Processes, `plugins/processes/chooser.lua:586` through `:591`, `companionWidth` only.

**Nobody overrides `width`.** Every chooser is 480 points wide,
`lib/chooser/providers/native.lua:377`. The clipboard's `widthPct` at
`plugins/clipboard/manager/ui.lua:1402` is inert, since `_desiredWidthPx` only reaches the
percentage branch when `L.width` is false, `lib/chooser/providers/native.lua:376` through `:378`.
See section nine for the rest of the clipboard block.

### 7.3 The companion pane

Two plugins reserve it through `layout.companionWidth`, FileSearch and Processes, plus the
clipboard through `previewW = true` at `plugins/clipboard/manager/init.lua:135`. Three manifests
declare `pane = true`, `plugins/clipboard/manifest.lua:120`,
`plugins/filesearch/manifest.lua:228`, `plugins/processes/manifest.lua:140`, which is what earns
them `opts.surface`, the shared drawing routine, at `lib/wire.lua:203`.

`companionWidth` resolution is `Chooser:_resolveCompanionWidth(chooserW)` at
`lib/chooser/providers/native.lua:305`. `true` inherits the chooser's own width, a number
overrides, `paneMaxW` caps both, and nil or false or non positive all mean no pane.

All three draw through `onPositioned`, and all three compose rather than replace the root's own.

- Clipboard, `plugins/clipboard/manager/ui.lua:1172` through `:1188`. Docks the preview and
  hands the root an anchor spanning both panes at `:1187`.
- FileSearch, `plugins/filesearch/chooser.lua:435` through `:460`. Records
  `lastChooserFrame` at `:439` for the later peek path, docks at `:441`, then seeds the first
  pane paint at `:449` because the atom seeds the highlight before it positions anything,
  stated at `:442` through `:448`. The seed is gated on `viewer.followsHighlight`, and the
  recorded bug at `:445` through `:448` is that without the gate merely opening the picker threw
  a Quick Look panel on screen.
- Processes, `plugins/processes/chooser.lua:337` through `:353`. Same shape, docking at `:339`
  and seeding at `:342`.

All three build the spanning anchor identically, `{ x, y, h }` of the chooser with
`w = (companionFrame.x + companionFrame.w) - chooserFrame.x`,
`plugins/clipboard/manager/ui.lua:1180` through `:1186`,
`plugins/filesearch/chooser.lua:454` through `:457`,
`plugins/processes/chooser.lua:347` through `:350`. Three literal copies of one calculation.

The atom fires `onPositioned` **twice per show**, once with a seed frame at
`lib/chooser/providers/native.lua:422` and once with the corrected frame after the settle at
`:352`. `self.paneFrames` is stamped at both, `:421` and `:351`, and is what the click watcher
reads.

`onScroll` exists only because a canvas has no scroll callback, stated at
`lib/chooser/providers/native.lua:60` through `:66`. Two consumers,
`plugins/clipboard/manager/ui.lua:1399` and `plugins/filesearch/chooser.lua:578`. Processes has
a pane but no scroll.

---

## 8. Intercept and back usage

Four consumers write `intercept`, three write `back`, and the decorator writes both onto all
thirteen.

### 8.1 The atom's contract

`intercept` is asked **before** a row is allowed to complete, `lib/chooser/providers/native.lua:470`
inside the key watcher, resolved at `Chooser:_intercept(item)` at `:489`. Answering true keeps
the chooser open and the atom then rebuilds the list from the top. It is filter mode only,
`:491`. The full rationale is at `:37` through `:47` and again at `:448` through `:454`, the
important part being that `hs.chooser` hardwires Return to complete and offers no hook before
it, so taking Return away with an eventtap is the only place such a row can be answered.

`back` is asked on Backspace while the field is empty, `Chooser:_back()` at
`lib/chooser/providers/native.lua:499`, also filter mode only at `:501`. Rationale at `:48`
through `:53` and `:456` through `:460`.

Both hooks call `refresh(true)` on the instance **after** the handler has returned. That
ordering is what forces the ActionPanel restore to defer, stated at
`host/actionpanel/init.lua:321` through `:329`.

### 8.2 The four intercept consumers

- **Launcher**, `host/launcher/init.lua:239` through `:245`. Routes the question to
  `_replacementFor`, calls the callable, promotes recency, answers true. This is list in list
  navigation in its purest form, since the replacement is either `seedQuery` or `enterPage`.
- **Clipboard**, `plugins/clipboard/manager/ui.lua:1130` through `:1136`, wired at `:1389`.
  Only active on the prune page, `:1131`. A row deletes a slice of history, notifies, and
  answers true so the list stands with a new count. The reason is at `:1385` through `:1388`,
  a row whose result is a differently counted list has nothing left to change once the window
  is gone.
- **FileSearch**, `plugins/filesearch/chooser.lua:563` through `:569`, for the parent row only.
  It sets the field through `picker:setQuery(query)` at `:567` and answers true. The design note
  at `:554` through `:562` says the atom's hook only says whether the row was a completion and
  leaves what it meant to whoever knows.
- **TmuxSessions**, `plugins/tmuxsessions/chooser.lua:145` through `:158`, wired at `:257`. Two
  cases, a `nav` row swapping levels at `:147` through `:151`, and picking a terminal provider
  at `:152` through `:156` which persists the choice and stays open so the moved marker is what
  confirms it.

### 8.3 The three back consumers

- **Launcher**, `host/launcher/init.lua:248`, `leavePage`.
- **Clipboard**, `plugins/clipboard/manager/ui.lua:1141` through `:1145`, wired at `:1390`,
  leaving the manage history page.
- **TmuxSessions**, `plugins/tmuxsessions/chooser.lua:160` through `:167`, wired at `:258`,
  leaving the settings level.

Note that the clipboard also declares the Backspace key in its manifest with `chord = false`,
`plugins/clipboard/manifest.lua:108` through `:109`, purely so the hint panel lists it, since
the binding itself belongs to the atom. The launcher does the same at
`host/launcher/manifest.lua:236` through `:237`.

### 8.4 The two consumers that reject the hooks and run their own eventtap

BrowserTabs and DisplayProfiles both do list in list navigation and both refuse `intercept`.

BrowserTabs, `plugins/browsertabs/chooser.lua:628` through `:642`. A passive
`hs.eventtap` swallows keycodes 36 and 76 and routes them into `M.enter()` at `:633`.
`M.enter()` at `:796` applies the selection and either redraws the new frame with no re show or
hides. The redraw is `drawFrame()` at `:613`, which clears the query, calls `refresh(true)`, and
sets a per level placeholder. The stack is `stack` at `:36`.

DisplayProfiles, the same trick, referenced at `plugins/displayprofiles/chooser.lua:443` and
noted as such in the tmux comment at `plugins/tmuxsessions/chooser.lua:221`.

This means the tree currently holds **three** competing mechanisms for the same behaviour. The
atom's `intercept` plus `back`, a per plugin Return swallowing eventtap plus its own stack, and
a close plus zero timer re show for the click path that neither of the first two covers,
`plugins/browsertabs/chooser.lua:850` and `plugins/displayprofiles/chooser.lua:447`.

### 8.5 The decorator occupies both hooks on every instance

`host/actionpanel/init.lua:423` and `:435`. Its own comments record the current arithmetic.
`intercept` is absent on ten of the twelve consumers, `:421`. `back` is absent on eleven of the
twelve, `:432`. When the panel is open on an instance the wrapped function answers for the
panel and never calls the original, and otherwise it falls straight through.

The stage cannot simply own `intercept` and `back` for itself. It has to coexist with a
decorator that already wraps both on every instance, and with two plugins that bypass both.

---

## 9. Surprises, where reality contradicts the plan doc

Stated bluntly, in descending order of how much they change the design.

**9.1 There are thirteen Chooser.new sites, not twelve.** The thirteenth is
`lib/overlaydisplay.lua:418`, a picker owned by the root itself. It has no manifest, no
`registry` entry, and no `surface` declaration. The count of twelve at
`lib/chooser/init.lua:75`, `host/actionpanel/init.lua:23`, `:387`, and `:421` is a count of
surfaced tools, not of instances. Phase 5 of the plan says migrations delete a plugin's
`Chooser.new` block per a manifest presentation block. Overlay display has no manifest to put
one in, so it either needs a special path or it stays a fourteenth window.

**9.2 The overlay display picker is not navigable and has no hint panel.** Its surface adapter
is built at `lib/overlaydisplay.lua:242` and handed out by `self.surface()` at `:254`, and
nothing ever puts it into the nav surfaces list. `surfaceAdapters` at `root/compose.lua:1186`
is built only from plan context owners, and overlay owns no context. Its predicate
`overlayDisplayOpen` is registered at `root/compose.lua:544` and referenced by no `when`
anywhere in the tree. Its `deps.panel` read at `lib/overlaydisplay.lua:417` is never supplied,
since the construction at `root/compose.lua:354` through `:375` passes no `panel` key, so
`triple` is always `{}` and the three callbacks are always nil. So j and k do nothing in it and
no shortcut hints appear. This is a live defect, not a stage question, but the stage will make
it visible.

**9.3 No consumer uses a non filter field mode, and three of the four modes are dead code.**
Item 0a of the plan lists "placeholder and field mode flips" as something to probe live. There
is nothing to flip. `off`, `input`, and `hybrid` at `lib/chooser/providers/native.lua:906` have
zero consumers, `config.onInput` read at `:720` has zero writers, and
`Chooser:setFieldMode(mode)` at `:929` has zero callers. The presentation contract in phase 1
should treat field mode as a constant unless the stage is meant to introduce a use.

**9.4 The clipboard's nine field layout block is eight no ops plus one real value.** Compare
`plugins/clipboard/manager/ui.lua:1401` through `:1412` against the config values at
`plugins/clipboard/manager/init.lua:130` through `:139` and the atom defaults at
`lib/chooser/providers/native.lua:104` through `:120`. `chooserWidthPct = 32` equals
`widthPct = 32`. `paneMaxW = 480` equals `paneMaxW = 480`. `chooserRows = 10` equals
`rowCount = 10`. `chooserRowH = 42` equals `rowH = 42`. `chooserBaseH = 94` equals `baseH = 94`.
`uiGap = 12` equals `gap = 12`. `uiTopFrac = 0.06` equals `topFrac = 0.06`.
`minVPad = 60` equals `minVPad = 60`. Only `companionWidth = previewW` differs from the default,
and `widthPct` is unreachable anyway since `width` is 480. The apparently most layout hungry
consumer in the tree actually needs one field.

**9.5 Row count is already uniform at ten, and only one consumer differs.** The plan's phase 5
says Caffeinate carries the row count answer. It is the only consumer that changes it,
`plugins/caffeinate/init.lua:353`, `{ rowCount = 2 }`, and the clipboard's `rowCount = 10` is
the default restated. So the row count question is a single plugin question, not a spread.

**9.6 Width is already uniform and nobody overrides it.** The plan reserves "one private stage
path for the rare width change, a hidden rebuild and reshow". No consumer in the tree passes
`layout.width` today. The capability has no current caller.

**9.7 The launcher's 0.1 second deferral is unconditional across all seven row kinds.** The
plan's phase 3 says "deferral survives only for dispatch into the outside world". Today the
same timer at `host/launcher/init.lua:223` covers opening a chooser and pasting into an app
alike, because `_runItem` at `:900` is one switch and the timer wraps the whole switch. Making
the deferral conditional means splitting the dispatcher, or moving the deferral inside the
branches, which touches `app`, `window`, `capture`, `settingsPane`, `calc`, and `scope` and not
only `special`.

**9.8 ActionPanel already owns intercept and back on all thirteen instances.** This is stronger
than "coexist". `host/actionpanel/init.lua:394` mutates every consumer's config table in place
and the correctness of doing so depends on a documented property of the atom, that config is
stored by reference and read live, `lib/chooser/init.lua:76` through `:85`. A stage that owns
its own presentation stack through `intercept` and `back` is a third writer of the same two
fields, after the consumer and the decorator, on a table whose live mutability is load bearing.
The plan does not mention the decorator at all.

**9.9 Two plugins already have a presentation stack and neither uses the atom's hooks.**
BrowserTabs at `plugins/browsertabs/chooser.lua:36` and `:628`, DisplayProfiles at
`plugins/displayprofiles/chooser.lua:443`. Both run a private Return swallowing eventtap. So
when the stage lands there will have been three separate implementations of "a row means this
list becomes another list" in this tree, and the two eventtap ones cannot be migrated by
deleting a `Chooser.new` block alone, since their stack, their `drawFrame`, their tap lifecycle,
and their click path re show are all entangled.

**9.10 The registry has a surfaces resolver that the live root does not use.**
`lib/registry.lua:627`, `instance.surfaces(spec)`, with warning paths at `:637`, `:643`, and
`:650`. The root builds its own list instead at `root/compose.lua:1186` through `:1214`, with
its own lazy proxy at `:1165` and its own dual calling convention fallback at `:1176`. Two
mechanisms exist for one question, and only one is wired. Worth deciding before the stage adds
a third.

**9.11 Three plugins carry a literal copy of the same anchor calculation.**
`plugins/clipboard/manager/ui.lua:1180`, `plugins/filesearch/chooser.lua:454`,
`plugins/processes/chooser.lua:347`. Identical arithmetic spanning the list and its pane for the
hint panel anchor. The stage, which will own positioning, should absorb this rather than
inherit three copies.

**9.12 The "row number" hazard is the single most repeated workaround in the tree.**
`lib/chooser/providers/native.lua:512` polls the highlighted row **number**, so any list that
changes under a stationary highlight fires no `onHighlight`. Three plugins compensate by hand.
FileSearch at `plugins/filesearch/chooser.lua:686` through `:690`, Processes at
`plugins/processes/chooser.lua:325` through `:327` and `:432` and `:469`, and BrowserTabs avoids
it entirely by skipping the redraw when the signature is unchanged,
`plugins/browsertabs/chooser.lua:714`. Any rows engine the stage grows should own this rather
than leave a fourth copy to be written.

**9.13 Caffeinate's surface answers three of the five nav functions.** `isShowing`, `hide`,
`insertSelected` only, `plugins/caffeinate/init.lua:309` through `:321`. That is deliberate,
`nav = false` at `plugins/caffeinate/manifest.lua:32`, and it works only because
`lib/nav.lua:69` checks the method exists before calling it. A presentation contract that
requires all five would break it, and one that requires none of them has to keep that check.

**9.14 The launcher's surface has a sixth function nothing else has.** `peekPreview` at
`host/launcher/init.lua:264`, named deliberately to match the verb the tools' own pickers
answer, stated at `:262` through `:263`. FileSearch answers the same name at
`plugins/filesearch/chooser.lua:731`. So the surface contract is already not five functions, it
is five plus whatever a context's own bindings name.
