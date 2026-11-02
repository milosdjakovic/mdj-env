#!/usr/bin/env bash
# lf in the directory the calling pane sits in. Every lf key works here, since lf runs its
# pickers in its own terminal and needs no multiplexer.
set -u
. "$(dirname "$0")/context.sh"
cd "$(herdr_pane_cwd)" 2>/dev/null || cd "$HOME" || exit 1
exec lf
