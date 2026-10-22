# Olm chooser keys

Status. The default chooser's text field lets Hyper presses through to their own dispatch, and
the action panel opens on Hyper and o in every list, with file search reveal on Hyper and f.

## Now

The default chooser's field event tap claims every key down so nothing reaches the app underneath, with
Escape answered first. The one exception is Hyper. The field takes an injected predicate,
`yields`, and a key it answers true for is passed on unclaimed. The composition root builds
that predicate over `owns` on every held leader in use, Hyper and META here, which its trigger
answers, since the phase A fix round of the list keys addendum in `olm-keymap.md`, so a key typed
under a held leader over a list never reaches the field and falls to that leader's one rule over
open lists. From phase 3 until then it asked only the one leader whose policy turned contexts on.
Since phase B the field also asks a list key watcher next, for a list chord with no held leader. Under the held trigger a key is the leader's
when it is the leader key or the leader is held, under the modifier trigger when its whole base
set is held. The field and the default provider know only that it is a
predicate, and the legacy provider needs nothing since its keys already reach Hyper.

The action panel is on Hyper and o in every list, declared once in `lib/surface.lua`, the loop
that once sat at the bottom of `config/keys.lua` having gone with that file. File search reveal in
Finder is on Hyper and f.

The docked shortcut hint pane shows after 800 ms with no key, and every key restarts that
countdown, Hyper moves included, since the default provider counts activity in selectNext,
selectPrev and insertSelected. Once shown it stays until the list closes.

The default chooser is the shipped default and the word chooser means it unless legacy is
named. The legacy chooser, the one wrapping hs.chooser, is deprecated, still selectable
through `chooser.provider` in the settings as a fallback, marked in its own header, and named
in a console warning on every load that picks it. Removing it is a later, separate step.

## Rejected

- **Putting the action panel on Hyper and k.** 2026-10-14. k already moves the cursor up in
  every list, so two actions would answer to one key.
- **Having the field name HyperKey and ask it directly.** 2026-10-14. The field would then
  depend on one concrete trigger, and the field is the reusable part. A predicate injected from
  the root keeps the dependency pointing at a contract.

## Log

### 2026-10-14 20:00

Estimated time. Found that no Hyper binding fired while a canvas picker was open, so confirm,
move and the action panel were all dead there. The brief's decision six had the field claim
every key down, and Hyper's dispatch sits downstream of that tap, so the claimed press never
arrived. Hyper is now the one exception, passed through the injected `yields` predicate.

### 2026-10-14 20:00

Estimated time. The action panel moved from Hyper and period to Hyper and o at the person's
request, and file search reveal moved from o to f to make room. Reveal had been on f before it
moved to o for reading as open, and f now reads as Finder. The panel row, the hint strip and
the inventory golden follow from the declarations.

### 2026-10-14 21:00

Estimated time. The shortcut hint pane now shows after 250 ms with no key, down from three seconds,
at the person's request, and each key restarts that countdown. It stays up once shown until the list
closes. Hyper presses are yielded by the canvas field, so they never reach its key handler where
activity used to be counted. Activity is now counted in the canvas provider's selectNext, selectPrev
and insertSelected, which is what the Hyper dispatch calls, and not at the field's yield, since the
leader key autorepeats while held and counting there would keep the pane from ever appearing.

### 2026-10-14 21:20

The 250 ms delay above was tried live and works, and the person asked for 2500 ms instead, so
that is what ships. The 250 ms entry stands as the record of what was tried first. The debounce,
the latch and where activity is counted are unchanged.

### 2026-10-14 21:25

After living with 2500 ms the person asked for 1650 ms, so that is what ships now. Nothing else
about the pane changed.

### 2026-10-14 21:31

1650 ms still felt long, and the person asked for 1300 ms, which is what ships now.

### 2026-10-14 21:33

1300 ms still felt long, and the person asked for 800 ms, which is what ships now.

### 2026-10-14 21:45

The canvas picker becomes the default on main at the person's request, and the native picker is
deprecated rather than removed, kept as a fallback for now with a header note and a load warning.
An unknown provider name now falls back to canvas instead of native.

### 2026-10-14 22:30

Estimated time, anchored to the commit before this one.

The two pickers are renamed at the person's request. The canvas provider is now the default
chooser and the hs.chooser provider is now the legacy chooser. The files moved to
`lib/chooser/providers/default/` and `lib/chooser/providers/legacy.lua`, the facade registry
keys are `providers.default` and `providers.legacy`, and the `chooser.provider` setting takes
`default` or `legacy`. From here on the word chooser means the default chooser unless legacy is
named. The legacy chooser is still deprecated and still warns on every load that picks it. The
earlier entries above keep their old names, canvas and native, since they are records.

### 2026-10-14 23:00

Estimated time, anchored to the commit before this one.

The row boundary snap on keyboard movement is removed at the person's request. The list model
used to floor scrollTop to a whole row before checking the highlight, so one move up after
scrolling down past the visible rows realigned the viewport and sent the cut top row to the
bottom, and the first key after a wheel or trackpad scroll that stopped between rows snapped
the list. The viewport now moves only when the highlighted row is not fully inside it, and then
only far enough to show that row at the edge it crossed. A highlight already fully visible
leaves scrollTop exactly as it was. A wrap still jumps to its row under the same rule. No
Rejected item or earlier decision owned the snap, it was only written into the model's comments
and its offline case, both updated in this change.

### 2026-10-22 10:31

The field's yield followed list keys onto any leader, phase A of the list keys addendum in
`olm-keymap.md`. The root builds the predicate over `owns` on every held leader some list key
binds on, which is Hyper alone on this machine, so nothing a hand does here changes. A held leader
binding no list key is not asked, so a key typed with Right Option held over a list still reaches
the field. The harness word `leaderHeld` asks the same set.

### 2026-10-22 10:46

Corrected, the entry at 10:31 had the field yield only to held leaders some list key binds on, so
Right Option and a letter over a list still typed into the field. The coordinator decided, matching
what Milos asked of META over lists, that the field yields to every held leader in use, so META and
SUPER over a list are swallowed by the one rule like any key the open list does not bind.

### 2026-10-22 19:45

A list opened over a password field is deaf. With Hyper coming from kanata as real modifiers, the
launcher opened from a Safari password field, but nothing typed or chorded reached it, because the
default chooser never takes focus and reads keys through an event tap, and secure input hides every
key from every tap while the password field has focus. Two probes were run with Milos, each
triggered by a chord from inside the field. `hs.focus()` did nothing, Safari stayed in front and
secure input stayed on. A native `hs.chooser`, a real window that becomes key, took focus from
Safari, secure input went off within a tenth of a second, every letter typed reached its field, and
hiding it and activating Safari again put the focus and secure input back. So a list over a
password field can hear keys only if it opens as a key window for that time. Not built yet, since
never taking focus is the reason the canvas chooser exists, see `lib/chooser/providers/default/surface.lua`,
and taking it only while secure input is on is a design change of its own.

### 2026-10-22 22:37

Built. `lib/securefocus.lua` holds focus while secure input is on. It shows an empty native
`hs.chooser`, moves its window off screen, and answers a release that hides and deletes it and
activates the app that had focus. The default provider takes it as an injected `focusHold`, asked
after the surface shows and released after it hides and before `onClose`, so an insert on close
lands in that app, and a second show over a list already up keeps the hold it has. The root is the
only file naming it, and the provider names no mechanism. Normal opens are untouched, since the
hold answers nothing while secure input is off. The cost is stated in the lib's header. While a
list is open over a password field secure input is off, so any event tap on the machine could read
what is typed into that list, for as long as it is open. A borderless webview and `hs.focus()`
were both measured unable to take focus from Safari, so the native chooser is the one mechanism
proven, and a titled webview was never tried. With Hyper from kanata, Milos confirmed typing, list
keys, Escape, picking an app and inserting an emoji over a Safari password field, focus returning
to the field each time, and no change over an ordinary field.
