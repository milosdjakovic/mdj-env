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

Both ends of a burst are sampled and neither alone would do. The end of it is what settles a page
that renames itself while it loads, and it is the only reason the delay exists at all. But
waiting for it also made a plain tab switch, which fires one title change and never a burst, take
the whole delay before anything was recorded. Measured, a switch reached the remembered order
1.448 seconds later, in three roughly equal parts, half a second for the title event to arrive,
the 0.45 second delay, and the Apple Event that reads the tab. So the start of a burst is sampled
too. A burst keeps a timer pending throughout, which is exactly the test for whether one is
already running, so the leading sample fires once when a quiet browser first stirs and not again
until it has gone quiet. That took the same measurement to 0.821 seconds. The cost is two Apple
Events per burst rather than one, and at worst a doubling under sustained title churn, which is
bounded by the delay because the leading edge cannot fire while a timer is pending.

Why that number matters rather than being a curiosity. The list paints what it holds and corrects
itself when the browsers answer, and the section further down on that describes how the paint is
made to agree with the answer. It can only agree as far as the remembered order is current, so
anyone switching a tab and reaching straight for the list was inside the lag and watched the list
rearrange itself. Measured through the surface, at a one second pause the switched tab was still
at rank two when the list painted and rows moved when the read landed. After the leading edge it
is at rank one by then and nothing moves. What is left is under about eight tenths of a second,
which needs the list opened at very nearly the same moment as the switch.

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

## Opening a tab is three separate acts, and one of them was missing

Choosing a row looks like one action and is really three, select the tab, make its window a real
window again, and put the browser in front. Only the first was ever in doubt and it turned out to
be the reliable one. Setting the tab works with the browser in the background, the choice survives
the browser coming to the front afterwards, and Safari and the Chromium family behave the same, so
a chosen tab that never appears is never about the tab.

The missing act was the minimized window, and it is the one that reads as the tool doing nothing at
all. Raising an application does not restore a window from the Dock, verified, the browser becomes
frontmost while the window stays down, so the tab is selected in a window nobody can see and the
honest description is that a keystroke did nothing. Choosing the same row again does nothing twice.
So each provider restores its own window before selecting the tab, and that sits in the providers
rather than in the engine only because the dictionaries disagree on the name, `minimized` in the
Chromium family and in Arc, `miniaturized` in Safari, which is the Standard Suite spelling. Arc's
was read out of its own sdef rather than assumed from its Chromium heritage, since an sdef can be
read without launching the browser and a wrong guess here would fail silently inside a `try`.

The order of the restore against the window reorder inside the provider is not something to
theorise about. It was written one way, then written the other way after a measurement that turned
out to have been taken through a drifting specifier and so was reading a different window than it
believed. Measured again with the window addressed by its id, both orderings end with the window
restored, at index one, and frontmost, on both browsers. So neither is better and no rule about it
belongs here.

The order of the two outer acts is measured rather than chosen. Raising the browser before the
provider answers looks like the obvious way to save a tenth of a second, and it loses the front
every time, because a chooser hands focus back to the application it was opened over when it hides,
so the raise lands and that restore immediately undoes it. Sent after the answer it is past the
restore and it holds. That is why the raise sits in a callback that otherwise looks like it could
be flattened.

## Why choosing a tab used to do nothing, four separate faults with one symptom

Every one of these ends as the browser not switching, which is why it read as one intermittent
fault for so long, and why fixing any one of them left it still failing sometimes. All four were
found by instrumenting the shipped path and driving it with synthesised keystrokes through the real
shortcut, the real chooser and a real Return, and each fix was confirmed on both browsers with a
window that was minimized, a window in the background, and a window already in front.

A positional window specifier drifts under the very writes this code makes. `app.windows[i]` binds
to the slot rather than to the window, so any reorder silently redirects it, and both setting
`window.index` and restoring a minimized window reorder the list. Proved directly, a reference
holding Safari window 9536 reported window 206 after a reorder, with Chrome behaving the same. So
the minimize restore was reading and writing a different window whenever the target was not already
first. Every provider now addresses its window through `windowById` in the shared prelude, which
resolves the id afresh on each access, and the prelude lives in `jxa.lua` rather than in each
provider so a new provider cannot forget it.

Raising an application is not the same as raising a window. macOS restores whichever window that
application last had focused, which is very often not the one the tab lives in, so the browser
arrives showing something else and the switch looks like it failed. Measured against a second
window three times out of three, and focusing the window directly won three out of three under the
same conditions. So the engine finds the tab's own window and focuses that, and only falls back to
raising the application when it cannot.

Finding that window is the hard part, and the reason the engine tries three things in order. A
browser numbers its windows in its own dictionary and the window server numbers them in another.
Safari's are the window server's own and match exactly, Chrome's are a private counter around 1.2
billion that matches nothing, so the id is tried first and never assumed, over this application's
own windows so a number meant for one namespace can never match a window in the other. Failing
that, the window's own name, which the provider reads after the tab switch. Failing that, the tab's
title. Both of the last two are needed because each covers the other's measured failure. Chrome
elides a long window name in the middle with an ellipsis, which appears in no accessibility title,
and the tab title goes stale when a page retitles itself after the list was read, which was caught
happening to an ordinary shopping page mid run. The test is containment rather than equality or a
prefix, because the two browsers decorate the accessibility title at opposite ends, Chrome
appending its own name, any tab group and the profile, Safari prefixing the tab group. A prefix
test was the first attempt and it failed every time on Safari.

`hs.application.applicationsForBundleID` returns an empty list on the first call after the browser
has been disturbed, even though the browser is running, is in `runningApplications`, and answers
`hs.application.get` by name, and twenty further calls in the same instant all succeed. The engine
answered that by silently raising nothing, and the same call decides whether a browser is listed at
all, so it could equally have dropped a browser's tabs from the list. `apps.lua` exists for this one
fact and asks a second way when the first comes back empty. It is a workaround for a library
behaviour, which is why it sits in its own file with the measurement written down rather than being
inlined at the four call sites that need it.

Safari lists a window that is not on screen at all, a leftover carrying a single Start Page tab,
invisible to the accessibility layer, so the row offered for it can be chosen and nothing happens.
The provider now skips a window with no document. The test is the document rather than the
`visible` flag, because a minimized window is not visible either, and neither is any window of an
application hidden with Command H, so filtering on that would throw away real tabs. A window
genuinely showing the Start Page still has a document. All three cases were measured.

## A tab position is not a tab identity

The tab numbers in a listing move whenever a tab is opened or closed afterwards, and they do,
within minutes of ordinary browsing. Activating purely by position therefore lands on a neighbour,
which reads as the tool switching to the wrong page or opening something unasked for. So each
provider checks the position against the URL that came with the tab and only trusts it when the two
still agree, otherwise it looks the URL up. The position is preferred rather than the URL because a
window very often holds the same address more than once, and when nothing has drifted the position
is the only thing that says which of them was meant. Verified in both directions on both browsers,
and verified not to move when a window holds three tabs on one URL.

What is still not guaranteed is the raise itself. macOS honours a cross application raise asked for
by an application that is not frontmost at its own discretion, and it was seen ignored twice while
Hammerspoon had never held the front, the tab correctly selected and the browser left behind. From
the real path, where the chooser held the front a moment earlier, it held every time it was tried.
There was no retry for a long time, because a second raise is only worth adding against a failure
that can be reproduced, and that one could not be.

A failure of this family can be reproduced now, on Safari, and the section below records exactly
what it looks like. It is the open defect in this spoon and the next thing to work on.

Two things this tool cannot answer at all. A tab in a window on another Space costs whatever the
Space switch costs, which is macOS animating rather than anything to tune here. And while a
password field holds focus macOS turns on secure input, which stops every event tap on the machine
from seeing keys, so the leader that opens this list never fires and nothing reaches this spoon,
the pressed letter going into the field instead. Neither is a defect here and neither has a fix
here.

## The suite that guards all of this, and why it can only be an integration one

Everything above was found by hand and would have been lost the same way, so `test/` now holds a
harness that drives the real thing. Its own README carries the detail, but the reasoning behind its
shape belongs here, beside the faults it exists for.

None of the four faults could have been caught by a test with a fake browser in it. Every one lived
in Apple Events, in the accessibility layer, or in real browser state, so a suite built on fakes
would have passed cleanly through the whole period this tool was broken, which is worse than having
none for being reassuring. That is the entire argument for the cost, and the cost is real. It takes
the machine-wide test lock, it steals focus for about twenty minutes, and it cannot run anywhere but
on a machine with these browsers open.

A round is judged by two witnesses that share no implementation, because this tool writes to two
layers and reads back through only one of them, so it agreeing with itself proves nothing. The
browser's own dictionary says which window is in front and which tab it shows, and System Events,
from outside this process, says the same about the accessibility layer. They are tied together by
the window frame rather than by the title, since a frame is a number belonging to one window while a
title is decorated differently by each browser and changes under you as a page loads. Where two
windows share a frame, which happens constantly, the title breaks the tie.

A state that cannot be created reports itself as not covered rather than passing, and the summary
keeps that apart from what passed. A pinned Chrome tab, a Safari tab group, and a discarded tab are
all in that category some of the time, and a suite that quietly counted them as passes would be
claiming coverage it never had.

What the suite has actually said so far is in its README, both the case by case record and the
harness defects it caught in itself, every one of which had been producing false passes. That
record is the reason to trust a green run at all, so it is kept rather than left in a results file
the next run deletes.

## The one open defect, a Safari restore that Safari says happened and nobody can see

The suite reproduces this on demand through the ordinary path, which is what the raise paragraph
above had been waiting for. The case is `minimized on safari`. Chrome has never once failed it.

The witnesses disagree in a specific way. Safari's own dictionary says the window is not minimized,
that it sits at index one, that it holds a document, and that the fixture tab is the selected one.
The window server says Safari has no windows at all, and three readers agree about that
independently, System Events from another process, `hs.window`, and `hs.spaces.windowSpaces`.
Safari is nonetheless the frontmost application. The state does not resolve, it holds for the whole
four and a half second settle the suite allows.

So the restore is acknowledged and never completes on screen. That matters more here than it would
anywhere else, because this tool reads back through the browser and the browser is the layer that is
wrong. Every check inside this spoon would call that round a success. From the person's side the
keystroke did nothing, which is the original complaint this spoon was rewritten to fix.

What was ruled out, each by measurement rather than argument. Not a locked screen, checked before
every round. Not the window still being minimized, the browser is asked directly and says
otherwise. Not a window on another Space, both windows sit on the focused Space at rest. Not the
harness driver, since it fails through real synthesised keys. Not one particular window, since the
same window both passed and failed across two runs. Not the first round of a run, since it has
failed the first two rounds and passed the third. And not state accumulated over a long suite,
since it returns within a handful of rounds of a freshly restarted Safari, though a restart does
delay it.

What it does correlate with is minimizing and restoring the same Safari window repeatedly in quick
succession, which is what the case does and what nobody does by hand. That is worth saying plainly,
because it means this may be Safari failing under abuse rather than a fault in this spoon. It is
still this spoon's problem, since the tool cannot tell the difference and currently reports success
either way.

The fix this argues for, not yet written, is to confirm through the accessibility layer that a
window really arrived after the restore and the raise, and to say so in the console when it did
not, with a second attempt if that proves to help. Reading back through the layer the tool does not
write to is the same principle the suite is built on, and it is the only thing that would have
caught this without a person watching the screen.

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

## Both outside tools are declared, and neither is injected

This spoon runs two binaries, `osascript` from `jxa.lua` and `swiftc` from
`permissions.lua`, and each is declared in a `.dependencies` file beside the file that
names it. Both are the system kind, binaries at fixed absolute paths that cannot move
between machines, so the declaration records the path and the Lua file keeps the same
literal. Nothing is resolved at load and nothing is handed in through `configure`. The
declarations exist so the repository's manifest records what this spoon actually runs,
which is the whole point of declaring rather than probing.

`swiftc` is declared here and also by `Eyedropper`, which compiles its own native helper.
Both declarations are kept. A declaration belongs beside whatever knows the tool, and
neither spoon should have to learn that the other exists. The manifest carries a line per
owner, the repository joins them by name, and one map entry answers both.

Both are optional rather than required, because required means the root should refuse to
wire the spoon, and the root wires this one unconditionally. A missing compiler is already
answered in this spoon's own words through the permission rows.

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

## What a query is scored against, which is three fields and never one string

The first build glued the title, the address and the browser name into one searchable string and
handed that to the matcher. That is wrong in a way worth recording, because it looks harmless and
reads as generosity. The shared matcher is a subsequence scorer, so one string lets a query be
satisfied by taking a letter from the title, a letter from the address and a letter from whatever
follows, which is a match no reader would call one.

The browser name at the end was the worst of it, and it was measured rather than reasoned about.
A trailing gap costs almost nothing in that matcher, so `far` reads as a contiguous run inside
`Safari` and lifted every Safari tab in the list, thirty four rows on this machine, not one of
which contained the word. Scoring the fields apart cut the same query to twenty five rows and
every one of them was a real hit.

So the title, the host, and the full address are each scored on their own and the best of them
wins. The host is scored apart from the address it sits inside, because against the host alone a
query lands at the start of a short string and earns what it is due, while buried in a long
address the same letters read as a weaker match, and a tab on `github.com` should answer to `git`
whatever its page is called.

The browser name is still a field, gated behind a plain prefix test rather than scored freely.
The gate is the fix, not the removal, and the difference showed up as a regression when the name
was merely admitted at a fixed low score instead, which let a Safari page that fuzzily resembled
`chrome` sit above sixty six actual Chrome tabs. Once the gate has passed, the name goes through
the same matcher as everything else, so typing a browser gathers its tabs and a page genuinely
named after that browser can still outrank them. This is the same reasoning as the settings
keyword test above, and for the same reason, a fuzzy match against a short fixed name fires on
queries that never meant it.

A row therefore carries no `filterText`. That field is how a row tells the atom what to search,
and the atom is stood down here and in the launcher scope alike, so a row carrying one would be
stating a searchable text nothing reads, which is the kind of second source of truth that drifts.

## Recency reorders a typed query, and the unit it is measured in is the point

Before this, recency decided the whole list until the moment you typed, and then stopped counting
entirely, surviving only as a tie break between two scores that happened to be exactly equal.
Typing one letter threw away the ordering the tool is built around. So a bonus scaled by recency
is now added to the score of every tab that matched.

It reorders and never overturns, which is the rule `FileSearch` already set for its frecency and
is the only rule that keeps this honest. The weight is set against the matcher's own scale. A
single better placed character is worth six points or more there, while two tabs matching the same
shape at different depths in their text differ by fractions of a point, so a bonus of three
separates the second pair and cannot touch the first. Measured on a real listing, a tab used
eighth most recently and scoring 62.00 moved above three rows scoring 62.34 to 62.44, and did not
pass the row above them at 65.78.

The unit is the part that was got wrong first and is worth knowing. Scaling the bonus by a tab's
place in the remembered order sounds right and is nearly inert, because that order holds every
address ever looked at, every step of a redirect chain and everything since closed, so on this
machine the twelve most recent stored keys contained three tabs that were still open. The bonus
is scaled by position among the tabs actually being listed instead, which the listing already
supplies since it arrives recency ordered, and then the tenth position means the tenth most
recently used tab you still have open. That count is taken over the whole listing rather than
over the tabs that matched, because a tab's recency is a fact about the tab and must not change
with what was typed.

A tab nobody has looked at earns nothing and takes no position, rather than being treated as
infinitely old. That is the same honesty the resting order keeps, and it is why the surface asks
for a rank that may be nil rather than for a number.

## Why the list used to rearrange itself a moment after it opened

Opening this list paints what was held from last time and then corrects it when the browsers
answer. That trade is right and is not the thing to change, since the alternative is an empty
window for as long as the read takes. What was wrong is that the correction almost always had
something to say, so the visible behaviour was a list that settled itself under the reader
rather than one that was simply there.

The window it settles in is measured, not guessed. A full read is 0.368 seconds across two
browsers holding 93 tabs, Safari answering in 0.288 and Chrome in 0.429, concurrently, so the
whole cost is the slower of the two. Third of a second is far too long to be reading a list
that is still moving.

The cache is stale in exactly one way and it is the same way every time. Opening a tab is what
closed this list last, and opening a tab is precisely what changes the remembered order, so the
order held is always at least one move behind. Switching tabs by hand between two opens does the
same through the title watcher. Membership changes far less often, only when a tab is actually
opened or closed.

So the remembered order is applied again to what is held, before anything paints. That costs two
ten thousandths of a second over 93 tabs and it makes the first paint agree with the answer that
is still coming.

Only the recency half of the ordering is reapplied, which is why the root hands the surface a
`reorder` that is not the same as what `listTabs` does. Settling the tabs nobody has looked at
into front to back depth means walking every window on screen, measured between 34 and 59
milliseconds, and that walk would land directly in front of the window appearing, which is the
very thing being fixed. Depth is not what went stale, and it only ever decides the tail below
everything observed, so the tail keeps whatever the last full read gave it.

The second half is that the correction is now skipped when it would correct nothing. A redraw
is not free even when every row comes back identical, because rebuilding the list keeps the
highlight's number and not the row it was sitting on, so a reader who had already arrowed down
lands somewhere else. The listing is kept alongside a signature of what it is made of, identity,
title and Arc's group, in order, and an answer matching it does not redraw. An empty list always
redraws, since what is on screen then is the reading row and it has to come down whatever the
answer was.

None of this makes the first open of a session instant. There is nothing held then, so the
reading row shows for the length of a full read, and that is honest. Warming the listing at
startup would fix it and is deliberately not done, because reading a browser's tabs is what
raises the macOS automation prompt, and raising that at login rather than when someone first
asks for their tabs is the wrong trade. The permission probe is warmed instead, which never
prompts.

## Handing the tabs to another list, without the settings level

`tabRows`, `explain`, `activate`, `prepare` and `ready` are the tabs offered to a surface other
than this chooser, which is what the launcher's `t` scope is. They are the tab level only, and
the settings level deliberately does not come along, since it is a step into a second list and a
scope shows one. So the guidance rows take the phrase naming where the browser switches are,
rather than saying "in settings below" where there is no row below.

The ranking is shared rather than copied. `matchedTabs` was pulled out of the frame supplier and
both callers go through it, so a scoped list and this chooser cannot disagree about which tabs a
query matches or in what order. What differs between them is only which extra rows get appended,
which is exactly the part that is per surface.

`prepare` is the one listing path and `reload` is now a call to it. A second ask while one is in
flight joins that flight and every waiter is called when it lands, so two surfaces asking at once
cost one read of the browsers and neither is dropped. `Vpn` took the same shape for the same
reason. Without that, a scope asking on entry while this chooser was already listing would script
every browser twice.

`ready` is what lets a caller tell an unread list from an empty one, which matters because they
look identical and mean opposite things. `explain` exists so the caller does not have to guess
which it is, this file knows whether it is still reading, whether nothing is switched on, or
whether a browser refused.

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
