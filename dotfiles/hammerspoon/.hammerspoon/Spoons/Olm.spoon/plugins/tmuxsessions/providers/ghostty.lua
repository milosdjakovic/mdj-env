-- Ghostty carries a real AppleScript dictionary (sdef /Applications/Ghostty.app), one of
-- only three backends here that do, so opening an attach is one scripting command rather
-- than a CLI flag guess. "new window with configuration {command:...}" takes the place of
-- the configured shell for exactly that one window, which is what makes a fresh attach a
-- single call with nothing to clean up after.

local BUNDLE_ID = "com.mitchellh.ghostty"

-- AppleScript string literals escape a backslash by doubling it and a double quote with a
-- backslash, the same rule a C string literal follows. A session name is free text someone
-- typed, so both are handled even though tmux itself discourages either character.
local function asQuote(s)
  return '"' .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

local P = { name = "Ghostty", bundleID = BUNDLE_ID }

function P.available()
  return hs.application.pathForBundleID(BUNDLE_ID) ~= nil
end

function P.running()
  return hs.application.get(BUNDLE_ID) ~= nil
end

function P.activate()
  hs.application.launchOrFocusByBundleID(BUNDLE_ID)
end

function P.openAttach(target)
  hs.application.launchOrFocusByBundleID(BUNDLE_ID)
  local cmd = "tmux attach-session -t " .. asQuote(target)
  -- Addressed by bundle id rather than by name, since "id" is the one identifier that
  -- cannot drift with a display name change across a version.
  local script = 'tell application id ' .. asQuote(BUNDLE_ID)
    .. ' to new window with configuration {command:' .. asQuote(cmd) .. '}'
  local ok, _, err = hs.osascript.applescript(script)
  if not ok then return false, tostring(err) end
  return true
end

return P
