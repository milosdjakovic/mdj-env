--- === Browser Switcher ===
---
--- Olm.app is the default browser and hands each link here, docs/DESIGN-BROWSER-SWITCHER.md. A
--- rule the person wrote opens it at once, and otherwise the list asks, the person's favourites in
--- their own order, a browser, a browser's profile or Copy Link, with Show All for the rest.
---
--- A target is a browser, or a Chromium browser's or Firefox's profile, read from the browser's
--- own files. Safari's profiles have no way in from outside, so Safari is one target. A link always
--- opens in a named browser, never through the default, since the default is Olm.

local M = { name = "BrowserSwitcher", version = "0.1", author = "Milos Djakovic", license = "MIT" }

local cfg = {}
local OLM = "local.olm.Olm"
local COPY = "Copy Link"

-- The browsers whose profiles can be named from outside, where each keeps its list of them under
-- Application Support, and how a link is opened in one.
local CHROMIUM = {
  ["com.google.Chrome"] = "Google/Chrome",
  ["com.google.Chrome.beta"] = "Google/Chrome Beta",
  ["com.brave.Browser"] = "BraveSoftware/Brave-Browser",
  ["com.microsoft.edgemac"] = "Microsoft Edge",
  ["org.chromium.Chromium"] = "Chromium",
  ["com.vivaldi.Vivaldi"] = "Vivaldi",
}
local FIREFOX = { ["org.mozilla.firefox"] = "Firefox" }

local SUPPORT = os.getenv("HOME") .. "/Library/Application Support/"

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

local function hostOf(url)
  return (url:match("^%a[%w+.-]*://([^/?#]+)") or ""):gsub("^[^@]*@", ""):gsub(":%d+$", ""):lower()
end

-- The browsers whose list of profiles is there but cannot be read, macOS keeping another app's
-- data from Hammerspoon, refreshed with every read of the targets.
local hidden = {}

-- Whether path is there but cannot be opened, which is macOS refusing it rather than no profiles.
local function refused(path)
  if not hs.fs.attributes(path) then return false end
  local file = io.open(path, "r")
  if file then file:close(); return false end
  return true
end

local function chromiumProfiles(folder)
  if refused(SUPPORT .. folder .. "/Local State") then return nil end
  local state = hs.json.read(SUPPORT .. folder .. "/Local State")
  local cache = state and state.profile and state.profile.info_cache
  if type(cache) ~= "table" then return {} end
  local out = {}
  for dir, info in pairs(cache) do
    if type(info) == "table" and type(info.name) == "string" then
      out[#out + 1] = { arg = "--profile-directory=" .. dir, name = info.name, order = dir == "Default" and "" or dir }
    end
  end
  table.sort(out, function(a, b) return a.order < b.order end)
  return out
end

local function firefoxProfiles(folder)
  if refused(SUPPORT .. folder .. "/profiles.ini") then return nil end
  local file = io.open(SUPPORT .. folder .. "/profiles.ini", "r")
  if not file then return {} end
  local out = {}
  for line in file:lines() do
    local name = line:match("^Name=(.+)$")
    if name then out[#out + 1] = { args = { "-P", name }, name = name } end
  end
  file:close()
  return out
end

-- Every target this Mac has, each browser and then each of its profiles when it has more than one.
local function targets()
  local out = {}
  local browsers = {}
  hidden = {}
  for _, bundle in ipairs(hs.urlevent.getAllHandlersForScheme("https") or {}) do
    if bundle ~= OLM and bundle ~= "org.hammerspoon.Hammerspoon" then
      local path = hs.application.pathForBundleID(bundle)
      if path and path ~= "" then
        local name = hs.application.nameForBundleID(bundle) or bundle
        browsers[#browsers + 1] = { bundle = bundle, name = name, path = path }
      end
    end
  end
  table.sort(browsers, function(a, b) return a.name:lower() < b.name:lower() end)
  for _, b in ipairs(browsers) do
    out[#out + 1] = { id = b.bundle, title = b.name, bundle = b.bundle, path = b.path }
    local profiles = {}
    if CHROMIUM[b.bundle] then profiles = chromiumProfiles(CHROMIUM[b.bundle])
    elseif FIREFOX[b.bundle] then profiles = firefoxProfiles(FIREFOX[b.bundle]) end
    if profiles == nil then hidden[#hidden + 1] = b.name; profiles = {} end
    if #profiles > 1 then
      for _, p in ipairs(profiles) do
        out[#out + 1] = { id = b.bundle .. "#" .. p.name, title = b.name .. " (" .. p.name .. ")", bundle = b.bundle,
          path = b.path, profile = p.name, args = p.args or { p.arg } }
      end
    end
  end
  return out
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

local function globToPattern(glob)
  return "^" .. glob:lower():gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
end

local function matches(pattern, link)
  local app = pattern:match("^app:%s*(.+)$")
  if app then
    app = app:lower()
    return (link.sourceName or ""):lower() == app or (link.sourceBundle or ""):lower() == app
  end
  local host = hostOf(link.url)
  if pattern:find("/", 1, true) then
    local rest = link.url:lower():gsub("^%a[%w+.-]*://", "")
    return rest:find(pattern:lower():gsub("^%a[%w+.-]*://", ""), 1, true) == 1
  end
  if host:match(globToPattern(pattern)) then return true end
  -- *.github.com takes github.com itself too.
  local bare = pattern:match("^%*%.(.+)$")
  return bare ~= nil and host == bare:lower()
end

-- The target the first matching rule names, nil when none matches or it names nothing here.
local function ruled(link)
  local known = byTitle(targets())
  for _, line in ipairs(lines(cfg.rules)) do
    local pattern, name = line:match("^(.-)%s*=>%s*(.+)$")
    if pattern and pattern ~= "" and matches(pattern, link) then
      if name:lower() == COPY:lower() then return { copy = true, title = COPY } end
      local target = known[name:lower()]
      if target then return target end
      say("Browser Switcher, the rule for " .. pattern .. " names " .. name .. ", which this Mac does not have")
      return nil
    end
  end
  return nil
end

--- M.link(params) -> handled. Olm.app's link, through the root's provides.links.
function M.link(params)
  local link = { url = params.url, sourceBundle = params.sourceBundle, sourceName = params.sourceName }
  if not params.ask then
    local target = ruled(link)
    if target then
      pending = link
      open(target, link.url)
      return true
    end
  end
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
  local favourites = lines(cfg.favourites)
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
  if #hidden > 0 and (showAll or #favourites == 0) then
    out[#out + 1] = { title = table.concat(hidden, ", ") .. " profiles are hidden",
      subTitle = "macOS keeps their list from Hammerspoon", filterText = "profiles hidden",
      icon = "warn", enabled = false, pinned = true, item = { id = "none" } }
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

function M.verbs:isFavourites() return not showAll and #lines(cfg.favourites) > 0 end
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
