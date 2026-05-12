#!/usr/bin/env bash
# Shared helpers for fzf pickers that want instant-open backed by a
# persistent cache, with live updates driven by fzf's --listen API.
#
# The pattern:
#   1. Seed a working cache file from a persistent cache on disk.
#   2. Open fzf with `--listen <unix-socket-path>` so the script knows
#      exactly where to push reload triggers (no port discovery).
#   3. Run the scan in the background, streaming rows into a tmp file.
#      Periodically swap the tmp onto the working cache and POST a
#      `reload(...)` to fzf so the visible list refreshes.
#   4. On scan completion, persist the cache atomically for next time.
#
# This file is sourced, not executed directly.

# Where persistent caches live.
fzf_cache_dir() {
  local base="${XDG_CACHE_HOME:-$HOME/.cache}/fzf-tmux"
  mkdir -p "$base" 2>/dev/null
  chmod 700 "$base" 2>/dev/null
  printf '%s' "$base"
}

# Allocate a unique Unix socket path for this invocation. fzf only
# accepts socket paths ending in .sock, so we build that suffix
# explicitly. The socket is bound by fzf and cleaned up by the
# caller's EXIT trap.
fzf_cache_socket() {
  local base
  base=$(mktemp -u -t fzf-cache.XXXXXX)
  printf '%s.sock' "$base"
}

# Consume a scan stream from stdin and drive fzf updates through it.
#
# Args:
#   $1 = listen socket path (where fzf is listening)
#   $2 = work cache (file fzf reads from)
#   $3 = persist cache (under ~/.cache, kept across invocations)
#   $4 = throttle (rows between in-flight reloads during the scan)
#   $5 = reload action template. The literal {{cache}} is replaced
#        with the work cache path before being sent to fzf.
fzf_cache_consume() {
  local sock="$1"
  local work_cache="$2"
  local persist_cache="$3"
  local throttle="$4"
  local reload_template="$5"

  # Give fzf a brief window to bind its listen socket. If it never
  # appears we still persist the cache; the picker will fall back to
  # showing the seeded snapshot.
  local i
  for i in $(seq 1 40); do
    [ -S "$sock" ] && break
    sleep 0.025
  done

  local scan_tmp
  scan_tmp=$(mktemp -t fzf-cache-scan.XXXXXX)

  local reload_action="${reload_template//\{\{cache\}\}/$work_cache}"

  _fzf_cache_swap_and_reload() {
    # Skip the swap if the caller already cleaned up its working cache
    # (e.g. fzf exited while the background scan was still running).
    [ -e "$work_cache" ] || return 0
    cp "$scan_tmp" "$work_cache.swap" 2>/dev/null || return 0
    mv "$work_cache.swap" "$work_cache" 2>/dev/null || return 0
    # `curl --unix-socket` fails silently if fzf has not yet started
    # listening or has already exited. Both cases are fine; the
    # persisted cache is what matters across runs.
    [ -S "$sock" ] || return 0
    curl -s --unix-socket "$sock" \
      -XPOST "http://localhost/" \
      --data-binary "$reload_action" >/dev/null 2>&1 || true
  }

  local count=0
  while IFS= read -r line; do
    printf '%s\n' "$line" >> "$scan_tmp"
    count=$((count + 1))
    if [ $((count % throttle)) -eq 0 ]; then
      _fzf_cache_swap_and_reload
    fi
  done

  # Final swap so any tail rows after the last throttle boundary show.
  _fzf_cache_swap_and_reload

  # Persist via a separate tmp path so the caller's own EXIT trap
  # cannot race with the persist write. mv across the same filesystem
  # is atomic so the persist cache is never observed half-written.
  local persist_tmp
  persist_tmp=$(mktemp -t fzf-cache-persist.XXXXXX)
  if cp "$scan_tmp" "$persist_tmp"; then
    mv "$persist_tmp" "$persist_cache" 2>/dev/null || rm -f "$persist_tmp"
  fi

  rm -f "$scan_tmp" "$work_cache.swap"
}
