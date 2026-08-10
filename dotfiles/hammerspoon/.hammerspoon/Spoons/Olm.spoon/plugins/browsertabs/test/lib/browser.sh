#!/usr/bin/env bash
# Reaching a browser, and reaching the accessibility layer.
#
# The runner never names an adapter file and never names a dictionary. It says a bundle id and an
# operation, and this decides which adapter answers, the same inversion the spoon itself uses
# between its engine and its providers. Adding a browser to the suite is a new adapter plus a line
# in the two tables below.

# Which adapter speaks for which browser. One entry per dictionary, not per application, so every
# Chromium shares one.
#
# Arc has none, deliberately. It has never been open when this suite ran, so an adapter for it would
# be code that has never once been executed, and the one Arc case here needs no adapter because it
# only asks whether a browser that is closed stays closed.
bt_adapter() {
  case $1 in
    com.apple.Safari) printf 'safari.js' ;;
    *) printf 'chromium.js' ;;
  esac
}

# The name the accessibility layer knows a browser by, which is the application's own name and not
# its bundle id. System Events has no way to find a process by bundle id directly.
bt_process_name() {
  case $1 in
    com.apple.Safari) printf 'Safari' ;;
    com.google.Chrome) printf 'Google Chrome' ;;
    company.thebrowser.Browser) printf 'Arc' ;;
    *) printf '%s' "${1##*.}" ;;
  esac
}

# The short name a case list uses for a browser, so the list reads as words rather than as bundle
# identifiers. This is the only place the two are joined.
bt_bundle_for() {
  case $1 in
    chrome) printf 'com.google.Chrome' ;;
    safari) printf 'com.apple.Safari' ;;
    arc) printf 'company.thebrowser.Browser' ;;
    *) printf '%s' "$1" ;;
  esac
}

# bt <bundleID> <op> [args...] and the adapter's JSON answer on stdout.
bt() {
  local bundle=$1 op=$2; shift 2
  osascript -l JavaScript "$BT_TEST_DIR/browsers/$(bt_adapter "$bundle")" "$bundle" "$op" "$@" 2>/dev/null
}

# The outside witness, which application is frontmost and what the accessibility layer has in
# front for this browser.
bt_ax() {
  osascript -l JavaScript "$BT_TEST_DIR/ax.js" "$(bt_process_name "$1")" 2>/dev/null
}

# Whether a browser is running at all, asked without launching it. Reading a property of a quit
# application would start it, which is exactly what the tool under test is careful never to do, so
# the harness must not do it either while deciding which cases can run.
bt_running() {
  local n
  n=$(osascript -e "tell application \"System Events\" to return (count of (application processes whose bundle identifier is \"$1\"))" 2>/dev/null)
  [ "${n:-0}" -gt 0 ] 2>/dev/null && printf 'true' || printf 'false'
}
