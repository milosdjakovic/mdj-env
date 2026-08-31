# TextCase.spoon

The decision trail and the important facts for this spoon. Cross cutting material
stays in the hammerspoon `CLAUDE.md`, which links here. The picker checklist and the
spoon lifecycle contract this file refers to live there.

## What it is

A picker that recases the current selection in place. It reads whatever text is
selected, lists every case as a row whose title is written in that case so the title
demonstrates the result, and whose subtitle previews the actual selection rendered
that way, and on select pastes the chosen result over the selection. Reached from the
launcher only, no dedicated key.

## Why a spoon and not inline

A picker that is only policy over the Chooser atom could live inline in the composition
root instead of as its own spoon. This one owns something of its own, the transform
catalog and the word tokenizer in `transforms.lua`, so folding it into the root would
bloat the composition root with algorithms that are not wiring, the same reasoning that
makes Emoji a spoon. It is a lean coordinator, it owns no watcher, timer, or eventtap, so
it has no `start`/`stop`, matching the lifecycle contract.

## The transforms are a Strategy family

`transforms.lua` is the pure policy set, an ordered catalog where each entry is an id, a
name, and a fn. The engine iterates it generically and never names a concrete transform,
so adding a case is a new row in that list and nothing else. Three families live there. The
literal ones (upper, lower, toggle) recase the characters in place, so they preserve every
separator and punctuation mark. The prose ones (title, sentence, capitalize) humanize first,
turning identifier delimiters (_ and -) and camelCase humps into spaces while leaving real
sentence punctuation intact, so a snake, kebab, or camel identifier reads as spaced words
but ordinary prose keeps its commas and periods; this was a correction, they used to keep
the delimiters. The identifier ones (camel, pascal, snake, constant, kebab, dot) tokenize
fully into words and rejoin them, so separators are replaced by the target convention. The
tokenizer splits on separators and on camel humps, lowercasing each word. It is ASCII, a Lua pattern limitation, so an accented letter is treated as a
separator by the reshaping transforms and is left untouched by raw upper/lower; a full
Unicode recase would be a larger change and is not the point here.

The catalog is loaded by the spoon itself with loadfile, not injected by the root, because
it has one implementation and one consumer, so injecting it would be indirection with a
single caller, the ceremony the design principles reject. Emoji loads its own dataset the
same way. Only the genuine cross-spoon seams, read and apply, are injected.

## It names no clipboard, read and apply are injected

The engine depends on two small contracts and names no concrete mechanism. `read(cb)`
yields the current selection, `apply(text)` writes text in place, and the composition root
supplies both. This is dependency inversion, the engine and the clipboard mechanism both
point at contracts rather than at each other. The root backs both with the ClipboardHistory
manager, `read` with `copySelection` and `apply` with `pasteText`, because that is where
the pasteboard snapshot and restore and the self capture guard already live, so reading and
writing the selection leave the clipboard and its history untouched. When the manager is
absent the root degrades `apply` to a typed paste and omits `read`, the same graceful
degradation the emoji insert takes.

## The selection round trip and why it works from the launcher

The launcher special action fires deferred, after the launcher tears down and macOS
restores focus to the source app, so when `show` runs the app is frontmost with its
selection intact. `read` copies the selection (a copy never clears it), the picker opens on
the built rows, and on select the picker tears down, focus returns to the app, the selection
is still there, and the paste replaces it. Nothing about the selection is held across the
chooser lifecycle: the transform runs once at show time and each row carries only its
result string, the Command as data rule every list tool here follows, since `hs.chooser`
serialises rows and would drop a function.

The read is asynchronous, a clipboard round trip polling for the copy to land, so the
picker is shown only once the selection is in hand. With nothing selected the copy never
lands and the picker opens to a single non-actionable guidance row, the same shape Vpn's
unavailable row uses, plain data naming no key.

## Why this tool cannot be a launcher scope, which was built and then removed

A query scope was wired for this tool and taken out again, which is worth recording so it is not
rebuilt on the same reasoning.

The round trip above is the obstacle, read from the other end. Reading the selection needs the
keyboard in the source app, and a launcher scope is a list inside a surface that is holding the
keyboard itself, so it cannot have the text. Reading before listing would mean a copy on the way
into a list nobody may pick from. So a scope can only list the cases with the preview replaced by
a fixed sample phrase, moving the real read to the moment of the pick.

That version worked. It was still removed, because the preview of your own text is most of the
reason to open this tool at all. Reading each case done to your actual selection is the answer to
"which one did I mean", and a list of case names without it is a menu you have to guess at. A
scope that has to drop the one thing a tool is for is not a faster route to that tool, it is a
lesser copy of it, and two ways in that do different things is worse than one way in that works.

The general rule this settled, and it is recorded in `Spoons/Olm.spoon/host/queryscope/CLAUDE.md` too, is
that a scope may be smaller than its tool but not smaller than the reason for the tool.

## The preview is display only

Each row subtitle collapses whitespace and elides a long selection so a multi-line or long
selection still reads as one tidy row, but the pasted result is always the full untruncated
transform carried on the row. The elision is byte based, so a non-ASCII preview could clip a
multibyte tail, which is cosmetic and never affects what is pasted.

## Picker integration

It follows the picker checklist in the hammerspoon `CLAUDE.md` like the other list tools. It
exposes a dot-called navigation adapter through `surface()`, which the root drops into the
shared `choosers` list, and the `textCaseOpen` predicate reads `isShowing()`. Its `textCase`
context gives it the shared j, k, i navigation with x to close. Rows are a static set per
open, so the shared fuzzy matcher filters them over title and subtitle with no per-tool
wiring, unlike the structured-query tools that opt out. Like the other native choosers it
docks the deferred shortcut panel through the three chooser callbacks.

## What it does not do

It recases one selection per open, it does not follow multiple carets or transform without a
selection. It does not offer a copy-to-clipboard alternative to the in-place paste, the
whole point being to recase the selection where it sits; the clipboard stays untouched.
