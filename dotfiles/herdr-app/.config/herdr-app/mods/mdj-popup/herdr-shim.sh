#!/usr/bin/env bash
# Stands in for the herdr TUI binary when the mdj-tools scripts run inside a Herdr app popup.
# The scripts call it through HERDR_BIN_PATH; each herdr call they make is answered here with
# hc or herdr-app, so the scripts in the dotfiles keep working for both programs unchanged.
set -u
case "${1:-} ${2:-}" in
  "notification show")
    # Queued for the popup's title bar, which posts them as app toasts when the popup closes.
    title="${3:-}"; shift 3; body=""
    while [ $# -gt 0 ]; do case "$1" in --body) body="${2:-}"; shift 2 ;; *) shift ;; esac; done
    [ -n "${MDJ_POPUP_NOTES:-}" ] && printf '%s\t%s\n' "$title" "${body//$'\n'/ }" >> "$MDJ_POPUP_NOTES"
    ;;
  "pane process-info")
    # The launcher looked at the calling pane when the popup opened: a shell in front, or not.
    if [ "${MDJ_CALLER_FREE:-no}" = yes ]; then pg=1; else pg=2; fi
    printf '{"result":{"process_info":{"foreground_process_group_id":%s,"shell_pid":1}}}\n' "$pg"
    ;;
  "pane run")
    # The pane id the scripts hold is the calling terminal's hc address.
    exec hc send "$3" "$4"
    ;;
  "tab create")
    shift 2; cwd=""
    while [ $# -gt 0 ]; do case "$1" in --cwd) cwd="${2:-}"; shift 2 ;; *) shift ;; esac; done
    exec herdr-app do tab.new --folder "${cwd:-$HOME}"
    ;;
  *)
    echo "herdr-shim: $* has no Herdr app equivalent" >&2; exit 1 ;;
esac
