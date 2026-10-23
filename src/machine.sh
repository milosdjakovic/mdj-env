#!/bin/bash
set -e

# The one reader of machines/, which says what each machine takes from this repository.
# machines/default/pieces holds one row per optional piece, and machines/<name>/pieces holds the
# rows of one machine that differ from it, each row written as `piece | value  # reason`.
#
#   machine.sh name        this machine's name, LocalHostName unless MDJ_MACHINE says otherwise
#   machine.sh get KEY     this machine's value for KEY, or the default when it has no row
#   machine.sh on KEY      exits 0 when that value is on, for a caller that only branches
#   machine.sh keys        every key, one per line, which is every optional piece
#   machine.sh listed      exits 0 when this machine has a pieces file of its own
#   machine.sh check       reports every row that names a key with no default and every directory
#                          that is no valid machine name, exits 1 on any
#   machine.sh capture     looks at what this machine has and brings its pieces file in line
#
# An unknown key is exit 3 from get and on, so a misspelt key in a caller fails loudly rather
# than reading as off. A machine name that is no safe directory name is exit 1 from every command
# that needs the name, and so is the name default, which belongs to the defaults directory.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DIR="$ROOT/machines"

# What a machine name may be, since it becomes a directory. Letters, digits, hyphen, dot and
# underscore, with no leading dot, which also rules out a slash and the names . and ..
NAME_SHAPE='^[A-Za-z0-9_-][A-Za-z0-9._-]*$'

pieces_file() { echo "$DIR/$1/pieces"; }

# key|value per line for one machine, with comments, blanks and padding removed.
rows() {
    local file
    file="$(pieces_file "$1")"
    [[ -f "$file" ]] || return 0
    awk -F'|' '
        { sub(/#.*/, "") }
        NF < 2 { next }
        {
            for (i = 1; i <= 2; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i)
            print $1 "|" $2
        }
    ' "$file"
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

# A pieces file is one header comment, `# NAME, captured DATE`, above the machine's rows.
# The header is what keeps a machine that captured every piece at its default from reading as
# one that was never captured.
header_of() {
    local file
    file="$(pieces_file "$1")"
    [[ -f "$file" ]] || return 0
    awk -v m="$1" 'index($0, "# " m ", captured ") == 1 { print; exit }' "$file"
}

value_for() {
    local machine="$1" key="$2"
    rows "$machine" | awk -F'|' -v k="$key" '$1 == k { print $2; exit }'
}

# Resolves and checks this machine's name once, in the main shell, so a bad name ends the run
# here and not inside a command substitution that would swallow the exit.
require_name() {
    NAME="$(name)"
    if [[ ! "$NAME" =~ $NAME_SHAPE ]]; then
        echo "machine.sh: '$NAME' cannot be a machine name, it becomes a directory under machines/ and may hold only letters, digits, hyphen, dot and underscore, with no leading dot" >&2
        exit 1
    fi
    if [[ "$NAME" == default ]]; then
        echo "machine.sh: 'default' is the directory of the defaults and cannot be a machine name" >&2
        exit 1
    fi
}

get() {
    local key="$1" default value
    default="$(value_for default "$key")"
    if [[ -z "$default" ]]; then
        echo "machine.sh: no default for '$key' in machines/default/pieces" >&2
        exit 3
    fi
    value="$(value_for "$NAME" "$key")"
    echo "${value:-$default}"
}

# What this machine already has for one piece, as `value|fact`. A probe reports a fact and the
# value that fact suggests, and the person decides, since whether a machine should take a piece
# is a judgement and not something a probe can see. A key with no probe answers `?`, so a new
# piece is reported as unprobed rather than silently proposed off.
probe() {
    case "$1" in
        mise)
            local own=() tool
            # The config file itself is asked, not its directory, since the mise package declares
            # its directory NO-FOLD and only config.toml is a link into this checkout.
            if [[ "$(realpath "$HOME/.config/mise/config.toml" 2>/dev/null)" == "$ROOT/dotfiles/mise/"* ]]; then
                echo "on|this repository's mise config is stowed"; return
            fi
            for tool in pyenv rbenv nodenv asdf fnm volta jenv; do
                command -v "$tool" >/dev/null 2>&1 && own+=("$tool")
            done
            [[ -d "$HOME/.nvm" ]] && own+=(nvm)
            [[ -d "$HOME/.pyenv" && ! " ${own[*]} " == *" pyenv "* ]] && own+=(pyenv)
            if [[ ${#own[@]} -gt 0 ]]; then
                echo "off|its own runtime setup, ${own[*]}"
            elif [[ -e "$HOME/.config/mise/config.toml" ]]; then
                echo "off|mise with a config of its own"
            else
                echo "off|no runtime manager"
            fi
            ;;
        hammerspoon) [[ -d /Applications/Hammerspoon.app ]] && echo "on|Hammerspoon installed" || echo "off|no Hammerspoon" ;;
        herdr)  command -v herdr >/dev/null 2>&1 && echo "on|herdr installed" || echo "off|no herdr" ;;
        mole)   command -v mole >/dev/null 2>&1 && echo "on|mole installed" || echo "off|no mole" ;;
        kanata)
            # Both halves, since kanata without the active driver extension runs and remaps nothing.
            if ! command -v kanata >/dev/null 2>&1; then
                echo "off|no kanata"
            elif systemextensionsctl list 2>/dev/null | grep -F org.pqrs.Karabiner-DriverKit-VirtualHIDDevice | grep -qF '[activated enabled]'; then
                echo "on|kanata and the Karabiner driver extension active"
            else
                echo "off|kanata without an active Karabiner driver extension"
            fi
            ;;
        docker) [[ -d /Applications/Docker.app ]] && echo "on|Docker Desktop installed" || echo "off|no Docker Desktop" ;;
        vpn)
            if command -v mullvad >/dev/null 2>&1 || [[ -d "/Applications/Mullvad VPN.app" ]]; then
                echo "mullvad|Mullvad installed"
            elif [[ -d /Applications/IVPN.app ]]; then
                echo "ivpn|IVPN installed, no Mullvad"
            else
                echo "none|no VPN app"
            fi
            ;;
        tools)
            # A tool counts as used when its catalog command is already on this machine, from
            # mise or from anywhere else, since a machine running poetry from Homebrew is a machine
            # that uses poetry. The names come back alphabetical, the order rows are written in.
            local found
            found="$(awk -F'|' '
                { sub(/#.*/, "") }
                NF < 4 { next }
                { gsub(/^[ \t]+|[ \t]+$/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $4); print $1 " " $4 }
            ' "$ROOT/dotfiles/mise/TOOLS" | while IFS=' ' read -r tool cmd; do
                command -v "$cmd" >/dev/null 2>&1 && echo "$tool"
            done | sort | paste -sd, -)"
            if [[ -z "$found" ]]; then
                echo "none|no command from any tool in the catalog"
            else
                echo "$found|commands found for $found"
            fi
            ;;
        *) echo "?|no probe for this piece" ;;
    esac
}

keys() { rows default | awk -F'|' '{ print $1 }'; }

ask() {
    local answer
    [[ -t 0 ]] || return 1
    read -r -p "$1 " answer < /dev/tty
    [[ "$answer" =~ ^[Yy] ]]
}

# Brings this machine's block in line with what the probes find, and is idempotent. A second run
# on an unchanged machine writes nothing. A row written by hand that disagrees with what was found
# is kept unless the person says otherwise, since a hand written row is a decision and a probe is
# only evidence. Only values that differ from the default become rows, the convention for the
# whole file, plus any value the person chose against the evidence, which is a decision worth
# keeping. Without a terminal it reports and writes nothing.
capture() {
    local machine key default explicit found fact final current file
    local new=() changes=0 interactive=0
    machine="$NAME"
    [[ -t 0 ]] && interactive=1

    if [[ -z "$MDJ_MACHINE" && "$machine" =~ ^(Mac|MacBook|MacBook-Pro|MacBook-Air|iMac|Mac-mini|Mac-Studio|Mac-Pro)(-[0-9]+)?$ ]]; then
        echo "$machine is a generic name another machine may share. Rename this Mac in System Settings, Sharing,"
        echo "or set MDJ_MACHINE to a name of its own in this machine's shell profile, then capture again."
        exit 1
    fi

    file="$(pieces_file "$machine")"
    echo "Machine  $machine"
    if [[ -n "$(header_of "$machine")" ]]; then echo "         $(header_of "$machine" | sed 's/^# //')"; else echo "         not captured before"; fi
    echo ""

    for key in $(keys); do
        default="$(value_for default "$key")"
        explicit="$(value_for "$machine" "$key")"
        current="${explicit:-$default}"
        IFS='|' read -r found fact <<< "$(probe "$key")"
        final="$current"

        if [[ "$found" == "?" ]]; then
            printf '  %-12s %-8s %s\n' "$key" "$current" "unchanged, $fact"
        elif [[ "$found" == "$current" ]]; then
            printf '  %-12s %-8s %s\n' "$key" "$current" "unchanged, $fact"
        elif [[ -n "$explicit" ]]; then
            printf '  %-12s %-8s %s\n' "$key" "$current" "the row says $current, found $fact, which suggests $found"
            if ask "    Change $key to $found? [y/N]"; then final="$found"; fi
        else
            printf '  %-12s %-8s %s\n' "$key" "$found" "was the default $default, found $fact"
            if [[ $interactive -eq 1 ]]; then
                local answer
                read -r -p "    Write $key = $found? [Y/n] " answer < /dev/tty
                [[ "$answer" =~ ^[Nn] ]] || final="$found"
            else
                final="$found"
            fi
        fi

        # A row is written where the value differs from the default, and also where the person
        # turned down what was found, so the refusal is recorded and the next run does not ask
        # the same question again.
        if [[ "$final" != "$default" || ( "$found" != "?" && "$final" != "$found" ) ]]; then
            if [[ "$final" == "$found" ]]; then
                new+=("$(printf '%-14s | %-9s # %s' "$key" "$final" "$fact")")
            else
                new+=("$(printf '%-14s | %-9s # %s' "$key" "$final" "set by hand, capture found $fact")")
            fi
        fi
    done

    # Compare rows only, values and reasons, never the header, so the date alone is not a change.
    local old_rows new_rows
    old_rows="$(grep -E '^[^#]*\|' "$file" 2>/dev/null | sed 's/[[:space:]]*$//' || true)"
    new_rows="$(printf '%s\n' "${new[@]+"${new[@]}"}" | sed '/^$/d; s/[[:space:]]*$//')"
    echo ""
    if [[ "$old_rows" == "$new_rows" && -n "$(header_of "$machine")" ]]; then
        echo "Nothing to change, the block for $machine already matches."
        return 0
    fi
    if [[ $interactive -eq 0 ]]; then
        echo "No terminal, so nothing was written. Run this in a terminal to write the block above."
        return 0
    fi

    local block tmp
    block="# $machine, captured $(date +%Y-%m-%d)"
    [[ ${#new[@]} -eq 0 ]] && block="$block, every piece on its default"
    [[ -n "$new_rows" ]] && block="$block"$'\n'"$new_rows"
    mkdir -p "$DIR/$machine"
    tmp="$(mktemp)"
    # The block is replaced where it stands, so any other comment in the file keeps its place,
    # and it is appended when the file has no header or row yet.
    if [[ -f "$file" ]]; then
        BLOCK="$block" awk -v m="$machine" '
            BEGIN { block = ENVIRON["BLOCK"] }
            {
                line = $0
                if (index(line, "# " m ", captured ") == 1 || (line !~ /^[ \t]*#/ && line ~ /\|/)) {
                    if (!done) { print block; done = 1 }
                    next
                }
                print
            }
            END { if (!done) print block }
        ' "$file" > "$tmp"
    else
        echo "$block" > "$tmp"
    fi
    mv "$tmp" "$file"
    echo "Wrote the block for $machine to machines/$machine/pieces. Commit it so every checkout has it."
}

case "$1" in
    name)   require_name; echo "$NAME" ;;
    get)    require_name; get "$2" ;;
    on)     require_name; [[ "$(get "$2")" == "on" ]] ;;
    keys)   keys ;;
    listed) require_name; [[ -f "$(pieces_file "$NAME")" ]] ;;
    capture) require_name; capture ;;
    check)
        bad=0
        known="$(keys)"
        for dir in "$DIR"/* "$DIR"/.[!.]*; do
            [[ -d "$dir" ]] || continue
            machine="$(basename "$dir")"
            [[ "$machine" == default ]] && continue
            if [[ ! "$machine" =~ $NAME_SHAPE ]]; then
                echo "machines/$machine is no valid machine name, it may hold only letters, digits, hyphen, dot and underscore, with no leading dot"
                bad=1
                continue
            fi
            while IFS='|' read -r key _; do
                [[ -z "$key" ]] && continue
                if ! grep -qxF -- "$key" <<< "$known"; then
                    echo "$machine sets $key, which has no default row"
                    bad=1
                fi
            done <<< "$(rows "$machine")"
        done
        exit $bad
        ;;
    *)
        echo "usage: machine.sh name | get KEY | on KEY | keys | listed | check | capture" >&2
        exit 2
        ;;
esac
