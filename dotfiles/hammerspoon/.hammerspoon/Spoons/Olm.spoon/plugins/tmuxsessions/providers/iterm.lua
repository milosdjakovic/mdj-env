-- iTerm2, scripted through its own dictionary. "create window with default profile
-- command" opens a fresh window running that command in place of the profile's shell,
-- the same shape Ghostty and Terminal.app each answer in their own words.
--
-- Not installed on the machine this was written on, so unlike Ghostty and Terminal.app
-- this one was verified against iTerm2's published scripting dictionary rather than a
-- live run. available() answers false on a machine without it either way, and the
-- Settings row shows it disabled rather than pretending it works.

local BUNDLE_ID = "com.googlecode.iterm2"

local function asQuote(s)
  return '"' .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

local P = { name = "iTerm", bundleID = BUNDLE_ID }

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
  local script = 'tell application id ' .. asQuote(BUNDLE_ID)
    .. ' to create window with default profile command ' .. asQuote(cmd)
  local ok, _, err = hs.osascript.applescript(script)
  if not ok then return false, tostring(err) end
  return true
end

return P
