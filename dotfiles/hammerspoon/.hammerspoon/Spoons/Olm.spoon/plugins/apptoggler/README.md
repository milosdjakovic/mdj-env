# AppToggler

Brings an application forward, and cycles through its windows when it is already
the frontmost app, so pressing the chord repeatedly walks the app's windows and
wraps to the first. An entry may instead ask for show and hide, where a second
press while the app is frontmost really does hide it, or for a url rather than a
plain focus, so the app lands on one settings pane instead of wherever it was
last, which is how the System Settings toggle lands on General. An entry may
also ask to be centered and sized once it actually shows, launches, or focuses,
never on a press that only cycled to another window of an app already in front.

Each app is bound to its own chord on the Hyper leader by default, holding Caps
Lock and pressing the app's own letter. An entry may instead state its own
`modifiers` and bind as a literal global combo through `hs.hotkey.bind`, live
all the time rather than only while Hyper is held, which is what a toggle
pressed mid work, rather than reached through a leader, wants. The whole set
also appears as rows in the launcher's application list, reached by typing a or
app to narrow to only those rows, and a literal combo entry carries its own
`description` there, since it never reaches the Hyper cheat sheet the way a
modal entry does and the launcher row is its only discoverability surface.

There are no other keys.

## The per entry fields

Every field beyond `app` and `key` is optional.

`modifiers` opts an entry out of the Hyper modal and into a literal combo.
Absent means the Hyper modal, fired by holding the physical Hyper key through
HyperKey's own hold engine, or the internal literal `HYPER` combo when HyperKey
is not wired at all, exactly as an unmodified entry always has. Stated, it asks
for that literal combo outright and skips the modal, regardless of whether
HyperKey is wired.

`hides` swaps the default focus-or-cycle behaviour for show and hide. Focused
hides, visible but unfocused focuses, hidden or not running launches or shows.
Absent means focus-or-cycle, first press showing the last focused window and
each press after walking to the next one, wrapping to the first, and never
hiding anything.

`description` labels the entry's launcher row. Already meaningful for any
toggle, it matters most for a literal combo entry, the one case with no other
discoverability surface.

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

## History

A show and hide behaviour and a placement engine both used to live in
TerminalHandler.spoon, a whole spoon kept outside Olm for the one app that
wanted them. Both turned out to be plain fields any entry here can ask for
rather than a tool of their own, so the spoon is gone and the terminal's own
toggle is now one entry in config/keys.lua's appToggles, alongside the plain
focus-or-cycle entry the same app already had.
