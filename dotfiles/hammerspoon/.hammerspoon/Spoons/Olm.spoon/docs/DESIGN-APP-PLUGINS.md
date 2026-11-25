# External plugins, a process each, run by Olm.app

Written on 2026-11-20, asked for by Milos once the resting point was called reached. It fills in
the third kind of source `docs/DESIGN-APP.md` names under The source, "an extension host, which runs
extensions someone else wrote in a process of its own", and it answers open question 3 of
`docs/PLAN-STANDALONE.md`, what extensions are written in. Milos said go on 2026-11-20, and step 1
is built, see As built.

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
| `open` | opens an http or https link, in the browser or profile Olm listed by that id, or in Olm's own choice |
| `store` | reads and writes a small JSON store of its own under `~/.olm/plugins/<id>/data/` |

**A plugin says what to open and Olm decides how,** decided by Milos on 2026-11-25. Whatever Olm starts
runs outside the plugin's sandbox, so `open` takes no application, no path and no argument, and refuses
a file, which can be a program, and every scheme but http and https. It is answered only within 5 s of
a row chosen or an action run in the plugin's list, one link for each, since a link carries data out of
a plugin with no network. A file waits for an ability limited to declared paths, and another app's
scheme for a plugin that declares it and an install page that shows it. `copy` and `notify` need only
the manifest's `needs`.

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
   that has not answered a cancelled request within 1 s more is taken as stuck and killed. A `ping`
   was planned instead and dropped as built, since a plugin answering pings on one thread while
   another spins answers them happily.
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
   whose memory passes 512 MB, read with `proc_pid_rusage` every second, is killed and said, and
   so is one that keeps more than 90 percent of a core busy for 10 s, a spin outside any request
   that no limit on a request can see.
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

**Switching a plugin on asks once.** When a plugin is installed or switched on, Olm shows one page,
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
Accessibility grant. So the runner starts every plugin disclaiming Olm's grants, and a plugin never
holds a permission of macOS's at all. What one needs, Olm does for it, see the next section, which
replaced on 2026-11-24 the first draft's plugin asking for a permission as itself. Disclaiming goes
through the spawn flag macOS's own Terminal and Xcode use.

**What it is not.** A plugin allowed to run `tmux` can do whatever `tmux` can, so the sandbox narrows
a plugin to what it said it needs and cannot make a powerful tool harmless. Installing a plugin is
still trusting its author with that list, and the page shows the list so the trust is informed.

**Two interfaces it stands on are not Apple's public ones.** The sandbox's rule language and the
command that starts a program inside it are deprecated, though Chrome and Claude Code depend on them
and they work on current macOS, and the disclaim flag is private. Either can change with a macOS
release, so step 1 proves both on this machine, with caffeinate and mullvad, before anything leans on
them, and the runner refuses to start plugins unsandboxed when they fail, saying why.

## macOS's permissions, held by Olm and lent by ability

Planned on 2026-11-24 with Milos, nothing built. It answers open question 2.

**Olm holds every permission and a plugin holds none.** Olm.app is the one program macOS knows:
Accessibility, Input Monitoring, Full Disk Access, Screen Recording, a folder, and the right to
control another app, which macOS calls Automation. A plugin runs disclaimed and sandboxed, so if it
reaches for something protected itself, macOS holds the plugin responsible and refuses it. What a
plugin needs that a permission guards, it asks Olm for as an **ability**, a named action from a list
Olm keeps, and Olm does it with its own permission and hands back the result. This is how a browser
treats its extensions, the browser holding the camera and an extension asking the browser.

Olm does an ability only when three things hold, each checked on every request: the plugin declared
it, the person allows it for that plugin, and Olm has the permission it rides on. Every use and every
refusal is written to the plugin's log, and the last use is shown beside it.

Why not the others. A plugin inheriting Olm's permissions gives every plugin all of them, and macOS's
question then names Olm and never the plugin asking. A plugin holding its own permissions puts each
plugin in each list of System Settings by hand, Full Disk Access having no question at all, and loses
them when a plugin built from source is signed afresh.

**Declared in the manifest, in plain words.**

```lua
abilities = {
  { use = "browserProfiles", why = "List each browser's profiles so a link can open in one" },
  { use = "receiveLinks",    why = "Be asked where each clicked link opens" },
},
```

Each ability also carries what stops working without it, as a need's `breaks` does, so a plugin
keeps working with less when one is blocked.

**The abilities, Olm's list.** An ability is an action rather than a permission, so Olm can narrow it,
`readFiles` to the paths the plugin declared and shows, and a plugin can never simply have Full Disk
Access.

| Ability | What Olm does | The permission it rides on |
|---|---|---|
| `browserProfiles` | lists the browsers and their profiles | Full Disk Access |
| `moveWindows` | moves or sizes another app's window | Accessibility |
| `hearKeys` | passes key presses on | Input Monitoring |
| `captureScreen` | takes a picture of the screen | Screen Recording |
| `controlApp:<app>` | sends that app commands | Automation, asked once per app |
| `readFiles:<path>` | reads files under a declared path | that folder's, or Full Disk Access |
| `readClipboard` | reads the pasteboard | none of macOS's, gated by Olm since it is private |
| `receiveLinks` | hands it each link while Olm is the default browser | the default browser |

**What the person sees.**

- **Switching a plugin on** allows every ability it declares and asks nothing, decided by Milos on
  2026-11-24. Its abilities are listed on its page and under each permission, and any one is turned
  off there afterwards. An update that adds an ability allows it the same way and says so once.
- **An ability not on Olm's list is refused,** decided by Milos on 2026-11-24. The plugin keeps
  working without it, as its `breaks` says, its page names the refused ability, and a plugin never
  holds a permission of macOS's as itself. Olm adding the ability to its list is the only way in.
- **The Permissions page** keeps one row per permission, Olm's own state from macOS and Open
  Settings, with a chevron and how many plugins use it. Open, it is an accordion of the plugins using
  that permission, each with its icon and name, its reason, when it last used it and a switch. Off
  refuses that plugin that permission and no other. Olm's own uses are listed in it too, greyed and
  with no switch, so the list is whole. The permission row itself has no switch, since only macOS
  can take Olm's permission away. A permission no plugin uses has no chevron and reads no plugins.
  While Olm lacks a permission its plugins' switches keep what was set, greyed, and the row says
  what to fix. Collapsed at first, several may be open at once, decided by Milos on 2026-11-24, and
  a search for a plugin's name opens the accordion holding it.
- **Each plugin's switch under a permission turns that permission off for that plugin alone,** while
  Olm keeps it and every other plugin keeps using it, decided by Milos on 2026-11-24. It is possible
  because the plugin never holds the permission, it asks Olm, and Olm reads the switch before every
  use, so off applies at once and macOS is never involved. There is no switch on the permission row
  blocking it for every plugin, since each plugin has its own and macOS's own switch in System
  Settings already takes the permission from Olm and so from all of them.
- **Automation is switched one app at a time,** decided by Milos on 2026-11-24, since macOS grants
  it per app. Under Automation each plugin lists the apps it declared, `controlApp:<app>`, each with
  its own switch, so Chrome can be allowed and Safari not.

```
Permissions                                   6 of 6 allowed
┌──────────────────────────────────────────────────────────────┐
│ ▸ Accessibility        Olm: Allowed   3 plugins  [Open Settings]
├──────────────────────────────────────────────────────────────┤
│ ▾ Full Disk Access     Olm: Allowed   1 plugin   [Open Settings]
│     Browser Switcher                                     [ ● ]
│        List each browser's profiles · used 2 min ago
├──────────────────────────────────────────────────────────────┤
├──────────────────────────────────────────────────────────────┤
│ ▾ Automation           Olm: 2 apps    1 plugin   [Open Settings]
│     Browser Tabs
│        Google Chrome · read the open tabs                [ ● ]
│        Safari · read the open tabs                       [ ○ ]
├──────────────────────────────────────────────────────────────┤
│ ▸ Input Monitoring     Olm: Allowed   no plugins [Open Settings]
└──────────────────────────────────────────────────────────────┘
```

- **A plugin's own page** opens with a Permissions group, one row per ability, what it does, the
  permission it rides on, whether Olm has it with the way to fix it, when it was last used, and the
  same switch. Both places are one setting, saved under the plugin in `~/.olm/state/settings.json`,
  so it travels with an export.
- **The accordion is a new part,** `DisclosureRow`, added to Parts in `docs/DESIGN-APP-SETTINGS.md`
  when it is built. A page, the gear and Back, stays the way to a row's own settings, and an accordion
  is for a short list belonging to a row, switched in place. Opening one moves the rows below, which
  the person did, and the chevron's room is kept on every row so the names line up.

**While the plugins live in Hammerspoon.** A Lua plugin runs inside Hammerspoon with Hammerspoon's
permissions, so nothing it does can be refused by Olm. The manifest field and both views can still be
built first, true as information, and a switch refuses only an ability Olm already performs itself,
Browser Switcher's profiles, which Olm.app reads. Enforcement comes with the runner, an ability then
being a request over the plugin's pipes that the sandbox stops it going around.

**Olm's signature has to hold.** macOS keys a permission to the program's signature. Signed ad hoc
with a requirement naming only the bundle id, which kept the permissions across rebuilds from
2026-11-09, any program signed as `local.olm.Olm` matched it, and signing that way needs no key. So
since 2026-11-24 Olm.app is signed with a certificate made once on the machine, `src/lib/olm-signing.sh`,
in a keychain of Olm's own under `~/.olm/state/signing`, and its requirement names the certificate's
hash too. A grant given before that still names the bundle id alone until it is given again.

**Decided with Milos on 2026-11-24.**

1. A plugin switched on is allowed every ability it declares, and one is turned off later.
2. An ability not on Olm's list is refused, never held by the plugin as itself.
3. Automation is switched per app.
4. Several accordions may be open at once.
5. Each plugin has its own switch under each permission, which turns it off for that plugin alone,
   and the permission row has no switch for all of them.

**The order to build it in, each when Milos says.**

1. The `abilities` field and its check, the accordion on the Permissions page and the group on a
   plugin's page, Browser Switcher declaring `browserProfiles` and `receiveLinks`, its block real
   since Olm reads the profiles.
2. Olm.app signed with a stable certificate, built 2026-11-24.
3. Enforcement in the runner, with the first Swift plugin.

## Hammerspoon until it is gone

While the move runs, the plugins not yet rewritten are still served by Hammerspoon over the bridge,
as they are today. Each external plugin of ours is rewritten in Swift, run beside the Lua one in
shadow where its rows can be compared, then flipped, which switches the Lua plugin off in
`config/plugins.lua`. When the bridge serves nothing, Hammerspoon is switched off, the end of stage 6.

## As built

**Nothing runs before Allow, built 2026-11-25.** Asked by Milos, before the install page.

- **The gate,** `OlmPlugins/PluginGate.swift`. A folder in `~/.olm/plugins` is built, loaded and read
  only when it is Olm's own, the same manifest and sources as the copy in the signed app's
  `Resources/Plugins`, or when the person allowed everything it asks for, its `needs`, its permissions
  and running in the background. Asking for more waits with only what is new. Abilities are not part
  of it, they are allowed with the plugin. A change to the sources alone is not asked about again.
- **The records** are `~/.olm/state/plugin-records.json`, never a setting, so no import reaches them.
  A broken file lets nothing through but Olm's own.
- **Its program is always one Olm built,** from the sources and the kit it has now, known by hash. One
  that came with the folder, or was put in its place, is built again.
- **Refused whole:** a link anywhere but in data and tmp, a folder whose name is not its id, an id Olm
  uses as a word, more than 5000 files or 32 MB of sources.
- **`~/.olm` is kept from every plugin** whatever place it is granted, its own folder given back after,
  since a grant of the home folder reached the records and the signing key.
- A held plugin is a locked row in Plugins saying why. Nothing can allow one until the install page.
  Olm reads the folder at launch only, until then.

**Requests narrowed, built 2026-11-25.** `OlmPlugins/PluginRequests.swift` reads a link and
`RunningPlugin` refuses a request the manifest's `needs` does not name, a bad link and a link nobody
chose, before Olm sees it, each refusal logged. A name in `needs` Olm does not do refuses the
manifest. The host hands a plugin each browser's id in place of its path and arguments, looks the id
up in its own scan, with profiles only while Browser Profiles is on, and serves nothing to a plugin
switched off. A refused link keeps Browser Switcher's list open and says so. `test/olmplugins.sh`
holds each case.

**Step 3 of the permissions plan, Browser Switcher run by Olm.app, built 2026-11-24.** Runner steps 2
and 4 in part, asked by Milos, the install page and the `olm` command left for the next step.

- **`OlmPluginKit`**, `app/PluginKit/OlmPluginKit.swift`, one file bundled with the app and compiled
  into every plugin beside its own sources, so a plugin is its handlers, `open`, `rows`, `choose`,
  `run` and `actions`, and asks Olm with `openLink`, `copy` and `notify`.
- **The app runs them.** `Sources/Olm/Plugins.swift` finds each folder under `~/.olm/plugins`, builds
  one whose sources or the kit are newer than its program, loads it into the runner, and answers what
  it asks: `open` a link or file in a named application, a browser's profile by starting its program
  with the profile, until 2026-11-25 by any path and arguments the plugin sent, `copy`, and `notify`, drawn on Hammerspoon's message toast through the bridge
  until the app has one. Its list opens with what it is opened with, the link, its settings and, for
  a plugin declaring Browser Profiles, the browsers Olm found, their profiles only while it is on.
- **Its bar, actions pane and launcher row** are laid out by the app from `olm-plugin.json`'s
  `surface` and `row`, the leader legend and the shared keys taken from the launcher's share, since
  Hammerspoon writes no share for it. A plugin with no `row` has no launcher row, Browser Switcher's
  dropped by Milos as a row nothing can be done with. `olm://<id>` opens its list too.
- **Its Hyper list keys** reach it through one list context of Hammerspoon's bridge, `olmAppPlugin`,
  which answers for whichever list the app says is up that Hammerspoon does not serve and hands each
  key to the app as a verb, its actions pane kept by `actionsInApp`. Hyper and O did nothing before
  it, reported by Milos.
- **Its settings are the app's,** `~/.olm/state/plugins.json`, decided by Milos on 2026-11-24 so each
  settings file keeps one writer. `OlmSettings/ExternalPlugins.swift` draws its switch, settings and
  abilities on its page in Plugins and under each permission through the same parts, and the window
  sends their changes there rather than to Hammerspoon. Olm's list of abilities is kept in Swift
  beside `lib/abilities.lua` until Hammerspoon goes.
- **Browser Switcher** is `app/Plugins/External/browserswitcher`, sandboxed with no permission of its
  own, `src/setup-olmapp.sh` copying it into `~/.olm/plugins`. The Lua one was switched off, then
  deleted the same day once Milos confirmed this one, and the favourites saved for it were taken over once. Checked by driving the
  built program over its pipes, and `test/olmplugins.sh` still holds every case.
- **Not yet.** Installing a plugin by dropping it on Olm Settings and asking for its sandbox
  permissions, offering a block with Allow, the `olm` command, and the plugin's own log in the window.

**Step 2, Olm.app signed with this Mac's certificate, built 2026-11-24.** `src/setup-olmapp.sh` makes
a self signed code signing certificate once, with the system's `openssl`, into
`~/.olm/state/signing/olm.keychain-db`, a keychain macOS does not search, its random password in a
file beside it readable by this account alone, so no build asks the person anything. `app/build.sh`
unlocks it and signs, the requirement becoming the bundle id and the certificate's hash, and stops
rather than signing ad hoc when it does not unlock, since codesign asks for a locked keychain's
password in a dialog and an ad hoc build would match no grant given to the certificate. Seen live:
Full Disk Access held across the switch and across a second rebuild, which reused the certificate.
A build into a folder of its own, `test/olmapp.sh`, is still ad hoc.

**Abilities, step 1 of the permissions plan, built 2026-11-24.**

- **The list and the check.** `lib/abilities.lua` holds Olm's abilities and the permission each
  rides on, and reads a manifest's `abilities`, an unknown one refused with a console line and kept
  as refused. The root declares each as a switch, `ability.<identity>.<use>`, through
  `lib/settings.lua`'s `abilities`, on until turned off, the off ones kept in `abilities.off`.
  `test/settings.lua` pins both.
- **Refused where Olm performs it.** Receive Links is asked before every link, so off sends the
  next one to Safari, and a plugin providing links that declares no `receiveLinks` gets none.
  Olm.app reads the browsers' profiles only while a plugin has Browser Profiles on, so off lists
  each browser once. Every other ability is listed and switched, and is enforced with the runner.
- **The Permissions page** folds open under each permission, `DisclosureRow`, with Olm's own use
  greyed first and each plugin's switch under it, `AbilityRow`. Default Browser joined the list,
  since Receive Links rides on it. A permission a plugin's ability names that Olm does not list,
  Automation today, is shown after Olm's with nothing held.
- **A plugin's page** has a Permissions group under its settings with the same switches, and the
  gear in Plugins is in the accent while one is off.
- **Not built yet.** When each was last used, and a search for a plugin's name opening the
  permission holding it.

**Step 1, the runner, the sandbox and a test plugin, built 2026-11-20.** `app/Sources/OlmPlugins`.

- **Proved first, on macOS 27.0.1.** A probe started a child through `sandbox-exec` with rules
  written for it. Declared, caffeinate ran and `mullvad status` reached its daemon. Undeclared,
  `/bin/ls`, `~/.zshrc`, `~/Documents` and the internet were each refused, and its own data folder
  was written. The disclaim flag, `responsibility_spawnattrs_setdisclaim`, found by `dlsym`, is what
  keeps a plugin from Olm's grants: a child started without it read the Accessibility grant of the
  program that started it as its own, and with it read none. Every refusal is logged by macOS with
  the process's name and pid, which is what a block offered with Allow will read, step 3.
- **`RunningPlugin`**, an actor per plugin, starts it on the first request, says hello, holds every
  request to its limit, cancels with `$/cancelRequest` and kills after the grace, reads memory and
  processor every second, stops it after the idle time and counts each ending. **`PluginRunner`**
  holds them and switches a plugin off after three failures in ten minutes. **`PluginProcess`** is the
  spawn, `posix_spawn` of `sandbox-exec` with only the plugin's stdin, stdout and stderr open in it,
  a process group of its own so a kill takes every program it started, utility or background
  quality of service and the disclaim, and its writes go out on a queue of their own so a plugin
  that stops reading never holds the runner.
- **`ExternalSource`** opens the plugin's level and is then the bridge's own `BridgedLevel` over a
  different peer, `LevelPeer`, the requests, notifications and levels both the bridge and a plugin
  answer, so a plugin's rows, effects and actions read exactly as Hammerspoon's do. A plugin that is
  off, cannot start or stopped says why as its list's status. A timed out answer keeps the rows shown.
- **The rules** start from `(deny default)` and macOS's own `bsd.sb`, its folder read, its `data`
  and `tmp` folders written, its own program run, and each declared program resolved on a fixed
  path, never the person's PATH, and handed to the plugin in `hello` under the name it declared. A
  program inside an application bundle may read that bundle. Every path goes through `realpath`,
  since Foundation's own resolving strips `/private` and the rules then match nothing, which is how
  mullvad was first refused its socket. Two lookups Foundation makes on every launch are refused
  without a log line, so the log holds only what a plugin really tried.
- **The manifest** is `olm-plugin.json`, its id, title, version, protocol, `background` and
  `permissions` with `programs`, `files`, `network` and `services` as `mach`, `socket` or `iokit`.
- **The check** is `test/olmplugins.sh`, run on its own since it takes about eighty seconds. It
  builds `app/Plugins/External/misbehave` and checks 40 things: the sandbox's answers, an answer in
  a second kept, a ten second request cancelled and the polite plugin left running, one that hangs
  or spins killed about 3.1 s after it was asked, one burning a core in the background killed in 5 s,
  one leaking killed at 512 MB in about 2 s, a crash started again on the next request, a message
  past 8 MiB stopping it, idling not counted as a failure, three crashes switching it off and its
  list saying so. Through all of it the main thread stayed within 5 ms at p99, and its worst single
  delays, 9 to 18 ms, came in any case including the baseline with no plugin running, which is the
  machine rather than the runner. No line of the runner runs on the main thread.
- **Left for later steps.** Reading the sandbox's refusals and offering Allow is step 3, the
  requests a plugin makes of Olm, `notify`, `redraw`, `copy`, `paste`, `open` and `store`, come with
  step 4, and nothing in Olm.app loads a plugin yet.

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
   page of what it asks for, builds it and lists it with its state, its grants, its log and its
   switch, and a block in use is offered with Allow.
4. **The first plugin of ours.** Browser Switcher, built 2026-11-24, Milos's choice over keep awake,
   which was first planned here: keep awake, small and pure, rewritten in Swift as an external
   plugin, run in shadow beside the Lua one and flipped. Then the others, one per step.
5. **The skill,** written once steps 2 and 3 have settled the commands.
6. **Other languages,** JavaScript through JavaScriptCore and a ready made program, when someone
   asks.

Each step ends with Milos's trial.

## Open questions

1. The budgets, 150 ms soft and 2 s hard for rows, 5 minutes idle, 512 MB, are first guesses, to be
   set from what the step 1 harness measures.
2. Whether every plugin disclaims Olm's permissions, as proposed, or a plugin may ask to share them.
   Answered on 2026-11-24: every plugin disclaims, Olm holds the permissions and lends them by
   ability, see macOS's permissions, held by Olm and lent by ability.
3. How wide a file grant may be before the page warns, the home folder for one, decided with the
   first plugin that asks for it.
