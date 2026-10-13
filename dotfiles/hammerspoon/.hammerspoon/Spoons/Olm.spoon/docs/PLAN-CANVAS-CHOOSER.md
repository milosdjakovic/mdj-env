# Canvas chooser backend, plan of 2026-09-06

## Goal

A second picker backend drawn on `hs.canvas`, selectable per configuration, with the
native `hs.chooser` backend kept and left as the default until the canvas one has been
lived with. The shape is Strategy, the providers are interchangeable policy and
`lib/chooser/init.lua` is the facade that names one, wired at the composition root. The
seam already exists and its own header says it was kept for exactly this, a config
`provider` field accepted and ignored because native is the only backend.

The reason to want a second backend is not styling. It is that `hs.chooser` is somebody
else's window and can never be a pane inside ours, so the three pane surface this
configuration is heading for, a list with a right side pane and a bottom pane in one
window, is not reachable from the widget we have. A canvas backend is the step that
makes it reachable, and a webview backend later is a third provider through the same
door.

## Evidence this plan rests on

Gathered 2026-09-06 by reading the tree and the history, cited so a builder can check
rather than trust.

The blast radius is two files. `Chooser.new` has exactly one live call site,
`host/stage/init.lua:233`. `host/actionpanel/init.lua` is the only other holder of a raw
instance, captured through the `decorate` seam at `lib/chooser/init.lua:117`, and it calls
only behavioural methods, `isShowing`, `refresh`, `selectRow`, `selectedItem`,
`selectedRow`, `query`, `setQuery`. Every plugin reaches the picker through the stage and
holds no instance at all.

The contract is eighteen names and one of them is dead. The stage and the action panel
between them use `show`, `hide`, `isShowing`, `refresh`, `query`, `setQuery`,
`setPlaceholder`, `setRows`, `selectNext`, `selectPrev`, `selectRow`, `selectedRow`,
`selectedItem`, `insertSelected`, `textBudget`, `textWidth`, plus direct field access to
`layout` and `matcher` and `paneFrames`. `activeTheme`, defined at
`lib/chooser/providers/native.lua:941`, has no caller anywhere in the tree and does not
enter the contract.

Half of the native provider is workaround rather than function. The 126 point row text
inset was measured through the accessibility API because the widget is a compiled nib with
no readable geometry, `lib/chooser/providers/native.lua:132`. Row hit testing reads the
accessibility tree because the widget renders rows at one height and settles to another,
`native.lua:610`. The caret is collapsed through the accessibility tree because there is no
field object and no caret api, `native.lua:836`. Placement is corrected by a thirty
millisecond timer that finds the window by title and moves it, `native.lua:333`. Width is
converted to a percentage macOS measures against the wrong screen, `native.lua:361`. The
highlight is discovered by polling every eighty milliseconds because there is no callback,
`native.lua:539`. All six exist only because we do not own the pixels, and all six leave
with a canvas backend.

The widget cannot resize while visible. `docs/PROBE-FINDINGS-2026-08-27.md` sections C2 and
C4 measured that a live window ignores both `rows` and `width`, and that each applies on the
next show of the same instance, so today a size change costs a hide and a show. Section A
measured a first show at 99 to 130 ms before anything is on screen, a reshow at 61 to 90 ms,
and a hide at about 30 ms. A canvas show is a draw.

The webview backend that was removed did not fail on architecture. `4884c6e` removed it for
having no live consumer, `11cbe1e` had already pinned menu search back to native as
noticeably snappier, and the run of fixes before that, `ba661b1`, `5e46895`, `33be562`,
`a9bbc9d`, are all one failure, the frosted backdrop rendering only while the webview was
the key window with a focused field. Its own plan named focus and paste as the riskiest
behaviour, since the native chooser restores the previous app for free and that is what
makes the clipboard paste land.

## What the canvas backend gains and what it costs

Gains. Width, height and position become live and free rather than a hide and a show.
Rows, icons, dimming, truncation and the active row marker become arithmetic we already
have written down in `DEFAULT_LAYOUT`. Click hit testing and highlight change stop needing
the accessibility tree and the poll. Focus never leaves the covered app, so the restore
that the webview attempt found riskiest simply does not arise, and the launcher's tenth of
a second wait for focus to come back, `host/launcher/init.lua:1021`, stops being needed
though it stays harmless.

Costs, and the first one is the whole risk. `hs.canvas` has no keyboard api at all, only
mouse tracking, so the field is an event tap we own. Caret blink is a timer. Caret position
needs true text measurement rather than the memoised per character sum at `native.lua:975`,
which runs about zero point seven percent high, invisible in truncation and visible as a
drifting caret. The long tail is the thirty or so editing behaviours a real field gets from
the responder chain, shift arrows, shift drag, double and triple click, Cmd A, the
clipboard three, Option and Cmd arrows, Option Delete, Cmd Delete, forward delete, and the
emacs bindings macOS honours in every text field. Call it four to six hundred lines to
reach the point where it stops being noticeable.

Two costs are permanent. Input method composition is gone, so no candidate window and no
dead key accents. Accessibility is gone, since a canvas has no tree, which also retires the
accessibility route our own probes currently use to drive a live chooser, so the probe
method changes with the backend.

One cost is a live hazard rather than a missing feature. Because the canvas never takes
focus, the frontmost app keeps receiving keys unless the tap swallows them, so the tap
returns true for nearly everything while the picker is open. `1ccab6f` is the fresh record
of what a lost key up or an overrunning callback costs on this machine, and nothing in this
configuration handles secure input anywhere, so a password field holding it means no typing
at all. That is a new failure mode, not one already guarded.

## Decisions

1. Native stays wired, stays the default, and is not modified beyond what phase one moves.
   The backend is chosen in one place, the composition root, and nothing above the facade
   ever learns which one is up.

2. The contract is written down and validated rather than left implicit in what the stage
   happens to call. Presence and arity, the discipline `3c8ad9d` gave the VPN provider
   contract. A provider that does not satisfy it is refused at load with a phrase naming
   the method and what it declares, not a bare name.

3. Pane placement comes back behind the facade before a second provider exists.
   `host/stage/init.lua:633` finds the Hammerspoon window titled Chooser, reads its frame
   and moves it with `setTopLeft`, and `host/stage/init.lua:130` carries its own copy of the
   atom's thirty millisecond settle delay. That is native specific code sitting above the
   seam. It is a leak today and it would follow a canvas provider into being broken, so it
   moves first, as a change that alters no behaviour.

4. The list owns its own canvas and prepends `CanvasPanel.surfaceElements` for the chrome,
   the second supported use `lib/panel.lua` documents and the one the clipboard preview
   already takes. It does not become a `CanvasPanel` content strategy, because that engine
   was built for a hint bar and a cheat sheet, static content with idle reveal timing and a
   four times a second state poll, which is the wrong model for a surface that redraws on
   every keystroke.

5. Theming is inherited, not invented. The surface look resolves from `settings.surface`
   through `CanvasPanel.surfaceElements`, the row colours from `settings.chooserTheme`, and
   the display from the one `overlaydisplay` instance already injected into both atoms at
   `root/compose.lua:234`. No new settings block.

6. The field ships and is lived with before the list is built on it, because it is the only
   part of this that can fail on feel rather than on logic.

## The component design, agreed 2026 10 13

One canvas component owns the window, the style, focus, the keyboard and the mouse. Three
components sit on it, each with a small API of its own. The chooser takes searchable items
through the frozen picker contract. The side pane is told which item is highlighted and
answers what to draw for it. The bottom pane draws the hints built from the manifest's key
bindings. A plugin decides what a pane shows and the pane decides how it is drawn.

Under all three sits a kit of drawing primitives, text in named variants such as title,
body, sub, dim, mono and heading, a key badge, an icon, a row, a divider, a spacer and a
stack. A pane answers a list of primitives and the canvas lays them out. Only the kit reads
the style, so no component picks a font, a size or a colour of its own, and that is what
makes the chooser and every pane look the same by construction.

This revises decision five. The surface, chooserTheme and the font settings become one style
block painted from the theme palette, read only by the kit. That lands after phase four and
before phase five.

## Roles

The main session orchestrates, writes the briefs, makes the decisions and verifies. Sonnet
subagents implement from briefs. Opus is used only where the delegated work carries
judgment that cannot be checked cheaply on return, and the reason is stated before it is
spawned. Milos is architect and QA and says start before any live screen test.

## Checklist

- [x] 0. Contract brief. The eighteen names with signatures and semantics, what is read
      live and what is read once, the callback set the config carries, and the validation
      rule. Written from the surveys of 2026-09-06 rather than from a fresh read.
- [x] 1. Freeze the contract, no behaviour change. Extract it into a contract module with
      a validate, make the facade refuse a provider that fails it, and move the stage's own
      window hunting and settle delay back behind the facade per decision three. Native
      passes unchanged. This phase is provable by the dry gate and the existing probes with
      no live test beyond one clean load.
- [x] 2. The field alone. A canvas text field on an event tap, no rows, proving typing,
      caret blink and position, selection, the editing key set, escape, and swallowing.
      Shipped as its own probe surface rather than wired into anything, so it can be judged
      on feel before anything depends on it.
- [x] 3. The canvas provider. Rows, highlight, icons, dimming, truncation, the active row
      marker, click and scroll, geometry, drawn on its own canvas with the shared chrome.
      Satisfies the phase one contract and nothing above the facade changes.
- [ ] 4. Selectable at the root, native still the default. One line naming the provider,
      and a week of real use on canvas before any question of moving the default.
- [ ] 4b. One style block and the primitive kit, the chooser and today's docked panes
      drawn through it, per the component design above.
- [ ] 5. The three pane surface, which is the reason for all of the above and is not
      attempted before phase four has been lived with.

## Testing discipline

Probes run against the live instance through the `hs` CLI with `dofile` scripts, no inline
angle brackets, no config reload, no devlock. Live tests of changed config follow the
worktree and devlock rules in the hammerspoon `CLAUDE.md`, and the screen is never driven
until Milos says start. The accessibility route these probes use to read a live chooser
does not exist for a canvas, so phases two and three need their own way to report, and
naming it is part of phase two rather than a thing discovered during it.

## Out of scope

Removing the native backend. Changing any plugin. Changing the presentation contract.
Rebuilding the cheat sheets or the hint panel. The webview provider, which is a later
sibling through the same door and not a reason to shape anything here around it.
