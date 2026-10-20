---
name: handoff
description: (mdj) Write a handoff prompt that carries this session's work into a fresh one, saved to a file and put on the clipboard. Manual only, run it as /handoff, optionally followed by what the next session should focus on.
argument-hint: [focus for the next session]
disable-model-invocation: true
allowed-tools: Bash(ls:*), Bash(mkdir:*), Bash(find:*), Bash(date:*), Bash(pbcopy:*), Bash(cat:*), Bash(basename:*), Bash(pwd:*), Bash(git status:*), Bash(git log:*), Bash(git branch:*), Bash(git diff:*), Bash(git rev-parse:*), Bash(git stash list:*), Read, Write
---

# Handoff

This skill ends a session on purpose. It reads everything that happened here and writes one
prompt that a fresh session can be started with, so the work continues without the next
session having to rediscover what this one learned. The prompt is written to a file and put on
the clipboard, and the file is deleted by the session that consumes it.

It must run inline, in this conversation, never as a forked subagent. A fork starts with an
empty context and would have nothing to hand off.

## Step 1, gather the facts the conversation cannot tell you

The conversation says what was decided. The repository says where things actually stand right
now, and the two can disagree, so check before writing.

```bash
pwd
git rev-parse --show-toplevel 2>/dev/null
git branch --show-current 2>/dev/null
git log --oneline -8 2>/dev/null
git status --short 2>/dev/null
git stash list 2>/dev/null
```

Then run `ls` on every file path you intend to name in the handoff. A path that does not exist
is removed or corrected before it is written. The next session will act on these paths without
checking them, so this check is the one place it happens.

## Step 2, write the handoff

Write it for a reader who knows the domain and has read none of this conversation. Outcomes,
not a play by play. Every date absolute. No name invented during this session unless the file
or the code uses it too. No secrets, tokens or credentials, even if they appeared here.

The optional argument is `$ARGUMENTS`. When it is present it names what the next session
should focus on and it leads the plan section. When it is empty the plan follows from the
conversation.

The handoff carries these parts, in this order, each under its own heading.

**Opening.** One paragraph addressed to the next session. It says this is a handoff from an
earlier session, names the project and its root as an absolute path, and states the goal of
the work in one or two sentences.

**Done so far.** What was achieved, as outcomes. Which parts are verified, meaning tested, run
or observed, and which are only believed. The distinction matters more than the list.

**Decisions and why.** Each decision with the reason behind it. Include approaches that were
considered or tried and turned down, with the reason, since those are exactly what a fresh
session proposes again.

**Corrections from the person.** Every time the person corrected course, said no, or stated a
preference during this session. These are rules the next session inherits, and they are the
first thing lost at a context boundary.

**Current state.** Branch, last commit, uncommitted or stashed changes, anything half finished,
and anything left running or left in a changed state on the machine.

**Plan.** Next step first, then the rest in order. The argument above leads this section when
it was given.

**Open questions.** Anything unresolved, anything unverified, anything that needs the person.

**Files.** The crucial files as absolute paths, each with one clause on why it matters. Rules
files the next session has to read come first, then the files being changed, then the files
that explain the surrounding design. Keep it to the files that matter, not every file touched.

**Instructions to the next session.** Read the files listed above before acting. Confirm the
understanding of the state and the plan in a few lines, and wait for the person's go ahead
before changing anything. Then delete the handoff file at the path named in the next part, since
the handoff has been consumed and the file is only a safety net for a lost clipboard.

**Where this file is.** The absolute path the handoff was saved to, so the instruction above can
be carried out.

Aim for something a person reads in two or three minutes. If it runs long, cut the play by play
before cutting a decision or a correction.

## Step 3, store it, copy it, prune

The handoffs live in one global folder outside every repository, `~/.claude/handoffs/`. The
file is named by project and time, the project being the basename of the repository root or,
outside a repository, of the working directory.

```bash
mkdir -p ~/.claude/handoffs
find ~/.claude/handoffs -name '*.md' -mtime +7 -delete
project="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
stamp="$(date '+%Y%m%d-%H%M')"
echo ~/.claude/handoffs/"$project-$stamp.md"
```

The prune runs before the write and removes anything older than a week, so a handoff that was
never consumed disappears on its own. Consumption deletes the file the moment the next session
has read it, so the folder never grows past a handful of files, and no hook is needed.

Write the handoff to that path, then put the same text on the clipboard.

```bash
pbcopy < ~/.claude/handoffs/"$project-$stamp.md"
```

If `pbcopy` is not available the file is still written and the reply says so.

## Step 4, reply

The reply is two lines. The absolute path the handoff was written to, and that it is on the
clipboard. Do not repeat the handoff in the reply, the person has it in two places already.
