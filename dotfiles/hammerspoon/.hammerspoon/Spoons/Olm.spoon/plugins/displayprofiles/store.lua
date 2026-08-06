--- === DisplayProfiles.store ===
---
--- The persistence layer for captured profiles, a small backend the engine never sees. It
--- owns one JSON file, keyed by LocalHostName exactly like config/displays.lua, holding the
--- arrangements the user captured from the chooser. The curated config/displays.lua stays
--- the hand maintained reference and is read elsewhere, this file is the only writer of the
--- JSON, so the two never fight over the same source.
---
--- JSON rather than writing back into the Lua was chosen so the captured set can be shared
--- across machines through git without rewriting commented code, edited by hand when needed,
--- and read with hs.json in one line. Per host keying plus portable serial ids keep the two
--- machines from colliding in the one file.
---
--- The file lives under the config directory, which sits inside the watched .hammerspoon
--- tree, so a write would trip the pathwatcher and reload. The composition root excludes
--- this one file from the reload watch, and the chooser rebuilds the engine in memory after
--- a write, so a capture takes effect at once without a reload. The store does not know any
--- of that, it just reads and writes its path.
---
--- The shape is a map from host to a list of { name, command }. Names are unique within a
--- host, which the add and rename guards enforce, so a name identifies a captured profile
--- for rename and delete.

local S = {}
S.__index = S

--- store.new(opts)
--- opts.path  absolute path to the JSON file, resolved by the composition root from the live
---            config directory, so nothing here hardcodes a location.
--- opts.host  LocalHostName, the key this machine's captured profiles live under.
function S.new(opts)
  opts = opts or {}
  return setmetatable({ path = opts.path, host = opts.host }, S)
end

-- Read the whole file as a host to list map, or an empty map when the file is absent or
-- unreadable. A first capture on a fresh machine simply starts from empty. The file is
-- stat'd first, since hs.json.read logs a noisy error on a missing file and this is read on
-- every keystroke while the chooser is open.
function S:_readAll()
  if not self.path then return {} end
  if not hs.fs.attributes(self.path) then return {} end
  return hs.json.read(self.path) or {}
end

-- Write the whole map back, pretty printed so a hand edit or a git diff reads cleanly, and
-- replacing the file. Returns true on success.
function S:_writeAll(all)
  if not self.path then return false end
  return hs.json.write(all, self.path, true, true) == true
end

--- S:list()
--- The captured profiles for this host as a list of { name, command }, in file order, or an
--- empty list when there are none.
function S:list()
  local all = self:_readAll()
  local list = all[self.host]
  if type(list) ~= "table" then return {} end
  return list
end

-- Whether a name is already used by a captured profile for this host.
function S:exists(name)
  for _, p in ipairs(self:list()) do
    if p.name == name then return true end
  end
  return false
end

--- S:add(name, command)
--- Append a captured profile. Returns true, or false plus a message when the name is empty
--- or already used, so the caller can show the reason rather than writing a duplicate.
function S:add(name, command)
  name = name and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if name == "" then return false, "name is empty" end
  if not command or command == "" then return false, "no arrangement to capture" end
  if self:exists(name) then return false, "name already used" end
  local all = self:_readAll()
  local list = all[self.host]
  if type(list) ~= "table" then list = {}; all[self.host] = list end
  list[#list + 1] = { name = name, command = command }
  if not self:_writeAll(all) then return false, "could not write the profiles file" end
  return true
end

--- S:rename(oldName, newName)
--- Rename a captured profile. Returns true, or false plus a message when the new name is
--- empty or already used, or the old one is not found.
function S:rename(oldName, newName)
  newName = newName and newName:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if newName == "" then return false, "name is empty" end
  if newName == oldName then return true end
  if self:exists(newName) then return false, "name already used" end
  local all = self:_readAll()
  local list = all[self.host]
  if type(list) == "table" then
    for _, p in ipairs(list) do
      if p.name == oldName then
        p.name = newName
        if not self:_writeAll(all) then return false, "could not write the profiles file" end
        return true
      end
    end
  end
  return false, "profile not found"
end

--- S:remove(name)
--- Delete a captured profile by name. Returns true, or false plus a message when it is not
--- found.
function S:remove(name)
  local all = self:_readAll()
  local list = all[self.host]
  if type(list) == "table" then
    for i, p in ipairs(list) do
      if p.name == name then
        table.remove(list, i)
        if not self:_writeAll(all) then return false, "could not write the profiles file" end
        return true
      end
    end
  end
  return false, "profile not found"
end

return S
