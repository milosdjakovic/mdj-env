# zsh

The shell configuration. Stow links `.zshenv`, `.zshrc.custom`, `.p10k.zsh` and `.config/fzf/fzfrc`
into the home directory. `~/.zshrc` itself is not stowed. `src/setup-zshrc.sh` generates it,
since it embeds this machine's Homebrew prefix, and it sources `.zshrc.custom`.

## Which file a setting goes in

`.zshenv` is read by every zsh, interactive or not, so it holds only what a shell that never
reads `.zshrc` still needs. That is a command another program starts, a script, or a pane a
multiplexer opens with a command of its own, which is how a Rex floating pane runs its tool.
Today that is `~/.local/bin` on PATH, mise's shims first on PATH where this repository's mise
config is linked, and the fzf options file. Everything interactive, the prompt,
plugins, aliases and tool initialisers, goes in `.zshrc.custom`.

The fzf export lived in `.zshrc.custom` until 2026-11-02, and a Rex floating pane's finder drew
fzf's own colours because its zsh never read that file. `decisions/rex.md` has the measurement.

## A machine with a `.zshenv` of its own

Installers write to `~/.zshenv`, uv's added `~/.local/bin` to PATH on this machine. Stow moves
such a file into `~/.mdj-env-backup/` before linking, so read what it held and carry anything
still needed into this one, written with `$HOME` rather than an absolute path. With the link in
place an installer that appends writes into this repository, and it shows in `git status`.
