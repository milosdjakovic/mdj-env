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
real chooser, a real query typed into it, and a real Return. Nothing on the path is stood in for,
and the section below on why the keyboard cannot be skipped is the evidence that this is not
excessive.

## Running it

```bash
Spoons/Olm.spoon/plugins/browsertabs/test/suite.sh              # everything
Spoons/Olm.spoon/plugins/browsertabs/test/suite.sh --quick      # one pass of each, no repeats
Spoons/Olm.spoon/plugins/browsertabs/test/suite.sh --only drift # one group
Spoons/Olm.spoon/plugins/browsertabs/test/suite.sh --list       # what there is
```

`suite.sh` takes the machine-wide test lock so this checkout becomes the live Hammerspoon config,
switches the harness on, runs the cases, and then puts the lock, the config, and the browsers back
whether it passed, failed, or was interrupted. It steals focus continuously for the whole run, so the
machine is not usable while it runs.

Use `--quick` while working on a change. It runs one pass of every case and drops the two that
spend their time waiting on animation, which is most of the length. Use the full run before merging,
because the repeats exist for the cases that were genuinely flaky and one pass proves least about
exactly those.

`run.sh` is the same thing without the lock and the marker, for when Hammerspoon is already pointed
here and the harness is already loaded, which is what you want while iterating on a single case.

## Why every round still uses the keyboard, though it was tried the other way

This is the most useful thing measured here, so it is worth reading before trying to make the suite
faster the obvious way.

Most cases look like they are not about the keyboard. A minimized window, a stale window reference,
a hidden application, none of that lives anywhere near the typing. So a second driver was built that
skipped the chord and the query and committed through the chooser's own public activate, the same
seam the launcher's tab scope already uses. Everything below that seam, the ranking, the providers,
the window search and the raise, was still the real code.

It was withdrawn, and the honest reason is that its effect could not be separated from the
machine's own drift. What was seen, in order. Every Chrome round passed throughout. Safari's
minimized round failed on the short path in five runs out of five, three different ways, once with
the accessibility layer reporting no window for Safari at all, once with Safari showing another of
its windows, once with a real page of the user's in front. The same case on the full path passed
six out of six in between, which looked conclusive. Then, after the short path was removed, the
full path failed the same case too, first once and then three times out of three, with the same
signatures.

So the comparison was run against a baseline that was moving, and no causal claim survives it. What
does survive is the reason not to assume the two paths are equivalent, and it is already in this
spoon's notes. macOS grants a cross application raise at the system's discretion, and what it
grants it to is an application acting on user input. A driver that commits from a timer instead of
from a real Return changes who is asking, and that is the one thing this suite is least able to
notice going wrong. Cheapening a round by removing the keyboard has to be treated as changing the
experiment until somebody proves otherwise against a baseline that is holding still.

The failure it uncovered is real and it outlived the driver that found it. It has since been
narrowed down and it is recorded below and in the spoon's own notes as the one open defect.

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

Commands reach the agent as files dropped in a directory it polls, and answers come back as files
too. Both halves of that are the result of ruling something out. The Hammerspoon command line tool
blocks while the config has asynchronous work in flight, this tool nearly always does, and a call
killed while blocked leaves the channel dead for the rest of the session. A URL does not block and
was what this used first, but opening one goes through Launch Services and takes focus, and focus
is the thing most of these rounds measure. So the channel is files, it activates nothing, and the
directory sits under the caches directory rather than in the config tree, since a file written
there would trigger a reload on every command.

The harness travels with the spoon into the home directory, because stow symlinks a spoon as a
whole directory and there is no way to leave one subdirectory behind without unpicking that. It is
inert there, since nothing loads without the marker and the marker is not committed.

## Traps this harness fell into, all of which produced false passes

Worth reading before changing anything here, because every one of them made the suite report
success while testing nothing, which is the only failure mode of a test suite that really matters.

Typed characters have to be posted at Hammerspoon by name rather than at whatever holds focus. This
was found when every command still arrived by opening a URL, which took key focus off the list, so
the characters landed in the application underneath and the list stayed unfiltered. Return kept
working throughout, because the chooser catches Return with an event tap rather than through focus,
so rounds still opened a tab and still passed. They were passing on the top row of an unfiltered
list. The URL is gone now and the targeting stays, because posting at whatever holds focus was
never right, it only stopped being obviously wrong.

That URL channel is worth one more line, because it disturbed the very thing it was measuring for
as long as it existed. It is the likeliest explanation for the single failure of the last full run
before it was replaced, where both witnesses agreed the tool had done its job and the terminal held
the front. Nothing in the channel activates anything now, so a repeat of that reading means
something real.

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

A locked screen produces failures that look exactly like the fault this suite is for. The
accessibility layer keeps answering questions about processes while returning no windows for any of
them, so the browser's own answers stay correct and the outside witness reports nothing in front. A
full run was lost to that once and two rounds of another were wrongly blamed on the tool. The screen
is checked before every round now, and the machine is held awake with an assertion that somebody is
present, because holding only the display awake was not enough. The lock runs off the idle timer and
synthesised keystrokes do not reset it.

## Two ways this suite destroyed somebody's work

Both are fixed and both are worth stating plainly, because a harness that runs against a real
browser full of a person's real tabs has to be held to a different standard than one that cannot
lose anything.

A window is created by asking the browser to make one, and what that returns is a positional
reference. Writing a URL through it too early navigates whichever window happened to be in front
instead, so a real window was sent to a fixture page and then cleaned up as one of the suite's own.
New windows are now found by which id is new, every window the suite opens is written down at the
moment it is created rather than recognised later by its contents, and the cleanup refuses to close
any window that existed when the run started. Recognising by contents cannot work, since Safari
opens a new window on the person's own homepage.

A disturbance closed a tab by position, on the assumption the position still held the filler it had
put there. The insert before it had failed without anybody checking, so the position held a real
page, closing it emptied the window, and the browser closed the window with it. A guard that only
refused to close windows was never going to catch that. Closing a tab now requires proof, the caller
passes a fragment that must appear in the tab's address and the adapter refuses anything else, so
the rule holds even when a caller is wrong.

## What the runs so far said

Kept here on purpose. `results/` is gitignored and the next run overwrites it, so without this a
green run would be a claim with nothing behind it, and the one case that is still failing would be
rediscovered from scratch by whoever comes next.

The last full run was seventy rounds. Sixty seven passed, one failed, two reported themselves not
covered. Every case below passed on both browsers named unless it says otherwise, and the six that
run three times are the ones that were genuinely seen failing during the original investigation.

`frontmost`, `background_window`, `other_app_front`, `hidden_app`, `already_selected`,
`far_from_selected`, `long_title`, `blank_title`, `duplicate_in_window`, `duplicate_two_windows`,
`retitles_on_load`, `drift_tab_inserted`, `drift_tab_closed`, `drift_window_reordered`,
`drift_window_closed`, `slow_press`, `existing_user_tab`, all passed on Chrome and Safari.
`drift_tab_moved`, `back_to_back`, `switched_off`, `escape_raises_nothing`, `fullscreen` passed on
Chrome, `pinned` and `phantom_not_listed` passed on Safari, and `not_running` passed against Arc.

`no_query on safari` failed once in that run and has not failed since. Both witnesses said the tool
had done its job and the terminal running the suite held the front instead. That was almost
certainly the harness disturbing its own measurement, since every command still reached the agent
by opening a URL at the time, which goes through Launch Services and takes focus. The channel is
files now and activates nothing, so a repeat of that reading would mean something real.

`discarded on chrome` cannot be created on this machine, since Chrome here has internal debugging
pages disabled by policy and there is no other way to force a tab out of memory. That is final
rather than a gap to close, and the hazard a discarded tab carries, a page reloading and renaming
itself as it is selected, is covered deterministically by `retitles_on_load`.

`tab_group on safari` finds its window by looking for one whose accessibility name differs from its
selected tab's title, and it only searches the front window, so whether it can run at all depends
on what happens to be forward. It has both passed and reported not covered. Making it search every
window is a small change worth doing.

`minimized on safari` is the open defect and the reason this file is worth reading. Two later runs
of three rounds each, on both browsers, went as follows. Chrome passed six of six. Safari failed
the first round of the first run, then the first two rounds of the second, so three of its six
rounds failed and the failures were not in the same place twice. The full witness trail and
everything ruled out is in the spoon's own `CLAUDE.md`, under the open defect. Safari
reports the window restored and the right tab selected while the window server reports Safari
having no windows at all, and it holds that way for the whole settle.

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
