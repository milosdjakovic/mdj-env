#!/bin/sh
# Tell herdr that this pane is running a Claude session, and tell it again when the session
# ends. Without this the pane never reaches herdr's agents panel at all.
#
# Why it is needed. Herdr decides what an agent pane is by reading the pane's foreground
# process, and iris is a PTY proxy, so the shell and everything the shell runs sit on iris's
# own pty behind it. The pane's foreground process list reads iris and iris, forever, and a
# pane that fails that first check never has a title rule or a screen rule evaluated against
# it. Every other part of herdr's detection works fine here, the OSC title this session sets
# matches the claude manifest exactly. Only the identification step was missing.
#
# Reporting from a custom hook is what these two commands are documented for, and a custom
# source id is the documented shape for a reporter that is not one of herdr's own
# integrations. So this is the supported interface rather than a way around one.
#
# Why a lifecycle report rather than the HERDR_AGENT hint the herdr documentation gives for
# wrapper processes. That hint is read from the foreground process environment, which is
# fixed when iris is exec'd from the zshrc, long before anyone knows whether this pane will
# run an agent. Setting it globally would make every shell pane claim to be a claude pane.
# A report costs nothing and says the truth at the moment it is true.
#
# Why not herdr's own claude integration, which installs a hook of exactly this shape. It
# reports session identity and nothing else, and session identity does not identify a pane.
# Worse, it is actively harmful here. Once a pane carries a session recorded by the source id
# herdr:claude, herdr treats that pane as owned by its own integration and refuses to let any
# other source identify it, so installing it permanently blocks this. That was measured, not
# assumed, and neither release-agent nor clear-agent-authority takes it back. Run
# herdr integration uninstall claude if it is ever installed by hand.
#
# The state reported at the start is only a seed. Herdr's own manifest takes over the moment
# the pane is identified, which is what we want, since the manifest reads the live screen and
# knows about permission prompts and transcript views and every other shape this hook cannot
# see. Reporting unknown does not identify a pane, so the seed has to be a real state.

set -u

action="${1:-}"

# Claude Code writes the hook payload to stdin and waits for the reader. Nothing here needs
# it, but leaving it unread risks a broken pipe on the writer, so it is drained and dropped.
cat >/dev/null 2>&1 || true

# Outside herdr there is nothing to tell, and both of these are absent in a plain terminal,
# so the hook costs two string tests and exits. There is no third test for herdr itself.
# Herdr sets these, so a pane that has them has herdr, and a missing binary would be swallowed
# below anyway.
[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0

# The source id is this repository, carrying the custom prefix the socket API documents for a
# reporter that is not one of herdr's own integrations. It matters that it is not one of
# those ids, for the ownership reason in the header. The agent label is what selects the
# detection manifest, so it has to be the name herdr knows the tool by.
source_id="custom:mdj-env"
agent="claude"

# The pane id comes first. Both commands take it as a positional argument and reject it when
# it trails the options, which reads like a broken parser and is not one.
case "$action" in
  start)
    herdr pane report-agent "$HERDR_PANE_ID" \
      --source "$source_id" --agent "$agent" --state idle >/dev/null 2>&1 || true
    ;;
  end)
    herdr pane release-agent "$HERDR_PANE_ID" \
      --source "$source_id" --agent "$agent" >/dev/null 2>&1 || true
    ;;
esac

# Never fail. A session must start whether or not herdr heard about it.
exit 0
