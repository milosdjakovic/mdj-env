-- Alacritty carries no AppleScript dictionary, so a fresh attach goes through its own -e
-- flag instead, which runs a program in place of the shell and must be the last thing on
-- its argv since it swallows everything after it. `open -na` is the one door from
-- Hammerspoon to a bundle's own argv without shelling to the binary directly, -n forcing a
-- new instance so a window that is already open and ignoring --args is not what answers.
--
-- Not installed on the machine this was written on, so unlike Ghostty and Terminal.app
-- this is unverified against a live run, only against Alacritty's documented -e flag.
-- available() answers false without it, and the Settings row shows it disabled.

local BUNDLE_ID = "org.alacritty"

local openPath = nil -- resolved absolute path to /usr/bin/open, injected via configure

local function shq(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local P = { name = "Alacritty", bundleID = BUNDLE_ID }

function P.configure(opts)
  openPath = (opts and opts.open) or openPath
  return P
end

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
  if not openPath then return false, "open is not resolved" end
  local cmd = shq(openPath) .. " -na Alacritty --args -e tmux attach-session -t " .. shq(target)
  local output, ok = hs.execute(cmd)
  if not ok then return false, tostring(output) end
  return true
end

return P
