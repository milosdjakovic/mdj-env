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

Typed characters had to be posted at Hammerspoon by name rather than at whatever held focus, for
the native list. This was found when every command still arrived by opening a URL, which took key
focus off the list, so the characters landed in the application underneath and the list stayed
unfiltered. Return kept working throughout, because the chooser catches Return with an event tap
rather than through focus, so rounds still opened a tab and still passed. They were passing on the
top row of an unfiltered list. The targeting stayed after the URL went, because posting at whatever
held focus was never right for the native list, it only stopped being obviously wrong.

That trap flipped on 2026-10-14. The default chooser became a hand drawn canvas whose surface never
becomes the key window, and its field reads keys only through a session level event tap. A
keystroke posted at a process id is delivered to that process directly and never passes a session
tap, so the targeting that had been right for the native list now reached nothing at all, and the
query never arrived. Typing is posted untargeted now, the same way Return always was, and the
field's own tap claims the characters while the list is up. The comment above `commands.type` in
`agent.lua` says the same, and `decisions/olm-browsertabs.md` has the measurement.

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

Asking the open chooser what it has highlighted does not work on the legacy native provider. That
is a fact about the native `hs.chooser` only, since the canvas provider's `selectedItem` and
`query` read live state. The native chooser's selected row is only meaningful inside its own Return
handler, and read from outside it reports the first row of the unfiltered
list however the list is actually filtered. That reading was believed briefly and it accused the
tool of opening tabs it had never been asked for, while a real Return in the same state opened the
right one every time. The ranking is recomputed here instead, and the check that counts is the one
after Return. Since phase three of the unified search on 2026-10-17 the tool's supplier hands
every row over in its resting order and the shared search ranks them, so `agent.lua` ranks the
presentation's rows itself through `lib/chooser/rank.lua` and the shared fuzzy matcher with the
presentation's own search, loaded from the spoon. Reading the supplier alone would answer the
resting order, every typed round would report the wrong top row and `existing_user_tab` would
always skip. No case's expectation changed with it. Every typed round types a token unique to the
round, which only its own tab answers, and `no_query` reads the resting order, which still leads
with the tab opened last.

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

A later full run, on 2026-08-18, was sixty six rounds. Fifty five passed, two failed, nine reported
themselves not covered. All nine were the same machine fact, one browser window open at the time,
which is the state the multi window cases need and cannot make for themselves. `minimized on
safari`, the open defect below, was not among the failures that day.

`no_query on safari` failed once in the seventy round run above. Both witnesses said the tool had
done its job and the terminal running the suite held the front instead. That was almost certainly
the harness disturbing its own measurement, since every command still reached the agent by opening
a URL at the time, which goes through Launch Services and takes focus. The channel is files now and
activates nothing, so that particular reading coming back would still mean something real.

It has not come back. What arrived instead is a different failure wearing the same case name, and
telling the two apart is the reason this paragraph is longer than it wants to be. In the run of
2026-08-18 `no_query` failed on Chrome and on Safari, and a repeat of just that case failed six
rounds out of six on both, with the same wrong tab on top every single time. Focus is not the
reason. The list opened and the intended tab was present, and the top row was simply a different
tab, a real page from ordinary browsing rather than a fixture this suite made. So what this now
reports is the order declining to lift a touched tab to the front, which is a different claim about
a different part of the tool.

Those same six rounds were then run against main with nothing modified, and main failed all six the
same way, same two tabs and same reason. That was read at the time as the failure belonging to the
tool rather than to any branch under test, and it was wrong.

Resolved on 2026-08-20, and the fault was here. The case touched the fixture FIRST and the other
tab second, then asserted the fixture was row one, which only holds if something demotes the most
recently opened tab. That demotion existed once, was found wrong in use and was deliberately
removed, and the spoon's own `AGENTS.md` says so under the last tab you opened leads. So the tool
was right every round and this case had been asking for reverted behaviour, which is exactly why it
failed identically on both browsers and on untouched main. Touching the other tab first and the
fixture second makes it agree with the one ordering rule the tool has, and it is a stronger check
that way, since it proves the order ranks two remembered tabs against each other rather than only
floating a remembered one above untouched ones.

The note above pointing at the two `touch` calls was the right instinct. What mattered was not
whether the order reflected them but which order they were made in.

Confirmed by running it rather than by reading it. Ten consecutive rounds on 2026-08-20, five on
Safari and five on Chrome, all ten passing. One round before those was driven by hand a step at a
time with the selection path instrumented, so what happened after Return was observed rather than
inferred from a verdict, the Return tap firing while the chooser was up, the in place confirm
reading row one, that row being a tab, the activation being called with the address the ranking had
put on top, and the browser arriving in front. So the ordering fix above was the whole of it and
there is nothing else hiding under this case.

One round did fail after that fix and has not come back, and it is recorded because a single red
round of this case is a thing to run again before it is investigated. It was one round taken minutes
before the fix was committed, and the witness shows the fixture correctly on top and then nothing
having moved at all, the other application still in front and the browser's own selected tab
unchanged. Ten rounds since have not reproduced it, and the console carries no complaint from the
engine, which logs a refused activation and a browser it could not bring forward. So it is left
unexplained rather than called solved. The nearest documented candidate is the discretionary cross
application raise in the spoon's own `AGENTS.md`, and it does not fit on its own, since a raise
macOS declined would still have left the tab selected.

The full run of 2026-08-20 was seventy rounds. Sixty eight passed, none failed, and two reported
themselves not covered. It is the first run of this suite with nothing red in it.

Two extra windows were opened by hand in each browser before starting, and that is the whole reason
this run answered more than the last one. Nine cases reported themselves not covered on 2026-08-18
for the single reason that one window was open, and every one of them ran and passed here. So
opening a second window in each browser is part of starting a full run rather than a nicety, since
without it the run costs the same twenty minutes and answers nine fewer questions.

`minimized on safari`, the open defect below, passed three rounds out of three. That is not a fix
and it is deliberately not written up as one. Nothing in that path changed, and the section below
records the failure as intermittent and correlated with minimizing and restoring one window
repeatedly, so three clean rounds is one clean run and not a resolution. It is recorded because a
run where it does not appear is itself information about how often it does.

The two not covered were `discarded on chrome` and `tab_group on safari`, both for machine reasons
already recorded further down, neither of which is a gap to close.

Two `jq` errors printed during that run, each reading that it could not iterate over null. They come
from a case cleanup asking a browser for its window list and getting nothing back, so `.windows[]`
had null to walk. No case failed and no assertion rested on them, and the switched off check, which
makes a similar call, demonstrably got its answer since it passed on the comparison that call feeds.
Where the two lines landed in a captured log is not evidence of which case produced them, since
stderr is unbuffered and the pass lines are not, so do not read their position as a clue. Cosmetic,
and a default on that jq path would end it.

A trap for anyone driving the harness by hand rather than through `suite.sh`. Every answer is read
straight out of a reply file by `hs_cmd`, so anything else the shell prints during that call lands
inside the JSON. An interactive shell on this machine has `rm` aliased to `rm -iv`, and the verbose
half printed the reply path immediately after the answer, which made `jq` fail on every call, which
reads exactly like an agent that has stopped answering. Both `suite.sh` and `run.sh` are unaffected,
since each runs under a non interactive bash where no alias of that shell is loaded, so drive
anything by hand from `bash` too and never from the interactive shell.

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
everything ruled out is in the spoon's own `AGENTS.md`, under the open defect. Safari
reports the window restored and the right tab selected while the window server reports Safari
having no windows at all, and it holds that way for the whole settle.

A quick run on main on 2026-10-17 at about 21:26 passed eight, failed twenty nine and reported
nine not covered, with the witness log in `results/last-run.log`. A run on a feature branch that
day had failed the same way, so main was run as the baseline and failed the same way too, which
put the fault in the harness and on this machine rather than in any change under test. Every
failing case types a query. The only full raise cases that passed were `no_query` on Chrome and on
Safari, the one case that types nothing. In every Safari round the browser ended on tab one, a
Google Drive page, and in most Chrome rounds the same Safari window ended frontmost, the same
remembered tab winning every time. That is what a Return pressed on an unfiltered list looks like,
since the top row of the resting order is the tab the tool opened most recently. It holds for every
Safari round and most Chrome rounds, and not for all of them. In `duplicate_in_window on chrome`
the typed round passed, with Chrome frontmost on the fixture's first copy and the accessibility
witness seeing its window, where an unfiltered Return would have taken Safari's Drive tab as the
rounds around it did. In the Chrome rounds the arrange already leaves the target tab active, so
the selected tab witness proves little on Chrome.

One more thing is open and is named the Chrome witness anomaly. In `hidden_app on chrome` Chrome
ended frontmost with the target window focused per `hs.window.focusedWindow`, yet System Events
reported no Chrome window for the whole settle and `allWindows` was empty. Across the Chrome rounds
`allWindows` on Chrome returns an empty list while `focusedWindow` returns a Chrome window, and in
`frontmost on chrome` the front window was a "Vicert One-Pager" window that the browser's own
dictionary does not list. The browser's dictionary, `hs.application:allWindows` and System Events
disagree. A second Chrome process or profile with the same bundle id is a plausible cause and is
unverified. It has nothing to do with typing, and the rerun is where it will be read.

The `top` precondition could not catch it. It is a ranking the agent recomputes from the plugin's
rows through `rank.apply`, never a reading of the live list, so it said the right tab was on top
while the list on screen was not filtered at all. That is the same family as the earlier trap about
asking the open chooser what it has highlighted, a check that reads something other than what
Return will take.

The first belief, written into the decision log that evening, was focus changes after synthetic
key presses on macOS 27 or a lapsed Automation grant. That was wrong. On 2026-10-19 at about 08:12
a short script armed a temporary session key down tap for 1.6 seconds and posted one
character with exactly the call `commands.type` made, targeted at Hammerspoon. In two runs the tap
saw none of the posted keystrokes. It did see the real keys Milos pressed in the same window, two
in the first run and one in the second, which is the control that the tap itself was working. So the
query had been going to a place the field does not listen. The fix is in this change. The rerun
after it is still owed, and it is also where the one real tool concern gets its first reading. The
canvas never holds the front, so a raise that selects the right tab and leaves the browser behind
would be the discretionary cross application raise in the spoon's own `AGENTS.md`, now met by the
harness on the real path for the first time. Milos's own hand test of the tabs list passed on
2026-10-17, which is a reading of a raise honoured from a canvas that never held the front, so
this is the concern's first harness reading and not its first reading. It is to be watched in that rerun and not fixed before it has been
seen.

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
