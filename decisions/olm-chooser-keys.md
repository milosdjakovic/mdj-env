# Olm chooser keys

Status. The default chooser's text field lets Hyper presses through to their own dispatch, and
the action panel opens on Hyper and o in every list, with file search reveal on Hyper and f.

## Now

The default chooser's field event tap claims every key down so nothing reaches the app underneath, with
Escape answered first. The one exception is Hyper. The field takes an injected predicate,
`yields`, and a key it answers true for is passed on unclaimed. The composition root builds
that predicate over `HyperKey:owns`, which each trigger shape answers. Under the leader shape a
key is Hyper's when it is the leader key or the leader is held, under the chord shape when
every chord modifier is held. The field and the default provider know only that it is a
predicate, and the legacy provider needs nothing since its keys already reach Hyper.

The action panel is on Hyper and o in every list, declared once in `lib/surface.lua` and in
the loop at the bottom of `config/keys.lua`. File search reveal in Finder is on Hyper and f.

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
