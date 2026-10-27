# Claude Code module

Everything an agent needs before touching this package. `CLAUDE.md` beside this file only
imports it, and `dotfiles/claude/.claude/` is what stow links into `~/.claude/`.

## What is here and what is not

Three things are stowed. `commands/` holds the older slash command files, `commit` and the
`olm-plugin` router. `skills/` holds every skill this repository ships, one folder each with a
`SKILL.md`, and the `statusline-command.sh` is the script the status line runs.

`settings.json` is not here and must never be stowed or tracked, because Claude Code rewrites it
itself. The keys this repository cares about, the status line command and `theme = "auto"`, are
merged into it by `src/setup-claude-settings.sh`, which runs from `setup.sh` after stow and
writes only on a difference. `decisions/claude-code-theme.md` has why.

## Skills, and how a new one reaches the machine

`~/.claude/skills` is declared in `NO-FOLD`, because Claude Code installs skills of its own into
that folder and a folded directory would send them into this checkout. The consequence is that
a new skill folder is not visible until stow links it, since only the folders stow knew about at
the last run have a symlink. After adding one, restow the package from `dotfiles/`.

```bash
cd dotfiles && stow -R -t ~ claude
```

Then check `ls -la ~/.claude/skills` shows the new folder as a link into this repository.
Editing an existing skill needs nothing, the link already points at the file.

A skill meant to be typed, never chosen by the model, carries `disable-model-invocation: true`
in its frontmatter. A skill that has to read the current conversation must not carry
`context: fork`, since a fork starts with an empty context. Prefer a skill folder over a file in
`commands/` for anything new, Claude Code treats both as skills and the folder can hold
supporting files.

## The handoff skill

`/handoff` writes a prompt that carries this session's work into a fresh one. It reads the
whole conversation, checks the repository state and every path it names, writes the handoff to
`~/.claude/handoffs/<project>-<stamp>.md`, puts the same text on the clipboard through
`pbcopy`, and replies with the path. An optional argument names what the next session should
focus on. The handoff tells the next session to read the listed files, confirm its
understanding before acting, and delete the file, and the skill prunes anything in the folder
older than a week before each write, so the folder cleans itself with no hook anywhere.
`decisions/claude-handoff.md` has what was turned down on the way, a plain command file, a mod
pane with a copy button, and a session end hook for the cleanup.

## Dependencies

Declared in `DEPENDENCIES` at this package root, by hand, since the module has no swappable
units. `jq` and `git` serve the status line, and `herdr` does too, optionally, since inside herdr the
status line reports the session name to its pane for the agents sidebar. `pbcopy` serves the handoff skill and is optional,
because the handoff file is still written without it. Never name an install command in a skill,
the reconciler scans every file under `dotfiles` for one.
