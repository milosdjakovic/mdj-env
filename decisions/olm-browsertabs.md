# Olm BrowserTabs, the harness and the raise

Status. The harness types untargeted and reads the live list before Return. The quick run of 12:00 on
2026-10-19 passed 44, failed 1 and skipped 1. The one failure, `no_query on chrome`, was the cross
application raise declined by macOS, reproduced for the first time with evidence, and the engine now
confirms a raise once and repeats it once. Two things are open. The first round close, `frontmost on
chrome`, did not reproduce in two runs with the trace armed, and the trace stays armed. The Chrome witness
anomaly of 2026-10-17 is unchanged. Whether the repeated raise is honoured where the first was declined
has not been read.

## Now

The harness drives the real path, the leader chord, a typed query and a real Return, all posted as
untargeted events through `hs.eventtap`, the chord stamped as hardware. The default chooser is a canvas whose surface
never becomes the key window, and its field reads keys only through a session level event tap, so
untargeted events are the only kind it can receive. A round is judged by two witnesses that share
no implementation, the browser's own dictionary and System Events. Its `top` precondition is a
ranking the agent recomputes from the plugin's rows, so it says what the ranking would put first and
nothing about what the live list shows. So a round also reads the live field text and the live
highlighted row through the stage before Return and requires the typed query and the intended tab,
and `commands.type` refuses unless the list is showing. The read goes through the root words
`stageQuery` and `stageSelectedItem` that the BrowserTabs surface exposes as `live()`.

The quick run of this branch on 2026-10-19 passed 37, failed 1 and skipped 8, against the baseline
on main of 2026-10-17 that passed 8, failed 29 and skipped 9. Every typed round printed a `live`
line with the typed token in the field and the intended tab under the highlight, and the browser then
arrived with it. The raise concern did not show. No round selected the right tab and left the
browser behind, so the first harness reading of a raise from a canvas that never held the front is
that macOS honoured it on every round that asked. The tool's own raise path is unchanged in code
since 2026-08-21, and the concern in `plugins/browsertabs/AGENTS.md` is read once and not closed.

The second quick run, from main at cb2d4da after the branch merged, ended at 10:14 on 2026-10-19. It
passed 43, failed 1 and skipped 2, and all eight multi window cases ran and passed. The two skips are
machine facts, no window in a tab group on Safari and no ordinary tab to pick on Chrome.

The quick run of 12:00 on 2026-10-19 passed 44, failed 1 and skipped 1, and the engine now confirms a
raise once and repeats it once, see the log. Two things are open. The first is the first round close.
`frontmost on chrome` failed at 08:39 and 10:14 with the list closed before the live read, and it passed in
the 11:50 and 12:00 runs, so it has not reproduced in two runs with the trace armed. The agent records the
closing handler's traceback, the field text, the frontmost application and every key down with its source
stamp, so a run that reproduces it names the closer. The trace stays armed.

The second is the Chrome witness anomaly from 2026-10-17, unchanged. There the browser's dictionary,
`hs.application:allWindows` and System Events disagreed about Chrome's windows, and a second Chrome
process or profile sharing the bundle id is a plausible cause and unverified.

## Rejected

- **Typing posted at the Hammerspoon process by name.** Chosen in the URL era, when every command
  arrived by opening a URL and that took key focus off the native list, so characters posted
  freely landed in the application underneath. Rejected 2026-10-19. Since 2026-10-14 the field
  listens on a session tap of a canvas that never holds key focus, and a keystroke posted at a
  process is delivered to that process directly and never passes a session tap. Measured on
  2026-10-19, a temporary session key down tap saw none of the characters posted this way in two
  runs, while it did see the real keys pressed in the same window.
- **Chasing the macOS 27 upgrade or a lapsed Automation grant before the harness typed.** Set
  aside 2026-10-19, and not ruled out in itself. The engine, the providers, `jxa.lua`, `apps.lua`
  and the activate closure are unchanged in code since 2026-08-21, `no_query` passes on both
  browsers, and nothing about the raise can be read until a query reaches the list. Both could
  matter, and the rerun is where they would show.

- **Treating the first round failure as a flake to run again.** Rejected 2026-10-19. It reproduced on
  the first round of both quick runs with the same signature, so it is a reading with a most likely
  cause and a named measurement, recorded in the log entry of 2026-10-19 10:30.

- **A raise retried in a loop or without a bound.** Rejected 2026-10-19. A loop keeps asking while the
  person has moved on, and fights their own next activation. One confirmed repeat answers the reading,
  since the failure is a single declined request and not a slow one.

## Log

### 2026-10-17 21:26, the harness fails on main, estimated

Anchored to `plugins/browsertabs/test/results/last-run.log`, whose modification time is the end of
the run, so the run ended about 21:26 and its snapshots are stamped 21:20. A quick run on main passed eight,
failed twenty nine and reported nine not covered. Every failing case typed a query. The only full
raise cases that passed were `no_query` on Chrome and on Safari, the one case that types nothing.
In every Safari round the browser ended on tab one, a Google Drive page, and in most Chrome rounds
the same Safari window ended frontmost. The belief held that evening, written into the entry of
2026-10-17 21:30 in `decisions/olm-unified-search.md`, was that the cause was most likely focus
changes after synthetic key presses on macOS 27 or a lapsed Automation grant. That was wrong.

### 2026-10-19 08:13, the harness posted its typed query at a process whose window no longer listened, estimated

Estimated, anchored to the probe of that morning, which ran at about 08:12 and 08:13. The survey
found that `commands.type` in `test/agent.lua` posted the query at the Hammerspoon process, while
`commands.key` posted Return untargeted. Targeting had been chosen in the URL era. Since commit
476cb47 at 21:45 on 2026-10-14 the default chooser is a canvas whose field reads keys through a
session event tap in `lib/chooser/providers/default/field/input.lua`. The rename that followed at
8005573 at 21:50 did not change which chooser is the default. The evidence was that the query never
reached the list, the untargeted Return took the top row of the resting order, which is the tab
opened most recently, and the `top` precondition could not see it because it is recomputed from
the plugin's rows and never read from the live list. The probe was a script that armed a session
key down tap for 1.6 seconds and posted one character with the harness's exact call. In two runs
the tap saw none of the posted keystrokes, and it did see the real keys Milos pressed in the same
window, which is the control that the tap worked. The decision was to post typing untargeted, the
route Return already takes, and to record the old belief as corrected.

The probe is written down here so anyone can rerun it. It was run with
`hs -q -c "return dofile('/tmp/keytap-probe.lua')"`, bounded in the background. The result file
read "targeted keystroke posted at Hammerspoon pid, session tap saw N keyDown event(s)" followed by
the keys seen, and none of them was the posted q in either run.

```lua
-- Does a keystroke posted at the Hammerspoon process reach a session level key tap, the way the
-- default chooser's field reads keys. One targeted keystroke, no chooser, nothing typed anywhere.
local out = "/tmp/probe-result.txt"
local seen = {}
local tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(ev)
  seen[#seen + 1] = tostring(ev:getKeyCode()) .. ":" .. tostring(ev:getCharacters())
  return false
end)
tap:start()
_G.__keytapProbe = { tap = tap }
_G.__keytapProbe.t1 = hs.timer.doAfter(0.4, function()
  local hammerspoon = hs.application.get("org.hammerspoon.Hammerspoon")
  hs.eventtap.keyStrokes("q", hammerspoon)
end)
_G.__keytapProbe.t2 = hs.timer.doAfter(1.6, function()
  tap:stop()
  local f = io.open(out, "w")
  f:write("targeted keystroke posted at Hammerspoon pid, session tap saw " .. #seen .. " keyDown event(s)\n")
  for _, s in ipairs(seen) do f:write("  " .. s .. "\n") end
  f:close()
  _G.__keytapProbe = nil
end)
return "armed"
```

The claim that every typed round took the top row of an unfiltered list is too strong, and the log
of the run does not support it. It holds for every Safari round and most Chrome rounds. In
`duplicate_in_window on chrome` the typed round passed, with Chrome frontmost on the fixture's
first copy and the accessibility witness seeing its window, where an unfiltered Return would have
taken Safari's Drive tab as the rounds around it did. In the Chrome rounds the arrange already
leaves the target tab active, so the selected tab witness proves little on Chrome.

One more thing is open and is named the Chrome witness anomaly. In `hidden_app on chrome` Chrome
ended frontmost with the target window focused per `hs.window.focusedWindow`, yet System Events
reported no Chrome window for the whole settle and `allWindows` was empty. Across the Chrome rounds
`allWindows` on Chrome returns an empty list while `focusedWindow` returns a Chrome window, and in
`frontmost on chrome` the front window was a "Vicert One-Pager" window that the browser's own
dictionary does not list. The browser's dictionary, `hs.application:allWindows` and System Events
disagree. A second Chrome process or profile with the same bundle id is a plausible cause and is
unverified. It has nothing to do with typing, and the rerun is where it will be read.

Two things stay open. The rerun of the harness after the fix is still owed. And one real tool
concern waits behind it, since the comment near `focusTabWindow` in `plugins/browsertabs/engine.lua`
assumes the surface hands focus back to the app on hide, while the canvas never holds the front and
macOS honours a cross application raise at its discretion for an application that never held it. A
rerun that selects the right tab and leaves the browser behind would be the first real reading of
that. It is to be watched and not fixed now, and `engine.lua` is not changed by this entry.

### 2026-10-19 08:28, a round reads the live list before Return

The harness had no reading of the live list. Its `top` precondition was a ranking the agent
recomputes, so a query that never landed stayed invisible until the wrong tab opened. A new `live`
command in `test/agent.lua` answers the field text, and the url and kind of the highlighted row,
read from the stage, and `run.sh` requires after the ranking loop that the field equals the typed
text and that the highlighted row is the intended tab, failing with the reason in each case. The
`top` line stays for diagnosis. `commands.type` now refuses with a reason unless the tab list is
showing, so a token is never typed into a browser page after the list closed. The stage could not
be reached as `spoon.Olm._composed.modules.stage` from the agent, since the dependency check
forbids any file under the plugins folder from naming that spoon. The lawful door is the root's
published words, so the root gained `stageQuery` beside the existing `stageSelectedItem`, the
BrowserTabs manifest declares both as optional, and the tool's surface answers them through a small
`live()` the agent calls. Nothing in the tool reads it while it runs. Nothing was run here, since
the rerun is still owed, and the first rerun will show the `live` line for the first time.

### 2026-10-19 10:05, the quick run and the rerun, estimated

Estimated, anchored to the console relaunch stamps 08:39:02 and 10:01:22, the first when the quick
run ended and main was restored, the second when the rerun ended and main was restored again. The
quick run was `suite.sh --quick` from the worktree with the lock, and it passed 37, failed 1 and
skipped 8, against 8, 29 and 9 on main of 2026-10-17. Every typed round printed a `live` line with the
typed token in the field and the intended tab under the highlight, and the browser then arrived
with it. No round selected the right tab and left the browser behind, so the raise concern did not
show, and the first harness reading of a raise from a canvas that never held the front is that macOS
honoured it on every round that asked. The Chrome witness anomaly did not recur in any raise round.
The one null window reading in the log was Finder in front in the `drift_window_closed on chrome`
round, a no crash round where no window is expected. The snapshot saw one window in Chrome and one in
Safari, so the eight multi window cases skipped, and `tab_group on safari` skipped as before.

The one failure was the first round, `frontmost on chrome`. Typing was not refused, so the list was
showing, and the recomputed top row was right, yet the live read answered that no list was showing
for its whole four second poll. The list had closed between the typing and the live read, on the first
chord after the config load, which the runner already warms up for. The rerun at 10:01, `suite.sh
--only frontmost`, took one round per browser. Safari passed and Chrome skipped with the browser has
no window, so the red round could not be run again. It stays a single first round reading to run again
when Chrome has a window. The console was read after both restores and was clean, with
`spoon.Olm._composed.problems` empty. The Status and Now above were rewritten from this entry.

### 2026-10-19 10:30, the second quick run and a survey of the first round reading, estimated

Estimated, anchored to the console relaunch stamp 10:14:36, when the run ended and main was restored,
and to the read only survey of the code that followed. The run was `suite.sh --quick` from main after
the branch merged at cb2d4da. Before it Chrome had no window and Safari had one, so two Chrome windows
and one more Safari window were opened on blank pages by their ids and closed by the same ids
afterwards, which left each browser with two windows at the snapshot. It passed 43, failed 1 and
skipped 2. All eight multi window cases ran and passed. The two skips were `tab_group on safari`, no
window in a tab group, and `existing_user_tab on chrome`, no ordinary tab to pick, both machine
facts. The Chrome witness anomaly did not appear in any round. The console on restored main was
clean.

The one failure was again the very first round, `frontmost on chrome`, with the same signature as at
08:39. Typing was not refused, so the list was showing when the token was typed, the recomputed top row
was right, and the live read answered that no list is showing for its whole four second poll. Twice in
a row on the first round of a quick run is no longer a single reading to run again, it is a
reproducible first round reading. In the 10:01 rerun where Chrome had no window, the Safari round was
the first after the load and passed, so being first alone does not fail. `background_window on
chrome`, the other case with Chrome frontmost at chord time, passed, so Chrome frontmost alone does not
fail either.

The survey found this. The message comes from the plugin's own showing flag in
`plugins/browsertabs/chooser.lua`, set true on present and false only on close, so the list was
really closed between the typing and the live read and not merely hidden. Nothing in the default
provider or the stage closes a list on an application change, a focus change, a screen or Space
change, or a timer, and the canvas is a non activating popup, so Chrome coming forward cannot close
it. The closers are Escape, Return, a mouse down outside the canvas, a programmatic stage hide from
another plugin, a second present over it, or a config reload, and a reload is unlikely since the
recomputed top row survived. The fixture page is inert, one script setting the title and heading.

The most likely cause is the leader being believed still held after the round's chord. The field
yields every key to Hyper while the leader is owned, `yields` in `root/compose.lua` through
`hyperkey:owns`, so the typed token's letters would run as Hyper chords instead of reaching the
field, and every token ends in x, which is the shared close key of every list context, so the list
would close on the token's own last letter. What would leave the leader believed held is a lost
leader key up, which `lib/chordkey.lua` documents as the one real fragility, caused by secure input
blanking the tap or a callback overrunning, and released by its watchdog only after thirty seconds.
That fits the first round, which follows the warm up chord and about three seconds of scripting
against Chrome with a freshly raised window. It is not proven.

The one measurement that settles it is a harness command polling the leader's active state and the
plugin's showing flag every twenty milliseconds from just before the typing until the failure, read
together with the console for a ChordKey lost key up line, a reload banner, or a second test agent
listening line. That measurement was not taken, so the item is recorded and left here. The Status and
Now above were rewritten from this entry, and the multi window cases are no longer open.

Corrected 2026-10-19 11:32, see below.

### 2026-10-19 11:22, the harness traces the leader through the typing and refuses to type while it is held

Built from the theory of the entry of 2026-10-19 10:30, and not yet run. The root gained a word,
`leaderHeld`, beside `stageQuery`, answering whether the Hyper leader is believed held through the
hyper key atom's own `isActive`, and the BrowserTabs manifest declares it as optional, saying only
the harness depends on it. The tool's surface hands it out inside `live()` and as its own
`leaderHeld()`. In `test/agent.lua` a `watch` command polls every twenty milliseconds for up to six
seconds and records the leader state and the showing flag only when either changed, a `watched`
command stops it and answers the lines, and the timer is kept on the module. The chord now polls
the leader after its key up for three hundred milliseconds, posts the key up again with the same
stamp when it is still held, at most three times, and answers how long the release took and how many
repeats it needed, or fails with a reason. `commands.type` refuses while the leader is believed held,
so a token is never dispatched as Hyper chords. The runner starts the watch before the typing and
prints the chord's reply and the trace as `chord` and `trace` lines only when a round fails.

The guard and the trace landed together on purpose. One run of the single case then both measures
and tests, since a round that would have failed by the leader staying held either is repaired by the
repeated key up, which the chord reply reports, or stops with the reason, and in both the evidence is
in the log.

If the theory holds the trace of a failing first round shows a sample with the leader held during the
typing, the showing flag going false shortly after it, and the chord reply showing a nonzero
`reposted` or a failure. A trace with the leader never held and the list closing anyway would mean
the theory is wrong and something else closed the list. The run is owed, and nothing here was run
against Hammerspoon.

Corrected 2026-10-19 11:32, see below.

### 2026-10-19 11:32, the leader theory is refuted and the trace is rebuilt to name the closer

The theory of the entry of 2026-10-19 10:30 and the guard of 11:22 rest on a mechanism that does not
exist. It was refuted on three grounds, read from the code and the library without running anything
against Hammerspoon. First, `hs.eventtap.keyStrokes` builds every character with keycode 0 and a
unicode string, verified by disassembling libeventtap.dylib, so a typed letter can never resolve to
the x binding. Second, `lib/chordkey.lua` at line 452 drops every event whose eventSourceStateID is
not 1, and typed characters carry no stamp, so they never reach the chord path at all. Third, the
token from `bt_uniq` in `test/cases.sh` is bttag, the process id, x, then a counter, so it ends in a
digit and not in x. The sentence of the 10:30 entry about the token's final x was wrong, and so was
the claim in the 11:22 entry that a token could run as chords.

Two further statements of the 11:22 entry were also wrong. The refusal in `commands.type` only keeps a
token from being typed while Hyper owns the keys. It does not ensure a token is never dispatched as
Hyper chords, since typed characters cannot reach the chord path. And the chord reply does not report
a repair either way. It reports a repair only when `reposted` is nonzero, and a clean release shows
`reposted` as zero.

What survives is hygiene. The chord's wait for the release and its repeated key up are sound
practice against a lost key up, but they are no longer the test of the first round reading.

The trace is rebuilt to name the closer. The `onClose` handler in `plugins/browsertabs/chooser.lua`
records the time and a traceback in `M.lastClose`. The agent's `watch` also records the field text
and the frontmost application's bundle id on change, and runs a passive key down tap recording each
event's keycode, source stamp, characters and leader state. `watched` answers the samples, and the
close time relative to the watch start when it falls inside the window, with the traceback. The
runner prints a `closer` line per traceback line on failure, and prints the chord line on any round
that reposted or released after a wait. The leader wiring is also checked, since a missing
`leaderHeld` word read as never held. The ping answers `leaderWired`, the chord reply carries
`wired`, and the run fails at the start when it is false. Nothing here was run against Hammerspoon.

### 2026-10-19 12:26, the declined raise is reproduced and the engine repeats it once

Two runs from the worktree that day, both before this entry. At about 11:50 `suite.sh --only frontmost`
passed both rounds, the first round included, with the chord released at once and no repost, so the chord
line never printed. At about 12:00 `suite.sh --quick`, with two windows in each browser opened on blank
pages by id and closed after, passed 44, failed 1 and skipped 1, the skip being `tab_group on safari`.
The first round, `frontmost on chrome`, passed. So the close between the typing and the live read did not
reproduce under the trace in two runs, and the trace stays armed.

The one failure was `no_query on chrome`, with com.apple.finder frontmost. The witnesses were these. The
browser's own dictionary reported window 1206251595 on active tab 38, the fixture. System Events reported
Finder frontmost. Chrome's own front window was the fixture window, named bttag58587x41, with a real
position. The live read before Return held the fixture under the highlight with an empty query. So the
provider selected the tab, the engine's `w:focus()` raised the window among Chrome's windows, and macOS
declined the application activation. This is the discretionary cross application raise that
`plugins/browsertabs/AGENTS.md` describes, seen for the first time under the harness with evidence, and
the first time on the real path since the canvas became the default on 2026-10-14. The same case passed
in the three quick runs before it that day, so it is intermittent. The console was clean after the
restore.

The plugin's note said a second raise is only worth adding against a failure that can be reproduced, and
this one now is. The decision is that `focusTabWindow` in `plugins/browsertabs/engine.lua` arms one timer
after any of its three raise calls, `RAISE_CONFIRM_SECONDS` of 0.15, kept as `M._raiseConfirm` and re armed
by stopping the previous one. If the browser is not frontmost when it fires, it calls `app:activate(true)`
once and logs one info line. The value is long enough for an honoured activation to have landed, since
measured activations land within a few tens of milliseconds, and short enough that nobody sees a pause.
The provider and the order of the activation are unchanged. Not run against Hammerspoon, and whether the
repeat is honoured where the first was declined is unread.
