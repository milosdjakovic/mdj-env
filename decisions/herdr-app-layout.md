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
- **Keeping every rail cube where its row was.** 2026-11-15 15:39. Asked for on 2026-11-11 and
  undone on Milos's word. Blank headers on the rail, and a Spaces list at its open height, left
  holes between the cubes that read as broken, and the alignment only showed at the moment of
  folding. Corrected 2026-11-15 16:05, the rejection was of the blanks, not of the alignment,
  which Milos wants kept. See the two entries below.
- **Packing the rail, with colour bars for group headers.** 2026-11-15 16:05. Built at 15:39 and
  taken out the same afternoon, asked by Milos. The cubes moved on folding, and a bar read as a
  divider rather than as the agents' group.
- **Herdr's shipped icons as they come.** 2026-11-15 15:39. They mix Lucide at stroke 2 and 1.5
  with a 16px set at 1.3 and a typed `+`, so Files beside Changes and the tab `+` beside the
  Spaces `+` drew at different weights.
- **A zoomed pane's border through `layout.set`.** 2026-11-15 20:14. Herdr's pane frame takes
  `border` and `focus` and nothing for a zoomed pane, so a mod would have to swap the border on
  zoom with `layout.set`. Tried once by hand. It writes the tree through the link into this
  checkout, reformatted, and deletes `layouts/.state/mdj.json`, the sidebar's width and fold and
  the shown panel with it. Both were restored from copies.
- **A search or palette button in the brand bar.** 2026-11-16 14:22. Search was the shipped
  bar's, and it vanished on the rail. Keeping it there, or adding one for the palette, was
  turned down with Milos, since `cmd-p` and `cmd-shift-p` open both and git, files and find have
  no button either. VS Code's one box, go-to with `>` for commands, would be an `mdj-picker`
  copy and is not built.
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

2026-11-15 15:39. The rail packs its cubes, asked by Milos after seeing the holes, which reverses
the 2026-11-11 14:10 entry. On the rail the Spaces list resizes to fit its cubes through
`layout.resize`, keeping the open height in shared `mdj.spaces.open` and putting it back on
opening. The grip is not drawn there and 8px stand in for it. The Agents header takes no room, and
a group header is a 14 by 3px bar in an 8px row, painted from that space's avatar slot in
`space.colors`, a priority section from its state, pinned in `dim`, so the agents under it read
as that space's. Checked by screenshot, folded and open.

2026-11-15 15:39. Every interface icon in the mdj mods comes from one Lucide set at stroke 1.75,
in `dotfiles/herdr-app/icons`, asked by Milos. Herdr draws nothing for a linked svg, measured on
2026-11-10, but a real file in a folder of ours draws, measured today with a copied file in
`mods/mdj-icons`, which has no `mod.json` and raised no error. So `src/setup-herdr-app.sh` copies
the set there and removes what the source no longer has. The typed `+` in the tab row and in a
machine header are the `plus` icon, the pane buttons are Lucide's columns-2, rows-2, maximize-2,
minimize-2 and x, Changes is git-compare, and the sidebar toggle is panel-left at 14px with its
fill moved to match. The spinner stays Herdr's, since it is an animated arc rather than an
outline, and so do program icons and the Windows window buttons.

2026-11-15 16:05. The 15:39 rail entry is undone, asked by Milos, who wants no row to move on
folding and an agent icon rather than a divider. The Spaces list keeps its open height again, so
`fitRail` and the shared `mdj.spaces.open` are gone, and the grip is back on the rail. The Agents
header keeps its 26px on the rail and holds the sort button as a cube, as Spaces holds its `+`.
A group header keeps its 30px and shows Lucide's `bot` at 14px where the name sits, in the space's
avatar slot, which is the one icon added to the set for it. Checked by screenshot, rail beside
open, every cube on its row's line. The resize the 15:39 version had made was put back by hand
with `layout.resize` to the 144px it had saved.

2026-11-15 16:30. Milos saw the icons still at different weights after the 15:39 entry, and they
were. The stroke was one number in every file, 1.75 in a 24 unit box, but it scales with the size
an icon is drawn at, and the mods draw at 10, 11, 12, 13 and 14px, so a line came out between 0.73
and 1.02 layout px. The 15:39 entry was wrong to call that one stroke. `setup-herdr-app.sh` now
writes a folder per size with the stroke that makes every line 1 layout px, `LINE` in the script,
and each mod names the folder for the size it draws. In the same pass the tab `+`, the Spaces `+`
and the Agents sort were painted `dim` beside search, the sidebar toggle and Files in `muted`, which
read as a thinner line too, so all icon-only buttons are `muted`. Checked by screenshot.

2026-11-15 20:14. Asked by Milos, a zoomed tab no longer shows the shipped " Z" after its name.
`mdj-tabs` draws the pane header's zoom icon, `maximize-2` at 12px in `accent`, in an 18px box
after the name. Checked by screenshot. A purple border round the zoomed pane was asked in the same
breath and is not built, see the rejection above.

2026-11-15 20:25. Milos chose one look for focused and zoomed, so the layout's pane `focus` is now
1px in `accent`, where it was 0 in `background`. A zoomed pane is always the focused one, so it
takes the border without a mod. Checked by screenshot, no `layout.error`.

2026-11-15 20:35. Milos saw the focused border shrink the tab's content, since Herdr draws a frame
border inside the pane and the terminal loses its width. Every pane now carries a 1px `border` in
`background`, unseen against the pane, so focus swaps only the colour. `terminal_padding` went from
14 by 12 to 13 by 11 to give the text back its place. No `layout.error`. Not checked on a split
tab, which needs a pane opened and closed in the live window, left to Milos.

2026-11-15 20:50. Asked by Milos, to try. A tab's status and close button no longer take width.
They sit over the end of the name, 5px from the tab's right edge, behind an eased 20px fade in the
tab's own paint, and the zoom icon moved into the same overlay so a status could not cover it.
Checked by screenshot with a working tab, its name fading under the spinner. Hover was not checked,
since nothing here can move the pointer.

2026-11-15 21:00. The overlay's solid part cut the tab's right corners square, since its paint was
a child layer and a clip does not follow rounding. The tab's colour is now mixed from the theme in
the mod and set on the rounded box. Checked by screenshot on a selected tab with a dot.

2026-11-15 23:41. Asked by Milos. `cmd-w` closes the focused pane rather than the tab, and
`cmd-alt-w` closes the tab. Herdr already closes a tab with its last pane, checked by closing the one
pane of a test tab, so `cmd-w` on a lone pane still closes its tab. Closing the shown tab now goes
back to the tab shown before it instead of the neighbour Herdr picks. `mdj-tabs` keeps each space's
tabs in the order they were shown and, when the newest is gone and Herdr shows another, selects the
newest one left, holding off for a second while that selection lands. It lives in `mdj-tabs`
because that mod draws on every change of tabs, so a tab closed by a key, the close button, the menu
or a program exiting is caught alike. Checked live both ways, a tab opened from the first of four
then closed back to the first, and a tab reached from the fourth then closed back to the fourth.

2026-11-15 23:47. Asked by Milos. A tab's only pane no longer shows the accent focus border, and
a split tab's focused pane still does, zoomed or not. Herdr's frame has one `focus` for every pane
and `lone: false` would drop the header and the card too, and `layout.set` is rejected above, so
`work-body` now holds a `main-stack` stack of the pane block twice, `main` with the accent and
`main-lone` with `background`, and `mdj-tabs` runs `layout.select` on it by the shown tab's pane
count. `layout.select` writes only `layouts/.state`, and the sidebar and panel entries there were
checked intact after it. Checked by screenshot on a lone pane, a split tab and a zoomed one, no
`layout.error`.

2026-11-15 23:57. Asked by Milos, to try. Vim-like navigation beside Herdr's keys, none of
which changed. `cmd-ctrl` with h and l for tabs and j and k for spaces, shift with h and l moving
the tab, and `cmd-alt` with j and k for agents. `cmd` is in both so a pane program never sees
them, `alt` and `ctrl-alt` alone reach Neovim, where LazyVim moves lines on `alt-j` and `alt-k`.
`cmd-alt-h` stays macOS's hide others. Nothing in the Hammerspoon config claims either pair.
`cmd-alt-enter` was added for `pane.zoom` beside `cmd-shift-enter`. Keys loaded with no error and
`tab.move` with `by` was checked from the command line, the keys themselves left to Milos.

2026-11-16 00:02. Changed by Milos the same night. Tabs and spaces moved from `cmd-ctrl` to
`cmd-shift` with hjkl, agents stay on `cmd-alt` with j and k, and the tab moves stay on
`cmd-ctrl-shift` h and l. `cmd-alt` for tabs and spaces was turned down because `cmd-alt-h` is
macOS's hide others. `cmd-shift-l` was Herdr's own `layout.switch`, not a macOS convention, so it
moved to the free `cmd-alt-l`. Keys loaded with no error, the keys themselves left to Milos.

2026-11-16 08:08. Asked by Milos. `cmd-alt-h`, `app.hide_others`, is removed from `keys.json`,
so the chord is free in the Herdr app. Herdr's menu bar shows what `keys.json` binds, so the menu item
loses its key too, and an edited keys file never gets defaults added back. Nothing system wide was
needed, since Hide Others is each application's own menu item. Keys loaded with no error.

2026-11-16 08:15. Asked by Milos. The `alt-z` prefix is gone and every key is one chord. Panes
take `cmd-alt` with hjkl beside the arrows, freed by unbinding Hide Others, so agents moved to
`ctrl-alt` j and k and the layout switch to `cmd-ctrl-l`. The prefix keys moved onto VS Code's,
`cmd-b` folding the sidebar to its rail and `cmd-shift-b` hiding it, `cmd-shift-g` the git popup,
`cmd-shift-e` the files popup, `cmd-shift-f` the find popup, and `cmd-ctrl-w` closing the space
beside `cmd-w` for a pane and `cmd-alt-w` for a tab. Keys loaded with no error, and `mdj-sidebar`
was run twice from the command line, folding the sidebar to 36px and opening it again. The keys
themselves are left to Milos.

2026-11-16 14:22. Asked by Milos. The brand bar's search button is removed, so the open sidebar
shows only its toggle there, as the rail shows only the expand button in the tab row. No palette
button was added. `icons/search.svg` went with it, nothing else drew it.

2026-11-16 15:10. Asked by Milos. The selected row's accent border on a tab, a space and an agent,
and the pane frame's `border` and `focus`, go from 1px to 1.5px, and the icon line `LINE` in
`src/setup-herdr-app.sh` from 1 to 1.5, so a border and an icon's stroke are one width. The
tab's and the space's right-end overlay sit 1.5px in with corners 1.5 less, and `terminal_padding`
drops to 12.5 by 10.5 so the text stays where it was. Herdr took the fractional widths with no
`layout.error`.

2026-11-16 15:25. Asked by Milos. Every 1.5 of the entry above becomes 2, the borders, the icon
`LINE`, the overlay's inset and its corners, and `terminal_padding` goes to 12 by 10.

2026-11-16 15:45. Asked by Milos. No purple on any tab. The accent ring is gone from the selected
tab, space and agent, and the right-end overlay is flush with the row again. On dark the selected
row was the pane's own page, darker than the canvas, so it read as a hole. It now paints a new
theme key, `raised`, set by `theme-map` to the `dim` role on dark, a step lighter than the canvas,
and to the page on light, which is already lighter there, and hover is `raised` at half. The pane
frame and the icon `LINE` return to 1.5 from the entry above, and `terminal_padding` to 12.5 by
10.5. The pane's focus ring stays `accent`, since that was not a tab.

2026-11-16 16:00. Asked by Milos. The icon `LINE` goes to 1.25 to try it, and the pane frame's
`border` and `focus` back to 2 with `terminal_padding` at 12 by 10.

2026-11-16 16:10. Asked by Milos. The pane frame's `border` and `focus` go to 1.75 to try it, with
`terminal_padding` at 12.25 by 10.25.
