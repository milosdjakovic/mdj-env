-- Unit case for the typography scan the Olm dry gate runs, Olm.spoon/test/drygate-typography.lua.
-- It plants a violation and an exempted line in strings, so the rule is proven to find drift
-- and to accept an icon that declares itself, without touching the tree.
--
-- Each check prints one line, PASS or FAIL followed by a plain description.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local scanner = dofile(caseDir .. "/../../Spoons/Olm.spoon/test/drygate-typography.lua")

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local function count(hits, wanted)
  local n = 0
  for _, h in ipairs(hits) do
    if wanted == "exempt" and h.exempt then n = n + 1 end
    if wanted == "found" and not h.exempt then n = n + 1 end
  end
  return n
end

local planted = scanner.scan('local el = { type = "text", textSize = 18 }\n')
check("a hand set textSize is found", count(planted, "found") == 1)

check("a literal system font name is found", count(scanner.scan('local f = ".AppleSystemUIFont"\n'), "found") == 1)
check("a hand built font table is found",
  count(scanner.scan('local s = hs.styledtext.new("x", { font = { name = "Menlo", size = 12 } })\n'), "found") == 1)
check("a line height field is found", count(scanner.scan("p.minimumLineHeight = lh\n"), "found") == 1)

check("a size handed over by a variable is not found",
  #scanner.scan("c[1] = { textSize = layout.textSize, textFont = layout.font }\n") == 0)
check("a font table built from handed over values is not found",
  #scanner.scan("local s = { font = { name = font, size = size } }\n") == 0)

check("a comment line never counts", #scanner.scan("-- textSize = 18 and Menlo and minimumLineHeight\n") == 0)
check("a trailing comment never counts", #scanner.scan("local x = 1 -- textSize = 18\n") == 0)
check("a sentence that starts with a font name word inside a longer string is not found",
  #scanner.scan('local m = "Georgia is where this was filed, and more"\n') == 0)

local above = scanner.scan("-- type-exempt, a glyph drawn into an icon image\nlocal el = { textSize = 21 }\n")
check("an exemption on the line above is accepted with its reason",
  count(above, "exempt") == 1 and count(above, "found") == 0 and above[1].exempt:find("glyph", 1, true) ~= nil)

local same = scanner.scan("local el = { textSize = 21 } -- type-exempt, a glyph drawn into an icon image\n")
check("an exemption on the same line is accepted", count(same, "exempt") == 1)

local bare = scanner.scan("-- type-exempt\nlocal el = { textSize = 21 }\n")
check("an exemption with no reason is still a finding", count(bare, "found") == 1 and count(bare, "exempt") == 0)

local far = scanner.scan("-- type-exempt, a glyph\nlocal other = 1\nlocal el = { textSize = 21 }\n")
check("an exemption two lines above covers nothing", count(far, "found") == 1)
