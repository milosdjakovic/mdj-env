---
name: carried-forks
description: Check, update, rebase, drop or deploy a tool this repository runs from a fork rather than from a package. Use whenever asked about a fork, about whether upstream has fixed something, about new upstream versions, about the state of an issue, pull request or discussion a decision here rests on, or about updating and deploying a built binary. Carries the procedure, the rule for when a patch goes, and the gates before committing.
---

# Carried forks

Some tools here run from a fork because they carry a patch this machine needs and upstream has
not taken. This skill is the procedure. The contract is `forks/CLAUDE.md` and is read first,
every time, because it moves. Each fork's declaration names the file in `decisions/` that holds
its reasoning, and that file is read before anything is proposed, the Rejected section first.

Never guess which forks exist or what they carry. Read `forks/*/FORK`. A fork that is not
declared there is not carried.

## When this skill applies

Any of these, whether or not the word fork appears in the question. Asking how a built tool is
doing. Asking whether upstream has fixed something. Asking about a new version. Asking whether
an issue, pull request or discussion has moved. Asking to update, rebase, rebuild or deploy.
Asking whether a patch is still needed. Asking to add a fork.

## The rule that decides everything

A fork is a cost rather than a fix. It stops taking upstream's releases the moment it is
pinned. So the question is never whether the patch still applies, it is whether upstream still
needs it, and that is measured rather than argued.

A patch whose tests pass on unmodified upstream is dropped. Delete its branch, take the merge
out of the fork's main line, move the pin, rebuild, and say so in the decisions file. A patch
whose tests still fail is rebased and carried one more cycle. When the last patch of a fork
goes, the fork goes with it and the tool becomes an ordinary package line again, which means
the declaration directory, the map entry, the Brewfile line and the build dependencies all
move in the same change.

## Reporting, which is what most questions want

Run `./src/check-forks.sh`, or with a fork name for one of them. It reports and changes
nothing, so it is always safe. It answers four things. What upstream has released since the
pin. Whether each patch is still needed, by laying that patch's own expectations onto an
unmodified upstream checkout and running them there. Whether each patch still rebases cleanly.
And whether any watched upstream link has moved.

Read the answer rather than relaying it. A moved link is the interesting case, since a closed
issue may have been closed by a fix or by a bot, and only opening it says which. Proving a
patch is still needed costs a full build of upstream, so the reporter only asks when upstream
has actually released something, which is the only time the answer can change.

## Taking an update

Neither script does this, deliberately, because every step is a judgment.

1. Report first. Nothing below is decided without it.
2. For each patch upstream has taken, drop it by the rule above.
3. For each patch still needed, rebase the branch onto the new upstream in the fork checkout at
   `~/.cache/mdj-env/<name>-build`, resolve conflicts by hand, and push the branch. Keep each
   branch one series above upstream so it stays offerable without being rewritten.
4. Merge the branches still carried into the fork's main line, if that fork keeps one.
5. Run the fork's own tests, and the upstream suite where there is one. A test that fails in
   parallel and passes serially is upstream's flakiness rather than yours, and proving which is
   part of the work, not a step to skip.
6. Move `pin` in `forks/<name>/FORK` to the commit actually built.
7. Run `./src/build-forks.sh`. It is idempotent and rebuilds when something replaced a binary.
8. Write a dated entry in the decisions file the declaration names, in the same change. What
   moved, what was measured, what was left undone.

## Deploying, and what is not yours to do

Installing the binary is this repository's business. Making a running program use it is not
always. A long lived server, a session holding live panes, anything the person is working
inside right now, is theirs to restart or hand off. Install, say what command completes it, and
leave it. Never restart or hand off a live session to finish your own step.

## Offering a patch upstream

Check the project's contribution policy before writing a line about it, and treat the policy as
binding on you as well. At least one upstream here refuses outside pull requests by rule and by
a workflow that closes them, and instructs any agent reading its contributing file to refuse to
open one from an unapproved account. Never open a pull request against such a project, and
never suggest opening one as though the door were open. Record what the policy is in the
decisions file, with links, so the question is not researched twice.

Where an upstream does take contributions, offering is still the person's decision and not a
step in this procedure.

## Adding a fork

A directory under `forks/<name>/` holding `FORK`, an executable `build`, an executable `prove`
and a `DEPENDENCIES` manifest for whatever building it needs. No edit to either engine. Then
the map entry and the Brewfile lines for the build tools, the origin changed from a package to
manual for the tool itself, and a decisions file that says why the fork exists at all. Read
`forks/CLAUDE.md` for what each of those files must contain.

## Gates before committing

`./src/check-dependencies.sh` passes. `./src/check-forks.sh` runs clean, or every warning it
prints is explained. The decisions file carries a dated entry. Nothing general, the root
`CLAUDE.md`, an engine, or this skill, names an individual tool, since those state the rule and
point at the record, and the tool's name belongs in its declaration, its module guide and its
decisions file.
