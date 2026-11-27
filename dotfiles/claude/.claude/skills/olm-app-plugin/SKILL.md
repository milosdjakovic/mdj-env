---
name: olm-app-plugin
description: Build, change, test or review an external plugin for Olm.app, a folder with olm-plugin.json and Swift sources written against OlmPluginKit, run sandboxed by Olm.app and installed into ~/.olm/plugins. Use for any work on olm-plugin.json, OlmPluginKit, test.json, or the `olm plugin` command (new, test, dev, install, remove, list, log), in any folder. Not for the Lua plugins inside the Olm Hammerspoon spoon, which the olm-plugin skill of the mdj-env repository covers.
---

# Olm.app plugins

An external plugin is a folder Olm.app builds from source and runs as its own process, in a sandbox
written from its manifest, speaking to Olm over stdin and stdout. Olm draws everything. A plugin
answers rows and says what choosing one does, and asks Olm for what its sandbox keeps from it.
Nothing of it needs to live in any repository.

This skill holds the judgment. The truth lives on disk, and where the two disagree the disk wins and
the disagreement is reported, so it can be fixed here:

- **The kit,** `/Applications/Olm.app/Contents/Resources/OlmPluginKit.swift`. Every type and handler
  a plugin uses, compiled into each plugin beside its sources. Read it before writing code, never
  write the API from memory.
- **A plugin that ships,** `/Applications/Olm.app/Contents/Resources/Plugins/browserswitcher/`, its
  manifest and `Sources/main.swift`. The worked example of abilities, actions, settings and links.
- **The scaffold,** `olm plugin new ID DIR`, a folder whose `test.json` already passes.
- **The command,** `olm plugin` with no command prints every command and its arguments.

## Never propose a plugin

Build or change one only when the person asked for that plugin. Offering one as an option among
several is proposing it. A job that belongs to a shell, a script or a config file is solved there,
and when it cannot be, say so plainly and let the person decide.

## The work, in order

1. `olm plugin new ID` from the folder that will hold it, or `olm plugin new ID PARENT`. It makes
   `ID/` inside that folder, so never name the plugin's own folder as the second argument. The id is one lowercase word of letters and digits, the folder's name too,
   never one of Olm's own plugins' ids or Olm's words (olm, plugins, settings, log, ability and the
   like), which Olm refuses when it reads the manifest.
2. Read the kit and the example, then write `Sources/*.swift` and the manifest.
3. Write `test.json` for what the plugin promises and run `olm plugin test DIR` until every case
   passes. `olm plugin test DIR -q TEXT` prints the rows for a typed text. It builds the plugin apart,
   runs it through Olm's real runner and sandbox, ranks the rows with Olm's own search as the list
   would, and answers whatever it asks of Olm without doing it. A typed case that fails is a row
   missing a title word or a keyword, never a reason to filter by hand.
4. `olm plugin dev DIR` copies it into `~/.olm/plugins` on every change and prints its log. Olm builds
   it on its next use. A new or changed plugin waits for the person's Allow.
5. Hand it over with numbered steps: what to open, what should show, what could go wrong.

**Allow and Uninstall are the person's clicks.** `olm plugin install` and `olm plugin remove` only open
the page in Olm Settings. Never write `~/.olm/state/plugin-records.json`, never click Allow,
Uninstall or a block's switch through accessibility, and never work around a refusal of one.

## The manifest, olm-plugin.json

Required: `id`, `title`, `protocol` 1, `run: { "swift": "Sources" }`. Also read: `description` (one
line, the plugin's page and its row), `version`, `icon` (an SF Symbol name), `row: { detail,
keywords }` (its launcher row, the detail a few lowercase words saying what it is for), `needs`,
`permissions`, `abilities`, `surface`, `settings`, `background`. A wrong field refuses the whole
manifest with the reason, so read what `olm plugin test` or the log says.

- **`needs`,** what Olm does for it: `open` (a link, `plugin.openLink`), `copy`, `notify`. Anything
  else is refused. `log` is always allowed.
- **`permissions`,** the sandbox, and the least that works. `programs` (a bare name looked up in the
  system folders and Homebrew's, or an absolute path), `files` (`{ "path": "~/x", "access": "read" |
  "write" }`, starting `~/` or `/`, no `..`), `network` (`local` or `internet`), `services`
  (`{ "mach": name }`, `{ "socket": path }`, `{ "iokit": class }`) for what a program it runs needs.
  A program the plugin runs is inside the same sandbox. Its own data folder, `plugin.data`, and its
  temporary folder are always its own, and `~/.olm` never is.
- **`abilities`,** what Olm does with a permission only Olm holds, each `{ "use", "why", "breaks" }`,
  `breaks` saying what still works without it, since the person can turn each off. The list is Olm's:
  `browserProfiles`, `moveWindows`, `hearKeys`, `captureScreen`, `controlApp:<app>`, `readFiles:<path>`,
  `readClipboard`, `receiveLinks`. Anything else is refused. A plugin never holds a macOS permission.
- **`surface`,** the verbs: `primary` (Return), `secondary` (Command Return, an `action`), and `extra`,
  each a title in Title Case and an SF Symbol `icon`. Each action runs `plugin.run(action, key)`.
- **`settings`,** rows on the plugin's page in Olm Settings, each `key`, `kind`, `title`, `detail`,
  `keywords`, and `choices` and `default` for a choice. The values arrive in `open`'s context under
  `settings`. A plugin never builds a settings list of its own.
- **`background`,** only for a watcher that must run while nothing uses it. Otherwise a plugin is
  started on use and stopped after five idle minutes.

Every word a person reads is plain: no key named in any text, verbs and names in Title Case, a row's
subtitle on one line, a placeholder naming the list.

## The code

The kit's header shows the shape. `open` gets the context (`settings`, `browsers` with Browser
Profiles, `link` with Receive Links) and answers an `OlmLevel`. `rows` answers `OlmRow`s for the
typed text, `choose` and `run` answer `OlmEffect`s (`hide`, `redraw`, `placeholder`), and
`plugin.start()` comes last.

- **Search is Olm's.** Leave `searched` true and hand every row on every call. Olm ranks with its
  shared search, and `olm plugin test` ranks the same way, so filter by the typed text only where the
  text is not a search, a value being typed, with `searched` false. Words a row should be found by
  without showing go in `keywords`. A word matches inside another word only from three letters on.
- **Every row has a stable `key`,** unique in the list, so the highlight stays on its row across a redraw.
- **A row that only says something,** a status or why a list is empty, is `inert: true`. A row with no
  icon wears Olm's own, so name one only when it means something.
- **Budgets.** Rows answer within 150 ms or the list shows its working state, a request is cancelled
  at 2 s and a plugin that ignores the cancel for a second more is killed. Past 512 MB or a busy core
  for 10 s it is killed, and three failures in ten minutes switch it off. Slow work goes off the
  handler and ends in `.redraw`.
- **State a person keeps** lives in `plugin.data`. `plugin.usage` orders by most or last used.
- **`plugin.log`** writes the plugin's own lines to its log. Never log a secret or a whole link.

## When the sandbox blocks it

A refusal shows in the plugin's log and in `olm plugin dev`, and on its page in Olm Settings with a
switch the person may turn on. Do not answer a block by asking the person to allow it. Fix the
manifest so it declares what it needs, the narrowest path that works, and say what it asks for and
why. Secrets, keychains, browser profiles, Mail, ~/.ssh, ~/.olm, launch agents and anything as wide
as the home folder are never offered.

## Before calling it done

- `olm plugin test DIR` passes every case, including one for a row chosen and what it asked of Olm.
- `olm plugin log ID` shows no refusal and no error after a real use under `olm plugin dev`.
- The manifest asks for nothing the code does not use.
- The person ran it and said so. Their trial is the last gate.
