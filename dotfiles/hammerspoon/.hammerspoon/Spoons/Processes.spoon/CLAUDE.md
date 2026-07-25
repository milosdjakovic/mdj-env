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
Sources are an ordered list and a row is dropped when every port it holds has
already been claimed by an earlier source. That single rule, which mentions nothing
concrete, is what collapses a dozen identical docker proxy listeners into named
containers. Registering docker first is the whole mechanism. Reversing the order was
tested and does exactly the inverse, the proxy survives as one row holding ten ports
and the published containers get suppressed instead, which is the proof that the
claim really is decided by registration order and not by a special case somewhere.

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

## Two shellout facts that will bite anyone who touches this

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

A full scan is three shellouts, two of them concurrent, and costs about 72ms.

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
