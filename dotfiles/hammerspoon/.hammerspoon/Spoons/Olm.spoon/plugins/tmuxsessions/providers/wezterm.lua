-- WezTerm carries no AppleScript dictionary either, so a fresh attach goes through its own
-- `start -- command` form instead, reached the same way Alacritty is, through `open -na`
-- and --args, -n forcing a new instance for the same reason.
--
-- Not installed on the machine this was written on, so unlike Ghostty and Terminal.app
-- this is unverified against a live run, only against WezTerm's documented CLI. available()
-- answers false without it, and the Settings row shows it disabled.

local BUNDLE_ID = "com.github.wez.wezterm"

local openPath = nil -- resolved absolute path to /usr/bin/open, injected via configure

local function shq(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local P = { name = "WezTerm", bundleID = BUNDLE_ID }

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
  local cmd = shq(openPath) .. " -na WezTerm --args start -- tmux attach-session -t " .. shq(target)
  local output, ok = hs.execute(cmd)
  if not ok then return false, tostring(output) end
  return true
end

return P
