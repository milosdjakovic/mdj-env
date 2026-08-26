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

-- Resolved absolute paths, filled by configure below. This file is a plain module rather
-- than a colon called spoon, so the two tools it reaches for live as module locals rather
-- than on a self.
local swiftcPath = nil
local openPath = nil

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
-- thread, so the first read after an edit never blocks Hammerspoon. A missing swiftc is the
-- same shape as a build that failed, the probe cannot exist, so it takes the same route out
-- rather than a second one, and every status read then answers unknown, which is already the
-- answer the surface gives for a probe that could not be built.
local function ensureBinary(done)
  if binaryFresh() then done(true) return end
  if not swiftcPath then
    log.w("no swiftc, the permission probe cannot be built, so every browser reads unknown until the command line tools are installed")
    done(false)
    return
  end
  hs.fs.mkdir(CACHE_DIR)
  local build
  build = hs.task.new(swiftcPath, function(code, _, err)
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

--- M.configure(opts) - learn the resolved paths for the two tools this file reaches for.
--- opts.deps is the scoped dependency adapter the plugin root received, granted because the
--- plugin manifest declares both swiftc and open under this unit. Called from the plugin
--- root's own configure, before either tool is ever reached for, and safe to call with no
--- opts.deps at all, in which case both stay unresolved and every path below degrades the
--- way a genuinely missing tool already does.
function M.configure(opts)
  opts = opts or {}
  local deps = opts.deps
  if deps then
    swiftcPath = deps.path("swiftc")
    openPath = deps.path("open")
  end
  return M
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

--- M.openSettings() - open the Automation pane, the only way to undo a refusal. Answers
--- false plus a short reason when open never resolved, rather than shelling out to a bare
--- word that a missing PATH entry would silently fail on with nothing said anywhere.
function M.openSettings()
  if not openPath then
    log.w("no open, cannot reach the Automation pane, undo a refused browser by hand in System Settings instead")
    return false, "open is not resolved"
  end
  -- Built into a local rather than handed to hs.execute as a literal, so the resolved path
  -- is the whole of what this call names and the reconciler's own door check, which reads a
  -- quoted literal as the tool being invoked, sees a variable here exactly as it should.
  local cmd = "'" .. openPath .. "' '" .. SETTINGS_URL .. "'"
  hs.execute(cmd)
  return M
end

return M
