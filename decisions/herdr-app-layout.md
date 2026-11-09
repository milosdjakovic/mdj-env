# Herdr app layout

Status. The Herdr desktop app runs the `mdj` layout from this repository, with copies of the
shipped mods that make every tab, list row and menu item one shape, and shadows, fades and
corners that are measured rather than assumed.

## Now

`dotfiles/herdr-app` carries `layouts/mdj.json`, linked into `~/.config/herdr-app/layouts`, and
the `mdj-*` mods it names. A tab, a space, an agent and a menu item are 28px rows with an 18px
leading box 5px in and 13px text. A selected one takes the pane's look, `background` and a small
shadow, shown at once, and a hovered one takes `background` at half strength with no shadow.
Herdr clips whatever a block or a scroll area draws at its edge, so the layout pads the window by
4px and each mod pads 4px inside its own clip, which is where a shadow draws. The tab strip and
both side lists are not scroll areas. Each mod draws its rows at its own offset, so the fades at
an edge always match the rows. Every floating surface, the right-click menu and the tool popups,
draws its own frame with the pane card's 10px outer radius, and what sits inside its 4px padding
has 6px corners. `dotfiles/herdr-app/AGENTS.md` holds every measurement.

## Rejected

- **A soft shadow under each pane card.** 2026-11-09 13:40. Herdr clips a pane's own shadow to
  the pane, measured on a screenshot with 4px of room left around it in `main`. A shadow on the
  `main` block instead would wrap a split tab's panes as one card. Removed.
- **`md` shadows.** 2026-11-09 13:15. They reach about 9px below, more than any room a block
  leaves, and were cut. `sm` reaches about 4px.
- **Room for a shadow outside a scroll area.** 2026-11-09 13:30. The list's scroll area clipped
  the selected row at its own edge whatever padding sat around it.
- **Fades kept from wheel deltas over a scroll area.** 2026-11-09 14:05. A scroll area tells a
  mod no offset, and the strip moves by itself when a tab is selected, so the fade covered the
  first tab at the start and missed a cut tab, reproduced with ten test tabs.
- **Switching tabs with the wheel over the tab bar.** 2026-11-09 13:55. Asked to be taken out.
- **A fade on selecting.** 2026-11-09 14:50. A 180 ms opacity fade was built and taken out the
  same afternoon, asked for.
- **Dividers in the right-click menu.** 2026-11-09 14:00. The layout separates surfaces by
  space, never by a rule.
- **The shipped avatar hues.** 2026-11-09 14:45. Fixed colour values in a mod, which only
  `theme/palettes` may carry.

## Log

- 2026-11-09 12:30. Estimated, anchored to the session's first screenshot. Tabs given an always
  laid out close button, shown on hover, and selected rows given the pane's background and shadow.
- 2026-11-09 13:12. Every tab and side-list row measured on a screenshot at zoom 1.2, 67 pixels
  tall with the same shadow, pixel for pixel, after their leading icons were put in one 18px box.
- 2026-11-09 13:40. The window padding split into two 4px halves, the layout's and the mod's
  inside its clip, after the room was first given outside the scroll areas and did not help.
- 2026-11-09 14:20. The tab strip, then both side lists, moved off scroll areas onto their own
  offset. The strip clips 4px past its own box, measured with the fade painted red, so its right
  band sits 4px further out. Sizes are reported in window points and positions set in layout px,
  divided by the zoom.
- 2026-11-09 14:43. `layouts/mdj.json` moved into the package and linked, so another machine gets
  the layout. Herdr keeps clicks in `layouts/.state`, so the linked file is written only by an
  edit here. A new machine has to switch to it once.
- 2026-11-09 14:50. Floating surfaces given one outer radius of 10px with 6px inside a 4px
  padding, the tool popups through `frame: "none"` and a layout frame, the menu through its own
  card.
