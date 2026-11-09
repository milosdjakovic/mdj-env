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

2026-11-09 16:10. The tool popups' frame was `chrome`, the same as the bar and the terminal inside it, so the 4px padding and the 6px inner corner could not be seen, and the bar padded 12 on the right, putting the x 18pt from the top and 25pt from the right. The frame is now `canvas` around one `chrome` card at 6, and the bar pads 10 left and 5 right. Measured at zoom 1.2, the x's centre sits 42px from the top and 43px from the right.

2026-11-09 16:25. The `canvas` frame of 16:10 is taken back the same day. Its 4px rim read as a lighter border around the popup, which Milos did not want, so the frame is `chrome` again, one surface with the card. The bar's 10 and 5 padding stays.

2026-11-09 17:35. On the rail the agents were full width rows with a flat hover while the spaces were 32px cells, and the window buttons sat at [14, 15], above the tab row's middle. Agents now draw the spaces' cell, the buttons moved to [10, 20], and the rail narrowed from 76px to 60. The button positions were worked out from Herdr's own (x + 64) / zoom rule in the tabs mod rather than measured, since this shell has no screen recording grant and `herdr-app shot` leaves the buttons out.

2026-11-09 17:55. The 17:35 entry's guess at the buttons was off. A screen capture Milos took showed them 1pt below the tab row's middle and 19pt from the first tab against 10.5pt from the left edge. They moved to [9, 19] and the rail to (x + 52) / zoom, 51px, so both side gaps are the 8px used everywhere. The rail's numbered cells were taken back: centred 32px cells looked off beside left aligned rows, and a space's `·` for nothing to report read as a stray mark. Rail rows are now the full rows cut to the leading box, and the `»` text is a chevron in a 28px button.

2026-11-09 18:15. The left aligned rail of 17:55 left the buttons as 28px squares beside rows that ran the rail's width, which Milos found a poor use of the space. Removing the window buttons is not possible, since Herdr's types say the macOS traffic lights always stay. The rail items are now pills the width of the buttons with their content centred, an agent shows one slot that switches between its program icon, spinner, check and `!`, and a space shows its avatar with the same slot beside it.

2026-11-09 18:25. The space's state slot on the rail is taken back the same day. With the agent showing the same state below it, two indicators left Milos unsure which to read, and the avatar sat off centre. A space's pill now holds only its avatar, centred.

2026-11-09 18:35. The brand bar padded 14 on the right and the Agents sort was a bare 14px icon, so the sidebar button, the Spaces `+` and the sort stood at three different distances from the edge. All three are now 26px boxes 4px in.

2026-11-09 18:50. Rail pills the width of the window buttons were turned down by Milos. The rail is now 36px of 28px cubes, the pane moving left under the buttons while the tab bar pads itself past them, which needed the sidebar's `min` lowered from 44 to 36 and the tabs' padding rule changed from Herdr's `(x + 64) / zoom` to `(x + 52) / zoom + 4`.

2026-11-09 19:05. Three fixes from a screenshot of Milos's. The pane and the files panel stood 16px apart, `work-body`'s gap of 8 on top of the two 4px paddings, so the gap is 0. The pane header's spinner, a bare 12px icon, stood 6px from the side and 9 from the top and repeated the tab's, so it is gone. The window buttons at [9, 19] had 8pt either side and 20pt above and looked cramped, so they are at [19, 19] with the first tab 19.5pt past them, the tabs' padding rule now `(2x + 52) / zoom - 1.5` less the sidebar, the 1.5 measured.

2026-11-09 19:15. The resize bar between Spaces and Agents kept its open sidebar widths on the 36px rail, 44px when hovered, and ran past both 4px strips. On the rail it is now 16px, 28 when hovered.

2026-11-09 19:25. The resize bar sat in the middle of a 10px grip, 3px from the first agent row and 7 from the Spaces list's edge. The grip is 16px with the bar 8px from the rows either side, measured from the bar's edges rather than its centre.
