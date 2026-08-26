--- === TmuxSessions.providers.bundle ===
---
--- What every terminal backend here needed and each one used to carry its own copy of. Three
--- of the four methods contract.lua asks for are decided entirely by a bundle id, so all five
--- providers wrote the same three functions with only the id changing, and the two quoting
--- helpers were duplicated three times and twice on top of that. Nothing about a terminal
--- distinguishes how its presence is proven or how it is raised, so none of them should have
--- been answering that question in the first place.
---
--- The cost of that was measured rather than argued. Changing how running is proven, which
--- turned out to matter a great deal for how fast the picker closes, meant five identical
--- edits to five files, and getting four of them right would have left one terminal answering
--- the slow way with nothing reporting the difference.
---
--- So this supplies the bundle decided half and a provider file supplies what is genuinely its
--- own, its identity and its openAttach. Deliberately no further than that. Three of the five
--- backends open a fresh attach through AppleScript and two through their own argv, which is a
--- second real similarity, and collapsing it too would have meant a provider file no longer
--- showing the exact script or command line it sends. That text is the thing a person opens
--- one of these files to read, so it stays written out where it belongs.
---
--- Handed in rather than reached for. A provider file returns a function taking this module
--- and returns its finished table, so no provider ever computes a path or names a sibling, and
--- init.lua, which is this plugin's composition point for backends, is the one place that
--- loads this and passes it along.

local M = {}

--- M.provider(spec) -> a table satisfying contract.lua
--- spec.name and spec.bundleID are the identity, spec.openAttach the one method only this
--- backend can write, and spec.configure an optional setter for a backend that needs a value
--- injected before it can work. available, running and activate are supplied here, since a
--- bundle id is the whole of what each of them needs to know.
function M.provider(spec)
  local id = spec.bundleID
  local P = { name = spec.name, bundleID = id }

  --- Installed on this machine at all, asked of LaunchServices rather than of a path anyone
  --- here could name, so no provider carries an install location.
  ---
  --- The empty string test is not defensive padding. pathForBundleID answers an EMPTY STRING
  --- for a bundle id it cannot place, never nil, so the obvious test against nil is true for
  --- every application that is not installed. Measured on this machine, where iTerm, Alacritty
  --- and WezTerm are all absent and all three answered available.
  function P.available()
    local path = hs.application.pathForBundleID(id)
    return path ~= nil and path ~= ""
  end

  --- Running right now. applicationsForBundleID answers exactly this and nothing else, which
  --- is why it is here rather than hs.application.get, see this plugin's CLAUDE.md for what
  --- get costs when the answer is no.
  function P.running()
    return #hs.application.applicationsForBundleID(id) > 0
  end

  --- Bring it forward, launching it first when it was not running, which is what
  --- launchOrFocusByBundleID already means.
  function P.activate()
    hs.application.launchOrFocusByBundleID(id)
  end

  P.openAttach = spec.openAttach
  if spec.configure then P.configure = spec.configure end

  return P
end

--- M.asQuote(s) -> an AppleScript string literal.
--- A backslash doubles and a double quote takes a backslash, the same rule a C string literal
--- follows. A session name is free text someone typed, so both are handled even though tmux
--- itself discourages either character.
function M.asQuote(s)
  return '"' .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

--- M.shq(s) -> a POSIX shell single quoted word, safe for anything a session name can hold.
function M.shq(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

return M
