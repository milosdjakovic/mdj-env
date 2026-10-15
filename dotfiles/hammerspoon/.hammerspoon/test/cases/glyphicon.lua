-- Unit case for Olm.spoon/lib/glyphicon.lua, the glyph to icon facade lifted out of
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

-- A fresh engine with the emoji source alone, so no two blocks share a cache.
local function freshEngine()
  return dofile(iconsPath).new({ sources = { dofile(emojiPath).new() }, order = { "emoji" } })
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

-- A glyph answers an image, an hs.image this Hammerspoon instance actually drew.
do
  local M = freshModule()
  local instance = M.new(freshEngine())
  local img = instance.icon("➕")
  check(
    "a glyph answers an hs.image",
    img ~= nil and img ~= false and type(img) == "userdata"
  )
end

-- The same glyph answers the same cached object twice, not two separate drawings of it.
do
  local M = freshModule()
  local instance = M.new(freshEngine())
  local first = instance.icon("🗑️")
  local second = instance.icon("🗑️")
  check(
    "the same glyph answers the exact same cached object on a second call",
    first ~= nil and rawequal(first, second)
  )
end

-- nil answers nil, no canvas ever drawn for a binding with no glyph at all.
do
  local M = freshModule()
  local instance = M.new(freshEngine())
  check("a nil glyph answers nil", instance.icon(nil) == nil)
end

-- Two instances share no cache, each drawing its own copy of the same glyph, since
-- M.new(freshEngine()) hands back an independent instance every time, the same isolation
-- lib/recency.lua and lib/registry.lua both give their own callers.
do
  local M = freshModule()
  local a = M.new(freshEngine())
  local b = M.new(freshEngine())
  local imgA = a.icon("🔥")
  local imgB = b.icon("🔥")
  check(
    "two independent instances never share a cached object for the same glyph",
    imgA ~= nil and imgB ~= nil and not rawequal(imgA, imgB)
  )
end
