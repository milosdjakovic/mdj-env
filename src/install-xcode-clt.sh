#!/bin/bash
set -e

# Make sure this machine has a developer toolchain, since three things in this repository
# compile something and none of them can say so in time to help.
#
# Neovim's treesitter builds every parser from source on first open, and the Hammerspoon
# module compiles two small Swift helpers, the eyedropper's colour sampler and the browser
# permission probe. All three fail quietly and late, long after setup has said it was done.
#
# DEPENDENCIES.map named xcode-select --install as the detail for cc and swiftc for a long
# time and nothing ran it, which made it the one dependency this repository described instead
# of installing. It is a command rather than a checkbox in System Settings, so this layer may
# run it, and this layer is the only one allowed to.
#
# It runs first in setup.sh for two reasons. Everything later in the run that compiles wants
# it, and Homebrew's own installer wants it too, so having it already done is what keeps that
# step from stopping to ask.

# What macOS uses to find a compiler, so it is also what proves one is reachable. Asking
# xcode-select rather than testing a path, because there is no single path to test. The
# command line tools put cc under /Library/Developer/CommandLineTools, a full Xcode puts it
# under its own bundle in a toolchain folder with a different name again, and /usr/bin/cc is
# a stub present on every Mac whether or not either of those exists. So the stub proves
# nothing and only the active developer directory answers for both layouts.
developer_dir() {
    local dir
    dir="$(/usr/bin/xcode-select -p 2>/dev/null)" || return 1
    [[ -n "$dir" && -d "$dir" ]] || return 1
    printf '%s' "$dir"
}

if dir="$(developer_dir)"; then
    echo "Developer toolchain already present at $dir"
    exit 0
fi

echo "Installing the Xcode command line tools, expect a dialog..."
# Answers non zero when it has nothing to do, which the guard above already rules out, and
# again if the user closes the dialog. Neither is worth stopping the whole setup for, so the
# wait below is what decides what actually happened.
/usr/bin/xcode-select --install 2>/dev/null || true

# The installer is a window someone has to click, and the download that follows is as slow as
# the connection is. So this waits rather than racing ahead into steps that need a compiler,
# and it waits only when there is somebody there to click. A run with no terminal attached
# cannot be answered, and blocking one for a quarter of an hour to find that out helps nobody.
WAIT_SECONDS=900
POLL_SECONDS=10

if [[ ! -t 0 ]]; then
    echo "No terminal attached, so the dialog cannot be answered here."
    echo "Finish the install by hand, then run src/check-dependencies.sh to confirm."
    exit 0
fi

echo "Waiting for it to finish, up to $((WAIT_SECONDS / 60)) minutes. Ctrl C stops waiting."
waited=0
while (( waited < WAIT_SECONDS )); do
    if dir="$(developer_dir)"; then
        echo ""
        echo "Developer toolchain installed at $dir"
        exit 0
    fi
    sleep "$POLL_SECONDS"
    waited=$(( waited + POLL_SECONDS ))
    printf '.'
done

echo ""
# Never fatal. Everything after this step in setup.sh is worth running without a compiler,
# and check-dependencies.sh reports the state of this machine at the end of the run anyway,
# so stopping here would cost the whole rest of the setup to say something that gets said
# again in a minute.
echo "Still no developer toolchain after $((WAIT_SECONDS / 60)) minutes."
echo "Treesitter parsers and the Hammerspoon Swift helpers will not build until there is one."
