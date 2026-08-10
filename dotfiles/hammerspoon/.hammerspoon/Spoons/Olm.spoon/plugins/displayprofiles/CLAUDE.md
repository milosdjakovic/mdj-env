# DisplayProfiles

Why this spoon is shaped this way. The code sits beside this file, so this records the
decisions, not the lines.

## Two jobs, one contract kept stable

The spoon does two things. It auto applies the saved arrangement that fits the attached
displays, the original job, and it exposes an inspect and manage chooser, the new one. The
public face stays the colon methods the rest of the config already calls, `current`,
`reconcile`, `apply`, `capture`, `profiles`, `configure`, `start`, `stop`, the read and
lifecycle methods delegating to the engine while `profiles` returns the merged curated and
captured view the chooser lists.
A consumer in the main root reads `current()` to resolve the active arrangement, so that
contract could not change. The new surface hangs off `obj.chooser`, dot called, the same dot
called shape a manager surface uses, so the main root registers and gates it alongside its
list surfaces without the spoon growing a second object model.

## The composition root, engine, provider layout

`init.lua` is the composition root and names no policy beyond the merge. `engine.lua` is the
mechanism, it watches, matches, and applies, and knows nothing about machines, a catalog, a
store, or the chooser. `store.lua` persists the captured profiles. `chooser.lua` is pure
command policy over an injected `api`. The `api` `init.lua` builds is the one seam that joins
the engine and the store, so the chooser never touches either directly. Adding a backend or a
screen is a change in one file, not a rewrite across three.

## Inspect and manage, not apply

The engine already reapplies the matching profile on every screen change, and only one
profile ever matches the attached displays, so there is nothing to switch between. The
chooser therefore does not apply. The one apply like action is Reapply, shown only on the
active profile, mapping to `reconcile(true)`, for the rare case where macOS scrambled the
layout with no hardware change so no screen event fired. If this were built as a switcher it
would offer choices that can never take effect, which is the trap the design avoids.

## Nested menu stack over one chooser, with re-show

The chooser is one native `hs.chooser` instance driven as a stack of frames, not a chain of
separate instances. Navigation is in place, not a re-show. The native chooser closes on any
Return, which would force a close and reopen to move between levels, and that flash is what
reads as laggy. So a menu step mutates the frame stack and calls `refresh()` on the same
instance, updating the visible rows with no reopen. Two things make that work. Confirm is the
tool's own `enter`, wired to its own confirm binding and to a scoped eventtap that swallows
Return and the keypad enter while the chooser is up, so the native completion never fires and
the step stays in place. And the one path that still reaches the native completion, a mouse
click on a row, falls back to the old reopen, which is rare in this keyboard driven flow.
Escape and a click away
close for real, resetting the stack to the top for the next open.

Each level clears the field, since a filter typed at one level must not narrow the next, and
`refresh` jumps the highlight back to the first row of the new list. Clearing the field is
also what the rename and capture screens want, where the field is the name entry rather than a
filter. The row supplier reads the top frame plus the live query, so those rows morph as you
type, and stay disabled until the name is valid.

Entering a profile shows its displays straight away, one read only row per monitor, with
Reapply, Rename, and Delete beneath, so there is no separate list displays step. An earlier
version had that extra layer and it earned nothing.

## Storage, git tracked JSON merged with curated Lua

Captured profiles live in `config/display-profiles.json`, keyed by `LocalHostName` exactly
like `config/displays.lua`, read and written only through `store.lua`. The curated
`config/displays.lua` stays the hand maintained reference, read only from the tool. The
composition root merges the two into one list, curated first, each entry carrying whether it
is editable. Only captured profiles are editable, so the tool never rewrites the commented
curated Lua.

This was chosen over two rejected options. `hs.settings` is machine local, so it could not be
shared across the two machines. Writing back into `displays.lua` is fragile code generation
into commented source. The JSON gives all three wants at once, shared across machines through
git, editable by hand, and read in one line. Per host keying plus portable serial ids keep
the two machines from colliding in the one file. Capture appears only when the current
arrangement matches no profile, the tool's notion of add new. Saving a variant of an already
matched arrangement is a later addition, not part of this build, and there is no reordering
yet either.

## A write must not trigger a reload

The JSON lives inside the watched `~/.hammerspoon` tree, so a write would trip the pathwatcher
and restart Hammerspoon mid capture. The main root's pathwatcher callback therefore skips a
reload when the only changed file is `display-profiles.json`, and the chooser rebuilds the
engine in memory after every write, so a capture, rename, or delete is live at once with no
reload. A change to that file matched with any other file still reloads. A consequence is that
a git pull bringing new captured profiles is not picked up until the next reload, which is
correct, a data file should not force code reloads.

## The attached set is cached

The row supplier asks the engine which profile is active on every keystroke, so the engine
caches the attached id set read from displayplacer and clears it only on a settled screen
change, the one event that can change what is attached. So typing never shells out, and a real
dock or undock is still seen.

## Degradation

Without a `host` and `storePath` the store is disabled and the chooser shows only the curated
profiles, all read only, capture and the edit actions simply do not appear. Without
displayplacer on PATH the engine logs once and does nothing, the same as before. Dropping the
`obj.chooser` wiring in the main root leaves the auto apply engine fully working, since the
two jobs share only the engine.

## No restow

These files live inside an already symlinked spoon, so they resolve through the existing link.
Only adding a whole new spoon needs a restow.
