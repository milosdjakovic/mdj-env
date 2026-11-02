#!/usr/bin/env bash
# lf adapter for explorer.sh. This is the only file that knows lf, where it
# keeps its tags, and what shape that file has.
#
# Contract expected by explorer.sh:
#   explorer_name                  prints a human label
#   explorer_argv                  prints the command, one argument per line,
#                                  accepting an optional trailing path to show
#   explorer_needs_nested_session  0 when it opens sub-popups, 1 when it does not
#   explorer_tags                  prints one absolute path per line

# Named rather than pathed, so this module stays ignorant of where anything is installed and
# works the same on either architecture. Still overridable, which is how the contract above can
# be exercised against a stub.
LF="${LF:-lf}"

# lf writes its tags under the XDG data directory, falling back to the same
# default lf itself uses when the variable is unset.
LF_TAGS="${XDG_DATA_HOME:-$HOME/.local/share}/lf/tags"

explorer_name() { printf 'lf\n'; }

# lf takes an optional cd-or-select-path, so a directory opens in it and a file
# opens in its parent with the cursor already on that file.
explorer_argv() { printf '%s\n' "$LF"; }

# lf's sub-commands run full screen in lf's own terminal since 2026-11-02, so lf no
# longer needs a real pane for popups. The nested session stays because it is what lets
# prefix+b resume lf where it was left.
explorer_needs_nested_session() { return 0; }

# The tag file format is `path:X` with a single character tag, so the trailing
# `:X` is stripped to leave a plain path.
explorer_tags() { sed 's/:.$//' "$LF_TAGS" 2>/dev/null; }
