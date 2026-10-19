# Olm BrowserTabs, the harness and the raise

Status. The integration harness types untargeted since 2026-10-19, and its first rerun after
that is still owed. Two things are open and unread. Whether macOS honours the cross application
raise from a chooser that never holds the front, and the Chrome witness anomaly, where three
readers of one browser disagree about its windows. The anomaly has nothing to do with typing.

## Now

The harness drives the real path, the leader chord, a typed query and a real Return, all posted as
untargeted events through `hs.eventtap`, the chord stamped as hardware. The default chooser is a canvas whose surface
never becomes the key window, and its field reads keys only through a session level event tap, so
untargeted events are the only kind it can receive. A round is judged by two witnesses that share
no implementation, the browser's own dictionary and System Events. Its `top` precondition is a
ranking the agent recomputes from the plugin's rows, so it proves what the ranking would put first
and says nothing about what the live list shows. The Chrome witness anomaly is open. Across the
Chrome rounds of the run of 2026-10-17, `hs.application:allWindows` on Chrome returned an empty
list while `hs.window.focusedWindow` returned a Chrome window, and in `hidden_app on chrome`
System Events reported no Chrome window for the whole settle although Chrome ended frontmost with
the target window focused. In `frontmost on chrome` the front window was a "Vicert One-Pager"
window that the browser's own dictionary does not list. The three readers are the browser's
dictionary, `hs.application:allWindows` and System Events, and they disagree. A second Chrome
process or profile sharing the bundle id is a plausible cause and it is unverified. It has nothing
to do with typing, and the rerun is where it will be read. The tool's own raise path is unchanged in code
since 2026-08-21, and the raise concern in `plugins/browsertabs/AGENTS.md` stays open until a rerun
reads it.

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
