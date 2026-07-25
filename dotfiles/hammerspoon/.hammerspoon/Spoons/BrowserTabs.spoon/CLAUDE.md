# BrowserTabs.spoon

Why this spoon is shaped this way. The code sits beside this file, so this records the
decisions and not the lines. The provider spec deliberately lives in `contract.lua`, beside
the validation that enforces it, so a method list is never copied into prose here where it
would drift the moment the contract changed.

## What it is

Every open tab across every switched on browser in one list, ordered most recently looked at
first, each row carrying its browser's application icon so a tab's origin reads visually
rather than from its text. Choosing a tab selects it in its window, raises the window, and
brings the browser to the front. The last row opens a settings level where each browser is
switched on or off and shows whether it is installed, open, and allowed to be scripted.

## The shape, and why the root names the browsers

Strategy wired through injection, the same layout `Capture` and `Vpn` use. `engine.lua` is the
mechanism, it fans a listing out across the browsers and merges the answers, talking only
through `contract.lua` and naming no browser. `providers/` holds one file per browser.
`init.lua` is the spoon composition root and the ordering policy. `recency.lua` is the
observed order, `permissions.lua` the Apple Events grant, `chooser.lua` the surface.

The concrete browsers are named in the main `init.lua`, not here, which is why this spoon
exposes its backends as `BrowserTabs.providers` for the root to pick from. That follows the
Emoji precedent, where the root names the backends by reference, and it keeps the one
composition root of truth the hammerspoon `CLAUDE.md` describes. Adding a browser is a file in
`providers/` plus a line there, with no edit to the engine.

## Bulk property fetch is not an optimisation, it is the design

Asking a browser for each tab's title and URL one tab at a time costs one Apple Event per
property per tab. Measured on a real machine that was 3.08 seconds for an Arc holding 88 tabs
and 1.67 for a Chrome holding 60. Asking for every title in one call and every URL in one call
costs one event per property per window instead, and the same reads came back in 0.135 and
0.133 seconds. That is a twenty times difference and it is the line between a usable tool and
one nobody would open twice, so every provider is written in the bulk form and a future one
must be too.

This is also why the providers are JavaScript for Automation rather than AppleScript. JXA
expresses the bulk form directly, returns JSON, and addresses an application by bundle id, so
no provider needs a separate scripting name alongside its bundle id.

And it is why everything runs through `hs.task` and never `hs.osascript`. Even the bulk form
costs about a tenth of a second, most of it the interpreter launch, which `hs.osascript` would
spend blocking the main thread. Through tasks the browsers are asked concurrently and a full
listing costs about as long as the slowest single browser rather than the sum.

## An hs.task must be held or it dies

A task kept only in a local is collected once that local goes out of scope, before the child
process finishes, and its callback then never runs. That failure is silent, the caller simply
waits forever, and it is timing dependent so it appears intermittently. `jxa.lua` and
`permissions.lua` each hold their tasks in a table until the callback has fired. This bit
during development and the fix is easy to undo by accident, so it is commented at both sites.

## Recency is observed, because no browser reports it

Not one browser exposes a per tab last access time. Chrome and Arc give a tab an id, a title,
a URL and a loading flag, Safari does not even give an id, and none of the three carries a
timestamp. So the recency the tool is built around cannot be read and has to be watched, which
is what `recency.lua` does. It is the Observer half of the pair `DisplayMemory` forms with
`TerminalHandler`, a watcher that records what it sees and a persisted order read back later.

Two events mean a tab became current. A browser coming to the front, seen through an
application watcher. And a tab switch inside a browser that is already frontmost, which fires
no event of its own but does change the window title, because each of these browsers titles
its window after the active tab, so a window filter on title changes is the only signal
available. Both are coalesced, since a page load fires title changes in a burst and each
sample costs an Apple Event.

The honest limitation is that only tabs actually visited while Hammerspoon runs earn recency.
Everything else falls back to the resting order below, which is front to back depth on screen
and not recency at all. Presenting that fallback as recency would be a lie, so it only ever
decides the tail of the list, below everything observed.

## Identity is the bundle id plus the URL

It cannot be a browser tab id. Safari has none, and the ids Chrome and Arc do give are not
stable across a restart, so an order keyed on them would be worthless after a reboot. A URL
key costs two things. Two tabs on the same page in the same browser share one recency slot,
and a set of fresh blank tabs collapse together. Both were accepted deliberately. If tab
identity ever needs to be exact, this is the decision to revisit, and it lives in one place,
`recency.keyFor`.

## Arc reports no active tab

Arc's window `active tab` returns null, verified both while Arc was in the background and
while it was frontmost, and an Arc window's `name` is the space name rather than the active
tab title, so there is no route to it at all. That is a limitation of Arc's dictionary and not
a gap in `providers/arc.lua`.

Two consequences. No Arc row is marked as the active tab. And an Arc tab earns recency only
when it is opened through this tool, never from switching tabs inside Arc by hand. Arc still
implements `activeTab` and answers nothing, rather than omitting the method, so the contract
stays uniform and the one browser that cannot answer says so in exactly one place.

## Permission is readable without asking, which is the whole reason for the Swift helper

macOS gates Apple Events per pair of applications, so scripting a browser needs an Automation
grant for Hammerspoon against that browser specifically. The naive way to discover the state
is to send a real event and see what happens, but that is destructive: a refusal is remembered
forever and macOS then never prompts again. So looking has to be separable from asking.

`AEDeterminePermissionToAutomateTarget` does exactly that, and with its ask flag set it is
also the documented way to raise the prompt deliberately. Hammerspoon has no binding for it,
so it lives in `probe.swift`, compiled once and cached under Library Caches, outside the
watched config tree so building it never triggers a reload. That is the same arrangement
`Eyedropper` uses for its native sampler.

The status it reports describes the calling process, which for a helper spawned by Hammerspoon
is Hammerspoon, because macOS attributes automation to the responsible parent rather than the
immediate binary. That is what makes this work, and it is verifiable: the same binary reports
`granted` from a terminal that holds the grants and `notDetermined` from Hammerspoon, which
held none. Reading the TCC database confirms the grants are recorded against the parent.

Four states need different offers, which is why the browser level is a menu and not a single
toggle. `granted` needs nothing. `notDetermined` can become `granted` by asking, so the tool
offers that, and only while the browser is running, since a permission for a closed app cannot
resolve. `denied` cannot be re-prompted at all, so the only honest offer is the Automation
pane in System Settings. `notRunning` means there is nothing to ask about yet.

## A row appears only when it asks something of you

The browser level showed its state as read only rows at first, installed, open, and the
permission, whatever they said. That reads as thorough and works as clutter. Three rows all
confirming that nothing is wrong bury the fourth that is not, and the reader has to check each
one to learn there was nothing to do. So the switch is always there, since it is what the level
is for, and everything past it is shown only when it blocks you. Installed, allowed, switched
on, and the level is two rows.

Nothing is lost by hiding them, because every browser already carries its state in its subtitle
one level up, which is where glancing at a set belongs. Drilling in is for acting on one.

The pairing that makes this safe is the console. Since a state that reads fine leaves no trace
on screen, a quiet screen has to mean nothing was wrong rather than nothing was noticed, so
anything the surface cannot act on is logged instead of hidden silently. A permission that reads
unknown, a refusal, a request that ends as anything but granted, alongside the listing and
activation failures the engine already logs.

Permission rows are also gated on the browser being switched on. A switched off browser is never
scripted, so whether macOS would allow it is not a question yet, and offering to raise a system
prompt for a browser deliberately turned off would be asking for the wrong thing. Not installed
is the one obstacle the switch cannot answer, so it replaces the switch rather than sitting under
a control that would do nothing.

## A browser that is off or closed is never scripted

The toggle means not queried, not queried and hidden. A switched off browser costs no Apple
Events and never raises a permission prompt, which is the point of having the toggle for a
browser you would rather Hammerspoon left alone. The recency observer honours the same rule,
so switching a browser off silences the watching too.

Closed is checked at dispatch rather than resolved once at load, for a reason beyond freshness:
addressing a specifier on a quit application launches it, and being asked for its tabs must
never start a browser. Every provider carries the same guard inside its own script as well, so
the rule holds even if a caller forgets.

Only Safari is on by default, decided in the main root and not here. A fresh machine therefore
scripts one browser and raises one prompt, and the rest are switched on deliberately. A browser
added to the root later also starts off, because the default set and not mere presence is what
turns one on.

## Why the surface opts out of the shared matcher

It is a stack of frames, not one flat list, so letting the atom filter uniformly would rank
away the Back row on the settings levels and pull the pinned Settings row into the tab ranking.
So it opts out and scores its tab rows itself with the matcher the root injects, which keeps
the one shared matching policy while leaving the pinned rows outside it. That is the same
reason `DisplayProfiles` and the overlay display picker opt out, with the difference that this
tool still uses the shared matcher rather than writing its own filter.

The Settings row is pinned last rather than ordered, so it never drifts up into the recency
order and a typed filter targets the tabs, the same reason `Vpn` pins its action row above the
cities. Back is the first row on the settings levels, per the chooser menu convention.

Last is not the same as reachable, though, and the first build got that wrong. With a hundred
tabs above it the row sat a hundred keystrokes away, and the chooser's navigation clamps at the
ends rather than wrapping, so in practice it could only be reached with the mouse. It is still
last, and now a typed word that means settings brings it back, appended after whatever tabs
matched rather than ranked among them. That test is a prefix match over a small fixed keyword
list and deliberately not the injected matcher, because fuzzy matching against a keyword list
also fires on queries that never meant it, and a settings row appearing unbidden under a tab
list is noise.

Menu steps are in place, using the same Return interceptor `DisplayProfiles` uses, so stepping
into settings and back never closes and re-shows. Opening a tab is the one terminal action.

## Degradation

No provider validates, the list is empty and says so. A browser switched off, closed, or
refused each produce their own explanatory row rather than a short list with no reason, the
same self explaining shape `Vpn` gives a missing CLI. Without the Swift toolchain the probe
cannot build and every permission reads `unknown`, which costs the ask and the status wording
and nothing else, the tab list still works. Dropping the surface wiring in the main root leaves
the engine and the observer working, they just have nothing to draw.

## What it does not do

It does not close, move, or reorder tabs, only find and open them. It does not read tab history
or search page content. It does not group rows by browser, since one recency ordered list
across all of them is the point, and the browser icon plus the subtitle already say where a tab
lives.

Firefox is deliberately absent. It has no AppleScript tab support at all, so it cannot use this
shape, and would need a provider that parses `sessionstore-backups/recovery.jsonlz4`, which is
LZ4 behind a Mozilla header. That file is ironically the only place a genuine per tab
`lastAccessed` exists, and it also cannot activate a tab once found, so a Firefox provider
would be read only and asymmetric. It is a later addition, not an oversight.

## Restow

Adding this spoon needed a restow, since `~/.hammerspoon/Spoons` holds one symlink per spoon.
New files inside it resolve through the existing link and need none.
