#!/bin/bash
set -e

# Put kanata and the Karabiner virtual keyboard it types through on this machine, as two root
# daemons, and keep the two at versions that can talk to each other.
#
#   setup-kanata.sh             reconcile, each part skipped once it is already done
#   setup-kanata.sh --upgrade   move kanata to Homebrew's stable version and its driver with it
#   setup-kanata.sh --dry-run   print every change either of the above would make, change nothing
#
# Homebrew installs kanata, since the Brewfile lists it where the kanata piece is on. The driver
# is a signed package from its own GitHub release that no package manager here covers, so this
# step installs it, the way install-xcode-clt.sh installs what Homebrew cannot. Which package is
# read from dotfiles/kanata/DRIVER, one row per kanata minor version, which is the pin for both
# and the one place either version is written.
#
# Kanata is held with brew pin, so a bulk brew upgrade can never move it away from its driver.
# Moving it is --upgrade, a deliberate act that unpins, upgrades, installs the paired driver,
# restarts both daemons and pins again. decisions/kanata.md has the reasoning and what was
# measured, and dotfiles/kanata/AGENTS.md has the day to day.
#
# What only a person can do is the password, approving the driver extension, and allowing the
# kanata binary in Input Monitoring and in Accessibility. The password is asked once, by setup.sh
# for its whole run or by this step when it runs alone. The three grants are walked by
# src/setup-grants.sh, the one copy of that guide, which setup.sh runs after this step and which
# this step runs itself, for kanata alone, when it is run on its own. Without a terminal and
# without a sudo timestamp the step says what it still needs and stops, and a run from a terminal
# finishes it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
PACKAGE="$ROOT/dotfiles/kanata"
DRIVER_TABLE="$PACKAGE/DRIVER"

# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/lib/backup.sh"

# Where stow puts the config. The daemon reads it here, through the link into this checkout.
CONFIG="$HOME/.config/kanata/kanata.kbd"

# The driver's own fixed paths and identity, all of which come from its package.
DRIVER_PKG_ID="org.pqrs.Karabiner-DriverKit-VirtualHIDDevice"
DRIVER_BUNDLE="org.pqrs.Karabiner-DriverKit-VirtualHIDDevice"
DRIVER_TEAM="G43BCU2T37"
DRIVER_DAEMON="/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
DRIVER_MANAGER="/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"

# The two daemons, named for this repository so nothing else on the machine claims the labels.
# The kanata label is the seam with dotfiles/kanata/grants-probe, which finds the daemon and its
# log by it, so a change here is a change there.
KANATA_LABEL="mdj-env.kanata"
VHID_LABEL="mdj-env.karabiner-vhid-daemon"
DAEMON_DIR="/Library/LaunchDaemons"
LOG_DIR="/Library/Logs/mdj-env"
# What the kanata daemon was last started with, so a config change is a restart and an unchanged
# config is not. Root owned like the daemon, and readable by anyone so a dry run can compare.
STATE_DIR="/Library/Application Support/mdj-env"
CONFIG_STAMP="$STATE_DIR/kanata.kbd.sha256"
# The kanata the daemon runs, a root owned copy of the Homebrew binary. Homebrew's Cellar belongs
# to the person, so anything running as them could replace a binary there and be root at the next
# restart. A copy in a directory only root can write cannot be swapped that way, and it is the
# file the cmd proof runs against, so what was proven is what runs. Its path never changes, which
# is also the path Input Monitoring and Accessibility are given to.
BIN_DIR="$STATE_DIR/bin"
RUN_BIN="$BIN_DIR/kanata"
# Who must own the directories above, named once so the stubbed harness can stand in for root.
ROOT_OWNER="root"

MODE=setup
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --upgrade) MODE=upgrade ;;
        --dry-run) DRY_RUN=1 ;;
        *)
            echo "usage: setup-kanata.sh [--upgrade] [--dry-run]" >&2
            exit 2
            ;;
    esac
done

say()  { echo "$1"; }
fail() { echo "Error: $1" >&2; shift; local line; for line in "$@"; do echo "       $line" >&2; done; exit 1; }

#-------------------------------------------------------------------------------
# Changing things, every change goes through one of these two
#-------------------------------------------------------------------------------

# A command that changes the machine as this user. Printed instead under --dry-run.
change() {
    if [[ $DRY_RUN -eq 1 ]]; then
        printf '    would run '; printf ' %q' "$@"; printf '\n'
        return 0
    fi
    "$@"
}

# A command that changes the machine as root. Printed instead under --dry-run. The first one in a
# run makes sure sudo can be answered, and when it cannot, with no terminal to type a password
# into and no timestamp to reuse, the step says what is left and stops cleanly, since every part
# is skipped once done and a run from a terminal picks up where this one stopped.
ROOT_READY=0
as_root() {
    if [[ $DRY_RUN -eq 1 ]]; then
        printf '    would run  sudo'; printf ' %q' "$@"; printf '\n'
        return 0
    fi
    if [[ $ROOT_READY -eq 0 ]]; then
        if ! sudo -n true 2>/dev/null; then
            if [[ ! -t 0 ]]; then
                mdj_note "kanata is not fully set up, src/setup-kanata.sh needs your password, run it from a terminal"
                exit 0
            fi
            echo "    The next part needs root, so sudo asks for your password."
        fi
        ROOT_READY=1
    fi
    sudo "$@"
}

#-------------------------------------------------------------------------------
# Reading things, none of these changes anything
#-------------------------------------------------------------------------------

# The Homebrew kanata, asked of Homebrew itself and never of PATH, since a directory early on
# PATH that the person can write would otherwise decide what root runs.
source_bin() {
    local prefix
    prefix="$(brew --prefix kanata 2>/dev/null)" || return 1
    [[ -x "$prefix/bin/kanata" ]] || return 1
    realpath "$prefix/bin/kanata"
}
kanata_version() { "$1" --version 2>/dev/null | awk '{ print $2; exit }'; }
sha_of() { shasum -a 256 "$1" 2>/dev/null | awk '{ print $1 }'; }

# Kanata runs as root and reads a config in a checkout this user can write. That is safe only
# while the binary cannot run commands, so this is proven on every run, and the daemon is neither
# installed nor restarted unless kanata rejects a config that asks for one. The note it prints is
# the proof that the refusal is compiled in, rather than a config error of some other kind.
prove_no_cmd() {
    local bin="$1" cfg proof status
    cfg="$(mktemp -t kanata-cmd-check)"
    printf '(defcfg danger-enable-cmd yes)\n(defsrc a)\n(deflayer base (cmd echo hi))\n' > "$cfg"
    set +e
    proof="$("$bin" --check -c "$cfg" 2>&1)"
    status=$?
    set -e
    rm -f "$cfg"
    if [[ $status -eq 0 || "$proof" != *"compiled to never allow cmd"* ]]; then
        fail "kanata at $bin accepts a config that runs commands" \
            "A root daemon reading a config this user can write must not, so it is not started." \
            "decisions/kanata.md says what to do instead, copy the config to a root owned path."
    fi
    say "  $bin cannot run commands, it says it was compiled to never allow cmd"
}

check_config() {
    local bin="$1" check
    if ! check="$("$bin" --check -c "$CONFIG_READ" 2>&1)"; then
        echo "$check" >&2
        fail "kanata rejects $CONFIG_READ, so the daemon is left on what it had"
    fi
    say "  $bin accepts the config"
}

# A directory only root may write, made so or repaired to it. Anything the person can write
# along the way to the binary would let them swap it.
root_dir() {
    local dir="$1" owner mode
    if [[ ! -d "$dir" ]]; then
        as_root mkdir -p "$dir"
        as_root chmod 755 "$dir"
        return 0
    fi
    owner="$(stat -f '%Su' "$dir")"
    mode="$(stat -f '%Lp' "$dir")"
    if [[ "$owner" != "$ROOT_OWNER" || "${mode:1:1}" =~ [2367] || "${mode:2:1}" =~ [2367] ]]; then
        say "  $dir is $owner with mode $mode, making it root's alone"
        as_root chown root:wheel "$dir"
        as_root chmod 755 "$dir"
    fi
}
minor_of() { echo "$1" | cut -d. -f1,2; }

# The DRIVER row for a kanata minor version, as driver|url|sha256, or nothing.
driver_row() {
    awk -F'|' -v want="$1" '
        { sub(/#.*/, "") }
        NF < 4 { next }
        {
            for (i = 1; i <= 4; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i)
            if ($1 == want) { print $2 "|" $3 "|" $4; exit }
        }
    ' "$DRIVER_TABLE"
}

installed_driver() { pkgutil --pkg-info "$DRIVER_PKG_ID" 2>/dev/null | awk '$1 == "version:" { print $2; exit }'; }

extension_active() { systemextensionsctl list 2>/dev/null | grep -F "$DRIVER_BUNDLE" | grep -qF '[activated enabled]'; }

loaded() { launchctl print "system/$1" >/dev/null 2>&1; }
daemon_pid() { launchctl print "system/$1" 2>/dev/null | awk '$1 == "pid" && $2 == "=" { print $3; exit }'; }

# Pids of a program other than the one launchd runs under the label, found by the pgrep
# arguments that follow the label. The driver daemon's name is longer than the sixteen characters
# macOS keeps as a process name, so it is matched by its path instead.
strays() {
    local label="$1" own pid
    shift
    own="$(daemon_pid "$label")"
    for pid in $(pgrep "$@" 2>/dev/null); do
        [[ "$pid" == "$own" ]] || echo "$pid"
    done
}

# Runs a command for at most a number of seconds, for a program that may wait on a person.
bounded() {
    local limit="$1" pid waited=0
    shift
    "$@" &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if (( waited >= limit )); then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            return 1
        fi
        sleep 1
        waited=$(( waited + 1 ))
    done
    wait "$pid"
}

xml() { local s="$1"; s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; printf '%s' "$s"; }

# A daemon's plist, generated here from this run's home directory and resolved paths, so no
# person's path is ever written into the repository.
plist() {
    local label="$1" log="$2" arg
    shift 2
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$(xml "$label")</string>
    <key>ProgramArguments</key>
    <array>
EOF
    for arg in "$@"; do
        printf '        <string>%s</string>\n' "$(xml "$arg")"
    done
    cat <<EOF
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$(xml "$log")</string>
    <key>StandardErrorPath</key>
    <string>$(xml "$log")</string>
</dict>
</plist>
EOF
}

#-------------------------------------------------------------------------------
# Parts of the work, each one skipped once it is already done
#-------------------------------------------------------------------------------

# Writes one daemon's plist when its content differs from what is there and loads it when it is
# not loaded. Leaves DAEMON_RESULT as started when it started or restarted the daemon, so the
# caller does not restart it twice, current when it left a loaded daemon alone, and blocked when
# a copy started by hand keeps it from starting at all. The pgrep arguments that find such a copy
# follow the plist content.
DAEMON_RESULT=current
put_daemon() {
    local label="$1" content="$2" target="$DAEMON_DIR/$1.plist" tmp waited
    local changed=0 stray
    shift 2

    if [[ "$(cat "$target" 2>/dev/null)" != "$content" ]]; then
        changed=1
        say "  $label, writing $target"
        if [[ $DRY_RUN -eq 1 ]]; then
            printf '%s\n' "$content" | sed 's/^/      | /'
            say "    would run  sudo install -m 644 -o root -g wheel <the plist above> $target"
        else
            tmp="$(mktemp)"
            printf '%s\n' "$content" > "$tmp"
            as_root install -m 644 -o root -g wheel "$tmp" "$target"
            rm -f "$tmp"
        fi
    fi

    # Two copies of either program fight over the same keyboard or the same socket, so a copy
    # started by hand is reported and this one is not started beside it. Stopping it is the
    # person's call, since nothing here stops what it did not start.
    stray="$(strays "$label" "$@" | paste -sd' ' -)"
    if [[ -n "$stray" ]]; then
        mdj_note "a copy of what $label runs is already running outside launchd as pid $stray, stop it and run src/setup-kanata.sh again"
        DAEMON_RESULT=blocked
        return 0
    fi

    if loaded "$label" && [[ $changed -eq 1 ]]; then
        say "  $label, reloading it with the new plist"
        as_root launchctl bootout "system/$label" || true
        # bootout returns before launchd lets go of the label, and a bootstrap in that window
        # fails, so wait for it, bounded.
        if [[ $DRY_RUN -eq 0 ]]; then
            waited=0
            while loaded "$label" && (( waited < 10 )); do sleep 1; waited=$(( waited + 1 )); done
        fi
        as_root launchctl bootstrap system "$target"
        DAEMON_RESULT=started
        return 0
    fi
    if ! loaded "$label"; then
        say "  $label, loading it"
        as_root launchctl bootstrap system "$target"
        DAEMON_RESULT=started
        return 0
    fi
    say "  $label, loaded and current"
    DAEMON_RESULT=current
}

#-------------------------------------------------------------------------------
# Before anything, this machine has to want it
#-------------------------------------------------------------------------------

if [[ $EUID -eq 0 ]]; then
    fail "run this as yourself, not under sudo" \
        "It reads your home directory for the config and asks for root only where it needs it."
fi

# setup.sh runs this only where the piece is on, and a run by hand has to ask the same question,
# since rule 1 of the root AGENTS.md is that an optional piece that is off is not installed. A
# machine that switched it off keeps whatever an earlier run installed, because nothing here
# removes what a machine has, so this is also the one place that can say what is left.
if ! "$SCRIPT_DIR/machine.sh" on kanata; then
    say "kanata is off on $("$SCRIPT_DIR/machine.sh" name), so nothing is set up."
    if [[ -e "$DAEMON_DIR/$KANATA_LABEL.plist" || -e "$DAEMON_DIR/$VHID_LABEL.plist" || -n "$(installed_driver)" ]]; then
        mdj_note "kanata is off here and this machine still has its daemons or the Karabiner driver, which stay, dotfiles/kanata/AGENTS.md has the one off commands that remove them"
    fi
    exit 0
fi

[[ $DRY_RUN -eq 1 ]] && say "Dry run, nothing below is changed."

if ! source_bin >/dev/null; then
    fail "kanata is not installed" \
        "The Brewfile lists it where the kanata piece is on, so src/install-homebrew-packages.sh" \
        "installs it. Run that, or ./setup.sh, and then this again."
fi

#-------------------------------------------------------------------------------
# Upgrade, only when asked for, and only to a version DRIVER has a row for
#-------------------------------------------------------------------------------

pinned() { brew list --pinned 2>/dev/null | grep -qx kanata; }

if [[ "$MODE" == upgrade ]]; then
    say "==> Upgrading kanata"
    # Homebrew's own idea of the stable version is refreshed first, and the upgrade below is told
    # not to refresh it again, so the version checked against DRIVER is the version installed.
    change brew update
    stable="$(brew info --json=v2 kanata | jq -r '.formulae[0].versions.stable')"
    current="$(kanata_version "$(source_bin)")"
    say "  Homebrew's stable kanata is $stable, this machine has $current"
    if [[ -z "$(driver_row "$(minor_of "$stable")")" ]]; then
        fail "dotfiles/kanata/DRIVER has no row for kanata $(minor_of "$stable")" \
            "Write the driver version it needs from kanata's release notes, with the package URL" \
            "and the sha256 its GitHub release lists, commit it, and run --upgrade again."
    fi
    if [[ "$stable" == "$current" ]]; then
        say "  already on $stable, reconciling the rest"
    else
        # Pinned again however this ends, so a failure below cannot leave a bulk upgrade free to
        # move kanata away from its driver.
        pinned && change brew unpin kanata
        [[ $DRY_RUN -eq 0 ]] && trap 'brew pin kanata 2>/dev/null || true' EXIT
        # The old version is kept, since the running daemon still runs it until the new one is
        # proven below. brew cleanup removes it later.
        change env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew upgrade kanata
        if [[ $DRY_RUN -eq 1 ]]; then
            # Everything after this reads the kanata that is installed, which a dry run did not
            # upgrade, so it stops here with the rest said rather than shown against the old one.
            row="$(driver_row "$(minor_of "$stable")")"
            say "    then prove kanata $stable cannot run commands, copy it over $RUN_BIN and prove it"
            say "    again, install driver ${row%%|*} if it is not installed, ask macOS to activate it,"
            say "    restart both daemons, pin kanata again, and read the grants, which a new build may need again"
            exit 0
        fi
        upgraded="$(kanata_version "$(source_bin)")"
        [[ "$upgraded" == "$stable" ]] || fail "Homebrew upgraded kanata to $upgraded, not $stable"
    fi
fi

#-------------------------------------------------------------------------------
# Which kanata, and which driver it needs
#-------------------------------------------------------------------------------

say "==> kanata"
SOURCE_BIN="$(source_bin)"
version="$(kanata_version "$SOURCE_BIN")"
row="$(driver_row "$(minor_of "$version")")"
if [[ -z "$row" ]]; then
    fail "dotfiles/kanata/DRIVER has no row for kanata $(minor_of "$version")" \
        "This kanata was moved without its driver. Write the row from kanata's release notes," \
        "commit it, and run this again, or go back to a kanata the table has a row for."
fi
IFS='|' read -r want_driver driver_url driver_sha <<< "$row"
say "  kanata $version from Homebrew at $SOURCE_BIN, which needs driver $want_driver"

# Proven on the Homebrew file before anything is installed, so a binary that can run commands
# never lands in the root owned copy, and proven again on that copy once it is in place below.
prove_no_cmd "$SOURCE_BIN"

# The config as kanata will read it. A dry run before the stow step has nothing linked yet, so it
# reads the package's own copy, which is what the stow step links there.
CONFIG_READ="$CONFIG"
if [[ ! -f "$CONFIG" ]]; then
    if [[ $DRY_RUN -eq 0 ]]; then
        fail "$CONFIG is not there" \
            "src/setup-stow-dotfiles.sh links it where the kanata piece is on. Run it, then this again."
    fi
    CONFIG_READ="$PACKAGE/.config/kanata/kanata.kbd"
    say "  $CONFIG is not linked yet, the stow step links it, so this checks the package's copy"
fi
check_config "$SOURCE_BIN"

#-------------------------------------------------------------------------------
# The driver, at the version the row names, verified before it is installed
#-------------------------------------------------------------------------------

say "==> Karabiner driver"
DRIVER_INSTALLED=0
have_driver="$(installed_driver)"
if [[ "$have_driver" == "$want_driver" ]]; then
    say "  $want_driver installed"
else
    say "  ${have_driver:-none} installed, kanata $(minor_of "$version") needs $want_driver"
    if [[ $DRY_RUN -eq 1 ]]; then
        say "    would download $driver_url"
        say "    would refuse it unless its sha256 is $driver_sha and pkgutil says it is notarized and signed by team $DRIVER_TEAM"
        say "    would run  sudo installer -pkg <the download> -target /"
    else
        work="$(mktemp -d -t kanata-driver)"
        pkg="$work/$(basename "$driver_url")"
        curl -fsSL -o "$pkg" "$driver_url"
        got="$(shasum -a 256 "$pkg" | awk '{ print $1 }')"
        if [[ "$got" != "$driver_sha" ]]; then
            rm -rf "$work"
            fail "the driver package hashes to $got, DRIVER says $driver_sha, so it is not installed"
        fi
        signature="$(pkgutil --check-signature "$pkg" 2>&1 || true)"
        if [[ "$signature" != *"Notarization: trusted by the Apple notary service"* \
            || "$signature" != *"Developer ID Installer:"*"($DRIVER_TEAM)"* ]]; then
            echo "$signature" >&2
            rm -rf "$work"
            fail "the driver package is not notarized and signed by team $DRIVER_TEAM, so it is not installed"
        fi
        say "  hash, notarization and team $DRIVER_TEAM check out, installing"
        as_root installer -pkg "$pkg" -target /
        rm -rf "$work"
        have_driver="$(installed_driver)"
        [[ "$have_driver" == "$want_driver" ]] || fail "the installer finished but the package says ${have_driver:-nothing} is installed"
    fi
    DRIVER_INSTALLED=1
fi

# The manager asks macOS to load the extension it just installed, and replaces an older one. It
# runs as this user, which is how the driver's own README runs it. Approval is a click in
# System Settings that only a person can make, and it is a grant like the other two, so the
# grants walk at the end of this step, or the grants step in setup.sh, takes the person there.
if [[ $DRIVER_INSTALLED -eq 1 ]] || ! extension_active; then
    say "  asking macOS to activate the driver extension"
    # Bounded, since the request is answered by a person and nothing promises it returns first.
    if [[ $DRY_RUN -eq 1 ]]; then
        change "$DRIVER_MANAGER" activate
    else
        bounded 30 "$DRIVER_MANAGER" activate || true
    fi
else
    say "  driver extension activated and enabled"
fi

#-------------------------------------------------------------------------------
# The two daemons
#-------------------------------------------------------------------------------

say "==> Daemons"
if [[ ! -d "$LOG_DIR" ]]; then
    as_root mkdir -p "$LOG_DIR"
fi
root_dir "$STATE_DIR"
root_dir "$BIN_DIR"

# The root owned copy, replaced only when its content differs from Homebrew's, and a replacement
# restarts kanata below. The proof and the config check then run against the copy, the file the
# daemon runs.
BIN_CHANGED=0
if [[ "$(sha_of "$RUN_BIN")" != "$(sha_of "$SOURCE_BIN")" ]]; then
    say "  $RUN_BIN differs from Homebrew's kanata $version, copying it"
    as_root install -m 755 -o root -g wheel "$SOURCE_BIN" "$RUN_BIN"
    BIN_CHANGED=1
fi
if [[ $DRY_RUN -eq 1 && $BIN_CHANGED -eq 1 ]]; then
    say "    would prove $RUN_BIN cannot run commands and accepts the config, once copied"
else
    prove_no_cmd "$RUN_BIN"
    check_config "$RUN_BIN"
fi
# Made here, readable by anyone, rather than left to launchd, since the grants probe runs as the
# person and reads what kanata said about its permissions from its log.
for log in kanata.log karabiner-vhid-daemon.log; do
    [[ -e "$LOG_DIR/$log" ]] || as_root install -m 644 -o root -g wheel /dev/null "$LOG_DIR/$log"
done

# The driver daemon first, since kanata waits for it. A driver that was just installed replaced
# the daemon's binary under the running process, so it is restarted to run the new one.
put_daemon "$VHID_LABEL" "$(plist "$VHID_LABEL" "$LOG_DIR/karabiner-vhid-daemon.log" "$DRIVER_DAEMON")" \
    -f "Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
if [[ "$DAEMON_RESULT" == current && ( $DRIVER_INSTALLED -eq 1 || "$MODE" == upgrade ) ]]; then
    say "  $VHID_LABEL, restarting it on the new driver"
    as_root launchctl kickstart -k "system/$VHID_LABEL"
fi

# Kanata runs as the root owned copy, never from Homebrew's Cellar or its bin link, both of which
# the person can write. The copy's path stays the same across upgrades, so the plist does not
# change with one and a new binary is a restart instead. macOS keys the two grants to that path,
# and the binary is ad hoc signed, so its requirement is its own cdhash and a new build at the
# same path is not the build that was allowed. dotfiles/kanata/AGENTS.md says what that costs.
config_sha="$(shasum -a 256 "$CONFIG_READ" | awk '{ print $1 }')"
put_daemon "$KANATA_LABEL" "$(plist "$KANATA_LABEL" "$LOG_DIR/kanata.log" "$RUN_BIN" --cfg "$CONFIG")" \
    -x kanata
if [[ "$DAEMON_RESULT" == current ]]; then
    if [[ "$(cat "$CONFIG_STAMP" 2>/dev/null)" != "$config_sha" ]]; then
        say "  $KANATA_LABEL, restarting it on the changed config"
        as_root launchctl kickstart -k "system/$KANATA_LABEL"
        DAEMON_RESULT=started
    elif [[ $BIN_CHANGED -eq 1 ]]; then
        say "  $KANATA_LABEL, restarting it on the new binary"
        as_root launchctl kickstart -k "system/$KANATA_LABEL"
        DAEMON_RESULT=started
    elif [[ "$MODE" == upgrade ]]; then
        say "  $KANATA_LABEL, restarting it after the upgrade"
        as_root launchctl kickstart -k "system/$KANATA_LABEL"
        DAEMON_RESULT=started
    fi
fi
KANATA_RESULT="$DAEMON_RESULT"
if [[ $DRY_RUN -eq 0 && "$KANATA_RESULT" == started ]]; then
    tmp="$(mktemp)"
    printf '%s\n' "$config_sha" > "$tmp"
    as_root install -m 644 -o root -g wheel "$tmp" "$CONFIG_STAMP"
    rm -f "$tmp"
elif [[ $DRY_RUN -eq 1 && "$KANATA_RESULT" == started ]]; then
    say "    would record the config hash in $CONFIG_STAMP, what kanata was started with"
fi

#-------------------------------------------------------------------------------
# The pin, so nothing but --upgrade moves kanata away from its driver
#-------------------------------------------------------------------------------

say "==> Pin"
if pinned; then
    say "  kanata is pinned"
else
    change brew pin kanata
    if [[ $DRY_RUN -eq 0 ]]; then
        trap - EXIT
        say "  kanata is pinned, only src/setup-kanata.sh --upgrade moves it"
    fi
fi

#-------------------------------------------------------------------------------
# What only a person can give, walked by the one guide every grant goes through
#-------------------------------------------------------------------------------

# The driver approval, Input Monitoring and Accessibility for the root owned copy. Inside
# setup.sh the grants step after this one walks them with every other module's, so a person is
# taken through each grant once. Run alone, this step walks kanata's own through the same step.
# A daemon started a moment ago has not reached its permission checks yet, and the guide gives a
# probe that cannot answer a short wait before it calls the grant unknown, so nothing here waits.
# A new binary at the same path may need its grants switched off and on again, which the map's
# sentence for each grant says.
if [[ $DRY_RUN -eq 1 ]]; then
    say "==> Grants"
    say "    would walk every kanata grant not yet given, through src/setup-grants.sh kanata"
elif [[ -n "${MDJ_GRANTS_LATER:-}" ]]; then
    say "==> Grants"
    say "  left to the grants step later in this run"
else
    "$SCRIPT_DIR/setup-grants.sh" kanata
fi
