# Walking a person through the permissions no script can give.
#
# Sourced rather than executed, like backup.sh beside it, so it carries no shebang and sets no
# shell options of its own. src/setup-grants.sh is the step that uses it, and src/setup-kanata.sh
# reaches the same mechanism through that step when it runs alone, so there is one copy of it.
#
# The shape is an engine over a contract. The engine here knows how to walk the declared grants,
# ask about each one, open the place it is given and wait for it, and it knows no module. Each
# module's grants-probe is the strategy for its own grants, found by name the way the reconciler
# finds it, and it is the only thing that knows what a grant of that module is or which program
# needs it. DEPENDENCIES.map knows where a grant is given, the pane address in a grant row's
# fourth field. The step that sources this is the composition root, it says which modules are
# walked and whether a person is there to be guided.
#
# What the probe is asked, which the root AGENTS.md states as the contract.
#
#   grants-probe LOCATOR            prints granted, notDetermined or denied, exit 0. Exit 2 when
#                                   this machine cannot answer right now, anything else when the
#                                   locator is not one the module knows.
#   grants-probe --subject LOCATOR  prints what the person has to act on, or nothing. `file PATH`
#                                   is a program to add with the plus button, so it is revealed
#                                   in Finder to be dragged into the list. `app BUNDLE_ID` is an
#                                   application that asks for the grant itself and answers for it
#                                   only while it runs, so it is opened when it cannot answer.
#                                   A probe that predates this verb answers it as an unknown
#                                   locator, which reads as no subject, so every probe stays valid.

GRANTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
GRANTS_MAP="$GRANTS_ROOT/DEPENDENCIES.map"

# How long a person is waited for, per grant, and how often the probe is asked meanwhile. Zero
# means no bound, which is the default, since a person is at the terminal whenever a grant is
# guided and Enter is how they move on. A bound only ever made a slow person meet the closing
# notes and a second run. Taken from the environment so the scratch harness can run in seconds,
# and nothing in the repository sets them.
GRANTS_WAIT_SECONDS="${MDJ_GRANTS_WAIT_SECONDS:-0}"
GRANTS_POLL_SECONDS="${MDJ_GRANTS_POLL_SECONDS:-2}"
# A probe that cannot answer is usually a program that has only just started, a daemon that has
# not reached its checks yet or an application still loading. Without a terminal it is given
# this long, and with one it is waited for like a grant, until it answers or Enter is pressed.
GRANTS_UNKNOWN_SECONDS="${MDJ_GRANTS_UNKNOWN_SECONDS:-20}"

# Trimmed fields of a pipe table, comments and blank lines dropped, the same reading the
# reconciler gives every manifest and the map.
grants_records() {
    [[ -f "$1" ]] || return 0
    awk -F'|' '
        { sub(/^[ \t]+/, "") }
        /^#/ || /^$/ { next }
        {
            out = ""
            for (i = 1; i <= NF; i++) { f = $i; gsub(/^[ \t]+|[ \t]+$/, "", f); out = out (i > 1 ? "|" : "") f }
            print out
        }
    ' "$1"
}

# Every grant a module that is on here declares, as module|name|locator|policy|consumer, in the
# order the manifests list them. Restricted to the modules named, when any are. A module is
# found by its manifest and switched off through src/machine.sh, the same two questions the
# reconciler asks, so neither this nor the step names one.
grants_declared() {
    local manifest module
    {
        find "$GRANTS_ROOT/dotfiles" -maxdepth 2 -name DEPENDENCIES -type f | sort
        [[ -f "$GRANTS_ROOT/src/DEPENDENCIES" ]] && echo "$GRANTS_ROOT/src/DEPENDENCIES"
    } | while IFS= read -r manifest; do
        module="$(basename "$(dirname "$manifest")")"
        if [[ $# -gt 0 ]]; then
            [[ " $* " == *" $module "* ]] || continue
        fi
        [[ "$("$GRANTS_ROOT/src/machine.sh" get "$module" 2>/dev/null)" == "off" ]] && continue
        grants_records "$manifest" | awk -F'|' -v m="$module" '$2 == "grant" { print m "|" $1 "|" $3 "|" $4 "|" $5 }'
    done
}

grants_prober() {
    local module="$1" prober="$GRANTS_ROOT/dotfiles/$1/grants-probe"
    [[ -x "$prober" ]] || prober="$GRANTS_ROOT/$module/grants-probe"
    [[ -x "$prober" ]] || return 1
    echo "$prober"
}

# What the map says about a grant, the sentence a person reads and the address of the pane.
grants_detail() { grants_records "$GRANTS_MAP" | awk -F'|' -v n="$1" '$1 == n { print $3; exit }'; }
grants_pane()   { grants_records "$GRANTS_MAP" | awk -F'|' -v n="$1" '$1 == n && $2 == "grant" { print $4; exit }'; }

# The probe's word for one grant, with the probe's own exit status, and its complaint discarded,
# since the reconciler after this step shows it in full.
grants_read() { "$1" "$2" 2>/dev/null; }

grants_subject() {
    local subject
    subject="$("$1" --subject "$2" 2>/dev/null)" || return 0
    case "$subject" in
        "file "?*|"app "?*) echo "$subject" ;;
    esac
    return 0
}

grants_span() { if (( $1 >= 120 )); then echo "$(( $1 / 60 )) minutes"; else echo "$1 seconds"; fi; }

# Waits up to a number of seconds for the probe to answer granted, asking it every poll, and with
# no bound when the number is zero. With a person at a terminal, Enter ends the wait early, and
# the dots show it has not stalled. An unbounded wait whose terminal goes away stops there, since
# nobody is left to give the grant. A fifth argument of answered ends the wait on any word rather
# than on granted, which is how a probe that cannot answer yet is waited for.
# Answers 0 granted, 1 still not given, 2 still unanswerable, 3 skipped. GRANTS_STATE holds the
# last word or status, for the caller's line.
GRANTS_STATE=""
grants_wait() {
    local prober="$1" locator="$2" limit="$3" interactive="$4" until="${5:-granted}"
    local start=$SECONDS state status key asked
    while (( limit == 0 || SECONDS - start < limit )); do
        if (( limit == 0 && interactive == 0 )); then
            GRANTS_STATE="${GRANTS_STATE:-unanswered}"
            break
        fi
        if [[ $interactive -eq 1 ]]; then
            asked=$SECONDS
            if read -r -t "$GRANTS_POLL_SECONDS" key < /dev/tty 2>/dev/null; then
                # The terminal echoed the Enter, so the line is already ended.
                GRANTS_STATE="skipped"
                return 3
            fi
            # The bash macOS ships answers a timeout and the end of input with the same status,
            # so they are told apart by time. A read that failed at once found the terminal gone,
            # and the rest is a plain wait.
            if (( SECONDS == asked )); then
                interactive=0
                echo ""
                sleep "$GRANTS_POLL_SECONDS"
            else
                printf '.'
            fi
        else
            sleep "$GRANTS_POLL_SECONDS"
        fi
        state="$(grants_read "$prober" "$locator")"
        status=$?
        if [[ $status -eq 0 && "$state" == granted ]]; then
            [[ $interactive -eq 1 ]] && echo ""
            GRANTS_STATE="granted"
            return 0
        fi
        if [[ $status -eq 0 && "$until" == answered ]]; then
            [[ $interactive -eq 1 ]] && echo ""
            GRANTS_STATE="$state"
            return 1
        fi
        if [[ $status -eq 0 ]]; then GRANTS_STATE="$state"; else GRANTS_STATE="unanswered"; fi
    done
    [[ $interactive -eq 1 ]] && echo ""
    [[ "$GRANTS_STATE" == unanswered ]] && return 2
    return 1
}

# One grant, from reading it to the person giving it or the run moving on. Answers 0 when it is
# given, 1 when it is still not given, 2 when it could not be read, 3 for a repository defect,
# which the reconciler after this reports as an error, so this only names it.
#
# Silent when the grant is already given, so a machine that has everything sees one line from
# the step and nothing else. Without a terminal, or for an optional grant, nothing is opened and
# the closing notes carry the sentence from the map, which is what a run said before this was
# written. A required grant with a person there is the guided case, one line saying what to do,
# the pane opened once, the program revealed when there is one to add, and a wait until it is
# given or Enter is pressed.
grants_guide() {
    local module="$1" name="$2" locator="$3" policy="$4" consumer="$5" interactive="$6"
    local prober state status subject pane detail guided=0

    if ! prober="$(grants_prober "$module")"; then
        echo "    $module declares the grant $name and ships no grants-probe, src/check-dependencies.sh reports it" >&2
        return 3
    fi
    detail="$(grants_detail "$name")"
    [[ "$policy" == required && $interactive -eq 1 ]] && guided=1

    state="$(grants_read "$prober" "$locator")"
    status=$?
    if [[ $status -ne 0 && $status -ne 2 ]]; then
        echo "    $module/grants-probe does not know the locator $locator, src/check-dependencies.sh reports it" >&2
        return 3
    fi

    # Cannot answer. An application that answers only while it runs is opened, when someone is
    # there to see it, and every required grant is given a short wait, since what was just
    # started may still be on its way to its checks. An optional one is not waited for.
    if [[ $status -eq 2 ]]; then
        if [[ "$policy" == required ]]; then
            subject="$(grants_subject "$prober" "$locator")"
            if [[ $guided -eq 1 && "$subject" == "app "* ]]; then
                echo "    opening ${subject#app } so it can answer for $name"
                open -b "${subject#app }" >/dev/null 2>&1 || true
            fi
            if [[ $guided -eq 1 ]]; then
                printf '    %s cannot be read yet, waiting for %s to answer, Enter skips ' "$name" "$module"
                grants_wait "$prober" "$locator" 0 1 answered
            else
                echo "    $name cannot be read yet, waiting up to $GRANTS_UNKNOWN_SECONDS seconds for $module to answer"
                grants_wait "$prober" "$locator" "$GRANTS_UNKNOWN_SECONDS" 0
            fi
            status=$?
            state="$GRANTS_STATE"
            if [[ $status -eq 2 ]]; then
                mdj_note "$name for $module could not be read here, so whether it is given is unknown, $detail"
                return 2
            fi
            if [[ $status -eq 3 ]]; then
                mdj_note "$name was skipped before $module could answer for it, $detail"
                return 1
            fi
        else
            mdj_note "$name for $module/$consumer could not be read here, it is optional, $detail"
            return 2
        fi
    fi

    [[ "$state" == granted ]] && return 0
    if [[ "$state" != notDetermined && "$state" != denied ]]; then
        echo "    $module/grants-probe answered '$state' for $name, src/check-dependencies.sh reports it" >&2
        return 3
    fi

    if [[ $guided -eq 0 ]]; then
        if [[ "$policy" != required ]]; then
            mdj_note "$name is not given, it is optional, $module/$consumer runs without it, $detail"
        elif [[ "$state" == denied ]]; then
            mdj_note "$name was refused and macOS never asks again, $module needs it, $detail"
        else
            mdj_note "$name is not given, $module needs it, $detail"
        fi
        return 1
    fi

    echo ""
    if [[ "$state" == denied ]]; then
        echo "  $name was refused, and macOS never asks again, so the pane is the only way back."
    else
        echo "  $name is not given yet, and $module needs it."
    fi
    echo "    $detail"
    pane="$(grants_pane "$name")"
    if [[ -n "$pane" ]]; then
        open "$pane" >/dev/null 2>&1 || true
    fi
    subject="$(grants_subject "$prober" "$locator")"
    if [[ "$subject" == "file "* ]]; then
        echo "    ${subject#file } is shown in Finder, drag it into the list if it is not there."
        open -R "${subject#file }" >/dev/null 2>&1 || true
    fi
    printf '    waiting for it, Enter skips '
    grants_wait "$prober" "$locator" "$GRANTS_WAIT_SECONDS" 1
    case $? in
        0)
            echo "    $name is given"
            return 0
            ;;
        3)
            mdj_note "$name was skipped, $module needs it, $detail"
            return 1
            ;;
        *)
            if (( GRANTS_WAIT_SECONDS > 0 )); then
                mdj_note "$name was not given within $(grants_span "$GRANTS_WAIT_SECONDS"), $module needs it, $detail"
            else
                mdj_note "$name was not given before the terminal went away, $module needs it, $detail"
            fi
            return 1
            ;;
    esac
}
