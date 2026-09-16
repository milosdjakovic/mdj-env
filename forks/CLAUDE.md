# Forks

A fork carried here is a patch this machine needs and upstream has not taken. Each one is
declared in its own directory, and two scripts at the repository root read those declarations
without knowing which forks exist. Adding a third fork is a directory and nothing else.

Read this before adding a fork, before moving a pin, and before deciding a patch can go. The
decisions file named in a declaration is the record of why the fork exists, and it is read
first, the Rejected section before anything else.

## Why a fork is a cost rather than a fix

A fork stops taking upstream's releases the moment it is pinned, so it sits between this
machine and every feature released after it. That is the whole cost, and it is paid weekly by
whoever rebases. A patch that upstream takes must therefore be dropped rather than carried out
of habit, and the only honest test of that is whether unmodified upstream now passes the
patch's own tests. A fork that nobody asks that question about is a fork that outlives its
reason.

So the rule is two sentences. A patch whose tests pass on vanilla upstream is dropped, its
branch deleted and the pin moved. A patch whose tests still fail is rebased onto the newest
upstream and carried one more cycle. When the last patch of a fork goes, the fork goes with
it and the tool becomes an ordinary package line again.

## What a declaration says

`forks/<name>/FORK`, one `key | value` per line, comments and blank lines ignored.

`name` is the tool. `upstream` and `fork` are clone URLs, `base` is the upstream tag or branch
the patches sit on, and `pin` is the exact commit built. Tracking a branch is not allowed,
because two machines would then build different binaries. `dest` is where the binary lands,
written relative to the home directory, never absolute, so no declaration knows a prefix.
`decisions` names the file in `decisions/` that carries the reasoning.

`patch` repeats, once per branch, `branch | what it is | the upstream link it answers`. Each
branch is one commit above `base` where that is possible, so it can be offered upstream
without being rewritten first.

`watch` repeats, once per upstream link whose state would change a decision here,
`url | the state it was last seen in | what it is`. The reporter says when one has moved,
which is how a fix upstream, a reopened issue or an answered discussion reaches this
repository rather than being noticed by accident a year later.

## What a fork directory provides

Two executables, found by name rather than by the engine knowing the fork, the same way
`check-dependencies.sh` finds a manifest and a prober.

`build` takes a checkout and a destination and produces the binary at that destination. It
knows the language, the toolchain and the flags. It must not name an install command for
anything it needs, since the manifest and the map already answer that, and it must not write
a package manager prefix into itself, since the prefix differs between machines.

`prove` takes a vanilla upstream checkout, a branch name and the fork checkout, and answers
whether unmodified upstream already has that branch's behaviour. Exit 0 means upstream has it
and the patch can go, 1 means it is still needed, and 2 means this machine cannot answer right
now, which is a warning rather than an error. How it asks is the fork's own business, and for
both forks here it is laying the branch's own tests onto the vanilla checkout and running them.

## The two scripts

`src/check-forks.sh` reports and changes nothing. What upstream has released since the pin,
whether each patch is still needed, whether it still rebases cleanly, and which watched links
have moved. It never moves a pin, never pushes and never edits a branch, for the reason
`check-dependencies.sh` keeps the same split. Every answer it gives leads to a decision a
person makes.

`src/build-forks.sh` builds each fork at its declared pin and installs it, and is idempotent,
so a machine that already has the right binary is told so and nothing is compiled. It runs
from `setup.sh`.

Taking an update is the one thing neither script does. Rebase the patches still needed, merge
them into the fork's main line, move `pin`, rebuild, and write what happened into the decisions
file the declaration names. The `carried-forks` skill carries that procedure.
