# Herdr app

The Herdr desktop app, Herdr.app with bundle id `dev.herdr.app`. It is not the herdr
multiplexer, which `dotfiles/herdr` configures. This package carries the app's two theme
files and the terminal colours a pane is sent, `terminal-colors.zsh`, all painted from
`theme/palettes`, its `settings.json` and `keys.json`, and eleven mods of
our own, `mdj-popup`, `mdj-git`, `mdj-files` and `mdj-find`, and seven copies of shipped mods
for the `mdj` layout, where the panes are the only rounded cards and everything else sits on the
canvas with as little padding as it can take. `mdj-pane` is the `pane` header with its top
corners rounded to match its card. Its split, zoom and close buttons are the tab's close button, an 18px box with a 12px icon, and the header pads 6px on the right, so in its 30px height each sits 6px from the top, the bottom and the side. `mdj-brand` is `workspace-chrome` without the Herdr logo, and
it serves the sidebar's top bar and its footer. `mdj-tabs`, `mdj-status`, `mdj-spaces` and
`mdj-agents` are `tabs`, `workspace-status`, `spaces` and `agents`, and `mdj-menu` is `menu`, the right-click menu the tabs and spaces open, its rows built like theirs, 4px apart with no divider, and no row marked until the arrow keys move. It opens with `frame: "none"` and draws its own card, since Herdr's popup frame takes no radius. Every floating surface, this menu and the tool popups, has the pane card's outer radius of 10px, and whatever sits inside its 4px padding has 10 less 4, 6, so the curves run parallel. The menu's soft shadow has 4px of room inside a popup 8px wider than the 200px card. Each paints `canvas`
instead of `chrome`, draws no edge line, and has its padding cut. Every space between cards and the window edge is 8px, made of two halves. Herdr clips whatever a block draws at the block's edge, so a selected row's shadow needs room inside its own block. A scroll area clips too, so the room has to be inside it. Padding the mod's root outside the scroll area was tried on 2026-11-09 and the shadow was still cut at the row's own edge. The layout therefore pads the root by 4px and leaves the root gap at 0. Each list pads its scrolled content by 4px, the tab strip pads inside its scroll area, and the bar pads the buttons beside it. `main` and `panel` each pad 4px, with the panel's card look moved onto `panel-body`. `work-body` has no gap, so the pane and the panel stand 8px apart, the two 4px paddings, as everything else does. The pane header shows no spinner, since the tab and the agents list do, and its done dot sits in an 18px slot like the buttons. The pane card's own `"shadow"` is still cut at the pane's edge whatever room `main` leaves, so Herdr clips a pane's shadow to the pane, and no mod can reach it. The sidebar is 276px, 268 of rows plus the two 4px strips. The brand bar is 33px and the footer 60px, each taking its 4px at the window edge. The brand bar's sidebar button, the Spaces `+` and the Agents sort are each a 26px box 4px from the sidebar's right edge, so they stand in one column, with search beside the sidebar button. A tab sits 8px below the window top and 8px above the pane, and lines up with the pane's left edge. Spaces and Agents are split by an invisible grip at the top of `mdj-agents` that fades in and widens on hover. The grip is 16px with its 4px bar 4 from the top and 8 from the bottom, so with the Spaces list's own bottom 4 the bar's edges stand 8px from the rows either side, the gap between cards. The layout's own boundary drag jumped under it, so `sidebar-lists` is not resizable and the two lists drive `layout.resize` on `spaces` themselves, through shared state, dividing by the zoom because the pointer is in window points and layout px are not. Both lists fade into the canvas at an edge that has more to scroll to. Neither is a scroll area, for the reason the tab strip is not one below. Each mod draws its rows at its own offset, moved by the wheel and kept inside what the content leaves, so the fades always match the rows. There is no scrollbar. The fades are eased in 1px steps and hang off each panel rather than the list, and the bottom one runs 10px past the panel, because a panel stops a few points short of its block and its rows draw on into that strip whatever is clipped. Every tab, panel button and side-list row is 28px tall with 7px corners. Its leading icon sits in an 18px box 5px from the left, top and bottom edges, the space avatar filling that box, painted from the theme slot its stored colour names with its letter in `background`, since only `theme/palettes` may carry a colour value and a 14px program icon centred in it, then an 8px gap before a 13px name, so a tab and a side-list row are built the same way. The "Spaces" and "Agents" headers, machine headers, agent group names and the `mdj-popup` title are 13px too, the headers and group names in `dim`, the popup title in `foreground`. Measured on 2026-11-09 at zoom 1.2, a selected tab and a selected space are both 67 pixels tall with the same shadow, pixel for pixel. The close button on the right is the same 18px box, 5px in. A selected tab, space or agent, and an open panel button, take the pane's own look, `background` and `shadow_sm`, drawn as a layer under the row's content and shown at once. A 180 ms fade on selecting was tried on 2026-11-09 and taken out the same day. A hovered row that is not selected gets `background` at half strength and no shadow, so hovering never looks like selecting, and every button on the tab bar hovers the same way. Rows in Spaces and Agents are 4px apart, as tabs are. The pane card has no shadow, since Herdr clips it as said above. `sm` is used rather than `md` because it reaches about 4px, which fits the room above, while `md` reaches about 9px below and was cut. The tab block is 37px with the tabs at its top, 4px in, and the `work` column has no gap. The layout hides `status`. On macOS the window buttons sit at `traffic_lights` [19, 19], in window points, measured on 2026-11-09 at zoom 1.2 to put their middle on the tab row's and leave them 19.5pt from the window's top, its left edge and the first tab alike, a cell of their own. At [9, 19] the even 8pt sides against 20pt above read as jammed into the corner. The collapsed sidebar is a rail of 28px cubes in the 4px strips, 36px, with the layout's `min` lowered to match, since Herdr held it at the old 44. That is narrower than the buttons, so the pane moves left under them and `mdj-tabs` pads the tab bar to start x past the buttons' 52pt, `(2x + 52) / zoom - 1.5` less the sidebar, the 1.5 measured, so the tabs stay where they were. Each cube is centred: a space shows only its avatar, an agent one slot that is its state, its program's icon while idle, the spinner while working, a check when done and a `!` when blocked, since the agents already show every state and a second indicator on the space only raised the question of which to read. The `+` above, the chevron that opens the sidebar and the footer's buttons are the same cubes. The resize bar between the lists keeps inside the cubes' 28px there, 16px wide and 28 when hovered, against 28 and 44 on the open sidebar. Herdr keeps the macOS window buttons whatever the layout says, so they cannot be removed. The wheel scrolls the tab strip and never switches tabs, and the strip fades at an edge with more tabs to scroll to. The tab strip is not a scroll area either. A scroll area tells a mod no offset, and fades kept from wheel deltas drifted on 2026-11-09, covering the first tab at the start and missing a cut tab, because the strip moves by itself when a tab is selected. So `mdj-tabs` places the row at its own offset, measured in window points from each tab's size report and set in layout px divided by the zoom, and brings a newly selected tab into view. The strip clips 4px past its own box, measured, so the right band sits at `right(-4)` to reach the cut. A tab is at least four times as wide as it is tall. Its right-hand slot holds its status, the spinner or a dot, and the close button takes that same slot while the tab is hovered, so nothing moves. A space's close button is always laid out and transparent until the row is hovered. Both have their own hover. On light, `hover` and
`selected` equal `canvas`, so these copies use `chrome` for a highlight wherever the two match.
They are copies, so a Herdr update to the shipped mods does not reach them. The `mdj` layout itself is `layouts/mdj.json` here. Everything else under
`~/.config/herdr-app`, the shipped layouts, the clicks Herdr keeps in `layouts/.state`, the shipped mods, the guide, type files and state, is the
app's own and lives only on the machine.

## What is linked, and why the directories stay real

Every file here is linked file by file. `.config/herdr-app/themes/mdj-dark.json` and
`mdj-light.json`, `settings.json`, `keys.json`, `layouts/mdj.json`, and under `mods/` each mdj mod's `main.js` and
`mod.json`, with `mdj-popup/herdr-shim.sh` beside its own. Herdr keeps a layout's clicks, sizes and shown panels, in
`layouts/.state` rather than in the layout file, so the linked file is only written by an edit here. Which
layout the window shows is the machine's own, so a new machine shows `main` until
`herdr-app do layout.switch '{"name":"mdj"}'` is run once.

`NO-FOLD` keeps `~/.config/herdr-app`, its `themes` and `mods` folders, and each mdj mod folder
real directories. The app rewrites its guide, type files, layouts and frame on every start,
writes its shipped themes `atom-one-dark` and `win98` beside these two and its shipped mods
beside ours, and writes a `gpui-kit.d.ts` and a `jsconfig.json` into every mod folder. A fold
would send all of that into this checkout, so those two files stay real on the machine and are
not tracked here.

`settings.json` survives the app's own writes. The zoom keys and the settings screen save it,
and the save goes through the link rather than replacing it, which was checked on 2026-11-09 by
zooming in and out and finding the link intact with the new contents in this checkout. The app
reorders keys when it writes, so a diff after using the settings screen can be only that.
`keys.json` is written by the app only on `app.reset`, which sets it aside as
`keys.json.reset-<time>`, so after the escape hatch the link has to be made again.

## The mods, and why the launch code is written three times

The keys under the `alt-z` prefix, `alt-z alt-g`, `alt-z alt-f` and `alt-z f`, run
`mod.open` on `mdj-git`, `mdj-files` and `mdj-find`. Each launcher starts one of the herdr
tools in `~/.config/herdr/tools` in a hidden `hc` terminal in the focused pane's folder, opens
it as a titled dialog with `mdj-popup` drawing the title bar, and closes itself. The dialog opens with
`frame: "none"` and its layout draws the frame, 10px corners padded 4, around one card at 6 holding the bar and the terminal, frame and card both `chrome` so the popup is one surface. The bar pads 10 on the left and 5 on the right, so its close button is 9px from the popup's top and right alike, and the title starts where the x's stroke ends, measured on 2026-11-09. The popup
closes when the tool exits, and `mdj-popup`'s `close` ends the terminal however it went.

The tools call the herdr multiplexer's CLI. `herdr-shim.sh` stands in for it through
`HERDR_BIN_PATH` and answers each call with `hc` or `herdr-app`, typing into the calling pane
with `hc send`, opening a tab with `tab.new`, and queueing notifications that `mdj-popup` posts
as app toasts when the popup closes. The tools themselves are unchanged and still serve herdr.

The app refuses a module import that resolves outside the mod's own folder, and a linked
`launch.js` resolves into this checkout, so a shared launch module cannot be imported. The
launch code is therefore written out in each launcher's `main.js`, and a change to one is a
change to all three. A launcher does nothing unless it was opened as an overlay, because
`herdr-app check` runs `init` and would otherwise start the tool in a terminal nobody sees.

The stow step adds this package wherever the `herdr` piece is on. There is no piece of its own.

`settings.json` picks the pair with `"theme": { "light": "mdj-light", "dark": "mdj-dark" }`.
The files are named for the half they fill rather than for a palette, so that line never
changes, which is the same reason Ghostty's are named this way.

## The generated files carry no banner

`theme-emit` writes both files from `theme-map`. Never edit the JSON. Change the palette or the
map and run `./src/check-theme.sh`.

Herdr reads a theme with a strict schema, and an unknown field makes it reject the whole layout
with `layout.error`. That was found on 2026-11-08 when a `_generated` field was tried. JSON has no
comment, so the files cannot say they are generated. `src/check-theme.sh` knows they are because
the emitter lists them, and it exempts a `.json` file from the banner rule for that reason.

## What a program in a pane is told

The theme colours what the app draws, not what a program inside a pane is told. Herdr's core
answers a colour query from its own defaults, a dark grey page whatever the half, and the theme
holds exactly sixteen slots. So Claude Code and Neovim, which both ask the terminal for its page,
chose the dark half on the light page, and the Claude statusline grey in slot 17 came out navy.

`terminal-colors.zsh`, generated by the same emitter from the same map, holds every colour
Ghostty's theme sets, twenty slots, ink, page and cursor, as escape sequences for each half.
`dotfiles/zsh/.zshrc.custom` sources it in a Herdr app pane, where `__CFBundleIdentifier` is
`dev.herdr.app`, and sends the half macOS is on at a prompt when it has changed. A pane catches a
light and dark switch at its next prompt, so a program already running keeps the old half until
it exits, and all twenty three colours move together so that pane stays wholly on one half. A
pane opened before the hook existed gets it in a new shell. `decisions/herdr-app-colors.md` has
the measurements and what was turned down.

To check a pane, ask it. `printf '\e]11;?\e\\'` from a script reading the reply off the tty
should answer the `background` role of the half macOS is on, which `./src/check-theme.sh --show` prints.

## Reloading

Herdr watches its folder and applies a theme change within a second. A change through the link
is a change to the target, so the window follows a regenerated file. If it does not, run
`touch -h` on the link. After any change, check that `~/.config/herdr-app/layout.error` is absent.
`herdr-app shot file.png` captures the window to confirm it by eye.

Keys and settings apply the same way, and a rejected file leaves the old one running with the
reason in `keys.error` or `settings.error`, so `herdr-app status` must show no errors after an
edit. A mod does not reload when the file behind its link is saved, since the app watches the link, so run `touch -h` on the mod's `main.js` link after an edit, as with a theme. A change to one is done only when
`herdr-app check ~/.config/herdr-app/mods/<name>` passes for it.
