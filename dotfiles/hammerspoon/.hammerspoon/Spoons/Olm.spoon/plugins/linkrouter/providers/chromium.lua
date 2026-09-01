--- Chromium destination provider.
---
--- Expands a Chromium based application into one destination per profile, and opens a link in
--- the profile that was chosen. Chrome and Helium are both this today, and Edge, Brave and
--- Vivaldi would be too without a line changing here, because nothing in this file names a
--- browser.
---
--- Whether an application is Chromium is answered from disk rather than from a list of bundle
--- ids. Every Chromium build keeps a `Local State` json file in its own support directory with
--- a `profile.info_cache` object mapping each profile directory to its display name, so the
--- question this provider actually asks is whether such a file exists and parses. An
--- application nobody has heard of gets profile support on the day it is installed, and an
--- application that is not Chromium is simply not claimed and falls through to the plain
--- provider, which is the single row it always had.
---
--- Finding that support directory from a bundle id is the one genuinely awkward step, since
--- there is no rule Apple or Google guarantees. Rather than a table of known browsers, which
--- would be stale the moment anything new shipped, this builds candidate paths structurally
--- out of the bundle id and the application name and proves each one by opening the file.
--- Helium is reached by its bundle id alone, Chrome by the vendor and product pair its own
--- bundle id already spells. When no candidate proves out the application is not claimed,
--- which degrades to exactly the behavior before profiles existed rather than to an error.

local M = { name = "chromium" }

local log = hs.logger.new("LinkRouterChromium", "info")

-- Cached per bundle id, since destinations is asked on every keystroke while the list is open
-- and reading and parsing a file that size on each one would be a scan where the contract asks
-- for a read. Cleared through forget when a list is about to be shown rather than held for the
-- life of the config, so a profile added in the browser appears without a reload.
local cache = {}

local function supportRoot()
  return os.getenv("HOME") .. "/Library/Application Support/"
end

--- candidates(bundleID, appName) -> list of paths
--- The support directory this application might use, most specific first. Every one is a guess
--- and every one is proven by opening the file before it is believed.
local function candidates(bundleID, appName)
  local out = {}
  local root = supportRoot()
  -- The bundle id used verbatim as a directory, which is what Helium does.
  out[#out + 1] = root .. bundleID
  -- The vendor and product pair the bundle id already carries, com.google.Chrome becoming
  -- Google/Chrome, which is what Chrome does.
  local vendor, product = bundleID:match("^%w+%.([%w%-]+)%.([%w%-]+)$")
  if vendor and product then
    out[#out + 1] = root .. vendor:sub(1, 1):upper() .. vendor:sub(2) .. "/" .. product
  end
  -- The application's own name, for a build that uses neither of the above.
  if appName and appName ~= "" then out[#out + 1] = root .. appName end
  return out
end

--- readProfiles(bundleID, appName) -> map of directory to info, or nil
--- Opens each candidate's Local State and answers the first that parses and carries a profile
--- info cache. Every failure is silent and answers nil, since not being Chromium is the
--- ordinary case here rather than a fault worth a console line.
local function readProfiles(bundleID, appName)
  for _, dir in ipairs(candidates(bundleID, appName)) do
    local f = io.open(dir .. "/Local State", "r")
    if f then
      local body = f:read("a")
      f:close()
      local ok, parsed = pcall(hs.json.decode, body)
      local info = ok and parsed and parsed.profile and parsed.profile.info_cache
      if type(info) == "table" and next(info) ~= nil then return info end
    end
  end
  return nil
end

local function profilesFor(bundleID, appName)
  local hit = cache[bundleID]
  if hit ~= nil then return hit or nil end
  local info = readProfiles(bundleID, appName)
  cache[bundleID] = info or false
  return info
end

--- M.forget()
--- Drop the cache, called by the engine when a list is about to be shown.
function M.forget()
  cache = {}
end

function M:claims(bundleID)
  return profilesFor(bundleID, hs.application.nameForBundleID(bundleID)) ~= nil
end

--- M:destinations(bundleID, appName) -> entries
--- One entry per profile, ordered by the profile's directory name rather than by its display
--- name, so the order is stable when a profile is renamed. Default sorts first, since Chromium
--- spells the primary profile that way and it is the one most links are meant for.
function M:destinations(bundleID, appName)
  local contract = self.contract
  local info = profilesFor(bundleID, appName)
  if not info then return {} end
  local dirs = {}
  for dir in pairs(info) do dirs[#dirs + 1] = dir end
  table.sort(dirs, function(a, b)
    if a == "Default" then return true end
    if b == "Default" then return false end
    return a < b
  end)
  local out = {}
  for _, dir in ipairs(dirs) do
    local shown = info[dir] and info[dir].name
    local base = shown and (appName .. " (" .. shown .. ")") or appName
    -- The ordinary window and the private one are two entries rather than one entry and a
    -- modifier, so a private window is turned on and ordered exactly like everything else and
    -- needs no key anybody has to remember. Both are offered here and the configuration page
    -- decides which are worth showing, which for most people is the ordinary one alone.
    out[#out + 1] = {
      id = contract.entryId(bundleID, dir, false),
      bundle = bundleID, profile = dir, private = false, label = base,
    }
    out[#out + 1] = {
      id = contract.entryId(bundleID, dir, true),
      bundle = bundleID, profile = dir, private = true, label = base .. " private window",
    }
  end
  return out
end

--- M:open(entry, url, deps) -> boolean
--- Opens through the open binary rather than hs.urlevent.openURLWithBundle, which can name an
--- application but has no way to name a profile inside it. The profile is selected by the
--- browser's own argument, and the arguments go to the task as a list rather than as a command
--- string, so a profile directory or a url carrying a space or a quote needs no escaping and
--- cannot be reread as shell syntax.
---
--- open is optional, and without it this provider cannot do its one job, so it answers false
--- and lets the caller say so rather than pretending the link went somewhere.
local function launch(entry, url, deps, private)
  local openPath = deps and deps.path and deps.path("open")
  if not openPath then
    log.w("no open binary, could not reach a profile in " .. tostring(entry.bundle))
    return false
  end
  local appPath = hs.application.pathForBundleID(entry.bundle)
  if not appPath then return false end
  local args = { "-na", appPath, "--args", "--profile-directory=" .. tostring(entry.profile) }
  -- Chromium spells this the same way across builds, and a build that does not know the flag
  -- ignores it and opens an ordinary window rather than refusing to start, so an unknown
  -- Chromium never costs the link.
  if private then args[#args + 1] = "--incognito" end
  args[#args + 1] = url
  local task = hs.task.new(openPath, nil, args)
  if not task then return false end
  return task:start()
end

--- M:open(entry, url, deps) -> boolean
--- One door for both kinds, reading the entry's own private flag, so nothing outside has to ask
--- what this destination is capable of before sending a link to it.
function M:open(entry, url, deps)
  return launch(entry, url, deps, entry.private)
end

return M
