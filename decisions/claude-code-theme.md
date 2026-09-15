# Claude Code theme

Status. `theme` is `auto`, merged into `~/.claude/settings.json` by `src/setup-claude-settings.sh`.

## Now

Claude Code paints its UI in hex colours chosen per theme, not in palette slots, so unlike the
prompt, the iris menu or anything else drawn in slots it does not follow the terminal on its
own. `auto` is the one value that makes it ask, once by OSC 11 and then by listening for the
`2031` report, and that request travels through herdr and through iris, which is the chain
`iris-appearance-theme.md` exists to keep open. A fresh install defaults to `dark`, and
`settings.json` is not stowed because Claude Code writes to it, so the value was set by hand on
the first machine and never reached the second. The merge script now writes it alongside the
status line and the hook, and the script's own comment says why.

## Rejected

- 2026-09-15, stowing `settings.json` or tracking it. Claude Code rewrites the file itself, so a
  symlink into the repo would turn every session into an uncommitted change. Same reason the
  status line and the hook are merged rather than stowed.
- 2026-09-15, `claude config set theme auto`. The `config` subcommand is gone in 2.1.272, the
  binary treats it as a prompt and starts a session. `jq` on the file is the supported route
  this repository already uses.

## Log

### 2026-09-15 11:52

Milos reports, on the machine the env was just applied to, that slash commands in Claude Code
are light blue where they should be darker, and that yellow is off, the colours looking like
the dark palette kept on a light terminal. `~/.claude/settings.json` had `"theme": "dark"`.
The working machine is on `auto`, recorded in `iris-appearance-theme.md` at 01:05 the same
day, so the iris repaint fix was never in question here, Claude was simply never asking.
Set to `auto` by `jq`, then made `setup-claude-settings.sh` merge the same key so the next
machine gets it from `setup.sh`. Running the script after the hand edit reported already
configured, which is the convergence the script is built for.
