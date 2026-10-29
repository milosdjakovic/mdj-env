-- Unit case for the action panel's contract, docs/PLAN-ACTION-PANEL.md, the four fields a row of
-- surface.extra may carry and a verb of the panel alone, validated by lib/surface.lua and ordered
-- into sections by lib/hints.lua. The runner reaches this file with a dofile call carrying an
-- absolute path, and this file finds the modules from its own.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local libDir = caseDir .. "/../../Spoons/Olm.spoon/lib/"
local surface = assert(loadfile(libDir .. "surface.lua"))()
local hints = assert(loadfile(libDir .. "hints.lua"))()

local function check(description, ok, detail)
  print((ok and "PASS " or "FAIL ") .. description .. ((not ok and detail) and (", " .. detail) or ""))
end

local base = { context = "demo", primary = { action = "insertSelected", description = "Apply" } }
local function with(extra)
  local decl = {}
  for k, v in pairs(base) do decl[k] = v end
  decl.extra = extra
  return decl
end

check("a verb of the panel alone needs no key", surface.validate("demo",
  with({ { action = "rename", description = "Rename" } })) == true)
check("a keyless row with no description is refused", surface.validate("demo",
  with({ { action = "rename" } })) == false)
check("section, applies, choices and confirm are accepted", surface.validate("demo", with({
  { action = "a", description = "A", section = "S", applies = "fits" },
  { action = "b", description = "B", choices = "list" },
  { action = "c", description = "C", confirm = true },
  { key = "d", action = "d", confirm = "Really" },
})) == true)
check("choices and confirm together are refused", surface.validate("demo",
  with({ { action = "a", description = "A", choices = "list", confirm = true } })) == false)
check("a confirm that is not true or a title is refused", surface.validate("demo",
  with({ { action = "a", description = "A", confirm = 3 } })) == false)

local block = surface.context("demo", with({
  { key = "r", action = "keyed", description = "Keyed" },
  { action = "panelOnly", description = "Panel only" },
}), nil, {})
local boundPanelOnly = false
for _, b in ipairs(block.bindings) do if b.action == "panelOnly" then boundPanelOnly = true end end
check("a keyless verb is kept out of the bindings", not boundPanelOnly)
check("and listed in the block's panel", block.panel and block.panel[1].action == "panelOnly")

local ordered = hints.sectioned({
  { title = "Back" },
  { action = "x", title = "Manage one", section = "Manage" },
  { action = "y", title = "Plain" },
  { action = "insertSelected", title = "Apply", shared = "primary" },
  { action = "z", title = "Layout one", section = "Layout" },
  { action = "w", title = "Manage two", section = "Manage" },
})
local titles = {}
for _, r in ipairs(ordered) do titles[#titles + 1] = r.title end
check("Back and the primary lead, then plain verbs, then each section in declared order",
  table.concat(titles, ",") == "Back,Apply,Plain,Manage one,Manage two,Layout one", table.concat(titles, ","))

-- A verb on the same action as the secondary is the secondary on a second key, listed once.
do
  local plan = { contexts = { demo = { bindings = {
    { shared = "primary", action = "insertSelected", key = "i", description = "Open" },
    { shared = "secondary", action = "reveal", key = "return", mods = { "cmd" }, description = "Reveal" },
    { key = "f", action = "reveal", description = "Reveal" },
    { key = "y", action = "copyPath", description = "Copy path" },
  } } } }
  local rows = hints.rowsFor("demo", plan, {})
  local reveals = 0
  for _, r in ipairs(rows) do if r.action == "reveal" then reveals = reveals + 1 end end
  check("the secondary's action is listed once though a key also names it", reveals == 1)
end
