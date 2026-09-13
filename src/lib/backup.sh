# Where a displaced file goes when this repository takes its place.
#
# Two steps displace things. Stow, when a real file already sits where a symlink belongs, and
# the zshrc step, when it rewrites a file it did not write. Both put the casualty here rather
# than deleting it, under one directory per run, mirroring its own path below the home
# directory, so putting something back is a copy rather than a puzzle.
#
# Sourced rather than executed, so it carries no shebang and sets no shell options of its own.
# The stamp is taken from the environment when setup.sh exports one, so every script in a run
# shares a directory, and falls back to its own when a script is run alone.

MDJ_BACKUP_STAMP="${MDJ_BACKUP_STAMP:-$(date +%Y%m%d-%H%M%S)}"
MDJ_BACKUP_DIR="$HOME/.mdj-env-backup/$MDJ_BACKUP_STAMP"

# Move one path out of the way. Answers 0 when something moved and 1 when there was nothing
# there, so a caller can count what it displaced without testing the path itself first.
mdj_displace() {
    local path="$1"
    [[ -e "$path" || -L "$path" ]] || return 1

    local relative="${path#"$HOME"/}"
    local destination="$MDJ_BACKUP_DIR/$relative"

    mkdir -p "$(dirname "$destination")"
    mv "$path" "$destination"
    echo "    kept $relative in $MDJ_BACKUP_DIR"
    return 0
}
