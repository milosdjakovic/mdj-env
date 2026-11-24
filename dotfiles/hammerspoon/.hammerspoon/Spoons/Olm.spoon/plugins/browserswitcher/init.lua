--- === Browser Switcher ===
---
--- Olm.app is the default browser and hands each link here, docs/DESIGN-BROWSER-SWITCHER.md, and
--- the list asks, the person's favourites, a browser, a browser's profile or Copy Link, with Show
--- All for the rest.
---
--- A target is a browser, or a Chromium browser's or Firefox's profile, which Olm.app finds and
--- writes for this plugin. Safari's profiles have no way in from outside, so Safari is one target. A link always
--- opens in a named browser, never through the default, since the default is Olm.

local M = { name = "BrowserSwitcher", version = "0.1", author = "Milos Djakovic", license = "MIT" }

local cfg = {}
local OLM = "local.olm.Olm"
local COPY = "Copy Link"

-- What Olm.app found, every browser and each profile of one that has several, written as Olm.app
-- starts, before each link it hands over and while the page in Olm Settings is shown. Olm.app reads
-- the profiles, since macOS keeps them from Hammerspoon.
local SCAN = os.getenv("HOME") .. "/.olm/run/browsers.json"

-- The link waiting for an answer, kept after it opens so the launcher row can send it again.
local pending
local showAll = false

local function lines(text)
  local out = {}
  for line in tostring(text or ""):gmatch("[^\r\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and not line:match("^#") then out[#out + 1] = line end
  end
  return out
end

-- Every target, Olm.app's scan where it has written one, and otherwise each browser alone.
local function targets()
  local out = {}
  local scan = hs.json.read(SCAN)
  if type(scan) == "table" and type(scan.targets) == "table" and #scan.targets > 0 then
    for _, t in ipairs(scan.targets) do
      if type(t.title) == "string" and type(t.bundle) == "string" then
        local args = type(t.args) == "table" and #t.args > 0 and t.args or nil
        out[#out + 1] = { id = t.title, title = t.title, bundle = t.bundle, path = t.path, args = args }
      end
    end
    return out
  end
  for _, bundle in ipairs(hs.urlevent.getAllHandlersForScheme("https") or {}) do
    if bundle ~= OLM and bundle ~= "org.hammerspoon.Hammerspoon" then
      local path = hs.application.pathForBundleID(bundle)
      if path and path ~= "" then
        local name = hs.application.nameForBundleID(bundle) or bundle
        out[#out + 1] = { id = name, title = name, bundle = bundle, path = path }
      end
    end
  end
  table.sort(out, function(a, b) return a.title:lower() < b.title:lower() end)
  return out
end

-- The favourites, a list of names checked in Olm Settings, or words one per line as they were saved
-- before they were checkboxes.
local function favouritesList()
  if type(cfg.favourites) == "table" then
    local out = {}
    for _, name in ipairs(cfg.favourites) do if type(name) == "string" and name ~= "" then out[#out + 1] = name end end
    return out
  end
  return lines(cfg.favourites)
end

local function byTitle(list)
  local out = {}
  for _, t in ipairs(list) do out[t.title:lower()] = t end
  return out
end

local function say(text) if cfg.notify then cfg.notify(text) end end

local function copyLink(url)
  if not url then return end
  hs.pasteboard.setContents(url)
  say("Link copied")
end

-- Opens url in target, a browser through LaunchServices and a profile by starting the browser's
-- own program with the profile, which hands it to the copy already running.
local function open(target, url)
  if target.copy then return copyLink(url) end
  if not target.args then
    hs.urlevent.openURLWithBundle(url, target.bundle)
    return
  end
  local info = hs.application.infoForBundlePath(target.path) or {}
  local program = target.path .. "/Contents/MacOS/" .. tostring(info.CFBundleExecutable or "")
  local args = {}
  for _, a in ipairs(target.args) do args[#args + 1] = a end
  args[#args + 1] = url
  local task = hs.task.new(program, function()
    hs.application.launchOrFocusByBundleID(target.bundle)
  end, args)
  if not (task and task:start()) then
    say("Browser Switcher could not start " .. target.title .. ", opened in " .. (hs.application.nameForBundleID(target.bundle) or "its browser"))
    hs.urlevent.openURLWithBundle(url, target.bundle)
  end
end

--- M.link(params) -> handled. Olm.app's link, through the root's provides.links.
function M.link(params)
  local link = { url = params.url, sourceBundle = params.sourceBundle, sourceName = params.sourceName }
  if not cfg.stagePresent then return false end
  pending = link
  showAll = false
  cfg.stagePresent("browserSwitcher")
  if cfg.stageSetPlaceholder then cfg.stageSetPlaceholder(M.placeholder()) end
  return true
end

-- The link itself, its scheme left off and cut in the middle past a field's width, so the start of
-- the address and its end both show.
local LINK_ROOM = 64

function M.placeholder()
  if not pending then return "Open link in" end
  local text = pending.url:gsub("^https?://", ""):gsub("^www%.", "")
  if utf8.len(text) and utf8.len(text) > LINK_ROOM then
    local head = math.floor(LINK_ROOM * 0.6)
    local tail = LINK_ROOM - head - 1
    local chars = {}
    for _, c in utf8.codes(text) do chars[#chars + 1] = utf8.char(c) end
    text = table.concat(chars, "", 1, head) .. "…" .. table.concat(chars, "", #chars - tail + 1, #chars)
  end
  return text
end

function M.rows()
  if not pending then
    return { { title = "No link yet", subTitle = "Links you click while Olm is the default browser land here",
      icon = "warn", enabled = false, pinned = true, item = { id = "none" } } }
  end
  local all = targets()
  local list = {}
  local favourites = favouritesList()
  if showAll or #favourites == 0 then
    for _, t in ipairs(all) do list[#list + 1] = t end
    list[#list + 1] = { id = "copy", title = COPY, copy = true }
  else
    local known = byTitle(all)
    for _, name in ipairs(favourites) do
      if name:lower() == COPY:lower() then
        list[#list + 1] = { id = "copy", title = COPY, copy = true }
      elseif known[name:lower()] then
        list[#list + 1] = known[name:lower()]
      end
    end
  end
  local out = {}
  for _, t in ipairs(list) do
    local row = { title = t.title, key = t.id, filterText = t.title, item = t }
    if t.copy then
      row.icon = "copy"
    else
      -- The browser's own picture, a real image rather than an icon key.
      row.image = hs.image.imageFromAppBundle(t.bundle)
    end
    out[#out + 1] = row
  end
  if #out == 0 then
    out[1] = { title = "No favourite is on this Mac", subTitle = "Show All in the actions pane lists every browser",
      icon = "warn", enabled = false, pinned = true, item = { id = "none" } }
  end
  return out
end

function M.select(item)
  if not (item and item.id and item.id ~= "none" and pending) then return end
  open(item, pending.url)
end

function M.show()
  if cfg.stagePresent then
    showAll = false
    cfg.stagePresent("browserSwitcher")
    if cfg.stageSetPlaceholder then cfg.stageSetPlaceholder(M.placeholder()) end
  end
end

-- The actions pane's verbs, registry.surface.
M.verbs = {}

function M.verbs:isFavourites() return not showAll and #favouritesList() > 0 end
function M.verbs:isAll() return showAll end

function M.verbs:showAll()
  showAll = true
  if cfg.redrawPresented then cfg.redrawPresented("browserSwitcher", true) end
end

function M.verbs:showFavourites()
  showAll = false
  if cfg.redrawPresented then cfg.redrawPresented("browserSwitcher", true) end
end

function M.verbs:copyLink()
  if not pending then return end
  copyLink(pending.url)
  if cfg.stageHide then cfg.stageHide() end
end

function M:configure(opts)
  cfg = opts or {}
  return M
end

return M
