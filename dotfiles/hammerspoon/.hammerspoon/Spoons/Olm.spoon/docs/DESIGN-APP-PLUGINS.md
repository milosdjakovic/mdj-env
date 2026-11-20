# External plugins, a process each, run by Olm.app

Written on 2026-11-20, asked for by Milos once the resting point was called reached. It fills in
the third kind of source `docs/DESIGN-APP.md` names under The source, "an extension host, which runs
extensions someone else wrote in a process of its own", and it answers open question 3 of
`docs/PLAN-STANDALONE.md`, what extensions are written in. It waits on Milos's go.

## What he asked for

- In the end Hammerspoon is out of the picture. Nothing here keeps it.
- The core, what is reached constantly by key or touches windows, typing and the clipboard, is
  Swift built into the app. Everything else, display profiles, tmux sessions, VPN and the like, is
  an **external plugin**, and ours are written in Swift too.
- Anyone can write a plugin and install it without a build of Olm, by dropping it on Olm Settings
  or into a folder, and Swift source is compiled on install.
- Claude can develop a plugin in any folder, outside this repository, and test it there.
- **A plugin never clogs Olm.** Typing, the list, the keys and every other plugin stay live whatever
  one plugin does.
- **A plugin is sandboxed, without being boxed in.** It reaches only what it declared, it can still
  run the tools it is for, caffeinate, mullvad, the IVPN command and the like, and switching it on
  asks for its permissions once, in plain words, rather than failing later.

## The split, core and external

| | Plugins |
|---|---|
| Core, built into the app | the launcher and its apps, app toggler, window manager, window size, workspaces, clipboard, file search, emoji, menu search, input sources, text case, calculator and convert, System Settings panes |
| External, ours, in Swift | display profiles, tmux sessions, VPN, Wi-Fi, audio, volume, keep awake, Dock auto hide, speed test, processes, Obsidian, browser tabs, capture, eyedropper |
| Gone | Olm Chooser, Olm Placement, Olm Theme, Olm Plugins, which the settings window replaced |

The line is the round trip. A process round trip costs a few milliseconds plus whatever the plugin
spends, which no one feels in a VPN list and everyone feels in the launcher or a window key. Ours
being external is on purpose, so the format carries real plugins from the first day and a stranger's
plugin works exactly as ours do.

## The shape

```
 Olm.app                                                     one process per plugin
 ───────                                                     ──────────────────────
 stage, panel, keys, search          PluginRunner            ~/.olm/plugins/tmux/
 (main thread, never waits)   ◄──►   one actor per plugin ◄──► tmux, the built program
        ▲                            starts, watches, kills    reads stdin, writes stdout
        │ the same Source protocol   budgets every request     stderr to its log
        │ a native plugin answers
 ExternalSource, one per plugin
```

**The runner is part of Olm.app, not a process of its own.** `PluginRunner` is an actor in the app,
one child actor per plugin, and it does three jobs. It starts a plugin's process when it is first
needed, it speaks the protocol to it over the process's own pipes, and it holds every request to a
budget, killing a plugin that breaks one. Each plugin appears to the stage as an `ExternalSource`,
the third conformance of the `Source` protocol in `docs/DESIGN-APP.md`, so the stage cannot tell an
external plugin from a native one or from the Hammerspoon bridge, and every rule the stage already
keeps, generations, dropped late answers, effects applied in one place, holds for it unchanged.

A separate runner process was considered and is not needed. It would be one more process between the
app and the plugin, holding nothing the app's actor cannot, and the app is already the one place
that knows which list is open and which request is stale.

**One process per plugin, never one shared.** A plugin is a program the runner starts with
`posix_spawn`, its working folder its own, its stdin and stdout the protocol and its stderr its log.
One process per plugin means a plugin that spins, leaks or crashes takes down itself and nothing
else, and the runner can kill exactly it. A shared host running every plugin in one process was
rejected for that reason, below.

## The protocol, the bridge's, over pipes

It is `docs/PROTOCOL-BRIDGE.md` version 1, the framing and the words unchanged, carried over the
child's stdin and stdout rather than a socket. Each message is its length, a newline and then the
JSON, and the messages are JSON-RPC 2.0. Pipes rather than a socket because the app made the
process, so there is no path to secure, no peer to check and no reconnect, and the plugin dies with
its pipes when the app quits.

The words a plugin answers are the bridge's: `hello`, then opening a level and answering its `rows`
for a query generation, `choose` answered with the ordered effects, the actions pane's verbs, the
preview pane as content rather than drawing, and the info pane's lines. What a plugin may ask of the
app is a short list of its own, each named in the manifest before it is used:

| Request | What the app does |
|---|---|
| `notify` | shows one routine line, Olm's feedback, never a window of the plugin's |
| `redraw` | asks for its open level's rows again, coalesced to one per frame |
| `copy`, `paste` | writes the pasteboard, or pastes into the app that was in front |
| `open` | opens a URL or a file through LaunchServices |
| `store` | reads and writes a small JSON store of its own under `~/.olm/plugins/<id>/data/` |

A plugin never draws. It answers rows, icons by key or SF Symbol name, pictures as file paths and
previews as the kit's content, and Olm draws all of it in the one look, rule 9. A plugin never
binds a key either. It suggests keys in its manifest as today's `defaults.bindings` do, and the keymap
binds them, so `config/keymap.lua` today and the settings window later stay the one place a person
sets a key.

## Never clogging Olm

Each of these holds with no help from the plugin.

1. **Nothing waits on a plugin on the main thread.** Every request is sent and answered on the
   plugin's actor. The panel shows the field and the highlight from its own state, as it does for
   the bridge today, rule 1 of the protocol, and a late answer is dropped by its generation.
2. **Every request has a budget.** Rows answer within 150 ms or the list shows its working state
   and keeps the last rows, and an answer that comes later is drawn if its generation is still current.
   At 2 s the request is cancelled and the plugin is told. `choose` has 5 s, `hello` 2 s. A plugin
   that has a request past its hard limit and does not answer a `ping` within 1 s is killed.
3. **Started only when needed, and stopped when not.** The launcher's rows and actions for a plugin
   come from its manifest, so typing in the launcher starts no plugin. A plugin starts when its key
   is pressed, its alias typed or its row chosen, and is stopped after 5 minutes unused. A plugin that
   must run all the time, display profiles watching for monitors, says `background` in its manifest,
   and the settings window lists it as running in the background.
4. **A plugin runs at a lower priority than Olm.** The runner starts it at the utility quality of
   service, so the system gives Olm's threads the CPU first whatever a plugin is doing, and a
   `background` plugin at background quality.
5. **What a plugin may send is bounded.** A message is at most 8 MiB as on the bridge, rows are cut
   at the level's row limit, `redraw` and `notify` are coalesced and rate limited, and a plugin
   whose memory passes 512 MB, read with `proc_pidinfo` every few seconds, is killed and said.
6. **A plugin that keeps failing is switched off.** Three crashes or kills in ten minutes and it is
   off until a person turns it on again in Olm Settings, which says why, with its log one click away.
7. **The launcher's typed rows are the one live path, and the tightest.** A plugin whose rows come
   from what is typed into the launcher, a calculator or a converter, declares `launcherQuery`, gets
   50 ms per query, and its rows are merged when they come. The launcher never waits for it. That is
   also why the calculator and convert are core.

## A plugin on disk

```
tmux/
  olm-plugin.json     the manifest
  Sources/main.swift  Swift source, compiled on install
  icon.png            optional
```

`olm-plugin.json` is today's Lua manifest as JSON, the same fields and meanings, since the bridge
already serves manifests as JSON and the contract in `docs/PLUGIN-CONTRACT.md` is what plugins are
written against: `about`, `icons`, `defaults` with its bindings and aliases, `surface`,
`presentation` as the list of what the program answers, `registry` with its launcher row, `settings`
for Olm Settings, and two fields of its own:

- `run`, how the program is made, `{ "swift": "Sources" }`, compiled on install. Swift is the one
  language for now, below.
- `needs`, what it asks of the app, the requests above, and the permissions of the sandbox, the
  tools it runs among them, as `needs.tools` does today, so a missing tool is said rather than
  discovered.

**Swift** is built with `swiftc` from the command line tools, which this repository installs on
every machine and which the eyedropper and browser tabs plugins already compile with. It links one
small package, `OlmPluginKit`, the protocol's types and a loop that reads requests and writes
answers, so a plugin is its handlers and nothing else. The build runs in the background with its
output kept, and a plugin that fails to build is listed with the compiler's error.

**Swift only, for now.** Since a plugin is a program speaking the protocol, any language could be
one, and none is ruled out. Swift is the only one Olm builds and supports at first, since every
plugin of ours is Swift, Claude writes it, it builds on any Mac with the command line tools, and a
plugin built on the machine from source is never stopped by the download checks a program fetched
ready made would be. JavaScript through macOS's own JavaScriptCore, and a ready made program of any
language, are a later step when someone asks, the protocol unchanged.

## Installing, and developing

- **Drop it on Olm Settings.** The Plugins section takes a plugin folder or a `.olmplugin`, a zipped
  one. Olm reads the manifest, shows what the plugin is and what it asks for, builds it, and copies
  it to `~/.olm/plugins/<id>/`. A person says yes once.
- **Or put it in the folder.** Olm watches `~/.olm/plugins/`, so a folder appearing there is offered
  the same way.
- **Developing.** `olm plugin dev <folder>` links a folder in place rather than copying it. Olm then
  rebuilds and restarts the plugin whenever a file in it changes, and the plugin shows in Olm
  Settings as in development, its log beside it.
- **The `olm` command.** Olm.app carries a small command line tool, `olm`, linked into the PATH by
  `src/setup-olmapp.sh`: `olm plugin new`, `dev`, `install`, `remove`, `list`, `log` and `test`.
- **Testing without Olm.** `olm plugin test <folder>` starts the plugin and speaks the protocol to it
  from fixtures, the rows a query answers, what choosing a row does, so a plugin is checked with no
  window and no person, the way the bridge's transcript golden checks Hammerspoon today.

**For Claude.** A skill installed with Claude Code's own skills, so it is there in any folder, holds
the plugin contract, the `olm` commands and the gates, the external counterpart of the `olm-plugin`
skill. A plugin is scaffolded with `olm plugin new`, checked with `olm plugin test`, run live with
`olm plugin dev`, and nothing of it needs to be in this repository.

Our own external plugins live in this repository, one folder each, and `src/setup-olmapp.sh` installs
them as it builds the app, so a fresh machine gets them with no step of its own.

## The sandbox, and asking once

Every plugin runs inside a sandbox, the rule list macOS's own sandbox engine enforces, which Chrome
keeps its pages in and Claude Code keeps its commands in. The runner writes the rules from the
plugin's manifest each time it starts it, so what the manifest declares is what the plugin can do,
and the declarations are enforced rather than only described. Our own plugins run under the same
rules as anyone's.

**What every plugin has without asking,** since none of it reaches anything of the person's: its own
folder, `~/.olm/plugins/<id>/`, to read and its `data` folder to write, a temporary folder, the
system's libraries and frameworks, the time, the locale, and talking to Olm over its pipes.

**What a plugin asks for, in a handful of groups a person can read:**

| Group | Example in the manifest | What the person reads |
|---|---|---|
| Run programs | `caffeinate`, `mullvad`, `tmux` | Runs caffeinate, mullvad and tmux |
| Files | `~/Library/Application Support/obsidian` to read | Reads your Obsidian vaults |
| Network | `internet`, or `local` for this Mac only | Uses the internet |
| Services | the Mullvad daemon's socket, the power manager | Talks to the Mullvad VPN service |

A program a plugin runs is sandboxed with it, so the services that program uses are part of what
the plugin asks for. caffeinate needs the power manager, mullvad needs the Mullvad daemon's socket,
and the IVPN command needs its local port and the file holding it. Each is one narrow door, that
socket, that service, this Mac and not the internet, and none of them is the network or the person's
files.

Not too limiting is a design rule here. Files and folders are asked for as whole places a person
recognises, a vault, the Downloads folder, the home folder for a plugin that searches it, rather
than file by file. A plugin that genuinely needs the whole home folder or the internet says so and
gets it once allowed, and the window says so in those words.

**Switching a plugin on asks once.** When a plugin is installed or switched on, Olm shows one sheet,
its name and what it does, then the groups it asks for in plain words, and Allow or Cancel. Allowed,
it is never asked again for the same list. An update that asks for more shows only what is new. Our
own plugins, installed by `src/setup-olmapp.sh`, are allowed by that install, so a fresh machine
asks nothing for them.

**A block is offered, not hidden.** When the sandbox refuses something, macOS logs exactly what, a
program, a path, a service, a port. The runner reads that line, puts it in the plugin's log and, for
a plugin in use, shows one routine line, the VPN plugin was blocked from talking to the Mullvad
service, with Allow beside it. Allowing it adds that one door to the plugin's grants on this Mac and
restarts the plugin. That is also how a plugin's author finds what it needs: `olm plugin dev` shows
each block as it happens, the author adds it to the manifest and runs again, and the manifest ends
as the exact list of what the plugin touches.

**macOS's own permissions are not shared.** macOS counts a child process as part of the app that
started it for the permissions it holds, so without care a plugin would act with Olm's
Accessibility grant. Nothing an external plugin does should need it, since windows, keys and pasting
are the core's, so the runner starts every plugin disclaiming Olm's grants, and a plugin that needs a
permission of macOS's asks for it as itself. Disclaiming goes through the spawn flag macOS's own
Terminal and Xcode use.

**What it is not.** A plugin allowed to run `tmux` can do whatever `tmux` can, so the sandbox narrows
a plugin to what it said it needs and cannot make a powerful tool harmless. Installing a plugin is
still trusting its author with that list, and the sheet shows the list so the trust is informed.

**Two interfaces it stands on are not Apple's public ones.** The sandbox's rule language and the
command that starts a program inside it are deprecated, though Chrome and Claude Code depend on them
and they work on current macOS, and the disclaim flag is private. Either can change with a macOS
release, so step 1 proves both on this machine, with caffeinate and mullvad, before anything leans on
them, and the runner refuses to start plugins unsandboxed when they fail, saying why.

## Hammerspoon until it is gone

While the move runs, the plugins not yet rewritten are still served by Hammerspoon over the bridge,
as they are today. Each external plugin of ours is rewritten in Swift, run beside the Lua one in
shadow where its rows can be compared, then flipped, which switches the Lua plugin off in
`config/plugins.lua`. When the bridge serves nothing, Hammerspoon is switched off, the end of stage 6.

## Rejected

- **Loading plugins into Olm's own process,** a bundle, a library or a JavaScript context in the app.
  The library route was turned down on 2026-11-08 in `decisions/olm-standalone.md`, since every
  plugin must match the app's build, macOS signing refuses a library it did not see signed, and a
  fault in one takes the launcher down. A JavaScript context in the app avoids the first two and
  keeps the third, a loop in a plugin stalls Olm's own process.
- **One host process running every plugin.** One plugin that spins or leaks stalls or kills all of
  them, and the runner could only kill them all together.
- **A socket per plugin.** The app starts the process, so its pipes are already a private two way
  stream that ends with it. A socket adds a path to secure and a reconnect for nothing.
- **Lua as the plugin language after Hammerspoon.** Embedding Lua in the app was turned down on
  2026-11-05. A later step that runs a ready made program of any language would make Lua possible
  again by an interpreter a person installs, and Olm carries none.
- **No sandbox, trust at install alone,** as Tinycast does, its extensions in JavaScriptCore inside
  the app with its file, process and network shims open to them once extensions are switched on.
  Milos wants plugins sandboxed.
- **Apple's App Sandbox for each plugin.** It is made for whole apps, keeps a program in a container,
  and stops it running tools like `tmux`, `ps` or `mullvad`, which is most of what our plugins are
  for.

## Steps

1. **The runner, the sandbox and one plugin.** `PluginRunner`, `ExternalSource`, the protocol over
   pipes, the budgets, the kill and the restart, with a test plugin in Swift that answers rows
   slowly, spins, leaks and crashes on purpose. The sandbox and the disclaim proved on this machine
   first, a plugin running caffeinate and mullvad under its rules and refused what it did not
   declare. Checked by a harness that shows typing in the app is untouched by each, the timings of
   1.3f on the app's side.
2. **`OlmPluginKit`, the `olm` command and the test harness.** A plugin written, tested and run from
   a folder outside this repository, by hand and by Claude.
3. **Installing and asking.** The Plugins section of Olm Settings takes a dropped plugin, shows the
   sheet of what it asks for, builds it and lists it with its state, its grants, its log and its
   switch, and a block in use is offered with Allow.
4. **The first plugin of ours.** Keep awake, small and pure, rewritten in Swift as an external
   plugin, run in shadow beside the Lua one and flipped. Then the others, one per step.
5. **The skill,** written once steps 2 and 3 have settled the commands.
6. **Other languages,** JavaScript through JavaScriptCore and a ready made program, when someone
   asks.

Each step ends with Milos's trial.

## Open questions

1. The budgets, 150 ms soft and 2 s hard for rows, 5 minutes idle, 512 MB, are first guesses, to be
   set from what the step 1 harness measures.
2. Whether every plugin disclaims Olm's permissions, as proposed, or a plugin may ask to share them.
3. How wide a file grant may be before the sheet warns, the home folder for one, decided with the
   first plugin that asks for it.
