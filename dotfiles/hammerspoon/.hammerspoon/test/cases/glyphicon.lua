-- Unit case for Olm.spoon/lib/glyphicon.lua, the icon facade lifted out of
-- Launcher's own private drawing once ActionPanel became a second caller of it, phase
-- eight's third packet, and since 2026 10 15 a thin door over the icon engine in lib/icons.
-- Each instance below is given its own engine built from the real emoji source, so the drawing
-- under test is the one the root builds. The runner reaches this file with a dofile call carrying an
-- absolute path, so this file in turn locates itself the same way, through
-- debug.getinfo, and derives the module path from there. No absolute path is ever
-- written down here, and the module under test is only loaded, never edited.
--
-- Each check prints one line, PASS or FAIL followed by a plain description, and the
-- runner counts and reports from those lines alone, the same convention every other
-- case file already follows.
--
-- Every block below builds its own fresh instance with M.new, the same isolation
-- cases/recency.lua and cases/registry.lua already keep for their own factories, so one
-- block's drawings can never leak into another's expectations.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/lib/glyphicon.lua"
local iconsPath = caseDir .. "/../../Spoons/Olm.spoon/lib/icons/init.lua"
local emojiPath = caseDir .. "/../../Spoons/Olm.spoon/lib/icons/sources/emoji.lua"
local rowsPath = caseDir .. "/../../Spoons/Olm.spoon/lib/icons/rows.lua"

-- A fresh engine with the emoji source alone, so no two blocks share a cache.
local function freshEngine()
  return dofile(iconsPath).new({ sources = { dofile(emojiPath).new() }, order = { "emoji" } })
end

-- The resolver the facade sits over, built on a fresh engine with a declared icons table for one
-- owner, the way the root builds it from the manifests.
local function freshResolver()
  return dofile(rowsPath).new({
    engine = freshEngine(),
    declared = function(owner)
      if owner == "demo" then return { plus = { emoji = "➕" }, bin = { emoji = "🗑️" }, fire = { emoji = "🔥" } } end
      return nil
    end,
    points = 72,
  })
end

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    if detail then
      print("FAIL " .. description .. ", " .. detail)
    else
      print("FAIL " .. description)
    end
  end
end

local function freshModule()
  local chunk, err = loadfile(modulePath)
  if not chunk then
    error("could not load Olm.spoon/lib/glyphicon.lua, " .. tostring(err))
  end
  return chunk()
end

-- An icon key answers an image, an hs.image this Hammerspoon instance actually drew.
do
  local M = freshModule()
  local instance = M.new(freshResolver())
  local img = instance.icon("plus", "demo")
  check(
    "a key the owner declared answers an hs.image",
    img ~= nil and img ~= false and type(img) == "userdata"
  )
end

-- The same key answers the same cached object twice, not two separate drawings of it.
do
  local M = freshModule()
  local instance = M.new(freshResolver())
  local first = instance.icon("bin", "demo")
  local second = instance.icon("bin", "demo")
  check(
    "the same key answers the exact same cached object on a second call",
    first ~= nil and rawequal(first, second)
  )
end

-- nil answers nil, no canvas ever drawn for a binding with no icon at all.
do
  local M = freshModule()
  local instance = M.new(freshResolver())
  check("a nil icon answers nil", instance.icon(nil) == nil)
end

-- Two instances share no cache, each drawing its own copy of the same glyph, since
-- M.new(freshResolver()) hands back an independent instance every time, the same isolation
-- lib/recency.lua and lib/registry.lua both give their own callers.
do
  local M = freshModule()
  local a = M.new(freshResolver())
  local b = M.new(freshResolver())
  local imgA = a.icon("fire", "demo")
  local imgB = b.icon("fire", "demo")
  check(
    "two independent instances never share a cached object for the same icon",
    imgA ~= nil and imgB ~= nil and not rawequal(imgA, imgB)
  )
end

-- A table spec draws as it stands, with no owner, which is how a flag or an emoji of content is
-- named. A string that is not an identifier is the emoji shorthand a person writes in config.
-- An identifier the owner never declared answers nil rather than drawing its own letters.
do
  local M = freshModule()
  local instance = M.new(freshResolver())
  check("a table spec answers an image with no owner", type(instance.icon({ emoji = "🇸🇪" })) == "userdata")
  check("a string that is not an identifier reads as an emoji", type(instance.icon("🔥", "demo")) == "userdata")
  check("an undeclared identifier answers nil", instance.icon("nothing", "demo") == nil)
end
