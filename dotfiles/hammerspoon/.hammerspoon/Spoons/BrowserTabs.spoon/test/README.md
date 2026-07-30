# The BrowserTabs suite

This is an integration harness, and it is the only kind of test this spoon can usefully have.

Four defects once produced the same symptom here, a chosen tab that did not come forward, and not
one of them lived in a place a unit test could reach. A window reference that went stale when the
window list reordered, an application being raised instead of a window, an application lookup that
came back empty on its first call, and a Safari window with no document that could be listed and
chosen and could never do anything. All four are in Apple Events, the accessibility layer, and real
browser state. A suite with a fake browser in it would have passed cleanly through the entire
period the tool was broken, which is worse than having no suite at all, because it would have said
so out loud.

So every round here drives the real thing. The real leader chord posted as hardware events, the
real chooser, a real query typed into it, and a real Return. Nothing on the path is stood in for.

## Running it

```bash
Spoons/BrowserTabs.spoon/test/suite.sh              # everything
Spoons/BrowserTabs.spoon/test/suite.sh --only drift # one group
Spoons/BrowserTabs.spoon/test/suite.sh --list       # what there is
```

`suite.sh` takes the machine-wide test lock so this checkout becomes the live Hammerspoon config,
switches the harness on, runs the cases, and then puts the lock, the config, and the browsers back
whether it passed, failed, or was interrupted. It steals focus continuously for about twenty
minutes, so the machine is not usable while it runs.

`run.sh` is the same thing without the lock and the marker, for when Hammerspoon is already pointed
here and the harness is already loaded, which is what you want while iterating on a single case.

## How a round is judged

By two witnesses that share no implementation, because the tool writes to two layers and reads back
through only one of them, so agreeing with itself is not evidence.

The browser's own dictionary says which window it has in front and which tab that window is
showing. System Events, in a separate process, says which application is frontmost and which window
the accessibility layer has in front. The two are tied together by the window frame, which is a
number and belongs to exactly one window, rather than by the title, which each browser decorates
differently and which changes under you when a page finishes loading. When two windows share a
frame, and they very often do, the title breaks the tie.

There is a precondition as well. The tab the case means to open has to be the top row before Return
is pressed, since the top row is what Return takes. It is deliberately not required that the query
match one row only, because a fuzzy match over a hundred tabs always matches many.

## Where things live

`run.sh` is the mechanism. It knows how to put the tool through one round and how to judge the
result, and it knows no case by name. `cases.sh` is the policy, one function per case plus the list
saying which browser each runs against and how many passes it needs. Adding a case is a function
there and a line in that list, with no edit to the runner.

`browsers/` holds one adapter per dictionary rather than per application, the same split the spoon
itself uses, so every Chromium comes through one file and the bundle id is a parameter. `ax.js` is
the outside witness. `agent.lua` is the half that lives inside Hammerspoon, loaded only when the
`ENABLED` marker is present beside it, which the runner writes at the start and removes at the end.

Commands reach the agent as URLs and answers come back in files. That looks roundabout and is
deliberate. The Hammerspoon command line tool blocks while the config has asynchronous work in
flight, this tool nearly always does, and a call killed while blocked leaves the channel dead for
the rest of the session.

The harness travels with the spoon into the home directory, because stow symlinks a spoon as a
whole directory and there is no way to leave one subdirectory behind without unpicking that. It is
inert there, since nothing loads without the marker and the marker is not committed.

## Traps this harness fell into, all of which produced false passes

Worth reading before changing anything here, because every one of them made the suite report
success while testing nothing, which is the only failure mode of a test suite that really matters.

Typed characters have to be posted at Hammerspoon by name rather than at whatever holds focus.
Every command here arrives by opening a URL, and opening one while the list is up takes key focus
off it, so the characters landed in the application underneath and the list stayed unfiltered.
Return kept working throughout, because the chooser catches Return with an event tap rather than
through focus, so rounds still opened a tab and still passed. They were passing on the top row of
an unfiltered list.

An arrange runs inside a command substitution, so it is a subshell and nothing it assigns survives.
Disturbances that read a variable an arrange had set were disturbing nothing, and four drift cases
passed without ever causing any drift. The unique token counter had the same problem, which gave
two browsers pages with the same name and made a round open the first browser's tab, reading
exactly like the real fault this suite exists to catch.

Asking the open chooser what it has highlighted does not work. Its selected row is only meaningful
inside its own Return handler, and read from outside it reports the first row of the unfiltered
list however the list is actually filtered. That reading was believed briefly and it accused the
tool of opening tabs it had never been asked for, while a real Return in the same state opened the
right one every time. The ranking is recomputed here instead, and the check that counts is the one
after Return.

The chooser keeps the previous listing on screen while a new one is in flight, which is right for a
person and a trap here, since rows read just after opening do not contain what the case arranged.
Rounds wait for the intended tab to actually reach the top rather than sleeping a guessed interval.

And one that was not a false pass but was worse. A window is created by asking the browser to make
one, and what that returns is a positional reference, so writing a URL through it too early
navigates whichever window was in front. This suite did that to a real window and then closed it as
one of its own. New windows are now found by which id is new, and the cleanup refuses to close any
window that existed when the run started.

## What is deliberately not covered

A window on a second ordinary Space, because this machine has one. The full screen case is the
nearest reach, since a full screen window does live on its own Space.

Chrome pinned tabs, which can only be pinned through a context menu not worth driving. Safari's are
covered, since Safari has a menu item.

Anything needing a second display, unless one is attached when the suite runs.

A case whose state cannot be created reports itself as not covered rather than passing, and the
summary keeps that separate from what passed, so a suite that could not reach a state never reads
as a suite that checked it.

## What a green run does and does not mean

It means the four known faults are still fixed and that a change did not reintroduce them. It does
not prove an intermittent fault is gone, because some of these depend on timing and on what else
the machine is doing. Regression protection, not proof.
