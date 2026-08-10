# Work packet, a synthetic stroke goes to the application rather than to the system tap

Written 2026-08-09 against feat/olm at `9179c9c`, on a fault the user reported and on
measurements taken live on that machine the same day. Work on `feat/stroke-to-the-app` from
feat/olm in a worktree under `../.worktrees/`, never from main, and never push.

## The fault, and what was measured

Sequential paste, the `pasteNext` walk on Ctrl and Option and V, delivered nothing at all in
Ghostty while working in other apps. A lossless trace, taken from `hs.logger.history` after
raising only the three clipboard loggers, says the same thing on every press in that terminal.

    the focused field in com.mitchellh.ghostty refuses direct text
    wrote text, count=2407, app=com.mitchellh.ghostty
    cmd+v sent, app=com.mitchellh.ghostty, held=alt+ctrl

Nothing landed. The same run in Antinote logged `inserted 18 chars directly, ok=true` and
worked, so the walk, the store, the queue, and the restore are all sound. What fails is one
thing only, the fallback path, a synthetic Cmd+V arriving at a terminal while the chord that
asked for it is still physically held.

Three further measurements narrow it to the delivery and nothing else. Running the identical
code from the launcher row, where nothing is held, pastes correctly into that same terminal.
Asking the application for its Edit and Paste menu item through accessibility blocked for five
minutes and never answered, so driving the application's own paste command is not a route.
And a throwaway probe bound to Ctrl and Option and B, which posts the Cmd+V straight to the
frontmost application rather than to the system tap and fires a beat after the press so the
chord is still down, pasted consistently, at every speed the user tried.

So the held keys do not have to be lifted. The stroke has to be delivered somewhere else.

## The change

One funnel carries every synthetic stroke in `Spoons/Olm.spoon/lib/paste.lua`, the local
`stroke(mods, key)` near line 253, and that funnel is the entire change. It posts through
`hs.eventtap.keyStroke` today, which hands the event to the system, where the terminal reads
the live modifier state alongside it and sees a chord it has no binding for. Post a key down
and a key up built with `hs.eventtap.event.newKeyEvent` to the frontmost application instead,
through the application argument of `post`, which is what the probe proved. Keep the returned
held modifiers exactly as they are, since that report is what tells a silent failure apart from
an empty selection. Keep `hs.eventtap.keyStroke` as the fallback for the one case where there
is no frontmost application to post to, and reach for the application once at the moment of the
stroke rather than earlier.

Rewrite the comment above that funnel, which currently records the two attempts that were
removed and closes by saying a physically held key cannot be lifted from here so whoever binds
the key waits for the release instead. That closing conclusion is now wrong and a reader
following it would wait for a release that the fix makes unnecessary. Replace it with what was
measured, that the interference is the delivery rather than the modifiers, that a stroke posted
to the system was ignored by a terminal on every attempt while the same stroke posted to the
application landed on every attempt with the same keys held, and that the two earlier attempts
stay recorded because they say what does not work. Keep the paragraph about the stroke's own
flags never leaking, it is still true and still worth knowing.

The Cmd+C that reads a selection goes through the same funnel, so append copy on the same chord
gets the same correction with no separate work. Say so in one sentence rather than adding a
second path.

## What not to change

Do not touch `M.ownPasteInFlight` or the watcher that consults it in the clipboard's
`manager/monitor.lua`. Whether a posted stroke of this kind is still visible to an event tap
was not measured, so write no claim about it anywhere, and leave the guard in place, since the
fallback above still posts to the system.

Do not change `pasteDelay`, `copyDelay`, the queue, the drain, the restore, or anything in the
clipboard's `session.lua`. Do not add a per application table or any branch on which app is in
front. Do not add a configuration key for the delivery. One route with one fallback.

## Gate

`luac -p` parses every touched file. `test/units.sh` from the worktree hammerspoon directory
passes. `src/check-dependencies.sh` from the worktree root passes with no new warnings.
`test/inventory.sh` three times as committed, each passing. Do not take the devlock and do not
attempt to test a held chord, which needs hands. The user validates live after the land.

## Deliverable

This packet committed first, then the change, then the documentation, small commits, every
message ending after a blank line with Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
and a subject of the form scope subject with no colon after the scope. Merge to feat/olm with
no fast forward once the gates pass. The stowed tree points at this checkout, so the merge is
what makes it live, and a reload follows the house rule, scheduled through a timer and never
called inline, with the console read afterwards and any error line treated as a failing gate.

Documentation is two places. The Paste section of `Spoons/Olm.spoon/CLAUDE.md` carries the
paragraph headed by a synthetic stroke against a held chord, and its conclusion is the one this
fix overturns, so correct it there with the measurement above. Append a short paragraph to
`docs/superpowers/specs/2026-08-07-olm-validation-log.md` recording the fault, the measurement,
and the merge hash.

Report the merge hash, the documentation hash, each gate's numbers, the exact funnel you wrote,
and anything in the packet that did not survive contact with the code, flagged loudly rather
than worked around. Every line you author follows the repository writing rules, no colons, no
semicolons, no hyphens or dashes, periods and commas only, and copied lines keep their form.
