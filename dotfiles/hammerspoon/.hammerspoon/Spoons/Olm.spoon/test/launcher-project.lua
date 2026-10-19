-- The launcher's own catalog written as lines, the projection behind test/launcher.golden.
--
-- The catalog is every row the launcher builds that is not an app, the registry's rows first,
-- then every contributed row and the launcher's own rows in their declared order. App rows are
-- left out on purpose. They come from a disk scan and the running set, neither of which a
-- stubbed run can see, and no phase of the keymap plan moves them. This is the one place the
-- format is spelled, shared by the live probe and by the offline run, so the two cannot drift.
--
-- One line per row in resting order, the order an untouched list shows before any recency is
-- applied, nine fields separated by tabs.
--
--   n          the row's place in that order, from one.
--   remembered the key the launcher's recency timeline and its query memory remember the row
--              by, the kind joined to the row's own key or its name, or a dash for a row that
--              is never remembered. This must survive every phase untouched, or a person loses
--              the order the launcher learned.
--   title      what the row says.
--   subtitle   the subtitle it bakes, with the chord it shows spelled inside it, plus the word
--              live after a bar when the row also carries a subtitle computed at open time.
--   icon       the icon key the row names, image when it wears a real app icon, a dash for none.
--   iconOwner  whose manifest the icon key is read against.
--   when       the predicate gating the row, or a dash.
--   keywords   the further words it answers to, joined with a bar, or a dash.
--   order      the launcher order number the row was placed by, or a dash for a row placed by
--              the registry's own order.
--
-- Which runner a chosen row reaches is deliberately not a field. It is routing rather than what a
-- person sees or what the launcher remembers, and phase 2b of the keymap plan moved it on purpose
-- for the clipboard's three action rows, from the registry's command dispatch to the clipboard's
-- own runner, which test/keymap.lua pins instead.
--
-- It is pure Lua and touches no hs global. It reads the launcher module's own fields and calls
-- its row builder, which builds a fresh list without touching the caches an open uses.

local obj = {}

local DASH = "-"

-- The same rule host/launcher/init.lua keeps as recencyKey, written again here because the test
-- pins the key a row is remembered by rather than trusting the code under test to state it.
function obj.rememberKey(item)
  if type(item) ~= "table" then return nil end
  if item.kind == "calc" or item.kind == "scope" then return nil end
  if item.remember == false then return nil end
  if item.kind == "app" then return "app:" .. tostring(item.bundleID) end
  return tostring(item.kind) .. ":" .. tostring(item.key or item.name)
end

local function clean(s)
  return (tostring(s):gsub("[\t\n]", " "))
end

local function iconText(row)
  if row.image ~= nil then return "image" end
  local icon = row.icon
  if icon == nil then return DASH end
  if type(icon) ~= "table" then return clean(icon) end
  local parts = {}
  for k, v in pairs(icon) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
  table.sort(parts)
  return "{" .. clean(table.concat(parts, ",")) .. "}"
end

local function keywordsText(keywords)
  if type(keywords) == "string" then return keywords ~= "" and clean(keywords) or DASH end
  if type(keywords) ~= "table" or #keywords == 0 then return DASH end
  local parts = {}
  for _, k in ipairs(keywords) do parts[#parts + 1] = clean(k) end
  return table.concat(parts, " | ")
end

--- obj.orders(launcher) -> { [remembered] = number }
--- The number each contributed row and each of the launcher's own rows was placed by. A
--- contributed row carries its number on itself, asked again of its supplier here since the
--- built row keeps only what it shows, and the launcher's own rows take its own number.
function obj.orders(launcher)
  local out = {}
  for _, supplier in ipairs(launcher._rowSuppliers or {}) do
    local ok, answered = pcall(supplier)
    if ok then
      for _, r in ipairs(answered or {}) do
        local key = type(r) == "table" and obj.rememberKey(r.item)
        if key then out[key] = r.order end
      end
    end
  end
  for _, r in ipairs(launcher._specialRows or {}) do
    if type(r) == "table" and r.name then out["special:" .. tostring(r.name)] = launcher._launcherOrder end
  end
  return out
end

--- obj.lines(launcher) -> list of lines
function obj.lines(launcher)
  local rows = launcher:_buildActionRows()
  local orders = obj.orders(launcher)
  local lines = {}
  for i, row in ipairs(rows) do
    local item = row.item or {}
    local key = obj.rememberKey(item)
    local subtitle = row.subTitle ~= nil and clean(row.subTitle) or DASH
    if row.subTitleFn then subtitle = subtitle .. " | live" end
    local order = key and orders[key]
    lines[#lines + 1] = table.concat({
      tostring(i), key or DASH, clean(row.title), subtitle, iconText(row),
      row.iconOwner ~= nil and clean(row.iconOwner) or DASH,
      row.when ~= nil and clean(row.when) or DASH,
      keywordsText(row.keywords),
      order ~= nil and tostring(order) or DASH,
    }, "\t")
  end
  return lines
end

return obj
