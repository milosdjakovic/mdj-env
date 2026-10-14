-- Unit case for the type roles, title, body, caption, section and code, the typography file
-- that sets their fonts and sizes, and the fallbacks for every way that file can be wrong.
-- Plain Lua with the appearance and the file read stubbed, so no hs is needed. The runner
-- reaches this file with a dofile call, so it locates itself through debug.getinfo.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local uiDir = caseDir .. "/../../Spoons/Olm.spoon/lib/ui/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local function fresh(name)
  local chunk, err = loadfile(uiDir .. name)
  if not chunk then error("could not load lib/ui/" .. name .. ", " .. tostring(err)) end
  return chunk()
end

local styleLib = fresh("style.lua")
local kit = fresh("kit.lua").new(styleLib.names)

-- theme-exempt, fixture colours for a unit case, not a tool's look
local SPEC = {
  colors = {
    dark = { foreground = "#111111", subtext = "#333333", background = "#444444" },
  },
}

local function tokensFor(typography)
  local s = styleLib.new({ appearance = function() return "Dark" end })
  s.configure({ colors = SPEC.colors, typography = typography })
  return s.tokens()
end

local function warnings()
  local list = {}
  return list, { w = function(message) list[#list + 1] = message end }
end

local function loaded(text)
  local list, log = warnings()
  local result = styleLib.loadTypography("typography.toml", function() return text end, log)
  return result, list
end

local function mentions(list, word)
  for _, message in ipairs(list) do
    if message:find(word, 1, true) then return true end
  end
  return false
end

--------------------------------------------------------------------------------
-- roles, derived
--------------------------------------------------------------------------------

do
  local t = tokensFor()
  local sizes = { title = 20, body = 16, caption = 14, section = 12, code = 14 }
  local ok = true
  for role, size in pairs(sizes) do
    if t.text[role].size ~= size then ok = false end
  end
  check("the shipped sizes are 20, 16, 14, 12 and 14", ok)
  check("code is the mono font and the other four the ui font",
    t.text.code.font == ".AppleSystemUIFontMonospaced" and t.text.title.font == ".AppleSystemUIFont"
      and t.text.body.font == ".AppleSystemUIFont" and t.text.caption.font == ".AppleSystemUIFont"
      and t.text.section.font == ".AppleSystemUIFont")
  check("line height is ceil of size times 1.35 for every role",
    t.text.title.lineHeight == 27 and t.text.body.lineHeight == 22 and t.text.caption.lineHeight == 19
      and t.text.section.lineHeight == 17 and t.text.code.lineHeight == 19)
  check("title, body and code take foreground, caption and section subtext",
    t.text.title.color == "foreground" and t.text.body.color == "foreground"
      and t.text.code.color == "foreground" and t.text.caption.color == "subtext"
      and t.text.section.color == "subtext")
  check("the role colours resolve from the theme",
    t.colors.foreground.red ~= nil and math.abs(t.colors.subtext.red - 0x33 / 255) < 0.001)
  check("roles lists the five names in order",
    #styleLib.roles == 5 and styleLib.roles[1] == "title" and styleLib.roles[5] == "code"
      and kit.roles == styleLib.roles)
  check("every role is a name a text node accepts",
    pcall(function() for _, role in ipairs(kit.roles) do kit.text("x", role) end end))
  check("a text node may still pass a colour role to override",
    kit.text("x", "section", { color = "primary" }).color == "primary")
  local retired = {}
  for _, name in ipairs({ "sub", "label", "heading", "mono", "big", "hintKey", "hintLabel",
                          "cheat", "cheatTitle", "toast", "report", "reportDetail", "empty" }) do
    if t.text[name] ~= nil then retired[#retired + 1] = name end
  end
  local count = 0
  for _ in pairs(t.text) do count = count + 1 end
  check("the retired variants are gone and the five roles are all there is",
    #retired == 0 and count == 5, "still resolving " .. table.concat(retired, ",") .. ", " .. count .. " entries")
  check("a text variant outside the five roles is refused by the kit",
    not pcall(kit.text, "x", "heading") and not pcall(kit.text, "x", "toast"))
end

--------------------------------------------------------------------------------
-- the override
--------------------------------------------------------------------------------

do
  local t = tokensFor({ fonts = { ui = "Helvetica", mono = "Courier" },
                        sizes = { title = 30, code = 10 } })
  check("a typography table overrides the fonts", t.text.title.font == "Helvetica"
    and t.text.code.font == "Courier")
  check("a typography table overrides sizes and the line height follows",
    t.text.title.size == 30 and t.text.title.lineHeight == 41 and t.text.code.size == 10
      and t.text.code.lineHeight == 14)
  check("a size it leaves out keeps the shipped one", t.text.body.size == 16)
end

--------------------------------------------------------------------------------
-- the file and its fallbacks
--------------------------------------------------------------------------------

local VALID = [[
# a comment
[fonts]
ui   = "Helvetica"
mono = "Courier"

[sizes]
title   = 30
body    = 17
caption = 15
section = 13
code    = 11
]]

do
  local result, list = loaded(VALID)
  check("a valid file loads every key with no warning",
    result.fonts.ui == "Helvetica" and result.fonts.mono == "Courier" and result.sizes.title == 30
      and result.sizes.code == 11 and #list == 0, #list > 0 and list[1] or nil)
end

do
  local list, log = warnings()
  local result = styleLib.loadTypography("typography.toml", function() return nil end, log)
  check("a missing file is one warning and no override",
    #list == 1 and next(result.fonts) == nil and next(result.sizes) == nil
      and list[1]:find("typography.toml", 1, true) ~= nil)
end

do
  local result, list = loaded('[fonts]\nui = "Helvetica"\n[sizes]\ntitle = 30\nbody = 17\ncaption = 15\nsection = 13\ncode = 11\n')
  check("a missing key is one warning naming it and keeps the shipped value",
    #list == 1 and mentions(list, "fonts.mono") and result.fonts.mono == nil and result.fonts.ui == "Helvetica")
end

do
  local result, list = loaded(VALID .. "extra = 5\n")
  check("a key outside a section is a warning", #list == 1 and mentions(list, "extra"), tostring(list[1]))
  local result2, list2 = loaded(VALID:gsub("code    = 11", "code    = 11\nhuge = 40"))
  check("an unknown key is one warning naming it and is ignored",
    #list2 == 1 and mentions(list2, "sizes.huge") and result2.sizes.huge == nil)
end

do
  local result, list = loaded((VALID:gsub("title   = 30", "title   = 0")))
  check("a size of zero falls back with one warning naming the key",
    #list == 1 and mentions(list, "sizes.title") and result.sizes.title == nil)
  local result2, list2 = loaded((VALID:gsub("body    = 17", "body    = -4")))
  check("a negative size falls back with one warning naming the key",
    #list2 == 1 and mentions(list2, "sizes.body") and result2.sizes.body == nil)
  local result3, list3 = loaded((VALID:gsub("caption = 15", 'caption = "big"')))
  check("a size that is not a number falls back with one warning naming the key",
    #list3 == 1 and mentions(list3, "sizes.caption") and result3.sizes.caption == nil)
  local result4, list4 = loaded((VALID:gsub('ui   = "Helvetica"', "ui   = 12")))
  check("a font that is not a string falls back with one warning naming the key",
    #list4 == 1 and mentions(list4, "fonts.ui") and result4.fonts.ui == nil)
  local result5, list5 = loaded((VALID:gsub('mono = "Courier"', 'mono = ""')))
  check("an empty font name falls back with one warning naming the key",
    #list5 == 1 and mentions(list5, "fonts.mono") and result5.fonts.mono == nil)
end

do
  local result, list = loaded("[sizes]\ntitle = 1.5\n")
  check("a line the reader refuses is one warning and the shipped values",
    #list == 1 and next(result.sizes) == nil)
  local _, list2 = loaded(VALID .. "[colors]\nx = \"y\"\n")
  check("an unknown section is one warning", #list2 == 1 and mentions(list2, "colors"))
  local list3, log3 = warnings()
  local result3 = styleLib.loadTypography(nil, nil, log3)
  check("no path is the shipped values with no warning", #list3 == 0 and next(result3.sizes) == nil)
end

do
  local result = loaded(VALID:gsub("title   = 30", "title   = 0"))
  local t = tokensFor(result)
  check("a fallback reaches the tokens as the shipped size", t.text.title.size == 20
    and t.text.body.size == 17)
end
