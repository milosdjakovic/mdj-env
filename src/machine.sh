#!/bin/bash
set -e

# The one reader of MACHINES, which says what each machine takes from this repository.
#
#   machine.sh name        this machine's name, LocalHostName unless MDJ_MACHINE says otherwise
#   machine.sh get KEY     this machine's value for KEY, or the default when it has no row
#   machine.sh on KEY      exits 0 when that value is on, for a caller that only branches
#   machine.sh keys        every key, one per line, which is every optional piece
#   machine.sh listed      exits 0 when this machine has rows of its own
#   machine.sh check       reports every row that names a key with no default, exits 1 on any
#
# An unknown key is exit 3 from get and on, so a misspelt key in a caller fails loudly rather
# than reading as off.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FILE="$ROOT/MACHINES"

# machine|key|value per line, with comments, blanks and padding removed.
rows() {
    [[ -f "$FILE" ]] || return 0
    awk -F'|' '
        { sub(/#.*/, "") }
        NF < 3 { next }
        {
            for (i = 1; i <= 3; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i)
            print $1 "|" $2 "|" $3
        }
    ' "$FILE"
}

# Homebrew strips every variable from a Brewfile's environment except its own HOMEBREW_ ones,
# so install-homebrew-packages.sh hands the name across under that prefix. Without it a run with
# MDJ_MACHINE set would stow for one machine and install packages for another.
name() {
    if [[ -n "$MDJ_MACHINE" ]]; then
        echo "$MDJ_MACHINE"
    elif [[ -n "$HOMEBREW_MDJ_MACHINE" ]]; then
        echo "$HOMEBREW_MDJ_MACHINE"
    else
        scutil --get LocalHostName
    fi
}

value_for() {
    local machine="$1" key="$2"
    rows | awk -F'|' -v m="$machine" -v k="$key" '$1 == m && $2 == k { print $3; exit }'
}

get() {
    local key="$1" default value
    default="$(value_for default "$key")"
    if [[ -z "$default" ]]; then
        echo "machine.sh: no default for '$key' in MACHINES" >&2
        exit 3
    fi
    value="$(value_for "$(name)" "$key")"
    echo "${value:-$default}"
}

case "$1" in
    name)   name ;;
    get)    get "$2" ;;
    on)     [[ "$(get "$2")" == "on" ]] ;;
    keys)   rows | awk -F'|' '$1 == "default" { print $2 }' ;;
    listed) rows | awk -F'|' -v m="$(name)" '$1 == m { found = 1 } END { exit !found }' ;;
    check)
        rows | awk -F'|' '
            $1 == "default" { known[$2] = 1; next }
            { seen[NR] = $0 }
            END {
                bad = 0
                for (n in seen) {
                    split(seen[n], f, "|")
                    if (!(f[2] in known)) { print f[1] " sets " f[2] ", which has no default row"; bad = 1 }
                }
                exit bad
            }
        '
        ;;
    *)
        echo "usage: machine.sh name | get KEY | on KEY | keys | listed | check" >&2
        exit 2
        ;;
esac
