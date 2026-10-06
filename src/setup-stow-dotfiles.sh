#!/bin/bash
set -e

# Stow dotfiles to home directory using GNU Stow

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
DOTFILES="$ROOT/dotfiles"

# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/lib/backup.sh"

PACKAGES=(ghostty tmux nvim zsh hammerspoon claude lf lazygit herdr mise)

if [[ ! -d "$DOTFILES" ]]; then
    echo "Error: dotfiles directory not found at $DOTFILES"
    exit 1
fi

# A directory the configured program also writes into must stay a real directory.
#
# Stow folds a whole directory into a single symlink when nothing is there yet and one package
# supplies it. That is what every other folder here wants, since a new config file or a new
# spoon file then appears without restowing. It is wrong for a directory the program writes
# into as it runs, because the fold points the program's own state at this checkout, and its
# sockets, logs and caches land in the repository instead of in the home directory. A folded
# directory is also invisible until it happens, so two machines differ by nothing more than
# whether the program or stow reached the path first.
#
# Which directories those are is a module fact, so each module declares its own in a NO-FOLD
# file at its package root and this script never names one. Found by name, the way the
# reconciler finds a collector or a prober.
#
# Two things happen per declared path. The guard makes the real directory before stow runs so
# the fold cannot happen, and does nothing where the directory is already there. The repair is
# for a machine that folded before any of this existed, where the path is already a symlink
# into this checkout. It takes the link off, makes the real directory in its place, and moves
# everything the repository does not track out of the package and into it. Tracked is the test
# because which files a program writes is that program's own detail and a list of them here
# would go stale. Nothing is deleted, every move is printed, and the directory in the checkout
# stays exactly where it was.
trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

# Every path declared in a file of the given name at a package root, as module, path and
# reason separated by tabs, so every pass reads one source. NO-FOLD and SHADOW-PATHS share it.
declarations() {
    local name="${1:-NO-FOLD}" file module line relative reason

    while IFS= read -r file; do
        module="$(basename "$(dirname "$file")")"
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%%#*}"
            relative="$(trim "${line%%|*}")"
            [[ -n "$relative" ]] || continue
            reason=""
            [[ "$line" == *"|"* ]] && reason="$(trim "${line#*|}")"
            printf '%s\t%s\t%s\n' "$module" "$relative" "$reason"
        done < "$file"
    done < <(find "$DOTFILES" -maxdepth 2 -name "$name" -type f | sort)
}

unfold() {
    local relative="$1" target="$2" source="$3" source_real="$4"
    local inside name entry candidate owned
    local -a tracked=()

    echo "  $relative is one symlink into this checkout, unfolding it"

    # Null delimited on both sides. Plain ls-files quotes any path carrying a character outside
    # ASCII, so a tracked file with an accent in its name came back unrecognisable and would
    # have been carried out of the repository as though nothing owned it.
    inside="${source_real#"$ROOT"/}"
    while IFS= read -r -d '' name; do
        name="${name#"$inside"/}"
        name="${name%%/*}"
        [[ -n "$name" ]] && tracked+=("$name")
    done < <(git -C "$ROOT" ls-files -z -- "$inside")

    rm "$target"
    mkdir -p "$target"

    while IFS= read -r -d '' entry; do
        name="$(basename "$entry")"
        owned=0
        for candidate in "${tracked[@]}"; do
            [[ "$candidate" == "$name" ]] && owned=1 && break
        done
        (( owned )) && continue
        mv "$entry" "$target/$name"
        echo "    moved $relative/$name into the home directory, the repository does not track it"
    done < <(find "$source" -mindepth 1 -maxdepth 1 -print0 | sort -z)

    # A program that was running through the old link still holds whatever it opened there, so
    # a socket or a log it keeps writing is now a path nothing answers on. Which program that
    # is belongs to the module, so the line says where rather than what to restart.
    mdj_note "restart whatever writes into $relative, it was running while the path moved"
}

# A declared path has to be a directory the package actually supplies, since that is the only
# kind stow can fold. A typo would otherwise make a real directory nobody asked for, pass the
# check after stowing because that directory is real, and leave the one that was meant folded.
check_declarations() {
    local module relative broken=0

    while IFS=$'\t' read -r module relative _; do
        if [[ ! -d "$DOTFILES/$module/$relative" ]]; then
            echo "Error: $module declares $relative in NO-FOLD and supplies no such directory" >&2
            broken=1
        fi
    done < <(declarations)

    return "$broken"
}

keep_real_directories() {
    local module relative target source resolved source_real

    while IFS=$'\t' read -r module relative _; do
        target="$HOME/$relative"
        source="$DOTFILES/$module/$relative"

        if [[ -L "$target" ]]; then
            resolved="$(cd -P "$target" 2>/dev/null && pwd -P || true)"
            source_real="$(cd -P "$source" 2>/dev/null && pwd -P || true)"
            if [[ -n "$resolved" && "$resolved" == "$source_real" ]]; then
                unfold "$relative" "$target" "$source" "$source_real"
            fi
        fi

        # A link somewhere else, a dangling link, or a plain file, all of them keep the real
        # directory from existing and none of them is this repository's to overwrite.
        if [[ -L "$target" || ( -e "$target" && ! -d "$target" ) ]]; then
            mdj_displace "$target" || true
        fi

        mkdir -p "$target"
    done < <(declarations)
}

# A declared path that is a symlink again after stowing means the guard did not hold, which is
# a defect worth failing on rather than one found later in a git status.
verify_real_directories() {
    local module relative target broken=0

    while IFS=$'\t' read -r module relative _; do
        target="$HOME/$relative"
        if [[ -L "$target" || ! -d "$target" ]]; then
            echo "Error: $module declares $relative must stay a real directory and it is not" >&2
            broken=1
        fi
    done < <(declarations)

    return "$broken"
}

# A file the configured program reads besides the stowed config can override it.
#
# Ghostty on macOS reads ~/Library/Application Support/com.mitchellh.ghostty/config after the
# XDG config, so a file a machine carried from before this repository wins over the linked one,
# setting by setting, while the linked one looks perfectly correct. Stow cannot see such a path,
# since it lies outside anything a package mirrors, so the conflict handling below never
# reaches it. That is how a second machine was pinned to the dark half by a theme line written
# more than a year earlier.
#
# Which paths those are is a module fact, so each module declares its own in a SHADOW-PATHS
# file at its package root, found by name exactly like NO-FOLD, and this script never names
# one. Only packages this script stows are read, since a shadow can only override a config
# that has been put in place.
#
# Unlike a stow conflict, a shadow is never moved without asking. It can hold settings nobody
# has carried into this repository yet, and a person should see the list before it goes. The
# answer arrives the same two ways the editor question does. MDJ_SHADOWS carries it through a
# run with no terminal, move or keep, and setup.sh asks before its first step and exports the
# answer, so the question comes before the long part of the run rather than in the middle of
# it. Otherwise this asks, and with neither the files stay and a note names each one. Enter
# keeps them.
#
#   --shadows       print every shadow present on this machine, one per line as
#                   module | path | reason, and exit. Anyone asking before a run reads this.
#   --ask-shadows   ask on the terminal and print the answer, move or keep, or print nothing
#                   when there is nothing to ask about. setup.sh uses it for its early question.
stowed() {
    local module="$1" package
    for package in "${PACKAGES[@]}"; do
        [[ "$package" == "$module" ]] && return 0
    done
    return 1
}

# Every declared shadow that is present here, a real file, a directory or a link.
shadows() {
    local module relative reason

    while IFS=$'\t' read -r module relative reason; do
        stowed "$module" || continue
        [[ -e "$HOME/$relative" || -L "$HOME/$relative" ]] || continue
        printf '%s\t%s\t%s\n' "$module" "$relative" "$reason"
    done < <(declarations SHADOW-PATHS)
}

# The question, on the terminal, with the answer on stdout so setup.sh can capture it. End of
# input keeps them, the same as Enter, since keeping is the answer that changes nothing.
ask_shadows() {
    local found="$1" module relative reason answer

    {
        echo "These files override config this repository links, and nothing else will move them."
        while IFS=$'\t' read -r module relative reason; do
            echo "  ~/$relative"
            echo "      $module, $reason"
        done <<< "$found"
        echo "Moved files go to ~/.mdj-env-backup/ and are never deleted."
    } > /dev/tty

    if read -r -p "Move them there so this repository's config wins? [y/N] " answer < /dev/tty 2> /dev/tty \
        && [[ "$answer" =~ ^[Yy] ]]; then
        echo move
    else
        echo keep
    fi
}

sweep_shadows() {
    local found answer module relative reason

    found="$(shadows)"
    [[ -n "$found" ]] || return 0

    answer="${MDJ_SHADOWS:-}"
    if [[ -z "$answer" && -t 0 ]]; then
        answer="$(ask_shadows "$found")"
    fi

    case "$answer" in
        move)
            while IFS=$'\t' read -r module relative reason; do
                mdj_displace "$HOME/$relative" || true
            done <<< "$found"
            ;;
        keep | "")
            while IFS=$'\t' read -r module relative reason; do
                mdj_note "~/$relative still overrides the $module config, run src/setup-stow-dotfiles.sh in a terminal, or with MDJ_SHADOWS=move, to move it"
            done <<< "$found"
            ;;
        *)
            echo "Error: MDJ_SHADOWS is '$answer', it takes move or keep" >&2
            return 1
            ;;
    esac
}

case "${1:-}" in
    --shadows)
        shadows | sed $'s/\t/ | /g'
        exit 0
        ;;
    --ask-shadows)
        found="$(shadows)"
        [[ -n "$found" ]] && ask_shadows "$found"
        exit 0
        ;;
esac

echo "Stowing dotfiles..."
cd "$DOTFILES"

check_declarations
keep_real_directories
sweep_shadows

# This repository wins, and the thing it wins against is kept.
#
# A machine that has been used already has real files where these symlinks belong, and stow
# refuses rather than guessing. It reports every conflict it found and then aborts all of
# them, across every package in the same invocation, so one stale file stops the whole run and
# nothing after this script gets to happen. That is the correct default for stow and the wrong
# one here, since making the machine match the repository is the entire purpose of running it.
#
# The conflicts are read back out of stow's own dry run rather than predicted, because stow
# owns the question of what it would collide with and a reimplementation of that would drift.
# Three messages carry a target path, a plain file in the way, a link stow does not own, and a
# link belonging to another package, so all three are matched.
#
# Looping, because clearing one conflict can uncover another beneath a folded directory, and
# bounded, because a loop that cannot converge should say so rather than spin. Nothing is
# deleted, every displaced file moves into the backup directory first.
resolve_conflicts() {
    local pass report targets count

    for (( pass = 1; pass <= 5; pass++ )); do
        report="$(stow -n -v -R -t "$HOME" "${PACKAGES[@]}" 2>&1 || true)"

        targets="$(printf '%s\n' "$report" | sed -n \
            -e 's/.*over existing target \(.*\) since .*/\1/p' \
            -e 's/.*existing target is not owned by stow: \(.*\)/\1/p' \
            -e 's/.*existing target is stowed to a different package: \([^ ]*\) =>.*/\1/p')"

        if [[ -z "$targets" ]]; then
            return 0
        fi

        count="$(printf '%s\n' "$targets" | grep -c . || true)"
        echo "  pass $pass, $count path(s) already in the way"

        while IFS= read -r relative; do
            [[ -n "$relative" ]] || continue
            mdj_displace "$HOME/$relative" || true
        done <<< "$targets"
    done

    echo "Error: stow still reports conflicts after 5 passes, which it should not" >&2
    stow -n -v -R -t "$HOME" "${PACKAGES[@]}" >&2 2>&1 || true
    return 1
}

resolve_conflicts

# Restow (-R) so re-running removes stale links left by renamed or deleted files
# and relinks the current tree, giving the same result on a fresh or an already
# set up machine. Package docs named CLAUDE.md are kept out of $HOME by each
# package's own .stow-local-ignore.
stow -R -t "$HOME" "${PACKAGES[@]}"

verify_real_directories

echo "Dotfiles stowed successfully"
