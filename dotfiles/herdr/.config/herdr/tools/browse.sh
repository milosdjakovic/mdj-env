#!/usr/bin/env bash
# lf in the directory the calling pane sits in. Viewing only under Herdr, since every
# interactive key lf binds opens a tmux popup and there is no tmux session to open it into.
set -u
. "$(dirname "$0")/context.sh"
cd "$(herdr_pane_cwd)" 2>/dev/null || cd "$HOME" || exit 1
exec lf
