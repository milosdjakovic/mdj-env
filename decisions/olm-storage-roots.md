# Olm storage roots

Status. Everything Olm writes on this machine lives under `~/.olm`. A plugin's own files sit in
`data/` for what is durable and `cache/` for what is regenerable, one directory per plugin, reached
only through `lib/storage.lua`, and Olm.app and the bridge to it keep `app/`, `run/`, `log/` and
`state/` beside them.

## Now

`config/settings.lua` names the two plugin roots, `olmRoot = "~/.olm/data"` and
`cacheRoot = "~/.olm/cache"`, and `lib/storage.lua` hands each plugin its own directory under
them through `dataDir(name)` and `cacheDir(name)`. A plugin declares `needs.lib.storage` and
asks, and no plugin names a directory under HOME by itself. Durable today, the clipboard
history with its frozen files and thumbnails, the workspaces layouts, and the speed test runs.
Regenerable, the menu search snapshots, the file search previews and hidden files index, the four
compiled Swift helpers, the eyedropper sampler, the browser permission probe, the Quick Look
viewer and the file index helper, and the swift chooser's compiled library in
`~/.olm/cache/swiftchooser`, which `lib/chooser/providers/swift` builds and loads. The only store
left inside the config tree is DisplayProfiles, because a display arrangement is configuration a
person edits and commits.

Olm.app and the bridge to it are core rather than plugins and write beside those roots by fixed
paths. `src/setup-olmapp.sh` builds the app into `/Applications/Olm.app`, since 2026-11-23, its build scratch in
`~/.olm/cache/olmapp-package`. `host/bridge` writes the settings the app reads into `~/.olm/run`,
where the app's socket `bridge.sock` also lives, and keeps the pictures it hands the app in
`~/.olm/cache/bridge`. The app appends its shadow comparisons to `~/.olm/log/shadow-<tool>.jsonl`
and keeps each of its plugins' own state in `~/.olm/state/<plugin>`.

## Rejected

- **`~/Olm` as the durable root.** 2026-08-05, 1e03ca0, until 2026-09-16, the value
  `config/settings.lua` carried from the day the roots were declared. Visible on purpose, on the argument that a
  directory whose deletion loses something should be seen. Milos wants it hidden, and a
  visible folder in the home directory beside Documents and Downloads reads as a place to put
  things rather than a place a program keeps them.
- **`~/.cache/hammerspoon` as the cache root.** Same span. It is the XDG habit and it is
  shared with every other tool on the machine, claude, gh, nvim, the p10k dumps, so there is
  no one place to look for what Olm has written and nothing says the two roots belong to the
  same program.
- **Data inside `~/.hammerspoon`, an `olm/cache` and `olm/persist` beside the config.**
  Considered 2026-09-16 at Milos's suggestion and turned down. That directory is the config
  tree, watched by the pathwatcher for a reload on any change, so every cache write would need
  an ignore pattern and any miss reloads the whole config, which is the exact bug the
  workspaces store hit once already. It is also the stow target for this repository's
  hammerspoon package, and a hundred and seventy megabytes of clipboard images do not belong
  beside tracked configuration however carefully they are ignored.
- **Per plugin directories under `~/Library/Caches`, `Hammerspoon-Eyedropper` and friends.**
  From each helper's first build until 2026-09-16. The macOS convention, and each one was a
  path typed into the plugin that owned it, three of them plus `mdj-hammerspoon` for the hidden
  index and `hs-clipboard` under `~/.cache` for the clipboard, five names in five files that
  the storage lib existed to replace and had not yet reached.

## Log

### 2026-08-05 19:50

1e03ca0. `lib/storage.lua` lands with two roots, `~/Olm` and `~/.cache/hammerspoon`, and no
consumer yet. The menu search cache is the first, later, and the clipboard and the compiled
helpers keep the paths they already had.

### 2026-09-16 00:35

Purging the workspaces store from git raised the question of where a plugin's data goes at
all, and the answer was five different places. Milos asks for one hidden root and for the
existing data to be moved. `~/.olm/data` and `~/.olm/cache` are chosen over a directory inside
`~/.hammerspoon` for the reasons under Rejected, five plugins declare the storage lib and stop
naming a path, the dry gate configures the lib with throwaway roots so a plugin asking for its
directory at configure still reads as checked, and the files on disk are moved by hand with the
clipboard history's absolute paths rewritten to the new prefix.

### 2026-09-16 01:05

Milos asked why `~/.hammerspoon/olm` was turned down and `~/.olm` taken instead, and agreed
with the two reasons once stated, the pathwatcher and the stow target. The one honest caveat
is that the cost of the rejected layout is avoidable rather than fundamental, an ignore
pattern in `root/compose.lua` would make it work, so if the one directory feel ever outweighs
the two reasons it is two lines in `config/settings.lua` plus that pattern and a second move
of the files. Settled as `~/.olm` with that understood.

### 2026-11-16 15:59

Status and Now were out of date. They said everything Olm writes is reached through
`lib/storage.lua` under `data/` and `cache/`, and counted three compiled Swift helpers. Olm.app and
the bridge now write `~/.olm/app`, `~/.olm/run`, `~/.olm/log` and `~/.olm/state` by fixed paths, in
`src/setup-olmapp.sh`, `host/bridge/init.lua` and the app's own sources, and the compiled code in
the cache is four helpers, the file index helper being the one missed, plus the swift chooser's
library in `~/.olm/cache/swiftchooser`. Found by an audit against the repo on 2026-11-16.

### 2026-11-23 15:30

Olm.app moved out of `~/.olm/app` into `/Applications/Olm.app`, asked by Milos. The 2026-11-07
reason for keeping it beside Olm's data, that it is a part of Olm rather than an app a person
opens, no longer holds now that it has Olm Settings and takes over from Hammerspoon. The data
roots are unchanged, only the bundle moved.
