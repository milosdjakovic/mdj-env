# Olm chooser keys

Status. The canvas picker's text field lets Hyper presses through to their own dispatch, and
the action panel opens on Hyper and o in every list, with file search reveal on Hyper and f.

## Now

The canvas field's event tap claims every key down so nothing reaches the app underneath, with
Escape answered first. The one exception is Hyper. The field takes an injected predicate,
`yields`, and a key it answers true for is passed on unclaimed. The composition root builds
that predicate over `HyperKey:owns`, which each trigger shape answers. Under the leader shape a
key is Hyper's when it is the leader key or the leader is held, under the chord shape when
every chord modifier is held. The field and the canvas provider know only that it is a
predicate, and the native provider needs nothing since its keys already reach Hyper.

The action panel is on Hyper and o in every list, declared once in `lib/surface.lua` and in
the loop at the bottom of `config/keys.lua`. File search reveal in Finder is on Hyper and f.

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
