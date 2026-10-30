# Olm action panel

Status. The action panel is programmable. A plugin's `surface.extra` row may carry a `section`,
an `applies` method, `choices` or `confirm`, and may leave out its key to be a verb of the panel
alone. Workspaces and Display Profiles apply on Return and offer the rest in the panel, and the
clipboard, Text Case, Emoji and File Search have a secondary. Phase 3a moved VPN, Tmux Sessions,
Speedtest, Caffeinate and File Search onto the contract. Phase 3b and phase four were dropped, so
the track is finished.

## Now

A plugin declares what its rows can do and Olm draws it. The fields live on `surface.extra`,
validated in `lib/surface.lua`, carried and ordered into sections by `lib/hints.lua`, and answered
by `host/actionpanel`, which asks the open plugin's surface through the root for `applies` and
`choices` and opens a level for `choices` and `confirm`. A verb opening a level of its own tool
calls the new stage word `stagePush`. The root's dispatch forwards a value, so a choice reaches the
plugin's method as its argument. Keyless verbs live in a context's `panel` list, never in its
bindings, since every reader of a binding reads its key. The swift chooser's popover draws the
section headings and heads a level with its verb, and the canvas chooser lists the same order.

The root asks the plugin that owns the context the panel opened for, not whichever list is
showing, and hands it the row its tool made, through `QueryScope:payloadOf`, so a list hosted in
the launcher has its `applies` and `choices` answered by its own tool. A method the surface does
not have answers not found, and the verb stays listed. A choice may answer `enabled = false`, drawn
dimmed in the popover and choosing nothing, and the secondary may carry `applies`.

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

- **`stays`, a choices level that stays open as the mark moves, phase 3b.** 2026-10-30, decided by
  Milos. Its two targets did not fit. Olm Plugins' toggles are its top level, the list itself, so
  there is nothing to move into a panel. Browser Tabs' Browsers level reads each browser's
  Automation permission in the background when it opens and adds rows under a browser to ask for
  it or to open System Settings, so a level of the panel would need to redraw when an answer lands
  and to hold rows of a different kind, which is a page and not a pick. It stays a page. What would
  bring this back is a list whose setting is a set of toggles and nothing else.
- **Verbs one plugin offers every other list's panel, phase four.** 2026-10-30, built, checked live
  and dropped whole by Milos. It was `provides.panelVerbs`, rows the root added to every panel and
  ran on the plugin offering them, used for Theme, Placement, Switch off plugin over a launcher
  row, and Show keys. On the Placement list the panel offered Theme, on Theme it offered
  Placement, and on every list all of them, none an action of the list in front of the person.
  The panel holds the actions of the plugin whose list it opens over, Return, Command and Return
  and its own verbs, and nothing another plugin puts there. Theme and Placement stay on their own
  launcher rows, switching a plugin stays on the Olm Plugins page, and the key panel stays on its
  own key and in the action bar.

## Log

### 2026-10-29 19:08

Milos asked for the action panel programmable and done well, after it became a glass popover. A
read only survey of every plugin found that no plugin declared a secondary, only three declared
extra verbs, and nine built menus of their own that the panel could hold. He decided Return in
Workspaces and Display Profiles applies, and that this track is the contract and migrations, with
new actions later. Phase one built the contract, the levels, `stagePush`, section headings in the
popover and both plugins, and he checked it live. Display Profiles' monitor details, which lived on
the level Return used to open, became a Displays verb.

### 2026-10-29 19:16

Display Profiles' Return reapplies only the profile matching the attached displays, and runs
nothing on any other, since its own record says only that profile can take effect and the
engine's named apply would hand displayplacer monitor ids that are not attached. Milos accepted it
live. Phase two gave four lists a secondary on Command and Return, Copy in the clipboard through
the paste engine's own write so it never returns as a new entry, Copy in Text Case and Emoji, and
Reveal in Finder in File Search, which its f key also runs, so `lib/hints.lua` lists a verb on the
secondary's action once. The key goldens moved by exactly those Command and Return bindings.
Milos checked all four live.

### 2026-10-30 10:55

Phase 3a. Main had moved by one File Search commit, so the branch was rebased onto it and merged
with every gate green. VPN's provider page and Tmux Sessions' settings level each became one verb
with choices, Provider and Terminal, and the row at the foot of each list that led to them is gone,
so each list holds only what it lists. A backend or a terminal this machine lacks was a disabled row
on those pages, so a choice gained `enabled = false` rather than the not installed ones being
hidden. Speedtest's settings page became five choices under Run, Keep per network under History
beside Name this network, which opens its field through `stagePush`, and the two clears behind
confirms, each listed only when there is something to clear. The pane's paragraph explaining the
highlighted setting went with the page, and a choice carries at most a word or two of subtitle,
since the popover draws it where a chord goes. Caffeinate gained Stay awake for, half an hour to
eight hours with the clock each would end at. File Search's verbs on one entry name `applies`, the
secondary among them, which needed the secondary to accept the field.

Checking File Search found that the root asked whichever list was showing, which over a hosted
list is the launcher, and that a missing method answered nil, which the panel read as does not
apply, against its own comment. Hosted, Reveal, Copy path and Quick Look would have vanished. The
root now asks the context's owner and says whether the method exists. Wi-Fi's join was on the plan
and is its Return already, with nothing beyond it to move.
Milos checked all five live and approved them.

### 2026-10-30 12:00

Phase 3b was dropped by Milos, since neither of its lists fit. Phase four was built as verbs one
plugin offers every list, Theme, Placement, Switch off plugin and Show keys under an Olm section,
and loaded live. Milos found Theme and Placement offered on each other's lists and on every list,
which is navigation rather than an action, and then that the idea itself was not his. The panel
is the actions of the plugin the list belongs to, the way phases one to 3a built it. The whole of
phase four was reverted before any of it was committed, and the track ends with phase three.
