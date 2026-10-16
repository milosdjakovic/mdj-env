-- Unit case for the Plugins page of the settings plugin, plugins/settings/pluginspage.lua. The
-- runner reaches this file with a dofile call carrying an absolute path, so it locates itself
-- through debug.getinfo and derives every module path from there.
--
-- The page builder is pure, rows are data and the detail is kit nodes, so it is driven with the
-- real kit and a hand written catalog and no canvas is made. What pane.lua and init.lua decide,
-- the docking and the wiring, needs the running config and is outside this case.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local olm = caseDir .. "/../../Spoons/Olm.spoon/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local function eq(description, got, want)
  check(description, got == want, "got " .. tostring(got) .. ", wanted " .. tostring(want))
end

local function fresh(path)
  local chunk, err = loadfile(olm .. path)
  if not chunk then error("could not load " .. path .. ", " .. tostring(err)) end
  return chunk()
end

local page = fresh("plugins/settings/pluginspage.lua")
local styleLib = fresh("lib/ui/style.lua")
local ui = fresh("lib/ui/kit.lua").new(styleLib.names)

local catalog = {
  { identity = "alpha", about = { title = "Alpha", version = "1.2", author = "A", license = "MIT",
      homepage = "example.test" }, needs = { tools = { "tool1" }, libs = {}, siblings = { "beta" },
      data = { "wordOne" } }, disabled = false },
  { identity = "beta", about = { title = "Beta" }, needs = { tools = {}, libs = {}, siblings = {},
      data = {} }, disabled = true },
  { identity = "gamma", about = { title = "Gamma" }, needs = {}, disabled = false,
    offBecause = { "beta" } },
  { identity = "delta", about = { title = "Delta" }, needs = {}, disabled = true,
    lockedBy = "config" },
  { identity = "settings", about = { title = "Settings" }, needs = {}, disabled = false },
  { identity = "epsilon", about = { title = "Epsilon" }, needs = {}, disabled = false,
    lockedBy = "core" },
  { identity = "zeta", about = { title = "Zeta" }, needs = {}, disabled = false,
    offBecause = { "alpha", "beta" } },
}

local function row(title, subTitle, icon, item, enabled, filterText)
  return { title = title, subTitle = subTitle, icon = icon, item = item, enabled = enabled,
    filterText = filterText }
end

local rows = page.rows(catalog, row, "settings")
eq("one row per catalog entry", #rows, 7)
eq("an on plugin says on", rows[1].subTitle, "on")
eq("an on plugin carries the green circle", rows[1].icon, "selected")
eq("an off plugin says off", rows[2].subTitle, "off")
eq("an off plugin carries the red circle", rows[2].icon, "notSelected")
eq("a plugin off because of another names its title", rows[3].subTitle, "off because Beta is off")
eq("an off because plugin carries the red circle", rows[3].icon, "notSelected")
eq("a config locked plugin says so", rows[4].subTitle, "locked off in config")
check("a plain plugin is toggleable", rows[1].item.toggle == true and rows[2].item.toggle == true)
check("a locked or dependent plugin is not toggleable",
  rows[3].item.toggle == false and rows[4].item.toggle == false)
eq("the row carries the identity", rows[1].item.plugin, "alpha")
eq("the row states the identity as its key, so the stage holds the highlight on it",
  rows[1].item.key, "alpha")
eq("the page's own row says so", rows[5].subTitle, "this page")
check("the page's own row is not toggleable", rows[5].item.toggle == false)
eq("a plugin the core needs says so", rows[6].subTitle, "needed by the core")
check("a plugin the core needs is not toggleable", rows[6].item.toggle == false)
eq("two causes are both named", rows[7].subTitle, "off because Alpha and Beta are off")

eq("nothing staged has no summary, so no Apply row", page.pendingSummary(catalog), nil)

-- The same catalog with alpha staged off, the root's preview taking zeta off because of alpha
-- and leaving every other row as it is. Each row carries after while anything is staged.
local function staged(base, pendingFor, afterFor)
  local out = {}
  for _, entry in ipairs(base) do
    local copy = {}
    for k, v in pairs(entry) do copy[k] = v end
    copy.pending = pendingFor[entry.identity]
    copy.after = afterFor[entry.identity]
      or { off = entry.disabled == true or entry.offBecause ~= nil, offBecause = entry.offBecause }
    out[#out + 1] = copy
  end
  return out
end
-- Eta is added for this, a plain on plugin that the preview takes off with alpha.
local pendingCatalog = staged(catalog, { alpha = true }, { alpha = { off = true } })
pendingCatalog[#pendingCatalog + 1] = { identity = "eta", about = { title = "Eta" }, needs = {},
  disabled = false, after = { off = true, offBecause = { "alpha" } } }
local afterRows = page.rows(pendingCatalog, row, "settings")
eq("a staged switch moves the marker", afterRows[1].icon, "notSelected")
eq("a staged switch says what applying does", afterRows[1].subTitle, "off after apply")
check("a staged row can be toggled back", afterRows[1].item.toggle == true)
eq("a plugin going off with it says so and why", afterRows[8].subTitle,
  "off after apply, because Alpha is off")
eq("and carries the red circle", afterRows[8].icon, "notSelected")
check("and cannot be toggled while it is carried along", afterRows[8].item.toggle == false)
eq("an unchanged row keeps its plain words", afterRows[2].subTitle, "off")
eq("the summary names every change in catalog order", page.pendingSummary(pendingCatalog),
  "Alpha off, Eta off")

local onCatalog = staged(catalog, { beta = false }, { beta = { off = false },
  gamma = { off = false } })
local onRows = page.rows(onCatalog, row, "settings")
eq("a plugin staged on says on after apply", onRows[2].subTitle, "on after apply")
eq("and carries the green circle", onRows[2].icon, "selected")
eq("a plugin coming back with it says on after apply", onRows[3].subTitle, "on after apply")

local function said(node, out)
  out = out or {}
  if node.kind == "text" then out[#out + 1] = node.str end
  if node.facts then out[#out + 1] = tostring(node.facts) end
  if node.label then out[#out + 1] = tostring(node.label) end
  for _, child in ipairs(node.children or {}) do said(child, out) end
  return out
end
local function joined(node) return table.concat(said(node), "\n") end

local detail = joined(page.detail(ui, catalog[1], catalog, { off = true, others = { "gamma" } }))
check("the detail names the author", detail:find("A", 1, true) ~= nil)
check("the detail names the homepage", detail:find("example.test", 1, true) ~= nil)
check("the detail lists the tools", detail:find("tool1", 1, true) ~= nil)
check("the detail lists the siblings", detail:find("beta", 1, true) ~= nil)
check("an on plugin's cascade says turning it off, with titles",
  detail:find("Turning this off also turns off Gamma.", 1, true) ~= nil)

local back = joined(page.detail(ui, catalog[2], catalog, { off = false, others = { "gamma" } }))
check("an off plugin's cascade says turning it on",
  back:find("Turning this on also brings back Gamma.", 1, true) ~= nil)

local none = joined(page.detail(ui, catalog[1], catalog, { off = true, others = {} }))
check("an empty cascade says nothing about it", none:find("Turning this", 1, true) == nil)

local applying = joined(page.detail(ui, pendingCatalog[1], pendingCatalog,
  { off = true, staged = true, others = { "eta" } }))
check("a staged plugin's cascade says what applying does",
  applying:find("Applying this also turns off Eta.", 1, true) ~= nil)
check("and its state line says off after apply", applying:find("off after apply", 1, true) ~= nil)
local returning = joined(page.detail(ui, onCatalog[2], onCatalog,
  { off = false, staged = true, others = { "gamma" } }))
check("a plugin staged on says what applying brings back",
  returning:find("Applying this also brings back Gamma.", 1, true) ~= nil)

local bare = joined(page.detail(ui, catalog[2], catalog, nil))
check("a plugin with no author draws none", bare:find("Author", 1, true) == nil)
check("a plugin that needs nothing says so", bare:find("Needs nothing", 1, true) ~= nil)

-- The Plugins child must inherit the shared matcher, since it is a list a person picks from.
local initFile = io.open(olm .. "plugins/settings/init.lua", "r")
local initText = initFile and initFile:read("*a") or ""
if initFile then initFile:close() end
local childBody = initText:match("local function buildPluginsChild%(%).-\n  }\nend") or ""
check("the Plugins child body was found", childBody ~= "")
check("the Plugins child does not set matcher to false", childBody:find("matcher%s*=%s*false") == nil)

check("a plugin row filters on its title and identity only", rows[1].filterText == "Alpha alpha")
check("a staged row filters on the same text as before", afterRows[1].filterText == rows[1].filterText)
