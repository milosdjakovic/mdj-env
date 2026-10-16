-- Unit case for the layer rule scan the Olm dry gate runs, Olm.spoon/test/drygate-leaks.lua.
-- It plants every form the scan knows in strings, beside the shapes it must leave alone, so the
-- rule is proven to find a plugin name core writes and to stay quiet on the Hammerspoon api and
-- on a word core only happens to share. The rename proof, the second layer, runs inside
-- test/drygate.sh and is not driven from here.
--
-- Each check prints one line, PASS or FAIL followed by a plain description.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local scanner = dofile(caseDir .. "/../../Spoons/Olm.spoon/test/drygate-leaks.lua")

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

-- A small plugin set, two lower case identities sharing a word with the hs api, one directory
-- whose identity carries an upper case letter.
local identities = { settings = true, wifi = true, vpn = true, displayProfiles = true }
local dirs = { settings = true, wifi = true, vpn = true, displayprofiles = true }

local function forms(code)
  local out = {}
  for _, hit in ipairs(scanner.scan(code, identities, dirs)) do out[#out + 1] = hit.identity .. " as " .. hit.form end
  table.sort(out)
  return table.concat(out, "; ")
end

check("a quoted identity is found", forms('local x = modules["vpn"]\n') == "vpn as string literal")
check("a path into a plugin is found", forms('local p = "plugins/vpn/init.lua"\n') == "vpn as path into plugins")
check("a mixed case identity written as code is found", forms("local d = displayProfiles\n") == "displayProfiles as identifier")
check("a lower case field on a table is found", forms("local m = modules.wifi\n") == "wifi as field")
check("a lower case method call is found", forms("opts:vpn()\n") == "vpn as field")
check("a lower case table constructor key is found", forms("local t = { a = 1, vpn = true }\n") == "vpn as table key")
check("a string built by concatenation is found",
  forms('local x = modules["wi" .. "fi"]\n') == "wifi as string built by concatenation")
check("a path into plugins built by concatenation is found",
  forms('local p = "plug" .. "ins/v" .. "pn"\n') == "vpn as string built by concatenation into plugins")
check("string.format of literals is found",
  forms('local x = string.format("%s%s", "wi", "fi")\n') == "wifi as string built by format")
check("a format method on a literal is found",
  forms('local x = ("%sfi"):format("wi")\n') == "wifi as string built by format")
check("a plugins path finished at run time is found",
  forms('local p = root .. "plu" .. "gins/" .. name\n') == "plugins as path into plugins finished at run time")

check("the hs global's own settings is not found", forms('local v = hs.settings.get("x")\n') == "")
check("the hs global's own wifi is not found", forms("local n = hs.wifi.currentNetwork()\n") == "")
check("hs reached through another table is found", forms("local s = api.hs.settings\n") == "settings as field")
check("a bare local sharing a plugin's word is not found", forms("local settings = 1\nreturn settings\n") == "")
check("a comparison is not a table key", forms("if a == settings then end\n") == "")
check("a word inside a longer string is not found", forms('log("the wifi settings changed")\n') == "")
check("a comment is not read", forms("-- modules.vpn and \"wifi\"\nlocal x = 1\n") == "")
check("a format with a computed argument is not folded", forms('local x = string.format("%s", name)\n') == "")

local hits = scanner.scan('local t = {\n  vpn = 1,\n}\n', identities, dirs)
check("a hit carries its line number and the line's own text",
  #hits == 1 and hits[1].line == 2 and hits[1].text == "vpn = 1,")
