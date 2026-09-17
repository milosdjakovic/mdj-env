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

# Something a step has to tell the person and the run is the wrong place to say it.
#
# The stow step, when it unfolds a directory a program was writing into, owes one line, that
# the program has to be restarted. Printed where it happens, that line sits a fifth of the way
# into a run whose other two hundred lines are a listing of file extensions, which is exactly
# the burial the backup listing at the end of setup.sh exists to avoid. So a step says it
# twice. Once here, so a script run alone still says it, and once into the notes file when
# setup.sh has named one, so the run repeats every note in its closing block where it is read.
# Only setup.sh names the file, so a lone run leaves nothing behind.
mdj_note() {
    local line="$1"
    echo "    $line"
    [[ -n "${MDJ_RUN_NOTES:-}" ]] && printf '%s\n' "$line" >> "$MDJ_RUN_NOTES"
    return 0
}
