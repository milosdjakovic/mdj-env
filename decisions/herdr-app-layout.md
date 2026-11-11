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

2026-11-10 00:03. A space avatar's M sat left of its square in a screenshot of Milos's. Measured, the ink stood 14 device px from the left edge and 16 from the right for R and T, and 11 against 14 for M, since the UI font is proportional and gpui centres a glyph's advance, not its ink. The letter is now set in the terminal font, read from `settings().font_family` in the mod, which a mod gets under that name and not as `font`, the key `settings.json` uses. After it, every letter is within one device px of centre both ways. The colours were asked about in the same message and needed no change. They are the theme's `ansi` slots, which `theme/palettes/aura.toml` paints, so Aura's dark or light colours follow the half.

2026-11-10 00:05. Correction to the entry above. The monospace letter was not centred either, and it was bold, which Milos had not asked for. Its threshold measurement had misled, so the ink's centre of mass was measured instead, on both screenshots and a fresh one. Every letter sat about 1.2 device px left and 0.7 high in either face, a fixed offset in how the text box is placed rather than the letter's shape. The letter keeps the terminal font at regular weight, `font_bold` dropped, and is moved by `relative().left(0.5).top(0.3)` in layout px. After it, the centres are within half a device px across, and the box measured on the ink is 12 against 12 or 13 vertically.

2026-11-10 00:10. The chevron that opens the collapsed sidebar moved from the foot of the rail to the head of the tab row, asked by Milos as [window buttons] [>] [first tab], so it sits up where the open sidebar's own button is. `mdj-tabs` draws it with the tab bar's own button, a 28px cell 19.5pt past the window buttons where the first tab stood, and the tabs follow 8px after, the strip's 4 and the bar's gap of 4. It shows whenever the sidebar is narrower than 160px and not hidden, and opens it to `sidebar.width` or 276 as `mdj-brand`'s toggle does. The rail no longer has a chevron at its foot, and the brand bar's toggle is gone from the rail on every platform rather than only on macOS, so the tab row's chevron is the one way back.

2026-11-10 00:13. The tab row's button that opens the rail is Herdr's own sidebar outline rather than a chevron, asked by Milos so the icon stays the sidebar one, and the brand bar's toggle on the open sidebar is that outline with its left column filled, so the two states read apart, the filled column meaning the sidebar is shown. Herdr ships no filled variant, `panel-left.svg` being the same outline at a heavier stroke. An svg of ours in `mods/mdj-brand` was tried and rejected the same hour. Herdr drew nothing for it while it was the stow symlink, with or without an XML comment, and drew it at once as a plain file copied into place, so an asset under `mods/` has to be a real file, which stow cannot provide. A symlinked `main.js` loads, so only assets are affected. The fill is instead a div over the svg's column at 15/24 of the viewBox, coloured as the button's text is and following its hover through `on_hover`.

2026-11-11 13:57. `alt-z b` folds the sidebar to its rail instead of hiding it, asked by Milos. It was `layout.toggle:sidebar`, which hides the whole node. A key can reach a mod only through `mod.open`, so a new `mdj-sidebar` mod opens as a 1 by 1 popup, runs `mdj-brand`'s toggle, written out again since a mod cannot import another, and closes itself. A sidebar found hidden is shown rather than folded. Checked live the same minute by toggling it there and back with `herdr-app do mod.open`. `cmd-b` was left on `layout.toggle:sidebar`, since only the prefix key was asked about.

2026-11-11 14:10. Folding the sidebar moved the rows, which Milos wants to stay put. The Spaces header grew from 26px to 32 on the rail, and the Agents list dropped its 26px header, its group headers and its nesting, so the rail was a flat list from a different top. Now the rail keeps the Spaces header at 26 with a 26px `+`, leaves the Agents header and each 30px group header as empty space, and nests and groups as the open list does, a sub-agent drawn as a cube with its state. A folded group's agents are therefore hidden on the rail too, since showing them would move the rows below. Checked by screenshot at zoom 1.2, where every space and agent cube sits at its open row's height.

2026-11-11 14:20. An agent's program icon shrank on the rail, 14px there against 16 in the open row, which Milos noticed. The rail cube now draws it at 16 as well, inside the same 18px slot. A sub-agent's icon was already 14 in both.

2026-11-11 14:35. `cmd-0` returns to the zoom meant as the default, 1.2, rather than Herdr's 1.0, asked by Milos. The zoom keys write into the linked `settings.json`, so its zoom drifted to wherever the keys last were, 1.0 by this afternoon against the 1.2 committed, and Herdr's reset ignores it anyway. Herdr has no command that sets a zoom, so a new `mdj-zoom` mod runs `app.zoom_reset` and then `app.zoom_in` once per 0.1, the step measured the same minute, and the default is a `ZOOM` constant in that mod. Checked live from 1.4 and from 1.0, both landing on 1.2 with `settings.json` following.

2026-11-11 14:15. The 14:35 entry's stepping cannot reach a zoom like 1.14, which Milos asked about. Herdr takes 1.14 written into `settings.json` and applies it live, so `mdj-zoom` now writes `ZOOM` there instead. Writing with the mod's own `fs` was tried and did nothing, since that `fs` writes only under `~/.config/herdr-app` and the file is a link into this checkout. The mod runs `sed` on the link's target through `hc run` and `touch -h` on the link, which keeps the link and the file's other lines. Checked live from 1.14 back to 1.2. The 14:35 entry's time was written ahead of the clock, it came before this one.

2026-11-11 14:25. The default zoom is 1.14, the `ZOOM` in `mdj-zoom` and the zoom in `settings.json`, asked by Milos. In the same ask the interface text was made the terminal's size: every `text_size(13)` in the mdj mods is now 14, matching `font_size` 14 in `settings.json`, so at any zoom a row's name and a pane's text are both 15.96px at 1.14. The smaller secondary sizes, timestamps, badges and the sort menu, were left as they were. The terminal's `font_size` had moved from 15 to 14 through the settings screen at 14:09 and is kept, since the text was matched to it.

2026-11-11 15:05. The 14:25 entry was wrong to call the interface text the terminal's size. Both were 14px, but the interface is Herdr's own sans and the terminal MesloLGS, which draws taller, 31px against 28 for a word with an ascender and a descender, and the pane header was still 12px, which Milos pointed out. Milos chose to keep the two fonts and match what is seen. Every 14px in the mdj mods and the pane header's 12 are now 15.5, and measured again a capital is 26px in the pane header against 25 in the terminal, a round C overshooting by one. Using MesloLGS as `ui_font` was offered and turned down, since it would make the tabs and the sidebar monospace.

2026-11-11 15:10. The 15:05 entry's 15.5px read too big beside the terminal, which Milos saw at once. Matching capitals was the wrong measure, since size is read from the lowercase letters. At 14.5 a lowercase letter is 18px in the sidebar and 18px in the terminal at zoom 1.14, so every interface text that was 15.5 is now 14.5, the pane header with it.

2026-11-11 15:20. The interface still read much bigger than the terminal at 14.5 against 14, which Milos saw, though their lowercase letters measured the same, 18.2px against about 18.1 by row coverage of the stems. Herdr's sans is darker and wider than Meslo, so equal letter height does not look equal. Taking Milos's suggestion, the interface text went down to 14 and the terminal's `font_size` up to 15, which measures 17.9px against 19.4. Measuring whole pixels with a threshold had read 18 for both 14 and 14.5, which is why the earlier entries could not tell them apart.

2026-11-11 15:25. The interface text went down a half step more, from 14 to 13.5, asked by Milos after looking at 14 beside the terminal's 15. The terminal stays at 15.
