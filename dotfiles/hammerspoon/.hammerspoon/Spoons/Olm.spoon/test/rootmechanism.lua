-- The mechanism the composition root carried until 2026-10-21, in plain Lua. lib/labels.lua spells
-- a chord and a set of aliases, lib/listopen.lua answers whether a list is open, and
-- lib/rowintercept.lua answers what choosing a launcher row does in place of closing the launcher.
-- Each takes its collaborators from the root, so this hands it fakes and pins every branch the
-- root relied on, which no golden reaches since each answers only while a list is on screen.
--
-- It needs no Hammerspoon and no lock.
--
-- Run it.
--   lua test/rootmechanism.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %s, wanted %s, got %s", what, tostring(want), tostring(got)))
  end
end

local labels = assert(loadfile(here .. "../lib/labels.lua"))()
local listOpen = assert(loadfile(here .. "../lib/listopen.lua"))()
local rowIntercept = assert(loadfile(here .. "../lib/rowintercept.lua"))()

-- Labels.
do
  local chord = labels.chordLabel(function(key, mods)
    return (mods and #mods > 0 and table.concat(mods, "") or "") .. key:upper()
  end)
  eq(chord("Hyper", "k"), "Hyper K", "labels: a leader, a space and the glyph")
  eq(chord("Meta", "k", { "⇧" }), "Meta ⇧K", "labels: the glyph carries the modifiers")
  eq(labels.aliasLabel({ "v", "vpn" }), "(v, vpn)", "labels: aliases in brackets, comma joined")
  eq(labels.aliasLabel({}), "", "labels: none is the empty string")
  eq(labels.aliasLabel(nil), "", "labels: and so is nil")
end

-- Whether a list is open.
do
  local stage = { now = nil, up = false }
  function stage:current() return self.now end
  function stage:isShowing() return self.up end
  local presenting = { vpnIdentity = true }
  local open = { picker = false, sub = false, dot = false }
  local modules = {
    vpn = {},
    picker = { isShowing = function(self) return open.picker end },
    nested = { chooser = { isShowing = function(self) return open.sub end } },
    answered = { surface = function() return { isShowing = function() return open.dot end } end },
    bare = {},
  }
  local deps = {
    owners = { vpnList = "vpn", pickerList = "picker", nestedList = "nested", answeredList = "answered",
      bareList = "bare", goneList = "gone" },
    identity = { vpn = "vpnIdentity" },
    presentationFor = function(identity) return presenting[identity] and {} or nil end,
    stage = stage,
    modules = modules,
    manifests = { nested = { registry = { surface = "chooser" } }, answered = { surface = { member = "surface" } } },
  }
  eq(listOpen.isShowing("vpnList", deps), false, "open: a presenting owner is closed while the stage shows another")
  stage.now, stage.up = "vpnIdentity", true
  eq(listOpen.isShowing("vpnList", deps), true, "open: and open while the stage shows it")
  stage.up = false
  eq(listOpen.isShowing("vpnList", deps), false, "open: and closed once the stage hides")
  eq(listOpen.isShowing("unknownList", deps), false, "open: a context no one owns is closed")
  eq(listOpen.isShowing("goneList", deps), false, "open: an owner that did not load is closed")
  eq(listOpen.isShowing("bareList", deps), false, "open: a module with no surface is closed")
  eq(listOpen.anyShowing(deps), false, "any: nothing open")
  open.sub = true
  eq(listOpen.isShowing("nestedList", deps), true, "open: a surface on a submodule, by registry.surface")
  eq(listOpen.anyShowing(deps), true, "any: one open is enough")
  open.sub = false
  open.dot = true
  eq(listOpen.isShowing("answeredList", deps), true, "open: a member answering the adapter, called with a dot")
  open.dot = false
  open.picker = true
  eq(listOpen.isShowing("pickerList", deps), true, "open: a root that answers isShowing itself")
  open.picker = false
  eq(listOpen.surfaceOf(modules.nested, true), modules.nested, "surface: true is the module itself")
  eq(listOpen.surfaceOf(modules.nested, "chooser.missing.deeper"), nil, "surface: a path through nothing is nil")
end

-- What choosing a launcher row does.
do
  local did = {}
  local deps = {
    aliasQuery = function(item) return item.name == "aliasDirectory" and "? " or nil end,
    seed = function(query) did[#did + 1] = "seed " .. query end,
    presentationFor = function(name) return name == "vpn" and { name = "vpn" } or nil end,
    push = function(presentation) did[#did + 1] = "push " .. presentation.name end,
    actFor = function(item) return item.acts and function() did[#did + 1] = "act " .. item.name end or nil end,
    redirectFor = function(item) return item.word end,
  }
  local function run(item)
    local fn = rowIntercept.forRow(item, deps)
    if not fn then return nil end
    did = {}
    fn()
    return table.concat(did, ",")
  end
  eq(run({ owner = "clipboard", kind = "special", name = "vpn" }), nil, "intercept: a contributed row is its owner's alone")
  eq(run({ kind = "special", name = "aliasDirectory" }), "seed ? ", "intercept: the Aliases row seeds its word")
  eq(run({ kind = "special", name = "vpn" }), "push vpn", "intercept: a tool on the stage is pushed")
  eq(run({ kind = "special", name = "lock" }), nil, "intercept: a special row with no presentation runs as ever")
  eq(run({ kind = "scope", name = "files", acts = true }), "act files", "intercept: a scope that acts acts")
  eq(run({ kind = "scope", name = "emoji", word = "e " }), "seed e ", "intercept: else it narrows by its word")
  eq(run({ kind = "scope", name = "none" }), nil, "intercept: a scope with neither runs as ever")
  eq(run({ kind = "app", name = "vpn" }), nil, "intercept: any other kind runs as ever")
  deps.actFor, deps.redirectFor = nil, nil
  eq(run({ kind = "scope", name = "files", acts = true }), nil, "intercept: with no scope host a scope row runs as ever")
end

print(string.format("rootmechanism: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
