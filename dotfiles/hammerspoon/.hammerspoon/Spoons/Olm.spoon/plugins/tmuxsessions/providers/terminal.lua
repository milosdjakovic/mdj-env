-- Apple's own Terminal.app, scripted through its own long standing dictionary. "do script"
-- with no target window opens a fresh one, which is exactly what an attach wants.

local BUNDLE_ID = "com.apple.Terminal"

local function asQuote(s)
  return '"' .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

local P = { name = "Terminal", bundleID = BUNDLE_ID }

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
  -- Addressed by bundle id rather than by name, the same reasoning as Ghostty's provider.
  local script = 'tell application id ' .. asQuote(BUNDLE_ID) .. ' to do script ' .. asQuote(cmd)
  local ok, _, err = hs.osascript.applescript(script)
  if not ok then return false, tostring(err) end
  return true
end

return P
