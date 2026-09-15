--- === Workspaces ===
---
--- Layouts a person takes and puts back. Take a snapshot of where every window sits, give it a
--- name, prune the apps it should not speak for, and later apply it to place the windows that
--- are open now. Nothing here launches, closes, or hides an app, and nothing here watches or
--- records on its own. An app that is closed when a layout is applied stays closed and the
--- report says so.
---
--- A layout remembers which display each window was on by role, the built in panel or the
--- first, second, or third external, never which monitor, and each frame as a fraction of that
--- display, so the same layout applies in front of a different external monitor. A layout is
--- available when every display it places on is attached, and the list says which are and
--- which are not.
---
--- This file is the plugin composition root, following the composition root, engine, store,
--- chooser layout the settled plugins use. engine.lua reads displays and windows, takes a
--- snapshot, and applies one, and knows nothing about a chooser or a file. store.lua persists
--- the layouts in one JSON file. chooser.lua is the surface, pure command policy over an
--- injected api. The api this root builds is that one seam, and the report an apply produces
--- goes out through the injected report word rather than through any surface of this plugin's
--- own, since the root decides how a message is drawn and where it lands.

local obj = {}

-- Metadata
obj.name = "Workspaces"
obj.version = "2.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("Workspaces", "info")

-- Load the siblings by absolute path off this file's own location, loadfile rather than require
-- since a spoon directory is not on package.path. The chooser is exposed so the wiring layer can
-- reach its own configure step and the registrar can resolve its presentation members.
local pluginPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(pluginPath .. name)
  if not chunk then
    error("Workspaces: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end
local engine = load("engine.lua")
local store = load("store.lua")
obj.chooser = load("chooser.lua")

-- Owned state
obj._store = nil    -- the layouts on disk, or nil when no path arrived
obj._report = nil   -- the root's report word, or nil when the root published none

-- An app's own icon, cached by bundle id, the same cache and fallback shape browsertabs and
-- clipboard already use for the same call. A bundle id with nothing installed for it answers
-- nil, and every caller falls back to a generic mark rather than leaving the row blank.
local iconCache = {}
local function appIcon(bundleID)
  if not bundleID then return nil end
  local hit = iconCache[bundleID]
  if hit ~= nil then return hit or nil end
  local img = hs.image.imageFromAppBundle(bundleID)
  iconCache[bundleID] = img or false
  return img
end

--- Workspaces:init()
--- Method
--- Initialize the plugin. No side effects, per the lifecycle contract.
function obj:init()
  return self
end

-- What each apply outcome says on the report, one short phrase per app.
local function statusDetail(row)
  if row.status == "placed" then
    return row.recorded == 1 and "placed" or (row.recorded .. " windows placed")
  elseif row.status == "partial" then
    return row.placed .. " of " .. row.recorded .. " windows placed"
  elseif row.status == "notOpen" then
    return "not open"
  elseif row.status == "noWindow" then
    return "open, no window"
  elseif row.status == "noDisplay" then
    return "its display is not attached"
  elseif row.status == "refused" then
    return "would not move"
  end
  return ""
end

-- Everything the chooser is allowed to know, and the one place the engine and the store are
-- joined. Every write flushes at once, since each is a person's own act, and the answer to a
-- write is true or false plus a message the chooser logs.
function obj:_buildApi()
  local function withStore(fn)
    return function(...)
      if not self._store then return false, "nothing is stored, so there is nothing to change" end
      local ok, err = fn(...)
      if ok then self._store:flush() end
      return ok, err
    end
  end

  -- Every layout, available ones first, each carrying what the top level row needs.
  local function list()
    local attached = engine.attached()
    local out = {}
    for _, layout in ipairs(self._store and self._store:list() or {}) do
      local included, excluded = 0, 0
      for _, app in ipairs(layout.apps or {}) do
        if app.excluded then excluded = excluded + 1 else included = included + 1 end
      end
      local available, reason = engine.availability(layout, attached)
      out[#out + 1] = {
        id = layout.id,
        name = layout.name,
        taken = layout.taken,
        topology = engine.topologyLabel(layout.topology),
        apps = included,
        excluded = excluded,
        available = available,
        reason = reason,
      }
    end
    table.sort(out, function(a, b)
      if a.available ~= b.available then return a.available end
      return a.name:lower() < b.name:lower()
    end)
    return out
  end

  return {
    list = list,

    -- One layout by id, in the same shape a list row has, or nil once it is gone.
    get = function(id)
      for _, row in ipairs(list()) do
        if row.id == id then return row end
      end
      return nil
    end,

    -- Whether there is a file at all, so the surface can say what is missing rather than showing
    -- an empty list that looks like nothing was ever taken.
    persists = function() return self._store ~= nil end,

    -- The displays attached right now, in words, for the new snapshot row.
    here = function()
      local attached = engine.attached()
      return engine.topologyLabel({ internal = attached.internal, externals = attached.externals })
    end,

    -- One layout's apps, each with the app's name, its icon, whether it is excluded, and where
    -- its windows sit, sorted with the included ones first so the excluded read as a tail.
    apps = function(id)
      local layout = self._store and self._store:get(id)
      local out = {}
      for _, app in ipairs((layout or {}).apps or {}) do
        local displays, seen = {}, {}
        for _, w in ipairs(app.windows or {}) do
          if type(w.display) == "string" and not seen[w.display] then
            seen[w.display] = true
            displays[#displays + 1] = engine.roleLabel(w.display)
          end
        end
        out[#out + 1] = {
          bundle = app.bundle,
          name = app.name or app.bundle,
          icon = appIcon(app.bundle),
          excluded = app.excluded == true,
          windows = #(app.windows or {}),
          displays = table.concat(displays, " and "),
        }
      end
      table.sort(out, function(a, b)
        if a.excluded ~= b.excluded then return b.excluded end
        return a.name:lower() < b.name:lower()
      end)
      return out
    end,

    exists = function(name) return self._store ~= nil and self._store:nameExists(name) end,

    -- Take a snapshot of what is open now under the given name. Answers the new id.
    create = function(name)
      if not self._store then return nil, "nothing is stored, so a snapshot has nowhere to go" end
      local id, err = self._store:add(name, engine.snapshot())
      if id then self._store:flush() end
      return id, err
    end,

    update = withStore(function(id) return self._store:update(id, engine.snapshot()) end),
    rename = withStore(function(id, newName) return self._store:rename(id, newName) end),
    remove = withStore(function(id) return self._store:remove(id) end),
    exclude = withStore(function(id, bundle) return self._store:setExcluded(id, bundle, true) end),
    include = withStore(function(id, bundle) return self._store:setExcluded(id, bundle, false) end),

    -- Place the windows a layout records and report what did not happen, through the root's
    -- report word when it published one and on the console regardless. Only the apps that were
    -- not placed in full are reported, since a window that moved is its own feedback and the
    -- panel exists to say which apps the layout could not reach, closed ones above all. An
    -- apply where everything landed shows nothing.
    apply = function(id)
      local layout = self._store and self._store:get(id)
      if not layout then return false, "layout not found" end
      local available, reason = engine.availability(layout)
      if not available then return false, reason end
      local report = engine.apply(layout)
      local rows = {}
      for _, r in ipairs(report) do
        log.i(string.format("apply '%s', %s, %s", layout.name, r.name, statusDetail(r)))
        if r.status ~= "placed" then
          rows[#rows + 1] = {
            icon = appIcon(r.bundle),
            label = r.name,
            detail = statusDetail(r),
            dim = r.status == "notOpen",
          }
        end
      end
      if #rows > 0 and self._report then
        self._report({ title = layout.name .. ", not placed", rows = rows })
      end
      return true
    end,
  }
end

--- Workspaces:configure(opts)
--- Method
--- opts.storage  lib/storage.lua, the declared lib grant, asked for this plugin's own data
---               directory under the olm root. The file is layouts.json inside it.
--- opts.report   the root's report word, a function of { title, rows } that draws the list
---               on the shared overlay. Without it an apply says what it did on the console
---               only.
--- The chooser's stage words arrive separately, through its own wiring step, so this is safe to
--- call before or after that.
function obj:configure(opts)
  opts = opts or {}
  if opts.storage then
    self._store = store.new({ storage = opts.storage, dir = "workspaces", file = "layouts.json" })
  end
  self._report = opts.report
  self.chooser:configure({ api = self:_buildApi() })
  log.i("persistence " .. (self._store and "on" or "off"))
  return self
end

return obj
