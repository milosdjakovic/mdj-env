-- This machine's own app keys and app ids, read from ~/.hammerspoon/machine-apps.lua.
--
-- That file is not in this package. src/setup-hammerspoon-apps.sh copies it there from
-- machines/<LocalHostName>/hammerspoon-apps.lua at the repository root, or from
-- machines/default/hammerspoon-apps.lua for a machine with no file of its own, so which apps a
-- Hyper key reaches is decided per machine the same way machines/ decides everything else, and
-- this config never names a machine. It sits beside config/ rather than inside it, because
-- config/ is a link into the repository and a copy written there would land in git.
--
-- The file returns { keys = { [chord] = action }, apps = { [Name] = bundleID } }. config/keymap.lua
-- adds the keys to its own, and config/apps.lua lays the ids over its catalog, which is how an
-- app whose id differs per install, a Chrome web app, gets the right one here.
--
-- A missing file means setup has not run here, so there are no app keys at all, said once in the
-- console with the command that writes it. A file that does not load is said the same way.

local path = hs.configdir .. "/machine-apps.lua"
local empty = { keys = {}, apps = {} }

local chunk, loadError = loadfile(path)
if not chunk then
  if loadError and not loadError:match("No such file") then
    print("machine apps: " .. path .. " does not load, no app keys, " .. loadError)
  else
    print("machine apps: no " .. path .. ", so no app keys, src/setup-hammerspoon-apps.sh writes it")
  end
  return empty
end

local ok, value = pcall(chunk)
if not ok or type(value) ~= "table" then
  print("machine apps: " .. path .. " does not return a table, no app keys, " .. tostring(value))
  return empty
end

return {
  keys = type(value.keys) == "table" and value.keys or {},
  apps = type(value.apps) == "table" and value.apps or {},
}
