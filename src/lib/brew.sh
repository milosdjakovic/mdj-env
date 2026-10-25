# Homebrew owned by another account, borrowed for a run and handed back.
#
# A Mac with more than one account has one Homebrew, owned by whoever installed it, and every
# other account reads the Cellar but writes nothing, not even the lock Homebrew takes before it
# downloads its package index. So from any other account every install fails, and most reads
# too, since a read refreshes that index first. A run that changes the machine through Homebrew
# therefore takes the prefix over for its duration, with chown, and gives it back to its owner
# when it ends, however it ends. Homebrew then runs as the account running setup, which is the
# account whose home the checkout and the Brewfile sit in.
#
# Who to give it back to is written down before the prefix changes hands, so a run that dies
# without handing back is repaired by the next one, which finds the note, adopts the loan, and
# returns it at its own end. Apps a cask put in /Applications while the prefix was borrowed
# belong to the borrower, so they go back as well.
#
# Only the process that borrowed returns. A step run inside setup.sh finds the prefix already
# its own and does nothing either way, so the loan spans the whole run rather than each step.
#
# Sourced rather than executed, so it carries no shebang and sets no shell options of its own.
# It uses mdj_note, so src/lib/backup.sh is sourced first. decisions/homebrew-owner.md has it.

MDJ_BREW_LOAN_DIR="$HOME/.local/state/mdj-env"
MDJ_BREW_LOAN="$MDJ_BREW_LOAN_DIR/brew-lent-by"
MDJ_BREW_APPS="$MDJ_BREW_LOAN_DIR/brew-lent-apps"

mdj_brew_prefix() {
    command -v brew > /dev/null 2>&1 || return 1
    brew --prefix
}

# Answers 0 when this account may write Homebrew now, or when there is no Homebrew yet, since
# the step that installs it makes this account its owner. Answers 1 when the prefix belongs to
# someone else and sudo cannot be asked, with no terminal and no timestamp to reuse.
mdj_brew_borrow() {
    local prefix owner me
    prefix="$(mdj_brew_prefix)" || return 0
    owner="$(stat -f %Su "$prefix")"
    me="$(id -un)"

    if [[ "$owner" == "$me" ]]; then
        # A loan an earlier run never returned, adopted so this run returns it.
        if [[ -f "$MDJ_BREW_LOAN" && -z "${MDJ_BREW_BORROWER:-}" ]]; then
            export MDJ_BREW_BORROWER="$$"
            echo "==> Homebrew is still on loan from $(cat "$MDJ_BREW_LOAN"), returned when this run ends"
        fi
        return 0
    fi

    if ! sudo -n true 2> /dev/null && [[ ! -t 0 ]]; then
        mdj_note "Homebrew belongs to $owner, and borrowing it for this run needs your password, so run it from a terminal"
        return 1
    fi

    echo "==> Homebrew belongs to $owner, borrowed for this run and returned at its end"
    mkdir -p "$MDJ_BREW_LOAN_DIR"
    echo "$owner" > "$MDJ_BREW_LOAN"
    ls -1 /Applications > "$MDJ_BREW_APPS"
    export MDJ_BREW_BORROWER="$$"
    sudo chown -R "$me" "$prefix"
}

# Give the prefix back, when this process is the one that borrowed it. Safe to call always.
mdj_brew_return() {
    [[ "${MDJ_BREW_BORROWER:-}" == "$$" && -f "$MDJ_BREW_LOAN" ]] || return 0
    local prefix owner me app
    owner="$(cat "$MDJ_BREW_LOAN")"
    me="$(id -un)"
    prefix="$(mdj_brew_prefix)" || return 0

    echo "==> Returning Homebrew to $owner"
    if ! sudo chown -R "$owner" "$prefix"; then
        mdj_note "Homebrew is still borrowed from $owner, the next setup run returns it, or sudo chown -R $owner $prefix"
        return 0
    fi
    if [[ -f "$MDJ_BREW_APPS" ]]; then
        comm -13 <(sort "$MDJ_BREW_APPS") <(ls -1 /Applications | sort) | while IFS= read -r app; do
            [[ "$(stat -f %Su "/Applications/$app")" == "$me" ]] || continue
            sudo chown -R "$owner" "/Applications/$app" && echo "    /Applications/$app"
        done
    fi
    rm -f "$MDJ_BREW_LOAN" "$MDJ_BREW_APPS"
    unset MDJ_BREW_BORROWER
}
