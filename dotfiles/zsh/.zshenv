# Read by every zsh, interactive or not, before anything else. So it holds only what a shell that
# never reads .zshrc still needs, a command run by another program, a script, or a pane a
# multiplexer starts with a command of its own. Anything interactive belongs in .zshrc.custom.

# ~/.local/bin, where installers such as the Claude Code one put their commands. The generated
# .zshrc puts it first again for interactive shells, along with the Homebrew prefix.
export PATH="$HOME/.local/bin:$PATH"

# mise's shims, first on PATH, for every zsh. .zshrc.custom activates mise with --shims, but only
# an interactive shell reads it, so `zsh -c`, `zsh -l` and a script started outside a terminal
# found no shims at all, `env -i zsh` could not find node. The guard is the one .zshrc.custom
# uses, the config rather than the binary, so a machine that has mise without taking this
# repository's runtimes keeps its own. The path is rebuilt with the shims first and any other
# copy dropped, so a nested zsh does not stack them. This was a hand written ~/.zshenv on one
# machine until the stowed file displaced it on 2026-11-11, decisions/runtime-versions.md has it.
if [[ -e "$HOME/.config/mise/config.toml" && -d "$HOME/.local/share/mise/shims" ]]; then
  path=("$HOME/.local/share/mise/shims" ${path:#"$HOME/.local/share/mise/shims"})
  export PATH
fi

# fzf's options live in one file that fzf rereads at every launch, so the colours are written
# once and reach every picker, typed at a prompt or started by tmux, herdr, Rex or a script.
# It is here rather than in .zshrc.custom because a pane started with a command runs a zsh that
# never reads .zshrc, and its pickers drew fzf's own colours, which is how this was found.
#
# The export is guarded on the file being readable, because fzf treats a file it cannot open as
# a hard error, exit 2 with no output, rather than as an absent default. The variable is unset
# first, because fzf applies the file and then the variable, so a string inherited from a server
# or a shell older than this file would silently win over it, which is exactly what happened on
# the day the string moved.
unset FZF_DEFAULT_OPTS
[[ -r "$HOME/.config/fzf/fzfrc" ]] && export FZF_DEFAULT_OPTS_FILE="$HOME/.config/fzf/fzfrc"
