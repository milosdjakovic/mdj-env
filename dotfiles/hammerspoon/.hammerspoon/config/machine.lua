-- This machine's own Hammerspoon data, read from two files beside this config.
--
--   ~/.hammerspoon/machine-apps.lua      { keys = { [chord] = action }, apps = { [Name] = bundleID } }
--   ~/.hammerspoon/machine-displays.lua  { profiles = { { name = ..., command = ... }, ... } }
--
-- Neither is in this package. src/setup-hammerspoon-apps.sh copies each there from
-- machines/<LocalHostName>/hammerspoon-<kind>.lua at the repository root, or from
-- machines/default/hammerspoon-<kind>.lua for a machine with no file of its own, so what differs
-- between machines is decided the way machines/ decides everything else and this config never
-- names a machine. They sit beside config/ rather than inside it, because config/ is a link into
-- the repository and a copy written there would land in git.
--
-- config/keymap.lua adds the keys to its own, config/apps.lua lays the ids over its catalog, which
-- is how an app whose id differs per install, a Chrome web app, gets the right one here, and
-- config/displays.lua hands the profiles to DisplayProfiles.
--
-- A missing file means setup has not run here, so that part is empty, said once in the console
-- with the command that writes it. A file that does not load is said the same way.

local function read(kind)
  local path = hs.configdir .. "/machine-" .. kind .. ".lua"
  local chunk, loadError = loadfile(path)
  if not chunk then
    if loadError and not loadError:match("No such file") then
      print("machine " .. kind .. ": " .. path .. " does not load, so none, " .. loadError)
    else
      print("machine " .. kind .. ": no " .. path .. ", so none, src/setup-hammerspoon-apps.sh writes it")
    end
    return {}
  end
  local ok, value = pcall(chunk)
  if not ok or type(value) ~= "table" then
    print("machine " .. kind .. ": " .. path .. " does not return a table, so none, " .. tostring(value))
    return {}
  end
  return value
end

local function tableOr(value) return type(value) == "table" and value or {} end

local apps = read("apps")
local displays = read("displays")

return {
  keys = tableOr(apps.keys),
  apps = tableOr(apps.apps),
  profiles = tableOr(displays.profiles),
}
