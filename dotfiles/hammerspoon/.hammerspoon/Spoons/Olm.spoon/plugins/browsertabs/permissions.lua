--- === BrowserTabs.permissions ===
---
--- Whether Hammerspoon may script a given browser, and how to ask.
---
--- macOS gates Apple Events per pair of applications, so scripting a browser needs an
--- Automation grant for Hammerspoon against that browser specifically. Without a way to read
--- that state the settings surface could only guess, and guessing here is expensive: the
--- only other way to find out is to send a real event, and a refusal is remembered forever,
--- after which macOS never prompts again. So looking must be separable from asking.
---
--- Hammerspoon has no binding for the API that answers this, so it lives in a small Swift
--- helper beside this file, compiled once into a cached binary and run through hs.task. That
--- is the same shape Eyedropper's native sampler takes, including the cache living under
--- Library Caches rather than in the watched config tree, so building it never triggers a
--- config reload.
---
--- Four states matter and they call for different offers. granted needs nothing.
--- notDetermined can be turned into granted by asking, so the surface offers that. denied
--- cannot, because macOS will not prompt a second time, so the only honest offer is a trip
--- to the Automation pane in System Settings. notRunning means there is nothing to ask
--- about yet, since a permission for an app that is not running cannot be resolved.

local M = {}

local log = hs.logger.new("BrowserTabs", "info")

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local SOURCE = spoonPath .. "probe.swift"
local CACHE_DIR = os.getenv("HOME") .. "/Library/Caches/Hammerspoon-BrowserTabs"
local BINARY = CACHE_DIR .. "/probe"

-- The Automation pane, the only route left once a browser has been refused.
local SETTINGS_URL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"

-- Tasks in flight, held on purpose. An hs.task kept only in a local is collected once that
-- local goes out of scope, before the process finishes, so its callback never runs. Same
-- reason and same fix as in jxa.lua.
local inFlight = {}

--- The states the probe reports. Exposed so a consumer compares against these rather than
--- against loose strings.
M.states = {
  granted = "granted",
  notDetermined = "notDetermined",
  denied = "denied",
  notRunning = "notRunning",
  noTarget = "noTarget",
  unknown = "unknown",
}

--------------------------------------------------------------------------------
-- Building the native probe
--------------------------------------------------------------------------------

-- Whether the cached binary is present and no older than the Swift source, so a source edit
-- forces a rebuild and an unchanged one is reused instantly.
local function binaryFresh()
  local bin = hs.fs.attributes(BINARY, "modification")
  if not bin then return false end
  local src = hs.fs.attributes(SOURCE, "modification")
  return src == nil or bin >= src
end

-- Ensure the binary exists and is current, then call done(ok). Compilation runs off the main
-- thread, so the first read after an edit never blocks Hammerspoon.
local function ensureBinary(done)
  if binaryFresh() then done(true) return end
  hs.fs.mkdir(CACHE_DIR)
  local build
  build = hs.task.new("/usr/bin/swiftc", function(code, _, err)
    inFlight[build] = nil
    if code ~= 0 then
      log.e("could not build the permission probe (" .. tostring(code) .. "), " .. tostring(err))
    end
    done(code == 0)
  end, { "-O", SOURCE, "-o", BINARY })
  if not build then done(false) return end
  inFlight[build] = true
  build:start()
end

--- M.warm() - build the probe in the background now, so the first settings open is instant.
--- Called once at start, the same warming Eyedropper does for its sampler.
function M.warm()
  ensureBinary(function() end)
  return M
end

--------------------------------------------------------------------------------
-- Reading and asking
--------------------------------------------------------------------------------

local function run(bundleID, ask, cb)
  ensureBinary(function(ok)
    if not ok then
      cb(M.states.unknown)
      return
    end
    local argv = { bundleID }
    if ask then argv[#argv + 1] = "ask" end
    local task
    task = hs.task.new(BINARY, function(_, out)
      inFlight[task] = nil
      local word = (out or ""):gsub("%s+", "")
      cb(M.states[word] or M.states.unknown)
    end, argv)
    if not task then
      cb(M.states.unknown)
      return
    end
    inFlight[task] = true
    task:start()
  end)
end

--- M.status(bundleID, cb) - read the current permission and call cb(state). Never shows
--- anything to the user, so it is safe on every settings open.
function M.status(bundleID, cb)
  run(bundleID, false, cb)
end

--- M.request(bundleID, cb) - ask macOS for the permission, which shows the system prompt when
--- the state is notDetermined, then call cb(state) with the resulting state. On an already
--- refused browser this changes nothing, because macOS does not prompt twice, which is why
--- the surface offers M.openSettings there instead.
function M.request(bundleID, cb)
  run(bundleID, true, cb)
end

--- M.openSettings() - open the Automation pane, the only way to undo a refusal.
function M.openSettings()
  hs.execute("open '" .. SETTINGS_URL .. "'")
  return M
end

return M
