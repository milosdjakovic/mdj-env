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

local function row(title, subTitle, icon, item, enabled)
  return { title = title, subTitle = subTitle, icon = icon, item = item, enabled = enabled }
end

local rows = page.rows(catalog, {}, row, "settings")
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
eq("the page's own row says so", rows[5].subTitle, "this page")
check("the page's own row is not toggleable", rows[5].item.toggle == false)
eq("a plugin the core needs says so", rows[6].subTitle, "needed by the core")
check("a plugin the core needs is not toggleable", rows[6].item.toggle == false)
eq("two causes are both named", rows[7].subTitle, "off because Alpha and Beta are off")

local after = page.rows(catalog, { alpha = true }, row, "settings")
eq("a pending switch moves the marker", after[1].icon, "notSelected")
eq("a pending switch changes the words", after[1].subTitle, "off")

local function said(node, out)
  out = out or {}
  if node.kind == "text" then out[#out + 1] = node.str end
  if node.facts then out[#out + 1] = tostring(node.facts) end
  if node.label then out[#out + 1] = tostring(node.label) end
  for _, child in ipairs(node.children or {}) do said(child, out) end
  return out
end
local function joined(node) return table.concat(said(node), "\n") end

local detail = joined(page.detail(ui, catalog[1], catalog, { "gamma" }, {}))
check("the detail names the author", detail:find("A", 1, true) ~= nil)
check("the detail names the homepage", detail:find("example.test", 1, true) ~= nil)
check("the detail lists the tools", detail:find("tool1", 1, true) ~= nil)
check("the detail lists the siblings", detail:find("beta", 1, true) ~= nil)
check("an on plugin's cascade says turning it off, with titles",
  detail:find("Turning this off also turns off Gamma.", 1, true) ~= nil)

local back = joined(page.detail(ui, catalog[2], catalog, { "gamma" }, {}))
check("an off plugin's cascade says turning it on",
  back:find("Turning this on also brings back Gamma.", 1, true) ~= nil)

local none = joined(page.detail(ui, catalog[1], catalog, {}, {}))
check("an empty cascade says nothing about it", none:find("Turning this", 1, true) == nil)

local stale = joined(page.detail(ui, catalog[1], catalog, { "gamma" }, { alpha = true }))
check("a cascade is left out once the page has switched that plugin", stale:find("Turning this", 1, true) == nil)

local bare = joined(page.detail(ui, catalog[2], catalog, {}, {}))
check("a plugin with no author draws none", bare:find("Author", 1, true) == nil)
check("a plugin that needs nothing says so", bare:find("Needs nothing", 1, true) ~= nil)
