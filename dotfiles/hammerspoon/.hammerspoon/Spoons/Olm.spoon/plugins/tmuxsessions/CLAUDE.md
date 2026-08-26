# TmuxSessions

Why this spoon is shaped this way. The code sits beside this file, so this records the
decisions, not the lines.

## Two shapes, decided by whether anything is attached at all

Jumping to a session is only ever one of two things. Something somewhere already has a
tmux client attached, in which case that client is retargeted with tmux's own
`switch-client`, the exact primitive the tmux session strip in `dotfiles/tmux` already
uses. Nothing is attached anywhere, in which case there is no window to retarget, so the
configured terminal provider opens a fresh one that attaches on arrival. `engine.lua`'s
`goTo` is the whole of this decision, and every terminal provider only ever answers one of
`activate()` or `openAttach(target)`, never both at once, since the engine already knows
which one is needed before either is called.

## One terminal window at a time, and what that trades away

Raising the right app after a retarget needs no window matching at all when only one
terminal application is actually running, which is the ordinary habit this was built for
and confirmed with the person who asked for it before this was built at all. Several
terminal apps running concurrently, each already pinned to a different session, is the one
case this cannot disambiguate, since nothing here asks which physical window a tty
belongs to. `_raiseWhicheverIsRunning` falls back to whichever terminal is configured and
may simply raise the wrong app rather than claim to know. Solving it precisely would mean
walking the process tree behind each attached client's tty back to whichever application
owns it, real code with its own failure modes, deliberately not built for a case nobody
asked for.

## hs.execute sanitizes control bytes, discovered here the hard way

`hs.execute` hands back every control byte in a command's output replaced with an
underscore. A tab embedded in a tmux `-F` format string, the obvious separator for reading
back several fields from one line, survives perfectly through a raw `/bin/sh -c` run by
hand and is silently mangled the moment the exact same command runs through `hs.execute`,
turning `canvas-medical` followed by a tab and a `1` into `canvas-medical_1`, one field
instead of two with a stray digit stuck on the name. Measured against several other
control bytes, not only tab, so this is not a tab specific quirk. `FIELD_SEP` in
`engine.lua` is a pipe instead, the same choice `processes/sources/docker.lua` had already
made for its own `-F` output, quite possibly for this exact reason without either file
saying so before now. Any future file in this config that parses delimited command output
through `hs.execute` should read this before reaching for a tab, a newline survives fine
since only newlines split the rows, it is a byte inside one row that gets rewritten.

## hs.application.get costs a third of a second to say no, measured here

Choosing a window left the picker sitting on screen for a beat before it closed, and the whole
of that beat was one loop. `_raiseWhicheverIsRunning` asks every configured provider whether it
is running, and each provider answered by calling `hs.application.get(BUNDLE_ID)`. That call is
cheap when the app is running and expensive when it is not, because a failed bundle id lookup
falls through to searching names and window titles across everything running. Timed against the
five providers on this machine, the one running terminal answered in about a millisecond and the
four absent ones cost between twenty seven and fifty one, so the loop spent something near two
hundred and seventy milliseconds to learn one fact it already nearly had. `switch-client` and the
tty read together cost about forty five, so the raise was most of the delay rather than a part of
it.

`hs.application.applicationsForBundleID` answers the same question and does nothing else, no
fallback and no title search, and timed the same way it costs zero to a fraction of a millisecond
whether the app is running or not. Every provider's `running()` goes through it now, in one place
rather than five, which is the subject of its own section below since paying for this fix five
times over is what made the duplication worth removing. Nothing about
the ordering of the jump changed, and that was deliberate. `onSelect` still runs to completion
before the atom tears the chooser down, which is what lets a raise land before hs.chooser queues
its own restore of focus to whatever the picker covered, so the fix was to make the work cheap
rather than to move it behind a timer and race that restore.

Worth generalising from, since nothing about this is specific to terminals. Any hot path in this
config that asks `hs.application.get` about an app that is usually absent is paying the same
price, and the same substitution applies wherever only presence is being asked.

## A declared need can arrive nowhere and nothing says so

The picker reset its order on every open for as long as it existed, and the reason was one
omission in this plugin's own `configure`. `manifest.lua` declares `needs.lib.recency`,
`lib/services.lua` builds this plugin its own instance keyed to `olm.recency.tmuxSessions`, and
`lib/wire.lua` hands it over as `opts.recency`. This plugin's `configure` then built the engine's
options by hand, `deps` and `providers`, and never mentioned it. The engine guards every use of
`_recency` with a nil check, exactly so a plugin that declares nothing still works, so the
omission was not an error at any layer. It was `windows()` answering in plain session-then-index
order, forever.

What made it invisible is the shape rather than the slip. A declared need is validated when the
plugin loads, which reads as the need being handled, and the value travelling from the root to the
place that uses it is a separate journey nothing checks the end of. The cheap way to catch it is to
ask the running config rather than to read the wiring,
`hs.settings.get("olm.recency.tmuxSessions")` answered nil while browserTabs' own key held real
data, which is a one line probe that proves an injected service is not merely wired but actually
being written to.

Adding the missing word to that list was the first fix and it is not the one that is here. It
worked and it left the next granted service one forgotten word away from vanishing exactly as
quietly, which is not a fix so much as a reset of the same trap. The engine is a declared wiring
target now, one more line in `manifest.lua` beside the two the chooser already had, so
`lib/wire.lua` calls its `configure` directly with the whole granted options table and the engine
reads `deps` and `recency` off it. This plugin's own `configure` passes the provider chain and
nothing else, so it no longer knows recency exists at all. There is no list, so there is nothing to
forget a name from, and a service granted in future arrives with no edit here.

Two things had to be true for that to work and both are worth knowing. A declared step receives the
full options table by default, and `targetOf` in `wire.lua` resolves a single named submodule off
the plugin root, so `obj.engine` was already a legal target and no shared lib changed. And the
engine's `configure` had to stop resetting every field on every call, since it is now called twice
with two partial tables, once by this plugin with what it decides and once by the wiring with what
was granted. It writes only what it was actually handed. That is the same two caller arrangement
the chooser already had, and the manifest already documented for the chooser, so this is the
existing shape applied to the other half of the plugin rather than a new idea.

## Five identical edits are the smell, and consolidating them found a bug

Changing how a terminal's presence is proven cost five edits to five files, because three of the
four methods `contract.lua` asks for are decided entirely by a bundle id and every provider wrote
its own byte for byte identical copy of all three. The quoting helpers were duplicated too, an
AppleScript one in three files and a shell one in two. Only `openAttach` and the identity were ever
genuinely a backend's own.

`providers/bundle.lua` holds the bundle decided half now, and each provider file returns a function
taking it and answers with its identity and its `openAttach`. The mechanism is handed in rather
than reached for, so no provider computes a path or names a sibling, and `init.lua`, which is this
plugin's composition point for backends, is the only file that loads it. It stops deliberately
short of collapsing more. Three backends open through AppleScript and two through their own argv,
a second real similarity, and folding that too would leave a provider file no longer showing the
exact script or command line it sends, which is the text a person opens one of these files to read.

Consolidating them is what found a bug that had been in all five copies since the first one was
written. `hs.application.pathForBundleID` answers an EMPTY STRING for a bundle id it cannot place,
never nil, so `pathForBundleID(id) ~= nil` is true for an application that is not installed. Every
one of these providers reported itself available on a machine without it, which meant the Settings
level listed iTerm, Alacritty and WezTerm as Installed on a machine holding none of the three, and
`currentProviderName` would accept a stored choice naming one of them and then fail at the attach.
Measured rather than reasoned about, all three answered an empty path and all three answered
available. The test is `path ~= nil and path ~= ""`, which is exactly what
`browsertabs/providers/chromium.lua` and `host/hypercheatsheet/init.lua` both already wrote, the
second with a comment naming this trap, so this plugin was the outlier rather than the discoverer.

The same trap sits in three more places this plugin does not own, `lib/deps.lua` resolving a
declaration of kind `app`, and the clipboard's `raycast.lua` and `shortcut.lua` providers, all
three testing the path for truthiness where an empty string is truthy. None of them is answering
wrongly on this machine, since every bundle id they name is genuinely installed here, so all three
are latent rather than live. `deps.lua` is the one that matters, since an `app` kind declaration is
how this config guarantees an application is present and an empty string means it can never report
one missing.

## A read of tmux held for a moment, and why the picker could not own it

Every keystroke rebuilt the row list, and the row list came from two shell calls to the tmux
server, about twenty two milliseconds, so typing paid for two fresh round trips per character to
answer a question whose answer had not changed. The engine holds its last read for a second now.
Measured, a cold read is twenty four to forty two milliseconds and a warm one is two hundredths of
one, and dropping the held read puts it straight back to a real read.

The obvious shape is a snapshot taken when the picker opens and thrown away when it closes, and it
is wrong here, which is the part worth recording. The launcher's hosted list has no open and no
close. It asks `scopeRows` on every keystroke forever, so there is no moment there that could
stand for now, and a lifecycle snapshot would leave the hosted path paying the full cost while the
native picker paid none. So how long a read stays good is the engine's own business, since only
the engine knows what a read costs, and it is a short window rather than a lifecycle.

Two details keep it honest. It caches the READ and never the ordering, because a jump touches
recency and a cached ordering would then be wrong in a way a cached read never is, so `windows()`
applies recency over the held read on every call. And a deliberate open still reads fresh, since
`M.show` calls `invalidate` before anything else, which also makes an open cost one read rather
than two, because `pruneRecency` asks first and the first render reuses what it got.

## Registering is not enough, the launcher still needs its own line

`registry.register` makes a tool active, gives it a surface, and lets its row be asked for
through `rowFor`, but it does not put that row anywhere a person can see. The launcher's
own `_ensureStaticRows` in `host/launcher/init.lua` builds its row list from a fixed,
hand written sequence of `addTool(name)` calls, one per tool, and a tool missing from that
sequence is registered, active, fully working when reached by its Hyper key, and simply
absent from the launcher with nothing in the console naming why, since `rowFor` answering
something nobody asked for is not a failure of anything. This is documented in that file's
own header comment and in the Launcher's own `CLAUDE.md`, and it was still missed once
here, reached only after the row failed to turn up in a live query against the launcher's
own `_orderedRows()`. `addTool("tmuxSessions")` is the one line that closes it, sitting
beside `addTool("fileSearch")`.

## The list is windows, ordered by recency, with the tally pruned on open

The picker was first built session first, one row per session with its windows folded
into the subtitle. It is window first now, one row per window with the session it belongs
to as the subtitle, because a session is not what you are actually looking for, the window
inside one is, and two sessions keeping a plainly named window, `zsh` inside both `main`
and `mdj-notes`, need the session named to tell them apart at all.

Recency lives in the engine, not the chooser, the same place BrowserTabs and Vpn each keep
their own instance, injected once from the root rather than built here. `windows()` hands
back the flattened list already ordered, a remembered window leading in the order it was
last reached and everything else keeping its plain session-then-index arrival order behind
it, so the chooser only ever filters what it is given and never reorders it a second time.
The key a row carries, an ordering is remembered under, and a jump touches on success are
all the exact same string, the tmux target `session:index`, which is what lets `goTo`
recognise a window row's `go` field with no translation at either end.

A session or a window inside one can be killed at any time from outside this tool
entirely, a `tmux kill-session` in a terminal this picker never opened, which a
bundle id or a VPN city never has to worry about. Left alone, the remembered order would
keep a dead target sitting near the top of the list forever, or worse, silently reattach
its old recency to some unrelated later window that happened to reuse the same target
string. `pruneRecency()` is the fix, dropping any remembered key `windows()` cannot
currently produce, and it needed a real capability neither of `Olm.lib.recency`'s two
existing consumers ever asked for, so `prune(validKeys)` was added to that shared file
rather than reached around from here. It runs once per chooser open rather than on every
keystroke, since what can disappear only disappears between opens and a maintenance pass
belongs off the hot filtering path on principle even though its own cost is small either
way.

## A third place registering is not enough, and it is the same shape twice already

`registry.register`'s `scope` field describes a scope, it does not enter it into
`QueryScope`. `init.lua` builds the live catalog from its own hand written
`queryScopeSpec` list, folded through `registry.scopes(spec)`, and a tool absent from that
list is exactly as invisible to typing `u ` or `tmux ` as it was to the launcher before
`addTool("tmuxSessions")` was added, for the identical reason, one more fixed sequence a
new tool has to join rather than something a registration alone finishes. Verified by
calling `spoon.QueryScope:resolve("u ")` before the fix, which answered nil, and again
after adding `"tmuxSessions"` to `queryScopeSpec`, which answered the scope.

`hosted = true` also changes what choosing this tool's own launcher row does, from
opening the native picker to hosting the plain window list in place, the exact same
tradeoff BrowserTabs makes for its own row. The Settings level stays reachable only
through Hyper+U or through opening the picker directly, never through the alias or the
row, since hosting shows one list and Settings is a step into a second one.

`row.detail` and a real chord do not mix well either, and this one was a style choice
rather than a hidden mechanism. Setting `detail` makes the launcher's `addTool` print it
in place of the chord entirely, which is right for a tool with no dedicated key
(DisplayProfiles's own "inspect and manage arrangements") and wrong for one that has a
key, since it then hides the very shortcut a reader opened the launcher hoping to learn.
Leaving `detail` unset, the FileSearch shape, is what makes the subtitle read `Tools ·
Hyper U (u, tmux)`, category, chord, then the alias hint `add` appends on its own,
matching every other keyed tool rather than narrating what the tool does.

## Hyper+I did nothing while Return worked, because the two go through different doors

Return is the native chooser widget's own key, handled entirely inside the atom, which is
why `insertSelected`, `intercept`, and `back` all worked from the first build, verified
repeatedly against a live reload. Hyper+I is a different door. The root's shared
`contextActions` table dispatches a hyperContext action by calling a method of that exact
name on whichever surface is active, `routeNav("enter")` for the `i` binding here and
`routeNav("hide")` for `x`, and this chooser exposed neither name, only `insertSelected`
and a `close` it invented. `c[method]` was simply nil both times, and `routeNav`'s own
guard, `if c and c[method] then`, makes a missing method a silent no-op rather than an
error, so nothing in the console ever pointed at it.

DisplayProfiles and BrowserTabs both already answer to `enter`, but by hand-dispatching
through their own `applySelection`, since they predate the atom's real `intercept`/`back`
hooks this chooser already uses correctly. Copying their shape would have meant a second
implementation of logic this file already has right. `M.enter` is instead a one-line alias
for the existing `M.insertSelected`, since both names now have to reach the exact same
call, `chooser:insertSelected()`, and `M.hide` replaces the invented `M.close` outright,
nothing else in this plugin ever called it under the old name.

## Searching both fields at once, why a hand written word match rather than the shared one

Typing the whole session name found a row, and typing the whole window name found a row,
but the two together found nothing, because the first filter checked whether the typed
text matched entirely inside one field or entirely inside the other, never both at once.
`matchesQuery` fixes it by splitting the query on whitespace and requiring every word to
be a substring somewhere in the window name and the session name concatenated, in any
order, so `vic gen` finds the `general` window inside `vicert` even though neither word
names the whole of either field alone.

This is the same `words` strategy the clipboard and Local Servers already use over their
own multi-field bodies, for the identical reason, a query here is a real remembered
fragment of more than one thing rather than a single guess at one label. It stays a hand
written function rather than `Chooser.matchers.words` itself, because that matcher is a
construction-time option on the whole instance and this chooser's Settings level still
needs to opt out of any shared matcher entirely, the same reason DisplayProfiles and
BrowserTabs each write their own filter rather than turning the shared one on.

## Two Olm-wide landmines this plugin's wiring had to route around

`depsFor("Olm").satisfied()` answers for every required dependency anywhere under the
whole of Olm.spoon at once, not only for whatever plugin is asking, because the runtime
resolver stamps every declaration under Olm.spoon with the one consumer name Olm
regardless of which plugin subdirectory it lives in. Marking tmux required (accurate,
this tool is only a front end onto it) and then gating this plugin's own wiring on that
shared `satisfied()` would have made an absent tmux also fail Convert's own gate, and any
other required tool added anywhere later would just as quietly reach back into this one.
The root's wiring reads `have("tmux")` instead, which asks about exactly the one name this
plugin needs and touches nothing else declared under Olm.

Registration order matters for a different reason. `registry.activate(names)` walks the
activation list once and marks a name active only if something has already called
`register` for it by that moment; nothing retroactively activates a later registration.
This plugin's own `registry.register` call had to move earlier in `init.lua`, into the
same span BrowserTabs and DisplayProfiles already register in, ahead of the one
`registry.activate` call, rather than sitting wherever felt topically closest. A
registration placed after it is a tool that is present, has a working chooser, and is
permanently invisible to the launcher, with nothing in the console naming why.

## Terminal providers, and what was actually verified

Only Ghostty was installed on the machine this was built on. Ghostty and Terminal.app were
each verified with a live reload against the real tmux server on this machine, switching
an actually attached client between real sessions and back. iTerm was written against its
published AppleScript dictionary and not run live. Alacritty and WezTerm carry no
AppleScript dictionary at all, so their `openAttach` goes through `open -na <App> --args`
instead, `-e ... tmux attach-session` for Alacritty and `start -- tmux attach-session` for
WezTerm, both documented CLI shapes and neither one run live. `available()` answers false
for whichever of these are not installed on a given machine either way, so an unverified
provider degrades to a disabled Settings row rather than a wrong answer. That sentence was
written before it was true. The empty string trap above meant every absent backend reported
itself installed, so this section made exactly the promise the bug was breaking, which is worth
leaving on the record as the reason to measure a claim like it rather than write it down.

## No restow

This whole plugin lives inside the already symlinked Olm.spoon, so every file here,
including the new `providers/` subdirectory, resolves through that one existing symlink.
Only adding a new top level spoon directory would need one.
