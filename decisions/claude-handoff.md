# Claude Code handoff

Status. `/handoff` is a manual only skill in `dotfiles/claude/.claude/skills/handoff/`, it writes the prompt to `~/.claude/handoffs/` and to the clipboard, and the consuming session deletes the file.

## Now

A session ends by typing `/handoff`, optionally followed by what the next session should focus
on. The skill runs inline, reads the whole conversation, checks the repository state and every
path it is about to name, and writes one prompt with the goal, what was done and what of it is
verified, decisions with their reasons and the approaches turned down, every correction the
person gave, the current state, the plan, open questions, the crucial files as absolute paths,
and instructions to the next session. The file lands in `~/.claude/handoffs/` named by project
and time, the same text goes to the clipboard through `pbcopy`, and the reply is the path. The
next session is told to read the listed files, confirm its understanding before acting, and
delete the file. Before each write the skill prunes anything in the folder older than a week.

## Rejected

- 2026-10-20, a file in `commands/` rather than a skill folder. Claude Code treats both as
  skills now, and only the skill frontmatter carries `disable-model-invocation`, which is what
  keeps the model from firing a handoff on its own. A folder can also hold supporting files
  later. `commands/` stays for the two files already there.
- 2026-10-20, running the skill with `context: fork`. A fork starts with an empty context, and
  the whole point is reading the conversation that just happened.
- 2026-10-20, a mod pane with a copy button for the one click copy. The mod API has a pane,
  buttons and a clipboard call, so it is possible, but `pbcopy` from the skill puts the whole
  prompt on the clipboard with zero clicks, and the mod adds a plugin folder, a type contract
  and the hot reload enable flow for a gain felt only where the clipboard path fails, a remote
  or desktop app session. Kept as the fallback if that day comes, and the file based design
  means it can be added without changing the skill.
- 2026-10-20, a session end hook that deletes the consumed handoff. A skill cannot own a hook,
  so it would live in `settings.json` through the merge script, and it would need a marker
  saying which file the session consumed, since a hook knows nothing about the conversation.
  Consumption deleting the file, plus a prune on write, gives the same result with no hook.
- 2026-10-20, a separate template file beside `SKILL.md`. One consumer, so the parts of the
  handoff are listed in the skill itself.

## Log

### 2026-10-20 08:33

Milos asks for a manual way to carry a session into a fresh context, a prompt with what was
done and why, the current state, the plan and absolute paths to the crucial files, and asks
whether a mod could offer a click to copy. Proposal first, skill over command for the manual
only flag and the folder, `pbcopy` over a mod for the copy, inline rather than forked, and a
global folder for the files. He then asks for cleanup of consumed files and whether a hook
could do it. The answer is that consumption deletes and writing prunes, so no hook. Built the
skill, the module `AGENTS.md` for the claude package, which had none, declared `pbcopy` as an
optional system tool, and recorded this file. Its first real run is still owed.
