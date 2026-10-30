# Plan, a programmable action panel

Opened 2026-10-29 by Milos, after the action panel became a glass popover over the swift
chooser. He asked for it programmable and done well. A plugin declares what its rows can do, and
Olm draws it, sections, actions that depend on the row, submenus and confirms, the way Raycast's
action panel works. Every phase is checked live by Milos before the next starts.

## Decisions

- Return in Workspaces and Display Profiles applies the layout or the profile. Rename, Edit apps
  and Delete move into the action panel, Delete behind a confirm, and the level Return opened
  today goes away. Decided by Milos on 2026-10-29.
- This track is the contract and moving what plugins already do into it. New actions the survey
  found, Open With, kill signals, Forget network, Paste as plain text, Copy URL, follow as
  separate pieces once the contract has proven itself. Decided by Milos on 2026-10-29.
- Escape closes the whole panel, Backspace on an empty field steps back one level, and a
  submenu has its own filter in the field.
- The canvas chooser keeps working. It shows no section headings and a submenu replaces its
  rows in place, which is how its panel already works.

## The contract, four fields on a row of `surface.extra`

Each is optional, and a manifest that sets none behaves exactly as before.

- `section`, a short heading the verb is listed under. The primary and the secondary always lead
  the panel with no heading. Verbs with no section follow them, then each section in the order
  its first verb is declared.
- `applies`, the name of a method on the plugin's surface, called with the row the panel was
  opened over, answering whether the verb applies to that row. A verb that does not apply is
  left out of the panel. Its key, where it has one, still reaches the plugin, which already
  answers for itself.
- `choices`, the name of a method on the plugin's surface, called with that row, answering a
  list of choices, each `{ title, subtitle, icon, value, current }`. Choosing the verb opens
  them as a level inside the panel, and choosing one runs the verb's action with its `value`.
  `current` marks the choice in force with the green circle every list uses for that.
- `confirm`, a string or true. Choosing the verb opens a level of two rows, Cancel first, since
  a stray Return then does the harmless thing, and the confirm row, titled with the string or
  the verb's own description. Choosing it runs the verb.

A row of `extra` may leave out `key`, which makes it an action of the panel alone, never bound,
listed in no key panel, and found by name in the panel. It still needs an action and a
description.

The verb's action is run the way every verb is, through the root's dispatch to the plugin's
surface method of that name, now handed the choice's value as its argument. A verb with no
choices is handed nothing, as before.

## Phases

1. The contract and the mechanism. `lib/surface.lua` validates the four fields and the keyless
   row, `lib/hints.lua` carries them onto the panel's rows and leaves keyless rows out of the key
   panel, `host/actionpanel` filters by `applies`, opens a level for `choices` and `confirm`, and
   steps back on Backspace, the root hands the panel a way to call the open plugin's surface, and
   the dispatch forwards a value. The popover draws section headings and a level's title. Proved
   on Workspaces and Display Profiles, Return applying and their levels moving into the panel.
2. The quick secondaries, Copy in Text Case and Emoji, Reveal in Finder in File Search, Copy in
   the clipboard, each a declared `secondary`.
3. The migrations, one plugin at a time, split in two on 2026-10-30.
   - 3a, the plugins the contract fits as it is. The provider levels of VPN and Tmux Sessions
     became a Provider and a Terminal choice. Speedtest's settings page became choices under Run
     and History, Name this network a verb opening its field, and its clears confirms. Caffeinate
     gained Stay awake for, the common spans as choices. File Search's verbs that act on one
     entry name `applies`, the secondary among them. Three small additions came with it, a choice
     may be disabled, the secondary may carry `applies`, and the root asks the plugin owning the
     context rather than the list showing, so a hosted list's verbs are answered by their tool.
   - 3b, `stays`, a choices level that stays open with the mark moving as a choice is made, for
     Browser Tabs' browsers level and Olm Plugins' toggles.
   - Not moved, as proposed. Processes' confirm guards Return itself, which a confirm in the
     panel cannot replace, and the clipboard's manage history takes a typed duration that fixed
     choices cannot express. Wi-Fi's join is its Return and every row offers nothing beyond it, so
     there was nothing to move. Forget network is a new action and follows with the others.
4. Olm's own actions on any row. On a plugin's row in the launcher, Enable or Disable through the
   staged switch in `lib/pluginswitch.lua`, and Show keys. Theme and Placement as submenus from
   any list.
