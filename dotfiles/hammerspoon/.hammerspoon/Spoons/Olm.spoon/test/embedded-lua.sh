# Sourced by every offline gate in this directory, never run. It sets OLM_LUA to an interpreter
# of the Lua version Hammerspoon embeds, and every gate starts Lua through "$OLM_LUA" so none of
# them names a version or reaches for whatever lua happens to be on PATH.
#
# Why this exists. Hammerspoon compiles its own Lua into the app, and a gate run on a different
# one proves less than it looks. Lua 5.4 refuses a function with more than 200 locals and 5.5
# accepts it, so a change passed every offline gate on Homebrew's lua and then failed to load
# live. decisions/lua-version-align.md has the day. The version is therefore asked of the
# module's own runtime-probe at its package root, which reads it from the installed app, and
# the interpreter is resolved through mise from that answer, so the version is written nowhere
# in this file and moves when the app does.
#
# Resolution, in order.
#   1. OLM_LUA_OVERRIDE names an interpreter to use as it is, with a warning, and skips the
#      checks below. It exists to prove a gate under another Lua on purpose and is never set
#      by a gate.
#   2. A parent gate that already resolved passes OLM_LUA down, marked by OLM_LUA_RESOLVED, so
#      a gate that runs another does not ask twice.
#   3. runtime-probe prints the version this module embeds. Exit 2 from it means the app is
#      not installed here, which leaves nothing to align with, so the gate says so and stops.
#   4. mise names where that version of lua is installed, and the interpreter inside it must
#      report the same major and minor in its own _VERSION, since a path that merely looks
#      right is how this went wrong. Nothing here installs, and nothing changes mise config.
#
# Every failure stops the gate with exit 2, the same code the gates use for a machine that
# cannot run them, and says which catalog row and which step supply the interpreter.

_olm_lua_fail() {
  echo "embedded-lua.sh: $1" >&2
  echo "  The Lua that Hammerspoon embeds comes from the lua5.4 row of dotfiles/mise/TOOLS, which a" >&2
  echo "  machine takes through its tools row in machines/<name>/pieces and receives from the mise" >&2
  echo "  step, src/install-mise-tools.sh, run through setup.sh." >&2
  exit 2
}

_olm_lua_resolve() {
  local test_dir module_root probe line version where candidate reported
  if [ -n "${OLM_LUA_OVERRIDE:-}" ]; then
    echo "embedded-lua.sh: OLM_LUA_OVERRIDE is set, so this gate runs on $OLM_LUA_OVERRIDE without checking its version" >&2
    OLM_LUA="$OLM_LUA_OVERRIDE"
    return 0
  fi
  if [ -n "${OLM_LUA_RESOLVED:-}" ] && [ -x "${OLM_LUA:-}" ]; then
    return 0
  fi

  test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  module_root="$(cd "$test_dir/../../../.." && pwd -P)"
  probe="$module_root/runtime-probe"
  [ -x "$probe" ] || _olm_lua_fail "the module's runtime-probe is missing at $probe"

  line="$("$probe")"
  case $? in
    0) ;;
    2) _olm_lua_fail "the module's runtime-probe cannot answer on this machine, so there is no embedded Lua to match" ;;
    *) _olm_lua_fail "the module's runtime-probe failed, which is a defect in it and not a fact about this machine" ;;
  esac
  version="$(printf '%s\n' "$line" | awk '$1 == "lua" { print $2; exit }')"
  [ -n "$version" ] || _olm_lua_fail "the module's runtime-probe named no lua version, it printed '$line'"

  command -v mise >/dev/null 2>&1 || _olm_lua_fail "mise is not on PATH, and it is what finds the Lua $version interpreter"
  where="$(cd "$HOME" && mise where "lua@$version" 2>/dev/null)" ||
    _olm_lua_fail "mise has no lua $version installed, and Hammerspoon embeds Lua $version"
  candidate="$where/bin/lua"
  [ -x "$candidate" ] || _olm_lua_fail "mise's lua $version has no interpreter at $candidate"

  reported="$("$candidate" -e 'io.write((_VERSION:gsub("^Lua ", "")))' 2>/dev/null)"
  [ "$reported" = "$version" ] ||
    _olm_lua_fail "$candidate reports Lua '$reported', and Hammerspoon embeds Lua $version"

  OLM_LUA="$candidate"
  OLM_LUA_RESOLVED=1
}

_olm_lua_resolve
export OLM_LUA OLM_LUA_RESOLVED
