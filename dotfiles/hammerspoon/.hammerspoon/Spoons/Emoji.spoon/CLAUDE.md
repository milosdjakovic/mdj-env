# Emoji.spoon

The decision trail and the important facts for this spoon. Cross cutting material
stays in the hammerspoon `CLAUDE.md`, which links here. The picker checklist and
the spoon lifecycle contract this file refers to live there.

## What it is

Hyper+J opens a filterable picker over the Chooser atom, carrying both emoji and a
generous slice of native Unicode symbols, currency and arrows and math and the Mac
modifier keys and more, the same glyphs the macOS Character Viewer shows. Typing
matches by name, shortcode, tag, or category, so a keyword like happy or money or a
group word like food finds the glyph without its exact Unicode name. Return, or
Hyper+i, inserts the highlighted glyph into whatever field was focused before the
picker opened. Emoji always rank above symbols in the results, so a query lists every
matching emoji first and the plainer glyphs below, never interleaved.

## Why a spoon and not inline

Menu search lives inline in the root because it is only policy over the Chooser atom.
This picker owns something of its own, the vendored emoji dataset plus the matching
and ranking over it, so folding it into the root would bloat the composition root
with a data file and a scoring function that are not wiring. It is a small coordinator
instead, the same call the launcher is, though leaner. It owns no watcher, timer, or
eventtap, so it has no start or stop, matching the lifecycle contract.

## The data is vendored, not fetched at runtime

The picker searches offline and opens instantly, so the set is fetched once by
`regenerate.sh` and committed as `data.json` beside the spoon. Runtime never touches
the network. Two sources feed one flat list. Emoji come from the GitHub gemoji
project, chosen because one well maintained file already carries, per emoji, the
glyph, a human name, the shortcode aliases, freeform tags, and a category, which is
exactly the material a keyword match needs. Symbols come from the official Unicode
Character Database, a slice of the standard blocks the Character Viewer shows.
Rerun `regenerate.sh` to refresh the set, for example when new Unicode glyphs land,
and commit the new `data.json`.

Each entry is reduced to the same shape whichever source it came from, so the spoon
loads one file and never learns which source a row is. `e` is the glyph, `n` is the
display name, `a` is the shortcode aliases or a synonym line shown as the row
subtitle, `k` is a lowercased haystack that folds the name, the aliases or synonyms,
the tags, and the category into one string, and `t` tags the source, `e` for an emoji
and `s` for a symbol, which is the one field the ranking reads to keep emoji above
symbols. Folding the category into `k` is deliberate, it is what lets a group word
surface a whole group, food or animal or flag or arrow, without an exact name. The
reduction and the lowercasing happen once in the generator, so the runtime match is a
plain substring scan with no per keystroke normalization.

### How the symbol slice stays safe and clean

The symbol side of `regenerate.sh` earns its length because raw Unicode is not
directly pickable. Three rules shape it. Only real standalone glyphs are taken, whose
general category is a letter, number, punctuation, or symbol, so combining marks,
invisible format and control characters, and separators are left out, since those
render as nothing or attach to other text. The mass CJK ideograph and Hangul syllable
blocks are excluded, tens of thousands of entries that are not keyword findable and
would only slow the match. And a render filter, `filter-glyphs.lua`, drops anything
that draws as a missing glyph box on this Mac, since the only authority on what the
system fonts can draw is the render itself. It learns the boxes by rendering
unassigned codepoints, which can only be boxes, then rejects any candidate whose image
matches one. That is why regeneration needs Hammerspoon running and why the output
depends on the machine's fonts as well as the upstream revision. A small synonym table
keyed by codepoint adds words the official names lack, so euro finds the euro sign and
command finds the command key though its real name is place of interest sign.

A codepoint can appear in both sources at once, an emoji default glyph like the check
mark or a zodiac sign also sits in a symbol block, which would list the same picture
twice. So after both sources are tagged and merged, the list is deduplicated by glyph
keeping the first occurrence. Emoji lead the list, so the emoji copy always wins and
the redundant symbol copy is dropped.

## The match

An empty field lists a leading slice in upstream order, which is emoji first since
they lead the dataset, grouped and roughly common first, so it browses. A query is
split into whitespace tokens and an entry is kept only when every token appears in its
haystack, so two words narrow with AND rather than widen. Kept entries are then ranked
in two tiers. The `t` tag is the top tier, every matching emoji sorts above the first
matching symbol, so a broad word like arrow or star lists the emoji arrows and then
the glyph arrows below rather than weaving the two together. Within a tier a text
score orders, an exact alias or exact name first, then a name that starts with the
query, then the count of tokens found, with ties keeping the upstream order. The scan
runs over the whole set on each keystroke, a few milliseconds over several thousand
rows, so no index is needed, unlike the launcher whose app scan is the expensive part.

The visible list is capped at a small maximum, `MAX_RESULTS`, both for an empty field
and a query. The cap bounds only the display, the match still runs over the whole set,
so any glyph stays findable by typing, and nobody scrolls past a hundred rows to find
a glyph rather than typing a better word. The cap also bounds how many icons a single
open has to render, which is the reason it matters here rather than being cosmetic,
and is why it is kept modest even though the scan itself could show far more.

## Icons

The glyph is the row icon, not text in the title, so a row reads like an app row in
the launcher with a large glyph on the left and the name beside it. hs.chooser has no
emoji rendering, so each glyph is drawn once through one reused canvas into an
hs.image and cached, the same idea as the launcher's glyph icons but sharing a single
canvas rather than making one per glyph, since at this scale a canvas per glyph is the
whole cost. A glyph is rendered at most once ever, and the cap above keeps any one
open from rendering more than a bounded batch.

Render once and keep forever is deliberate, not lazy. Measuring showed each rendered
icon costs about 38KB and that memory is not reclaimed by the garbage collector until
a config reload, a property of the canvas render rather than something a cache policy
can undo, and the cost is the same at a small icon size as a large one, so shrinking
the icon is not a lever. A bounded cache that cleared old icons would be worse, not
better, since a re render only allocates fresh memory that also never comes back, so
clearing then redrawing grows the total without bound. Keeping each glyph exactly once
is therefore the leanest option, and `MAX_RESULTS` is what actually paces it, since it
bounds how many distinct glyphs a session can ever reach. A normal session that views
a few hundred glyphs costs tens of MB, and the ceiling, only reached if every glyph in
the set is deliberately surfaced, is a couple of hundred MB, which a reload resets.

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

It opts out of the shared fuzzy matcher with `matcher = false`, the same escape hatch
caffeinate and the display profiles menu take. The shared matcher filters and ranks
over a row's visible title and subtitle, but this tool matches over the hidden haystack
in `k`, the folded name, aliases, tags, and category, so a glyph found only by a tag
would be dropped if the atom filtered again. `_rows` also caps the visible rows to bound
the icon render, which the atom styling every survivor would undo. So `_rows` owns the
query end to end and the atom does no second pass.

## What it does not do

It keeps no recency or frequency memory, so a picked glyph does not float to the top
next time. The launcher's recency timeline is the model to follow if that is wanted
later, a small persisted list keyed by glyph, promoted on select. It also inserts one
glyph per name, it does not offer skin tone variants, since the gemoji base set is one
glyph per name.
