# Read by every zsh, interactive or not, before anything else. So it holds only what a shell that
# never reads .zshrc still needs, a command run by another program, a script, or a pane a
# multiplexer starts with a command of its own. Anything interactive belongs in .zshrc.custom.

# ~/.local/bin, where installers such as the Claude Code one put their commands. The generated
# .zshrc puts it first again for interactive shells, along with the Homebrew prefix.
export PATH="$HOME/.local/bin:$PATH"

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
