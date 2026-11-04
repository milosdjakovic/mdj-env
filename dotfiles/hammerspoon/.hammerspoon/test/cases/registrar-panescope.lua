-- Unit case for the scope Olm builds for a tool whose list carries a preview pane,
-- decisions/olm-query-scope-handover.md. Such a tool joins the scope list by having aliases and
-- nothing else, gets one pinned row naming it and its presentation for the root to hand over to,
-- and a scope it still declares is ignored and named. A tool with no pane keeps the scope it
-- declares, and a tool with no aliases gets no scope.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local spoon = caseDir .. "/../../Spoons/Olm.spoon/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local chunk, err = loadfile(spoon .. "lib/registrar.lua")
if not chunk then error("could not load lib/registrar.lua, " .. tostring(err)) end
local registrar = chunk()

local function present(width) return { name = "x", previewPaneWidth = width } end
local declared = { rows = function() return {} end, run = function() end }

-- Five active tools. files and speed have a pane, files declaring nothing and speed still
-- declaring a scope. keep has no pane and declares one. quiet has a pane and no aliases. narrow
-- has a pane width of zero, which is no pane.
local tools = {
  files = { row = { description = "File Search", icon = "search", aliases = { "/" } }, presentation = present(420) },
  speed = { row = { description = "Speed Test", aliases = { "st" } }, presentation = present(true), scope = declared },
  keep = { row = { description = "Keep Awake", aliases = { "k" } }, presentation = present(nil), scope = declared },
  quiet = { row = { description = "Quiet" }, presentation = present(300) },
  narrow = { row = { description = "Narrow", aliases = { "n" } }, presentation = present(0), scope = declared },
}
local order = { "keep", "files", "speed", "quiet", "narrow" }
local registry = {
  active = function() return order end,
  rowFor = function(name) return tools[name] and tools[name].row end,
  scopeFor = function(name) return tools[name] and tools[name].scope end,
  presentationFor = function(name) return tools[name] and tools[name].presentation end,
}

-- The set answers keep, speed and narrow, the tools that declare provides, and files declares none.
local out = registrar.scopeSpec({ identity = {}, effective = {} }, registry, { "keep", "speed", "narrow" }, {})
local byName, names = {}, {}
for i, s in ipairs(out) do byName[s.name] = s; names[i] = s.name end

check("a tool with a pane and aliases joins without declaring provides", byName.files ~= nil,
  table.concat(names, ","))
check("set members keep their order and a pane tool follows them", table.concat(names, ",") == "keep,speed,narrow,files",
  table.concat(names, ","))
check("Olm's scope carries the presentation for the root", byName.files and byName.files.presentation == tools.files.presentation)
local rows = byName.files and byName.files.rows("anything") or {}
check("Olm's scope answers one pinned row naming the tool", #rows == 1 and rows[1].pinned == true
  and rows[1].title == "File Search" and rows[1].icon == "search", tostring(#rows))
check("Olm's scope keeps the tool's aliases", byName.files and byName.files.aliases[1] == "/")
check("a scope a pane tool still declares is replaced", byName.speed and byName.speed.presentation ~= nil
  and byName.speed.rows ~= declared.rows)
check("and is named as ignored", out.ignored and #out.ignored == 1 and out.ignored[1] == "speed",
  out.ignored and table.concat(out.ignored, ",") or "nil")
check("a tool with no pane keeps the scope it declares", byName.keep and byName.keep.rows == declared.rows
  and byName.keep.presentation == nil)
check("a pane width of zero is no pane", byName.narrow and byName.narrow.rows == declared.rows
  and byName.narrow.presentation == nil)
check("a pane tool with no aliases gets no scope", byName.quiet == nil)
check("hasPreviewPane reads true and a positive width as a pane", registrar.hasPreviewPane(present(true))
  and registrar.hasPreviewPane(present(1)) and not registrar.hasPreviewPane(present(0))
  and not registrar.hasPreviewPane(present(nil)) and not registrar.hasPreviewPane(nil))
