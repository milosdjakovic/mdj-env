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
#   machine.sh capture     looks at what this machine has and brings its block in MACHINES in line
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

# A block is this machine's rows plus one header comment above them, `# NAME, captured DATE`.
# The header is what keeps a machine that captured every piece at its default from reading as
# one that was never captured.
header_of() { grep -E "^# $1, captured " "$FILE" 2>/dev/null | head -1; }

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

# What this machine already has for one piece, as `value|fact`. A probe reports a fact and the
# value that fact suggests, and the person decides, since whether a machine should take a piece
# is a judgement and not something a probe can see. A key with no probe answers `?`, so a new
# piece is reported as unprobed rather than silently proposed off.
probe() {
    case "$1" in
        mise)
            local own=() tool
            if [[ "$(cd "$HOME/.config/mise" 2>/dev/null && pwd -P)" == "$ROOT/"* ]]; then
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
            # A group counts as used when any command it lists is already on this machine, from
            # mise or from anywhere else, since a machine that runs poetry from Homebrew is a
            # machine that uses the dev group. The command is the last part of the tool name, the
            # one after the backend and the scope, which holds for every tool listed today.
            local file group cmd found=() missing=()
            for file in "$ROOT"/dotfiles/mise/.config/mise/config.*.toml; do
                group="${file##*/config.}"; group="${group%.toml}"
                cmd=""
                while IFS= read -r tool; do
                    tool="${tool##*:}"; tool="${tool##*/}"
                    if command -v "$tool" >/dev/null 2>&1; then cmd="$tool"; break; fi
                done < <(sed -nE 's/^"?([^"= ]+)"?[[:space:]]*=.*/\1/p' "$file" | grep -v '^\[')
                if [[ -n "$cmd" ]]; then found+=("$group"); else missing+=("$group"); fi
            done
            if [[ ${#found[@]} -eq 0 ]]; then
                echo "none|no command from any tool group"
            else
                local IFS=','
                echo "${found[*]}|commands for ${found[*]}${missing[*]:+, none for ${missing[*]}}"
            fi
            ;;
        *) echo "?|no probe for this piece" ;;
    esac
}

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
    local machine key default explicit found fact final current
    local new=() changes=0 interactive=0
    machine="$(name)"
    [[ -t 0 ]] && interactive=1

    if [[ -z "$MDJ_MACHINE" && "$machine" =~ ^(Mac|MacBook|MacBook-Pro|MacBook-Air|iMac|Mac-mini|Mac-Studio|Mac-Pro)(-[0-9]+)?$ ]]; then
        echo "$machine is a generic name another machine may share. Rename this Mac in System Settings, Sharing,"
        echo "or set MDJ_MACHINE to a name of its own in this machine's shell profile, then capture again."
        exit 1
    fi

    echo "Machine  $machine"
    if [[ -n "$(header_of "$machine")" ]]; then echo "         $(header_of "$machine" | sed 's/^# //')"; else echo "         not captured before"; fi
    echo ""

    for key in $(rows | awk -F'|' '$1 == "default" { print $2 }'); do
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
                new+=("$(printf '%-27s | %-11s | %-9s # %s' "$machine" "$key" "$final" "$fact")")
            else
                new+=("$(printf '%-27s | %-11s | %-9s # %s' "$machine" "$key" "$final" "set by hand, capture found $fact")")
            fi
        fi
    done

    # Compare rows only, values and reasons, never the header, so the date alone is not a change.
    local old_rows new_rows
    old_rows="$(grep -E "^$machine[[:space:]]*\|" "$FILE" 2>/dev/null | sed 's/[[:space:]]*$//')"
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
    tmp="$(mktemp)"
    # The block is replaced where it stands, so a machine keeps its place in the file, and it is
    # appended only when this machine has none yet.
    BLOCK="$block" awk -v m="$machine" '
        BEGIN { block = ENVIRON["BLOCK"] }
        {
            line = $0
            first = line; sub(/[ \t]*\|.*/, "", first)
            if (index(line, "# " m ", captured ") == 1 || first == m) {
                if (!done) { print block; done = 1 }
                next
            }
            print
        }
        END { if (!done) { print ""; print block } }
    ' "$FILE" > "$tmp"
    mv "$tmp" "$FILE"
    echo "Wrote the block for $machine to MACHINES. Commit it so every checkout has it."
}

case "$1" in
    name)   name ;;
    get)    get "$2" ;;
    on)     [[ "$(get "$2")" == "on" ]] ;;
    keys)   rows | awk -F'|' '$1 == "default" { print $2 }' ;;
    listed)
        [[ -n "$(header_of "$(name)")" ]] && exit 0
        rows | awk -F'|' -v m="$(name)" '$1 == m { found = 1 } END { exit !found }'
        ;;
    capture) capture ;;
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
        echo "usage: machine.sh name | get KEY | on KEY | keys | listed | check | capture" >&2
        exit 2
        ;;
esac
