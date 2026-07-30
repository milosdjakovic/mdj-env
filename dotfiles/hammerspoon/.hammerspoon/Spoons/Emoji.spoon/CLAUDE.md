# Emoji.spoon

The decision trail and the important facts for this spoon. Cross cutting material
stays in the hammerspoon `CLAUDE.md`, which links here. The picker checklist and
the spoon lifecycle contract this file refers to live there.

## What it is

The picker is a filterable list over the Chooser atom, carrying both emoji and a
generous slice of native Unicode symbols, currency and arrows and math and the Mac
modifier keys and more, the same glyphs the macOS Character Viewer shows. Typing
matches by name, shortcode, tag, or category, so a keyword like happy or money or a
group word like food finds the glyph without its exact Unicode name. Selecting a row
inserts the highlighted glyph into whatever field was focused before the picker
opened. Emoji always rank above symbols in the results, so a query lists every
matching emoji first and the plainer glyphs below, never interleaved.

## The backends, a provider strategy

Opening does not launch one fixed picker, it launches whichever backend the composition root
put first. Emoji is a facade, the same shape Chooser.spoon uses. It owns no picker of its
own, it holds a set of backends under providers/ and selects one, so swapping which emoji
picker opens is a one line change at the root and never a change to this code.

Three backends ship. The hammerspoon backend is the picker built over the Chooser atom,
the one the rest of this file describes, and it is always available so it is the safe
fallback. The macos backend triggers the system Character Viewer with Ctrl Cmd Space and
inserts through it, so it needs no dataset or icons of its own. The custom backend runs an
injected callback, so any external picker reached by a URL scheme, a remapped key, a shell
command, or a remote trigger becomes a backend with no file of its own, which is why there
is no Alfred or Raycast backend, each is just a custom one fronting the app by its own
trigger. The custom file returns a factory, not a backend, called with either a bare
function to run on show or a table carrying a name, a show, and an optional isAvailable and
isShowing.

Each backend honors one small contract, isAvailable, configure, show, isShowing, and
surface. The root lists the backends by reference in priority order, and configure walks
that order, logs any backend whose isAvailable is false, and configures only the first
available one, so a backend that never wins pays no setup cost, the dataset load and the
icon prewarm included. That walk is a Chain of Responsibility, the first backend that can
handle the open wins, and a custom backend fronting an app that is not installed declines
through its isAvailable so the facade falls through to the next, logging the skip so a
missing app is visible rather than silent. show, isShowing, and surface delegate to the
winner. Only the hammerspoon backend returns a real navigation surface, the macos and
custom backends return a no op surface so they stay out of the shared j, k, i navigation
registry, which is correct since a system or external picker drives its own keys.

`rows` and `insert` are an optional part of that contract, the list offered to a surface other
than the backend's own, which is what the launcher's `e` scope is. Optional because only a
backend that owns its list can hand it over, and the system Character Viewer and an external app
own nothing we can read. So the facade answers `lists` and the caller asks before assuming,
rather than every caller reasoning about which backend won. With a non listing backend fronted
the scope is simply not registered and its alias resolves to nothing, which leaves an ordinary
search unaffected and is better than a scope opening onto an empty list.

`insert` is also what the backend's own chooser now selects through, rather than the two calls it
used to make inline. A pick has a cost, remembering it, and one door onto that cost means a pick
made from anywhere is remembered identically. Two doors is how a recency memory quietly starts
depending on which surface you happened to use.

The rest of this file describes the hammerspoon backend, since it is the one with a
dataset, a match, icons, and a pick memory to explain.

## Why a spoon and not inline

A tool that is only policy over the Chooser atom can live inline in the root.
This picker owns something of its own, the vendored emoji dataset plus the matching
and ranking over it, so folding it into the root would bloat the composition root
with a data file and a scoring function that are not wiring. It is a small coordinator
spoon instead, though a lean one. It owns no watcher, timer, or
eventtap, so it has no start or stop, matching the lifecycle contract.

## The data is vendored, not fetched at runtime

The picker searches offline and opens instantly, so the set is fetched once by
`regenerate.sh` and committed as `data.lua` beside the spoon. Runtime never touches
the network. Two sources feed one flat list. Emoji come from the GitHub gemoji
project, chosen because one well maintained file already carries, per emoji, the
glyph, a human name, the shortcode aliases, freeform tags, and a category, which is
exactly the material a keyword match needs. Symbols come from the official Unicode
Character Database, a slice of the standard blocks the Character Viewer shows.
Rerun `regenerate.sh` to refresh the set, for example when new Unicode glyphs land,
and commit the new `data.lua`.

A refresh reports what it changed, which is the only reason to run one. The generated
file is thousands of lines and a line diff of it says nothing the moment upstream
reorders anything, so the generator answers the question while it still holds both the
new set and the committed one, listing what arrived, what left, and for each arrival the
words that reach it beyond the ones already in its own name. An arrival with none of
those is reachable only by its official Unicode name, which is fine for a rightwards
arrow and useless for a place of interest sign, so the report states the fact and leaves
the call. Acting on it means adding a line to the synonym table in the generator, which
stays hand written for exactly that reason. A departure is a glyph this Mac's fonts
stopped drawing, the other thing worth knowing and otherwise silent. An unchanged
refresh says so and writes a byte identical file, so a rerun that changes nothing leaves
no diff to review.

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

### Why the artifact is a Lua table and not json

The load is a `loadfile` of a committed Lua table, for one measured reason.
`hs.json.decode` is quadratic in the number of objects in an array, not in the size of
the file. The same rows cost 118 ms at a thousand entries, 620 ms at 2500, and 3063 ms
at the full 5648, while a flat array of the same content as plain strings decodes in
20 ms. As json this set cost three seconds and as a Lua literal it costs six
milliseconds, and the whole `_load`, the parse plus the glyph index plus the settings
read, is under ten. That is worth having because `_load` runs in `configure`, so every
config reload paid it, which while working on this config means every file save.

Json was chosen first for a real reason, that a generator writing Lua would have to
escape names into Lua strings by hand and get it wrong on an apostrophe or a backslash.
The answer is where the write happens rather than what it writes.
`filter-glyphs.lua` already holds the finished list and already runs inside Hammerspoon,
so `string.format` with `%q` escapes exactly what Lua reads back and leaves utf8 bytes
untouched, and no hand written escaping exists to be wrong. It was verified once by
comparing every field of all 5648 entries against the json it replaced, with no
differences, the names carrying curly apostrophes included. Control characters are
flattened to a space first, since `%q` escapes a newline as a real line break, which is
also what keeps the promise of one row per line and a readable diff.

Json still shapes both upstream sources, since jq is what reshapes them, and only the
final write differs. Precompiled bytecode was measured too, 1.3 ms, and rejected,
because it saves under five milliseconds and costs a committed binary tied to a Lua
version. An absent, unreadable, or malformed file degrades to an empty list with one
console line, so a bad dataset costs the picker its rows and never the config's load.
The one structural limit is that the file is a single chunk holding one table
constructor, comfortable at this size and worth splitting into appended blocks only if
the set ever grew by an order of magnitude.

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
rows, so no index is needed, unlike a tool whose scan of its source is the expensive part.

The visible list is capped at a small maximum, `MAX_RESULTS`, both for an empty field
and a query. The cap bounds only the display, the match still runs over the whole set,
so any glyph stays findable by typing, and nobody scrolls past a hundred rows to find
a glyph rather than typing a better word. The cap also bounds how many icons a single
open has to render, which is the reason it matters here rather than being cosmetic,
and is why it is kept modest even though the scan itself could show far more.

## Icons

The glyph is the row icon, not text in the title, so a row reads like an app row
with a large glyph on the left and the name beside it. hs.chooser has no
emoji rendering, so each glyph is drawn once through one reused canvas into an
hs.image and cached, the same idea as glyph icons drawn elsewhere but sharing a single
canvas rather than making one per glyph, since at this scale a canvas per glyph is the
whole cost. A glyph is rendered at most once ever, and the cap above keeps any one
open from rendering more than a bounded batch.

Render once and keep forever is deliberate, not lazy. Each rendered icon holds its memory
until a config reload, since the canvas render is not reclaimed by the garbage collector,
a property of the render rather than something a cache policy can undo. Dropping every
reference to a batch of four hundred and collecting three times returns nothing at all,
which is what closes the question. So a bounded cache that cleared old icons would be
worse, not better, since a re render only allocates fresh memory that also never comes
back, and clearing then redrawing grows the total without bound. Keeping each glyph
exactly once is therefore the leanest option, and `MAX_RESULTS` is what paces the count,
since it bounds how many distinct glyphs a session can ever reach.

What that costs was measured wrong once and the corrected figures matter, because the
wrong ones are what chose `ICON_SIZE`. Resident memory over batches of four hundred
glyphs, sampled around a collection, is 78 to 112KB per glyph at 44 points and about
92KB at 72. The earlier note claimed 30KB against 143KB, which is the raw pixel buffer
at each size, 88 by 88 at four bytes being almost exactly that 30KB, so what it measured
was the bitmap and not what the process retains. The consequence is that render size is
barely a lever at all, a fifteen percent difference rather than a fivefold one, and
dropping from 72 to 44 bought far less than it appeared to. So `ICON_SIZE` should be
chosen on how a row looks and nothing else. The honest totals are 30 to 44MB for four
hundred glyphs, and a ceiling near 440MB if every glyph in the set were deliberately
surfaced, which a reload resets.

Prerendered files would cut that, by less than it first looked, and how that number was got
wrong twice is the useful part. Loading four hundred saved PNGs appeared to cost 17KB each
against the render, a fivefold saving, and that figure was an artifact. An `hs.image` from a
file decodes lazily, so what was measured was an undecoded handle, while a canvas render
materialises immediately. Forcing the pixels with `colorAt` and comparing the same four
hundred glyphs down both paths in the same process gives 20KB undecoded and 53KB decoded
from disk, against 60KB fresh and 92KB once touched from the canvas, with the disk path at
0.38ms an icon against 0.74ms. So it is roughly 40 percent less memory for an icon that gets
drawn and 66 percent less for one that never does, and about twice as fast, rather than the
fivefold anything.

Both mistakes came from measuring one side of a comparison, first the bitmap instead of the
retained cost, then an undecoded handle against a materialised one, and the second was found
only by asking whether a lazily decoded image was being compared honestly. That is worth
repeating before trusting any figure here. Compare the same glyphs, in the same process, in
the same state, since colour emoji and monochrome symbols do not weigh the same either.

The remaining structural difference is the one that survives correction. A canvas render
costs most of its memory the moment it exists, whether or not the row is ever drawn, and the
picker supplies a hundred rows while showing about ten. A file backed icon stays at the
undecoded price until something draws it, and it outlives a reload rather than being
rebuilt.

Even one reused canvas is too slow to render the whole set at once, so the empty state
icons are warmed in the background right after configure, in small batches on a self
stopping timer, and the cost is paid before the first open rather than during it. An
open before the warm finishes, or a typed query that reaches glyphs outside the warmed
slice, renders those on demand and caches them, so correctness never depends on the
warm having completed, only the smoothness of the first open does.

## Rows are data, never functions

Each row carries only the glyph string as its item, which the Chooser serialises and
hands back to onSelect, so no function is ever placed on a row, the same rule the
other list tools follow. The effect of a pick is injected as onInsert, so the
spoon never learns what a pick does. The root wires onInsert to insert the glyph into the
field that was frontmost before the picker opened, which macOS restores once the chooser
tears down.

Insertion pastes through the clipboard rather than typing, which was a correction over an
earlier typing path. `hs.eventtap.keyStrokes` synthesizes a Unicode key event, and a
terminal and some native apps read that event rather than reassembling a character outside
the basic multilingual plane, so an emoji, which is a surrogate pair in the key event,
arrived as replacement boxes even though the same glyph pasted from the macOS Character
Viewer landed fine. A paste carries the real bytes, so it works everywhere a terminal
included. So the injected onInsert must paste rather than type, and the root wires it to a
paste path that snapshots the clipboard, writes the glyph, sends the paste, and restores
the original clipboard after, so the write leaves no trace. A pick still lands where the
cursor is and the clipboard is still left untouched, the promise the typing path made, now
kept by a mechanism that also works in the apps the old one failed in. When no paste path
is wired the insertion falls back to typing, the same graceful degradation the other optional
dependencies take.

## Picker integration

It follows the picker checklist in the hammerspoon `CLAUDE.md` like the other list
tools. It exposes a dot called navigation adapter through `surface()`, which the root
drops into the shared `choosers` list, and the `emojiOpen` predicate reads
`isShowing()` directly. It has an `emoji` context block giving it the shared j, k, and
i navigation with x to close, the same shape a pure policy picker uses, because the key
that opens it is itself the move down key inside so it cannot double as the close the way
an open key that is not also a navigation key can. Escape closes natively. Like the other native choosers it docks the deferred
shortcut panel through the three chooser callbacks.

It opts out of the shared fuzzy matcher with `matcher = false`, the same escape hatch
the structured-query tools take. The shared matcher filters and ranks
over a row's visible title and subtitle, but this tool matches over the hidden haystack
in `k`, the folded name, aliases, tags, and category, so a glyph found only by a tag
would be dropped if the atom filtered again. `_rows` also caps the visible rows to bound
the icon render, which the atom styling every survivor would undo. So `_rows` owns the
query end to end and the atom does no second pass.

## Recents, the most used first

The picker remembers what you pick, so an empty field leads with your most used glyphs
rather than the raw upstream slice. This is the same Observer shape a recency timeline uses.
`onSelect` promotes the chosen glyph through `_promote`, the one
writer of the memory, which lives in one `hs.settings` key, `emojiRecency`, so a favorite
survives a reload and a reboot, the same reason such a memory is persisted elsewhere.

The score is a decaying one, not a raw count, which is the important decision. A raw count
locks an old favorite at the top forever, since a fresh glyph would need as many picks as
the old one ever had to catch it. Instead each glyph holds a score that on a pick becomes
its own value decayed by `DECAY` to the power of the picks since it was last touched, plus
one. A glyph picked constantly converges to the geometric limit `1 / (1 - DECAY)`, so
`DECAY` at 0.9 sets a natural ceiling of 10, and a glyph left unused sheds about a tenth of
its standing per pick of anything else, so a new favorite overtakes a stale one within
roughly ten to twenty picks rather than never. The decay is measured in picks, not wall
clock, so the order reshuffles only as use moves on and an idle day changes nothing.
Swapping to a time based half life later is only a change in how that age is measured.

The score is computed lazily. A pick decays and bumps only the picked glyph and stamps it
with the current value of a global pick tick, and every other glyph is decayed to that tick
only when the recents are read, so a pick is one multiply and one add and never rewrites the
rest of the table. An entry whose decayed score falls below `PRUNE_FLOOR` is dropped on the
next pick, so the memory stays tiny. The empty view leads with the top glyphs by decayed
score, the most recent pick breaking a tie, capped at a small `RECENTS_MAX`, and the rest of
the leading slice follows in upstream order with those recents removed so none appears twice,
still bounded by `MAX_RESULTS`. A typed query is unchanged, the name and keyword ranking
stays in charge, so search stays predictable and the memory only shapes the browse view, the
same split between an empty timeline view and a typed rerank. A remembered
glyph that a regenerated `data.lua` no longer carries is skipped when the recents are built,
so the list is always renderable and the memory never has to be migrated. The recents glyphs
are warmed into the icon cache alongside the leading slice, since a favorite may sit outside
that slice, and there are at most `RECENTS_MAX` of them so the extra render is trivial.

## What it does not do

It inserts one glyph per name, it does not offer skin tone variants, since the gemoji base
set is one glyph per name.
