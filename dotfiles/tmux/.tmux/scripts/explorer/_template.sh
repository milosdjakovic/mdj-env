#!/usr/bin/env bash
# Template file explorer adapter for explorer.sh. Copy this to explorer/<name>.sh,
# implement every function, then set EXPLORER_ADAPTER=<name> at the top of
# explorer.sh.
#
# The interface is rigid. It only calls these functions and only understands the
# normalized values they emit, so opening the explorer and searching its tags
# look the same for any explorer.

# Human label shown wherever the explorer is named, for example lf or Yazi.
explorer_name() { printf 'CHANGEME\n'; }

# The command to run, one argument per line, so an argument may contain spaces.
# Name the binary rather than pathing to it, so this module stays ignorant of
# where anything is installed. The command must accept an optional trailing path,
# a file or a directory, and start showing it, since that is how the interface
# reveals one path.
explorer_argv() { printf 'CHANGEME\n'; }

# Whether the explorer opens popups of its own from inside the popup it runs in.
# Return 0 when it does, which makes the interface wrap it in a nested tmux
# session so those sub-popups have a real pane to target. Return 1 when it does
# not, and it runs directly.
explorer_needs_nested_session() { return 1; }

# Every tagged or bookmarked path, one absolute path per line, for the tag
# picker. An explorer with no such feature prints nothing, and the picker is
# then simply empty.
explorer_tags() { :; }
