# Olm action panel

Status. The action panel is programmable. A plugin's `surface.extra` row may carry a `section`,
an `applies` method, `choices` or `confirm`, and may leave out its key to be a verb of the panel
alone. Workspaces and Display Profiles apply on Return and offer the rest in the panel. Phases
two to four of `docs/PLAN-ACTION-PANEL.md` are open.

## Now

A plugin declares what its rows can do and Olm draws it. The fields live on `surface.extra`,
validated in `lib/surface.lua`, carried and ordered into sections by `lib/hints.lua`, and answered
by `host/actionpanel`, which asks the open plugin's surface through the root for `applies` and
`choices` and opens a level for `choices` and `confirm`. A verb opening a level of its own tool
calls the new stage word `stagePush`. The root's dispatch forwards a value, so a choice reaches the
plugin's method as its argument. Keyless verbs live in a context's `panel` list, never in its
bindings, since every reader of a binding reads its key. The swift chooser's popover draws the
section headings and heads a level with its verb, and the canvas chooser lists the same order.

Return in Workspaces and Display Profiles applies the layout or the profile, decided by Milos on
2026-10-29, and Rename, Apps, Displays and Delete moved into the panel, Delete behind a confirm.
This track moves what plugins already do into the panel. New actions follow as separate pieces.

## Rejected

- **Keyless verbs as bindings with `chord = false`.** 2026-10-29. A binding's key is read by the
  keymap, the key remap, the hints, the leader sheets, the wiring and the field keys, about twenty
  places, and a binding with no key would have been a nil in each. A separate `panel` list keeps
  them out of every reader that does not need them.
- **Row dependence as a presentation member answering a set of verb names.** 2026-10-29. One
  function for all verbs drifts from the verbs it names. `applies` sits on the verb it gates.
- **Escape stepping back out of a level.** 2026-10-29. Escape closes, as everywhere else in Olm,
  and Backspace on an empty field steps back, as it does out of every pushed level.

## Log

### 2026-10-29 19:08

Milos asked for the action panel programmable and done well, after it became a glass popover. A
read only survey of every plugin found that no plugin declared a secondary, only three declared
extra verbs, and nine built menus of their own that the panel could hold. He decided Return in
Workspaces and Display Profiles applies, and that this track is the contract and migrations, with
new actions later. Phase one built the contract, the levels, `stagePush`, section headings in the
popover and both plugins, and he checked it live. Display Profiles' monitor details, which lived on
the level Return used to open, became a Displays verb.
