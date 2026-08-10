# Work packet, the plugin registry, the door, the version check, and the activation list

Phase 7 of the build plan, packet one of four. Written 2026-08-10 against `feat/plugin-contract`
at `f7bfe4c`, from a scan of the live tree rather than from the design's citations, several of
which have drifted. Work in the worktree at `../.worktrees/plugin-contract` on the branch that is
already checked out there. Never work from the primary checkout, never push, and never merge.

## What phase 7 is, and what this packet is

Phase 7 replaces the many places a tool is named by one registration. The design frames that as
three or four join points. It is not true any more. A scan measured the clipboard named in
thirteen places and file search in twelve, and the two do not touch the same set, which is how
file search's chord ended up missing from the Hyper overlay with nothing to notice.

So phase 7 is four packets on one branch, and this is the first. This one builds the mechanism and
proves it against exactly one join point, the launcher's special action dispatch. The three that
follow fold in the rest, the choosers registry and `hostedInPlace`, then the scope adapters and the
catalog rows, then the dedicated chords. Do not reach ahead into any of them. A packet that lands
half of the next one cannot be reverted on its own, which is the entire reason this is staged.

## The shape, and why

A registry keyed by name, backing dispatch by name. That is Strategy with the strategy chosen at
runtime by a string, and the registry is the contract both sides point at. The launcher depends on
the registry's read side and on nothing concrete. A tool depends on nothing at all, which is the
part worth protecting.

**No plugin file is touched by this packet.** A plugin here never reaches for `spoon.Olm` and only
ever receives its slice through its own `configure`, which is a rule the tree already keeps and
this packet keeps too. So the composition root is what calls `register`, on each tool's behalf,
because the root is the only layer that knows a concrete tool. A third party plugin from the
search path would call the same `register` itself. One door, two callers, and the door does not
care which one knocked.

That is also why this packet is safe to build. Twenty three plugin directories stay untouched.

## The registry

New file, `Spoons/Olm.spoon/lib/registry.lua`, a factory in the same style as `lib/recency.lua`,
since a registry is state and the config builds one. It names no tool, reads no configuration, and
imports nothing from the tree. It is pure Lua with no Hammerspoon dependency beyond `hs.logger`,
which is what makes it the first part of this config testable in the unit runner rather than only
live. Keep it that way.

### The descriptor

One table per tool, handed to `register`. Every field except the first two is optional, and
optional means structural, absent rather than empty, in the way the lifecycle contract already
describes for `start` and `stop`.

`name`, a string, the tool's identity. It is the tool's own key in `config/keys.lua`, which is
already the key the row descriptor carries and the key a scope registers under, so there is
nothing for three strings to disagree about. Required.

`apiVersion`, an integer, the core version the tool was built against. Required.

`open`, a function of no arguments, what running this tool's launcher row does and, from a later
packet, what its dedicated chord does. Optional, because a tool may exist only as a scope.

`commands`, a map of name to function, extra named actions belonging to this tool. The clipboard
owns two, append copy and paste next. They are not tools of their own, they are commands of one
tool, and putting them here is what makes deactivating the clipboard take them with it.

Nothing else in this packet. Not the surface, not the scope, not the hosted bit. Those arrive in
packets two and three and adding a field early with no consumer is the indirection the design
principles reject.

### Registration

`register(descriptor)` validates, then records. It refuses rather than raises, so one bad tool
cannot empty the launcher, which is the same reasoning behind a query source that raises being
dropped for a keystroke. Every refusal is one log line at warning naming the tool and the reason.
Return true when it registered and false when it refused, so a caller can react if it ever wants
to, and the root ignores it.

Four refusals, and each one has a unit case.

A descriptor with no `name`, or a name that is not a string, is refused. It cannot be named in its
own error, so the line says what it can.

A second registration under a name already taken is refused, naming the tool. First registration
wins, because the alternative is a later one silently replacing behaviour the earlier one is still
wired to.

A `commands` key colliding with any name already indexed, whether a tool name or another tool's
command, is refused, naming both sides. The index that dispatch reads is flat, so a collision
there is ambiguity rather than a preference.

An `apiVersion` that does not equal the core's is refused, naming the tool, the version it
declared, and the version the core offers. Equality rather than a range, because the version is
bumped only on a breaking change, which makes every difference in either direction a mismatch by
definition. A missing or non integer `apiVersion` is refused the same way.

The core version is injected when the registry is built rather than read from `spoon.Olm`, since
the registry must not reach for the spoon that contains it.

### Activation

`activate(names)` takes a list of tool names and is called once after every registration. A
registered tool whose name is in the list is active. One not in the list is registered and
inactive. A name in the list that nothing registered produces one warning line naming it, and is
otherwise ignored, since a typo in a roster should be visible and harmless rather than fatal.

Read side. `run(name)` looks the name up in the flat index of tool names and command names, and
calls it when the owner is active. It returns true when it ran something and false when it did
not, which is what lets a caller fall through. `get(name)` hands back the descriptor of an active
tool or nil. `active()` lists active tool names in registration order. `all()` lists every
registered name with its active flag, for diagnostics only.

An inactive tool answers nil and false to every read except `all()`. That is the whole of what
inactive means in this packet. It does not yet unbind a chord or remove a row, and packets three
and four are what finish it. Say so in the file's own header comment so the next reader is not
misled by a half kept promise.

## The launcher

`Spoons/Olm.spoon/host/launcher/init.lua`, two changes and no more.

`configure` accepts one new injected collaborator, `registry`, stored the way the others are. It
is optional, and a launcher configured without one behaves exactly as it does today, because a
host that hard requires a registry cannot be tested without one.

`_runItem`'s special branch asks the registry first and falls back to the injected `actions.special`
table.

    elseif it.kind == "special" then
      local ran = self._registry and self._registry:run(it.name)
      if not ran then
        local fn = a.special and a.special[it.name]
        if fn then fn() end
      end

Two sources here is not a leak and the comment above it should say why. A registered name is a
tool. What stays in `actions.special` is a bare command with no tool behind it, lock, sleep, and
the System Settings search focus, and the design's own rule is to resist making everything a
plugin. They are different kinds of thing and one lookup for each is honest. The order matters
only because a name cannot be in both, which registration already refuses.

Nothing else in the launcher moves. Not `_buildActionRows`, not `surface`, not the scope
handling.

## The composition root

`dotfiles/hammerspoon/.hammerspoon/init.lua`.

Build one registry after Olm loads and before the launcher is configured, passing the core's
`apiVersion`. Register a descriptor for each of the eleven tools below, then call `activate` with
the list read from configuration, then pass the registry into `spoon.Launcher:configure`.

The eleven, each keyed by the name its current `actions.special` entry already uses, so no row
descriptor anywhere changes.

`clipboard`, opening `spoon.ClipboardHistory:open()`, with commands `appendCopy` and `pasteNext`
carrying the two closures that sit beside it today, comment and all. `caffeinate`. `vpn`.
`colorPicker`. `emoji`. `dockAutoHide`. `displayProfiles`. `textCase`. `browserTabs`. `processes`.
`fileSearch`.

Every one of those thirteen names then leaves `actions.special`, because the registry serves them
now and two owners for one name is the drift this phase exists to end.

Four names stay in `actions.special` and each stays for a reason worth writing in one comment
above them. `lock` and `sleep` are bare system commands with no tool behind them. `searchSettings`
focuses a field in a pane and belongs to no plugin either. `overlayDisplay` is a picker built out
of root local code rather than a plugin, so it has no descriptor to register, and the alias
directory is a scope, which packet three is where scopes move. Do not invent a plugin for any of
the four in order to tidy the table.

Every registration declares `apiVersion` equal to the core's current value, which is one. Write
the integer rather than reading `spoon.Olm.apiVersion` into each descriptor, because a
registration copying the core's own number can never mismatch and the check would then be theatre.

## Configuration

`config/settings.lua` gains one block, the default activation list, a plain array of tool names.
It lists all eleven, so this machine's behaviour is identical after the change and the inventory
diff can prove it.

The root reads that default and then, when an `hs.settings` key holds a list, prefers it. The
design settled that the activation list is persisted in `hs.settings` because a future roster
writes there, and that roster is deferred, so a hand edited file is the only usable surface today
and the settings key is the door the roster will use. Both together, the file as the default and
the setting as the override, is the honest version of that decision and costs one `or`.

Name the settings key in the same style as the keys already used here, and write one comment
saying the file is the default, the setting is the override, and nothing writes the setting yet.

## What not to change

Do not touch any file under `Spoons/Olm.spoon/plugins/` or the other two hosts. Do not change
`hostedInPlace`, the `choosers` registry, `queryScopes`, the `scope` helper, `_buildActionRows`,
`hyperActions`, `hyperContexts`, `config/keys.lua`, or any `HyperKey:bind` call. Do not add a
`stop` to anything. Do not change `obj.apiVersion`. Do not make the registry read configuration
or reach for `spoon.Olm`.

Do not gate a plugin's `dofile`, its `configure`, or its `start` on the activation list in this
packet. That is real and it is packets three and four, and doing it early is how a launcher comes
up empty with no way to bisect which fold did it.

## Gates

`luac -p` parses every touched file.

`test/units.sh` from the worktree hammerspoon directory passes, including a new
`test/cases/registry.lua` covering, at minimum, a good registration and a successful `run`, each
of the four refusals with the log line's content asserted where the runner can see it, a name in
the activation list that nothing registered, an inactive tool answering false to `run` and nil to
`get`, and a command dispatching through its owning tool. The registry is pure Lua, which is why
the two deliberate failures the phase gate asks for are unit cases here rather than a temporary
edit to a live config. Report the case count before and after.

`src/check-dependencies.sh` from the worktree root passes with no new warnings.

`test/inventory.sh --check` passes with an empty diff. That is the gate this phase was built
around, so run it three times as committed and report each. It takes the machine test lock itself
and gives it back, so never run `bin/hs-devlock` by hand.

## Deliverable

This packet committed first, then the registry with its unit cases, then the launcher, then the
root and the configuration, then the documentation. Small commits, each one able to stand alone.
Every message ends after a blank line with

    Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>

and every subject has the form scope subject with no colon after the scope.

Do not merge. The branch is reviewed and the four packets merge together at the end of phase 7.

Documentation is one place in this packet. `Spoons/Olm.spoon/CLAUDE.md` gains a Registry section
beside the others, holding what a reader would otherwise have to rediscover, the descriptor's
fields and which are optional, why registration refuses rather than raises, why the version check
is equality, why the root registers rather than the plugin, what inactive does and does not mean
today, and why the launcher looks in two places. Do not touch any other CLAUDE.md.

Report the exact registry api you wrote, each gate's numbers, the case count, the three inventory
runs, and anything in this packet that did not survive contact with the code, flagged loudly
rather than worked around. If a decision here turns out to be wrong once you can see the code,
stop and say so rather than choosing for yourself.

Every line you author follows the repository writing rules, no colons, no semicolons, no hyphens
or dashes, periods and commas only. Copied names and existing identifiers keep their form.

## Live testing, and the rules around it

The inventory run is the only thing that makes this checkout live, and its script takes and
releases the lock for you. If you need to read the Hammerspoon console, write a scratch file
containing exactly `return hs.console.getConsole()` and run it through `hs -c "dofile('...')"`,
because a console read can take minutes and is not hung. Never pass an angle bracket inside inline
Lua to `hs -c`, it wedges the command. Never call `hs.reload` inline, schedule it with
`hs.timer.doAfter` and poll `hs.configdir` afterwards. Never call
`hs.logger.setGlobalLogLevel`, it floods every logger and pins the process.

Never run `git reset`, `git checkout` on a path, or `git stash` to clean the tree. If the tree is
not what you expect, read `git status` and report it.
