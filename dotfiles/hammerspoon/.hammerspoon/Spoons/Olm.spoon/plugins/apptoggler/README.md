# AppToggler

Brings an application forward, and cycles through its windows when it is already
the frontmost app, so pressing the chord repeatedly walks the app's windows and
wraps to the first. A variant may instead ask for show and hide, where a second
press while the app is frontmost really does hide it, or ask to be centered and
sized once it actually shows, launches, or focuses, never on a press that only
cycled to another window of an app already in front.

The plugin holds no key. It answers one action per app in its catalog,
`apptoggler.Safari`, which focuses or cycles that app, and one per named variant
in its data, `apptoggler.GhosttyPlaced`, which runs the behaviour that variant
asks for. Both are built once in `configure` and answered through
`provides.actions`, and a person reaches any of them from `config/keymap.lua`,
`["hyper+S"] = "apptoggler.Safari"`, on Hyper or on a plain combination such as
Option and backtick, which is live all the time rather than only while Hyper is
held. The one key it suggests is Finder on Hyper and F, so a fresh install has a
working toggle.

Every action names its app in `app`, so Olm merges it into the launcher's own row
for that app, which then shows the chord, rather than listing the app twice.
Where two actions name one app and both have keys, a plain combination wins the
row, since it appears on no cheat sheet and the row is its only discoverability
surface, and the row shows that action's description beside it. Reached by
typing a or app to narrow the launcher to the application rows. Choosing an app
row always focuses or cycles the app.

There are no other keys.

## On the Hyper cheat sheet

Holding Hyper shows every app whose action has a key on Hyper, the apps running now first and the
rest faded below them, each with its key and its icon. The plugin supplies no section for this.
Each descriptor carries a group function answering a `RUNNING` table or a `DORMANT` table with
`faded = true`, which the sheet asks at every show, and `defaults.cheatSheetOrder = 10` keeps the
block of this plugin's rows ahead of the sheet's own at fifty. Which apps run is read in one
enumeration shared by every app's question within a quarter of a second, since asking per app cost
about twenty milliseconds each and dominated the overlay's show latency.

The sheet draws an app row with the app's own icon and name, resolved once when the sheet is built,
leaves off an app that is not installed, and orders the apps by key, letters and digits first, then
symbols, ignoring case. All of that is Olm's, decided from `app`, so the plugin knows nothing about
the sheet. A variant's description is its row's label in place of the app's name.

Until phase 6 of the keymap plan this plugin answered complete key rows through
`provides.bindings`, its own sheet sections through `provides.cheatSheetSections` and the
launcher's app row details through `provides.launcherAppDetails`, all built from a toggle list in
`config/keys.lua` that held the keys. All three are retired, and so is that file.

## The variant fields

A variant is keyed by its name, which is its action's name, and names its `app`
from the catalog. Every other field is optional. A variant naming an app the
catalog does not hold is logged and left out, and a field a variant does not
read is logged with where it belongs now, a key or modifiers in
`config/keymap.lua`, a url in System Settings' own pane action.

`hides` swaps the default focus-or-cycle behaviour for show and hide. Focused
hides, visible but unfocused focuses, hidden or not running launches or shows.
Absent means focus-or-cycle, first press showing the last focused window and
each press after walking to the next one, wrapping to the first, and never
hiding anything.

`description` labels the action wherever Olm lists it, the app's launcher row
when the variant's key wins it and the sheet row when its key is on a leader.
It matters most for a variant on a plain combination, the one case with no
other discoverability surface.

`placement` centers and sizes the window once the press actually showed,
launched, or focused the app. It never fires on a press that only cycled
between windows of an app already frontmost, since that window was already
positioned by an earlier press. Either a table or a function.

The table form states `width` and `height` in pixels, `padding`, and `at`.
Padding is a single number insetting every side alike, a table with `x` and
`y` insetting left and right by `x` and top and bottom by `y`, or a table with
any of `top`, `right`, `bottom`, `left` insetting exactly the sides named.
Padding insets the screen's usable frame, `screen:frame()` rather than
`fullFrame()`, into a box. Width and height are the desired size, each clamped
to that box, and an omitted dimension keeps the window's current size, itself
clamped the same way. `at` is a fractional anchor, a table with `x` and `y`
each from zero to one, half standing in for either axis left out and being the
default, position along an axis being the box's own edge plus whatever room is
left over times the anchor. A value outside zero to one is clamped to whichever
bound it overshot and named on the console.

The function form is a plain function receiving the box, already inset by any
padding the table form could have declared, and the window, and answering a
frame table of `x`, `y`, `w`, `h`. The engine clamps whatever comes back
against the screen's own frame before applying it, so a wild answer cannot push
a window off screen.

Both forms operate on the display the window is already on, `win:screen()`,
and never choose one. That decision belongs to TerminalHandler.spoon's own
history, this person's own of 2026-09-01, carried into this plugin rather than
revisited, since the shared overlay display policy resolves to the cursor's
screen, right for a chooser or an overlay that has to appear under the eye,
wrong for a window meant to sit still, and a window that changes display every
time it is summoned loses the one thing a person relies on, knowing where it
is without looking. Choosing a display at all is the workspaces plugin's job,
never this one's.

## Where the data comes from

The catalog of bundle ids is config/apps.lua and the variants are written in this plugin's own
apptoggler entry in config/plugins.lua, which hands both over as this plugin's own data rather
than through the flat shared channel in init.lua. Neither holds a key, every key is in
config/keymap.lua.

## History

A show and hide behaviour and a placement engine both used to live in
TerminalHandler.spoon, a whole spoon kept outside Olm for the one app that
wanted them. Both turned out to be plain fields any variant here can ask for
rather than a tool of their own, so the spoon is gone and the terminal's own
summon is now one variant, GhosttyPlaced, beside the plain focus or cycle
action the same app already had.
