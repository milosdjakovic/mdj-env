# Processes.spoon

The decision trail and the important facts for this spoon. Cross cutting material
stays in the hammerspoon `CLAUDE.md`, which links here. The picker checklist, the
spoon lifecycle contract, and the composition wiring this file refers to live there.

## What it is

A picker that finds the development servers you left running and stops them. A row
is identified by the port it holds and the project directory it runs in, and
selecting it takes down the whole process group or the whole container rather than
one leaf process. Reached from the launcher only, no dedicated key.

## Why the port and the working directory are the identity

These are the two fields a process list normally throws away and the two you
actually hunt by. The question is never "what is process 34513", it is "what is on
3000" or "is the canvas one still running", and neither Activity Monitor nor a plain
`ps` can answer either.

The working directory carries more weight than it looks. Node routinely rewrites its
own argv, so a running `next dev` reports itself as `next-server (v16.2.11)` and
names no project at all, while its cwd names the project exactly. So identity is
built from cwd first and the command line is only ever supporting detail. The label
walks up one level when the directory name is too generic to mean anything, which is
why a webpack server in `canvas/home-app/static` reads as `home-app / static` rather
than the useless `static`. That list of generic names is config data, not code.

## Stopping signals the group, and that is the point

A development server is the leaf of a supervisor chain. A real `next dev` here is
five processes, a keepalive shell into `npm run dev` into a node wrapper into the
server into a build worker, all sharing one process group. Signalling the listener
alone either gets it restarted by its parent or leaves the rest orphaned holding
memory, which is exactly why stale servers accumulate when you kill them by hand.
So the group is both the correct thing to signal and, because it can reach further
than you expect, the correct thing to show before signalling.

The escalation is graceful first, then unconditional after a grace period, with the
escalation reported rather than silent. The guards refuse a group containing launchd
or Hammerspoon itself, and refuse outright when the group is larger than the
configured threshold until the caller passes `confirmed`. That split is deliberate.
The threshold lives in the source, where the live process table is, while the
decision to ask lives in the UI, where the user is, so neither has to know the
other's business. Force stop skips both the grace period and the size check, since
it exists precisely for something already wedged.

The group is re-read live at stop time rather than trusted from the scan, because
the picker may have been open a while and a tree grows and shrinks underneath it.

## Sources are a Strategy family, and the merge is one generic rule

The Capture.spoon layout. `engine.lua` is the Context and names no source, each file
in `sources/` knows only itself, and `contract.lua` declares the three methods.
Termination lives on the source rather than in the engine, so signalling a process
group and stopping a container are two implementations of one method instead of a
branch the engine has to grow.

The merge rule is worth understanding because it does more than it appears to.
Sources are an ordered list and a row is dropped when everything that identifies it
has already been claimed by an earlier source. That single rule, which mentions
nothing concrete, is what collapses a dozen identical docker proxy listeners into
named containers. Registering docker first is the whole mechanism. Reversing the
order was tested and does exactly the inverse, the proxy survives as one row holding
ten ports and the published containers get suppressed instead, which is the proof
that the claim really is decided by registration order and not by a special case
somewhere. What identifies a row is spelled out under the claim section below, since
a row holding no port has to be identified by something else.

Docker is not a nicety. Every published container port is held by one long lived
proxy process, so without this source a port scan shows the same daemon a dozen
times and the only thing it offers to stop is Docker Desktop itself. On the machine
this was built on that is eleven of the listening ports.

## Discovery is an allowlist, not a denylist

A listener qualifies when its runtime is one you develop in, or when its working
directory sits under a dev root, which catches a toolchain the list has not met yet.
The runtime is matched against the kernel process name rather than argv, for the
argv rewriting reason above.

An allowlist because the set of system daemons that happen to hold a socket is
unbounded and grows with every macOS release, while the set of runtimes you develop
in is small and changes rarely. A denylist would need endless maintenance just to
stay quiet. The small ignore list that does exist is a safety net rather than the
filter, and `com.docker.backend` is on it so the raw proxy can never surface even
when the daemon is unreachable and its claim never arrives.

## Without a port the same two rules have to be ANDed

A port is strong evidence on its own, which is why the listener source is happy to
qualify a row on either half of the policy. `sources/runtimes.lua` looks for the
development processes that hold no port at all, a watch build, a test runner, a
wedged compiler, an orphaned worker, and there the evidence a port was carrying is
simply gone. Each half of the rule alone turns out to be far too weak to replace it.

The working directory half collapses first, and the numbers on this machine are
blunt. Nine biome language servers, a sourcekit-lsp, and four uv and python MCP
servers all run with a working directory inside a project, because an editor and an
agent inherit the cwd of whatever opened them. Every one of them would become a row
and nine identical language server rows would bury the one watcher you opened the
picker to find. The runtime half alone is no better, it would offer you every helper
your toolchain happens to have spawned.

So a portless process qualifies only when both halves hold, a kernel process name on
the allowlist AND a working directory under a dev root. The same two config keys,
read the stricter way the missing port forces. What that costs is the free catch of
an unfamiliar toolchain, which is real, and the fix is to name it in `runtimes`,
which the config already documents as the one place you edit.

The conjunction also decides the shellout order, though it is not the reason for it.
Reading a working directory is per pid and it is the expensive part. Measured here,
lsof over all 597 of my processes costs 142ms against a whole scan budget of about
72ms, while over the handful the allowlist leaves it costs 23ms. So the cheap half
runs first over a process table already in hand and the expensive half runs only
over what survives, and a full portless scan lands at 49ms. The kernel name comes
from a second small `ps` rather than from the big one, because that column is padded
to a fixed width and can contain a space, so putting it beside the command line
would leave two free form fields on a line with nothing to split them on. That
second query is restricted to your own uid, which means one call answers both what a
process is called and whether it is yours.

Rows are one per process group rather than one per process, since a watch build is a
tree exactly like a dev server is, and the shallowest qualifying member represents
it so the row still reads as the thing you started rather than as a hashed build
worker underneath it.

## The claim covers pids as well as ports, and ports outrank pids

A portless row holds no ports, so the original merge test could never drop one and
this source would have re-emitted every dev server the listener source already
found. The claim was generalized rather than special cased, and it now has two
halves that are deliberately not symmetric.

A kept row CLAIMS every token it carries in both namespaces, its ports and every pid
in its `tree`, not only its own pid. Claiming the whole tree is the part that
matters, because a listener row already stands for a whole process group, so without
it the portless source would resurface a child of a tree that was already reported
whole. But a row is TESTED against only the strongest kind of token it carries, its
ports when it holds any and its pids otherwise.

Testing both namespaces at once would look more symmetric and would be wrong. A
container row knows its published ports and cannot possibly know which host process
is proxying them, so a listener row for that proxy carries an unclaimed pid, would
pass a combined test, and would survive as exactly the nameless duplicate the
collapse exists to remove. Two listeners inside one process group are the same trap
from the other side, the second one must survive on its own port even though the
first already claimed both their pids. Ports outrank pids because exactly one row
should own a port, while an unclaimed pid is only ever the absence of evidence.

One consequence is worth knowing. Between docker and ports, reversing the
registration order inverts the collapse. Between ports and runtimes it does not, it
produces duplicates instead, because a portless row can never claim a port away from
a row that holds one. So runtimes goes last, and that is not a preference.

The old and new merges were run side by side over every shape the docker and ports
pair can produce, the typical collapse, a partial port overlap that must survive, a
container publishing nothing, a reversed registration, and two listeners in one
group. They agree on all of them, which is the guarantee that generalizing the rule
changed nothing that was already working.

## Three shellout facts that will bite anyone who touches this

**hs.task deadlocks on large output unless you stream it.** A task built with only a
completion callback silently never calls back once the child writes more than a pipe
buffer, because nothing drains the pipe until the child exits and the child cannot
exit until its writes are read. It presents as a hang, not an error. Measured here,
a full process table with command lines is around 180KB and the buffered form never
returned at all, while the same command drained through a streaming callback
finished in 52 milliseconds. So `util.run` always uses the streaming form and
accumulates chunks. Do not simplify it back.

**lsof ORs its selection criteria.** Without a leading `-a`, asking for
`-u you -iTCP -sTCP:LISTEN` means every file you have open OR any listening socket,
which is tens of thousands of rows and seconds of work. With `-a` the same scan
costs around sixty milliseconds. This was a real bug, not a tuning detail.

**The exit callback is not the end of the output.** The stream callback keeps firing
after the completion callback has already run, so reading the accumulated chunks at
exit can hand back output that is truncated, or empty when every chunk is still in
flight. The completion callback's own stdout argument does not cover the gap, it was
measured at zero bytes every single time, so there is nowhere else to look for the
missing data.

This is worse than a crash because it is silent and intermittent. A source returns
zero rows with no error and the picker simply reports that nothing is running, which
looks like an idle machine rather than a bug. Measured across a concurrent burst, a
command that exits almost immediately lost its output at the exit callback sixteen
times out of twenty, and both `ps` and `lsof` lost theirs once three sources were
scanning at once. Running the same commands one at a time never reproduced it, which
is why it stayed hidden until a third source existed. It had been seen once before
that and wrongly written off as a reload race.

So `util.run` treats the exit as one more event rather than the finish line, and
hands the result over only once the output has stopped growing for a short grace
period with the task already exited. Late chunks were measured landing within one
millisecond of the exit callback, so the fifteen millisecond grace is well over an
order of magnitude of headroom, and it is paid once per call rather than per chunk.
Do not remove it, and do not shorten it to buy back the milliseconds.

A full scan is four shellouts, run across three concurrent sources, and costs about
75ms with a worst case near 105ms.

## The live sampler runs only while the window is up

`metrics.lua` samples CPU and memory for the rows on screen, for exactly as long as
they are on screen. That is the shape of the module rather than a detail of it. This
config is always loaded, so a background poller would cost battery every minute of
every day to have numbers ready for the few seconds the picker is open. Start and stop
are the public lifecycle, `chooser.lua` owns them because it is the piece that knows
when the window opens and shuts, and the stop hangs off the Chooser atom's single
idempotent teardown, which fires once for a selection, an escape, a click away, or a
programmatic close alike. A tick is a chained `doAfter` rather than a `doEvery`, so the
next one is armed only once the last has landed and no dismissal can leave a timer
behind, and so an asynchronous sample can never overlap the one before it and take its
delta against a baseline that has already moved.

The CPU figure is a difference, never the `%cpu` column. That column is lifetime CPU
time over lifetime elapsed time, so a server that pinned a core during a build six
hours ago still reads comfortably and one thrashing right now barely moves it, which is
the opposite of the question being asked. Two snapshots of cumulative CPU time are
taken and the delta is divided by the monotonic clock between them, which is why the
first reading needs a second sample and why the second one is taken quickly rather than
a full interval later. The clock is monotonic because the elapsed time is the
denominator of every figure and an NTP correction landing between two snapshots could
make it negative.

Readings are aggregated over the process GROUP for the same reason a stop signals the
group. The work rarely happens in the leaf holding the socket, the build worker beside
it is what pins a core, so a per pid figure reads as idle for a tree busy compiling.
The group is also exactly the set a stop would take down, so the numbers answer what
you would reclaim. Summing resident memory across a group double counts the pages its
members share, which overstates by roughly one runtime binary, and that is the cheaper
error than reporting one process out of five. The CPU sum is taken as per pid deltas
rather than as the difference of two group totals, which is not cosmetic. A member that
exits takes its accumulated time out of the current total, so differencing totals would
report a large negative spike every time a build worker finished.

Containers carry no live figures. Asking the docker daemon for stats is a second
shellout costing more than the whole scan, for rows that are already named and already
the thing you would stop.

The score that heat ordering sorts on blends the two, weighted in favour of CPU, and
the weights are config rather than code. They can only mean something because each side
is normalised to its own unit first, one fully saturated core counts as one and
`memReferenceMb` of resident memory counts as one. Without that step the weights would
be comparing a percentage against a byte count and memory would always win.

History is a bounded list per row key rather than per pid, since the pid is the
unstable thing, and it is kept oldest first as a plain list because that is the order a
sparkline draws in. It is dropped on close along with the readings, because sampling
only happens while the picker is open, so a trail kept across a close would have a hole
in the middle that nothing can draw honestly.

## The numbers move, the rows do not

The tick redraws every row in place and never reorders. Reordering is a separate,
explicit act, `chooser.sortByLoad()`, which sorts the rows in hand by the latest score
once and resets the highlight to the top, since every row has moved and seeing the top
is the point of asking. Asking again re-sorts against whatever the numbers say by then,
and a rescan puts the engine's own order back, so heat order is a one shot rather than
a mode and there is no state to remember you are in.

The live figures are kept out of the search haystack. A query of "3" is asking about
port 3000, never about a row that happens to be at three percent this second, and
folding a moving number into the haystack would mean the set of matching rows changed
on its own every tick with nobody having typed anything.

The subtitle gained the two live figures at the front and lost the resident memory the
scan reported, which is a straight trade rather than a longer line. The live figure
supersedes it and says more, covering the whole group rather than the one listener, so
keeping both would have been the same fact twice. The live pair leads the line because
a number that changes under the eye has to sit in one fixed place, otherwise reading
down the column becomes a hunt. Until the first sample lands the memory falls back to
the listener's own reading, so the line is never briefly missing a number it is about
to have.

## The pane exists for the tree

A row is one line and the two things that decide whether you press stop do not fit on
it. What the process actually is, which the subtitle can only elide, and how far the
stop reaches, which the row cannot say at all. So the picker reserves a pane beside the
list and the highlighted row is described in it, the full working directory, every
port, the command line, the live trend, and the process tree.

The tree is the reason the pane was built and the rest is what fits around it. Stopping
signals the group, and the group routinely reaches further than the thing you think you
are stopping, so the number of processes and their parent and child shape is the fact
that makes the key safe to press. It is drawn as a real tree rather than a flat list
because the shape is the information, a keepalive shell over a package manager over a
runtime over a server reads as one chain you recognise, while the same five lines
stacked flat read as five unrelated processes.

The source hands over a pre order walk with a depth per member, which is enough to
rebuild the shape, and every prefix unit is exactly three columns wide so the
indentation is arithmetic rather than a byte count over a string of box characters.
Whether a member is the last of its siblings is not on the member and is read from the
walk instead, the next member at the same depth before any shallower one, and that one
lookahead decides both the corner it draws and whether its children carry a bar past
it. A root never carries a bar past it even when another root follows, because a root
draws no connector for a bar to descend from.

The tree also goes last and takes whatever vertical room the sections above it left,
since it is the one section that can be any length. Past that room it is cut with a
count of what was cut, and where there is no room for even one member the section is
dropped whole. The picker has no scroll bindings and this is why it needs none.

## The pane is one canvas docked into a rect it did not choose

It draws through the shared surface, the same routine behind the docked shortcut panel
and the cheat sheets, so the three read as one component. It is not a CanvasPanel
instance though, and the reason is placement rather than looks. A CanvasPanel computes
its own position from an anchor and its own size from its content, while this pane has
to land exactly on the companion rect the Chooser atom already reserved and reported
through `onPositioned`. That rect is also the one the atom's click watcher treats as
part of the picker, so a pane drawn a few points outside it would turn a click on
itself into a dismissal. Docking into the reported rect is what makes a click on the
pane harmless, and `clickActivating` is off on top of that so typing never leaves the
search field.

Everything the pane composes with is wrapped rather than replaced. `onPositioned`
docks the pane and then hands the shortcut panel an anchor spanning both panes, so the
hints sit under the pair rather than stopping short under the list, and `onClose`
destroys the pane on the same idempotent teardown path the sampler stops on. Destroyed
rather than hidden, because nothing may outlive a dismissal, and rebuilding one canvas
on the next open costs nothing.

Two redraws exist for two callers and the split is the reason the pane is cheap. The
static half, everything the row itself says, is built once per row and cached, because
the highlight fires from a poll and a command line does not change under it. The live
half is rebuilt on every paint, which is all a sampler tick costs. Its HEIGHT is fixed
by whether the row can be sampled at all rather than by whether a sample has landed, so
the static half never shifts when the first reading arrives and the cache survives the
whole open. There is no timer in the pane and there must not be, the sampler already
ticks and the surface calls the pane from that tick, so a sparkline can never disagree
with the figure printed above it.

The poll compares the highlighted ROW NUMBER, not the row, so a rescan or a heat sort
changes everything under a stationary highlight and fires nothing. Both of those
re-render the pane explicitly, otherwise it would keep describing whatever used to be
in that position.

The two sparklines are scaled differently and that is deliberate. CPU is an absolute
question, is this busy, so it runs from zero to the window's peak with a floor under it,
which keeps a server idling at a fraction of a percent along the bottom instead of
having its noise blown up into a mountain range. Memory is a relative one, is this
growing, so it runs across the window's own range, where a leak climbs and a steady
server sits flat down the middle. The figures beside each heading carry the absolute
anchor either way, and a peak is printed only when it is above the current reading,
since a peak that is the current reading is the same number twice.

## Rows differ, so a section is dropped rather than emptied

A container has no working directory and no tree, a portless watcher has no ports, and
a container carries no live figures at all because asking the daemon for stats costs
more than the whole scan. Rather than a branch per shape, the pane is a list of
sections each with a heading and a builder, and a builder that returns nothing drops
its whole section including the heading. So a container shows its ports, its image and
its short id, a portless watcher shows its directory, command and tree, and neither
shows a labelled space with nothing under it. The one heading that changes wording is
the command, which reads as the image on a row carrying a container id, and that tests
a field the row carries rather than the name of the source that produced it.

The pane shows the command line in full. The sources carry both forms, `command` elided
to 120 characters for the one line row subtitle and `commandFull` untruncated for the
pane to wrap, because the two readers want different things and neither should have to
compromise for the other. The tree labels stay elided only, since each of those is one
line anyway and a second copy would pay for nothing.

## The icon and the name are one decision

Two rows both reading node tell you nothing. One reading Next and one reading Vite tell
you which window to go close. So `icons.lua` answers both questions in a single lookup,
handing back a picture and a word, and the surface asks once per row rather than twice.

This is display policy and it lives away from the sources deliberately. A source reports
what the kernel says, which is that the process is `node`, and that stays true and stays
in the search haystack. Only the surface decides to call it Next. Pushing the guess down
into discovery would have a source inventing a fact it cannot see, and the merge in the
engine reasons about ports and pids and never about labels.

Detection is a chain of ordered rules, first match wins, and every needle is a plain
substring rather than a Lua pattern so a dash or a dot in a tool name cannot quietly
become a wildcard. It costs nothing, which is why it is worth doing. The full argv and
the working directory are already on the row from the scan, so this is string work over
data in hand with no extra shellout and no second pass over the process table. The
needles are chosen to be things a tool prints about itself rather than things that merely
sit near it, which is why Next is found by `next-server` and Puma by `puma`, both of
which are the tool rewriting its own process title. Where the only signal is a path the
needle carries enough of the path to be unambiguous, so Vite looks for `/vite` and a
project directory named invite is not suddenly a dev server.

A rule may name a label and no icon, and that is the normal case rather than a gap to
fill later. Astro and Gunicorn and Sidekiq have no mark in the font, so they correct the
word and leave the runtime's picture alone. Approximating an icon for them would be
worse than the honest fallback.

Containers never run through the rules. A container's command field holds an image name,
so one built from nginx would classify as a web server and lose the whale, and the whale
is the one thing that says at a glance which rows are containers.

## Icons are font glyphs, and only mark glyphs

An icon here is a codepoint plus a colour, which is one table row, so a new technology
costs a line rather than an asset. Nothing binary is committed and nothing new is
installed, because `font-meslo-lg-nerd-font` is already in the Brewfile for the terminal,
the prompt and the editor. Vector glyphs also stay sharp at any size and take their tint
from us, which matters more than it sounds.

Only mark glyphs, never wordmarks. Several devicon codepoints are whole words drawn into
one character cell, nginx and django and the php text logo among them, and at the 21
point size a row draws they are illegible smears. Every glyph in the table was rendered
and looked at before it was added. A technology whose only glyph is a wordmark gets its
runtime icon instead.

Tints are ours rather than the official brand hex, and there are two sets. Brand palettes
are tuned for white documentation pages, so several go muddy on a dark row and were
lifted. The native chooser then follows the system appearance, which means half the time
the same glyph lands on near white instead. Only the tints that actually fail on light
carry an override, Next being the clearest case since a near white triangle on a near
white row is an empty slot. Colours that survive both are deliberately in one table only,
because duplicating a working value would mean two places to keep in step for no gain.
The appearance is read when the picker opens rather than per row per keystroke, and the
drawn images are cached on the resolved tint, so switching back and forth redraws nothing.

If no Nerd Font is present the whole set degrades to emoji at once, not per key, because
a row of crisp glyphs with one stray emoji in it looks worse than a consistent set of
emoji.

## What it deliberately does not do

It is not a system monitor and should not grow into one. No network throughput, no
disk activity, no energy impact, no thermal view. Those need private APIs, and more
to the point nobody would open this to look at them. When you want to know why the
fans are on, Activity Monitor is still the right tool. This one is for hunting and
stopping your own servers and it should stay small enough to open and close in a
second.

It does not read `package.json` to name a project. The directory name is what you
actually think in, and a monorepo package name would often be wrong.

It does not reorder rows by live resource use. The numbers move, the rows do not,
because a list that reshuffles under the cursor while you are reading it is hostile
and is the single most annoying thing about Activity Monitor's CPU tab. Heat
ordering is available on demand rather than as the default.
