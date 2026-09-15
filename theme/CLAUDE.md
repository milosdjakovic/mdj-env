# Theme

One palette, declared here, painted into every tool's own format by a generator that lives
with the tool. Change a colour in one file and run one command, and Ghostty, Neovim and
everything that joins later follow. A fresh machine needs to generate nothing, because every
generated file is committed and stow puts it where the tool reads it.

Read this file before adding or changing a colour anywhere under `dotfiles`, and before adding
a tool that has a theme. A hex value written into a tool's config by hand is the drift this
directory exists to end, and `src/check-theme.sh` reports it.

## The three layers, and which one knows what

**The palette knows nobody.** `palettes/aura.toml` holds plain colours by name under
`[colors.dark]` and `[colors.light]`, and a `[roles]` table that says which colour answers
each role in `VOCABULARY`. It names no tool, no terminal slot, and no file format. A second
palette is another file of the same shape.

**A map knows one tool's vocabulary.** `dotfiles/<pkg>/theme-map` lists the tool's own keys,
Ghostty's `palette4` or Neovim's `purple_faded`, each pointing at a role. Only a role, never a
colour name and never a hex, so a palette that answers the vocabulary can be dropped in and the
map stays true. A key under `[dark]` or `[light]` answers only that half, which is how Ghostty
says ANSI black is the page on one half and the ink on the other.

**An emitter knows one tool's file syntax.** `dotfiles/<pkg>/theme-emit` is handed the map
already resolved, one file per half of `key TAB hex` lines, and writes the tool's file. It never
sees a role, a colour name, or the palette. `--list` prints the files it owns, relative to the
package root, which is how the checker knows what to snapshot.

`src/check-theme.sh` is the composition root. It reads `active.toml`, resolves every role for
each half, finds every emitter by name rather than by knowing any tool, resolves each map, and
runs each emitter. A file that came out different from what is on disk is reported as stale and
regenerated, the same way a stale `DEPENDENCIES` is, so the person reviews it and commits it.
`--show` prints what every role resolved to and stops.

## The vocabulary is the contract

`VOCABULARY` lists every role, its policy, and what it is for. A palette must answer every
`required` role. A map may name only roles that exist here. The ranking words, `primary`
through `senary`, are Aura's own, its published table calls `accent1` the Primary colour and
counts up, and they are kept rather than replaced with meanings like error or success that a
palette never promised.

Adding a role means adding it here with a policy and a sentence, and answering it in every
palette. Never in one palette only, since the next palette would then fail the first map that
used it.

## Rules over colours, and alpha

A role is answered by a colour name or by a rule over colour names, and the rules are the
reason the palette has one purple rather than three. Aura publishes a selection tint as
`accent20`, which is a dark purple at 50% alpha, and `accent38`, the same thing already
composited onto the page. Nothing here can blend a terminal cell, so the palette carries
neither and says `selection = { color = "purple", alpha = 0.14 }` instead, which is purple at
fourteen percent over the page, four units of green from Aura's own `accent38`.

`alpha` is always over that half's `background`, so `background` has to resolve before any role
that uses it, which is why it sits where it does in the vocabulary. `mix = ["a", "b"]` with
`amount` blends toward `b`. `darken` and `lighten` are the same blend toward black and white.
The arithmetic is one line, `alpha × top + (1 − alpha) × under`, and compositing and mixing are
that same line, which is why the checker has one function for all of it.

`[roles.light]` and `[roles.dark]` override a role for one half. The light ramp spans less than
the dark one, so a fraction that reads right on the dark half reads too faint on the light one,
and every role that differs says why beside its value.

## active.toml, and what mode costs

```toml
mode  = "system"   # system | dark | light
dark  = "aura"
light = "aura"
```

A half is the unit rather than a theme, so `dark` and `light` may name different palettes.
`mode` is resolved when the files are generated and reaches no tool. On `system` each half
takes its own palette. On `dark` both halves are written from the dark palette, so every tool
keeps asking the terminal or macOS which half it is on and both answers look the same. No tool
learns the word, no watcher exists, and holding a half adds no dependency anywhere. That is also
why the generated Ghostty files are `mdj-dark` and `mdj-light`, named for the half they fill,
so the `theme` line in Ghostty's config never changes and a light slot holding a dark palette is
not a file lying about its name.

## The subset of TOML the reader accepts

The checker reads these files with awk and nothing else, because the system Python on a fresh
Mac is 3.9 and cannot read TOML, and a palette that needed a Homebrew tool to be checked would
be the one thing on the machine that could not be checked before setup had run. So the format
is a subset, and the reader refuses a line outside it with its line number rather than guessing.

Sections as `[name]` or `[name.sub]`. A key is letters, digits, underscore, dash or dot. A
value is a quoted string, a number, a bare word, or one inline table `{ k = v, k = v }` whose
values are quoted strings, numbers, or an array of quoted strings. A comment is a hash at the
start of a line or after whitespace, and a hash inside quotes is not one, which matters because
every colour is a quoted string starting with one. Multi line tables, nested tables, dotted keys,
and everything else TOML allows are outside the subset.

## Adding a tool

1. Find out how the tool takes colour, a config file, an include, or an environment variable,
   and write it in the map's header. lf, for example, reads `LF_COLORS` from the environment
   and has no colour file, so its emitter would write a small file the shell sources.
2. Write `dotfiles/<pkg>/theme-map`, one `their_key = role` per line, with `[dark]` and
   `[light]` sections only where a key differs by half. Never a colour name, never a hex.
3. If the tool needs a colour no role names, add the role to `VOCABULARY` and answer it in every
   palette, with the reason.
4. Write `dotfiles/<pkg>/theme-emit`. It takes `--list` and prints the files it owns, or takes
   three arguments, the resolved dark map, the resolved light map, and the mode, and writes its
   files with `Generated by theme-emit` somewhere in each, at the top of a file it writes
   whole and at the region of a file it owns only in part. Exit 2 if it cannot run on this
   machine, any other nonzero if what it was given is wrong. Ghostty's is the settled example
   for a file of `key = value` lines, Neovim's for a file that is code, and herdr's for a tool
   with no include, where the emitter rewrites one span of a hand written config in place and
   copies every other byte through.
5. Add both to that package's `.stow-local-ignore`, they are repo only.
6. Run `./src/check-theme.sh`, review the generated file it names, and commit it.
7. Put the tool's reload step in that package's own `CLAUDE.md`.

## Adding a palette

Copy `palettes/aura.toml` to a new name, fill both `[colors]` halves with the theme's published
values, answer every required role under `[roles]`, and name it in `active.toml`. The checker
says which role is unanswered or which colour a role points at that does not exist.

## Changing a colour, and reloading

Edit the palette or the map, run `./src/check-theme.sh`, commit what it regenerated. Then
reload what is running. tmux with `tmux source-file ~/.tmux.conf`. Ghostty with its own
`Cmd+Shift+,`, which nothing outside Ghostty can send reliably, and once Ghostty repaints every
program drawing in palette slots follows. Neovim re-sources its colorscheme on the next
`background` change or restart.

## What is painted from here today, and what is not yet

Ghostty, both halves, sixteen slots and the six specials. Neovim, the twelve slots of
`lua/aura/palette.lua`. herdr, its eighteen tokens in both `[theme.custom.*]` tables, and the
three roles `highlight`, `subtext` and `fill` joined the vocabulary for it. iris, the four
keys of its selected row, the rest being slots. fzf, tmux and the Claude statusline, entirely
through slots, since Ghostty paints all 256 and its map declares 16 to 19 for the bar under a
current row, the secondary grey, the quiet rule and the page, so none of the three has a map
of its own. Nothing under `dotfiles` that is stowed carries its own copy any more. kitty and
wezterm are not stowed and still do.
