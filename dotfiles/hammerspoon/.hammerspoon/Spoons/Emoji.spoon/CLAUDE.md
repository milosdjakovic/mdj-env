# Emoji.spoon

The decision trail and the important facts for this spoon. Cross cutting material
stays in the hammerspoon `CLAUDE.md`, which links here. The picker checklist and
the spoon lifecycle contract this file refers to live there.

## What it is

Hyper+J opens a filterable emoji picker over the Chooser atom. Typing matches by
name, shortcode, tag, or category, so a keyword like happy or money or a group word
like food finds the glyph without its exact Unicode name. Return, or Hyper+i, inserts
the highlighted glyph into whatever field was focused before the picker opened.

## Why a spoon and not inline

Menu search lives inline in the root because it is only policy over the Chooser atom.
This picker owns something of its own, the vendored emoji dataset plus the matching
and ranking over it, so folding it into the root would bloat the composition root
with a data file and a scoring function that are not wiring. It is a small coordinator
instead, the same call the launcher is, though leaner. It owns no watcher, timer, or
eventtap, so it has no start or stop, matching the lifecycle contract.

## The data is vendored, not fetched at runtime

The picker searches offline and opens instantly, so the emoji set is fetched once by
`regenerate.sh` and committed as `data.json` beside the spoon. Runtime never touches
the network. The source is the GitHub gemoji project, chosen because one well
maintained file already carries, per emoji, the glyph, a human name, the shortcode
aliases, freeform tags, and a category, which is exactly the material a keyword match
needs. Rerun `regenerate.sh` to refresh the set, for example when new Unicode emoji
land, and commit the new `data.json`.

Each entry is reduced to four fields. `e` is the glyph, `n` is the display name, `a`
is the shortcode aliases shown as the row subtitle, and `k` is a lowercased haystack
that folds the name, the aliases, the tags, and the category into one string. Folding
the category in is deliberate, it is what lets a group word surface a whole group,
food or animal or flag, without an exact name. The reduction and the lowercasing
happen once in the generator, so the runtime match is a plain substring scan with no
per keystroke normalization.

## The match

An empty field lists a leading slice in upstream order, which is grouped and roughly
common first, so it browses. A query is split into whitespace tokens and an entry is
kept only when every token appears in its haystack, so two words narrow with AND
rather than widen. Kept entries are then ranked, an exact alias or exact name first,
then a name that starts with the query, then the count of tokens found, with ties
keeping the upstream order. The scan runs over the whole set on each keystroke, which
is fast enough at this size that no index is needed, unlike the launcher whose app
scan is the expensive part.

The visible list is capped at a small maximum, both for an empty field and a query.
The cap bounds only the display, the match still runs over the whole set, so any
glyph stays findable by typing, and nobody scrolls past a few hundred rows to find an
emoji rather than typing a better word. The cap also bounds how many icons a single
open has to render, which is the reason it matters here rather than being cosmetic.

## Icons

The glyph is the row icon, not text in the title, so a row reads like an app row in
the launcher with a large glyph on the left and the name beside it. hs.chooser has no
emoji rendering, so each glyph is drawn once through one reused canvas into an
hs.image and cached, the same idea as the launcher's glyph icons but sharing a single
canvas rather than making one per glyph, since at this scale a canvas per glyph is the
whole cost. A glyph is rendered at most once ever, and the cap above keeps any one
open from rendering more than a bounded batch.

Even one reused canvas is too slow to render the whole set at once, so the empty state
icons are warmed in the background right after configure, in small batches on a self
stopping timer, and the cost is paid before the first open rather than during it. An
open before the warm finishes, or a typed query that reaches glyphs outside the warmed
slice, renders those on demand and caches them, so correctness never depends on the
warm having completed, only the smoothness of the first open does.

Loading uses `hs.json.read` on the committed file rather than a Lua table literal, so
the generator never has to escape names into Lua strings, and a broken or missing
file degrades to an empty list rather than a load error.

## Rows are data, never functions

Each row carries only the glyph string as its item, which the Chooser serialises and
hands back to onSelect, so no function is ever placed on a row, the same rule the
launcher and menu search follow. The effect of a pick is injected as onInsert, so the
spoon never learns what a pick does. The root wires onInsert to type the glyph through
`hs.eventtap.keyStrokes`, deferred a moment so it runs after the chooser tears down
and macOS restores focus to the field that was frontmost before the picker opened.
Typing rather than copying to the clipboard was the choice, so a pick lands where the
cursor is and the clipboard is left untouched.

## Picker integration

It follows the picker checklist in the hammerspoon `CLAUDE.md` like the other list
tools. It exposes a dot called navigation adapter through `surface()`, which the root
drops into the shared `choosers` list, and the `emojiOpen` predicate reads
`isShowing()` directly. It has an `emoji` context block giving it the shared j, k, and
i navigation with x to close, the menu search shape, because the open key j is itself
the move down key inside so it cannot double as the close the way the launcher's Space
does. Escape closes natively. Like the other native choosers it docks the deferred
shortcut panel through the three chooser callbacks.

## What it does not do

It keeps no recency or frequency memory, so a picked glyph does not float to the top
next time. The launcher's recency timeline is the model to follow if that is wanted
later, a small persisted list keyed by glyph, promoted on select. It also inserts one
glyph per name, it does not offer skin tone variants, since the gemoji base set is one
glyph per name.
