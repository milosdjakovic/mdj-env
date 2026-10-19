-- Unit case for Olm.spoon/plugins/vpn/contract.lua, the location shape every adapter owes.
-- The runner reaches this file with a dofile call carrying an absolute path, so this file
-- locates itself through debug.getinfo, the same way cases/windowsize-row.lua does. The contract
-- reads nothing of Hammerspoon's own, so no stand in is needed.
--
-- Each check prints one line, PASS or FAIL followed by a plain description.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/plugins/vpn/contract.lua"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local chunk, err = loadfile(modulePath)
if not chunk then
  print("FAIL load the vpn contract, " .. tostring(err))
  return
end
local contract = chunk()

local function mullvad()
  return {
    id = "al/tia", label = "Tirana, Albania", country = "Albania", countryCode = "al",
    city = "Tirana", cityCode = "tia", detail = "al tia", terms = { "tia", "al" },
  }
end

local function ivpn()
  return {
    id = "us-ca-sjc.wg.ivpn.net", label = "San Jose, CA, United States",
    countryCode = "us", cityCode = "us-ca-sjc.wg.ivpn.net",
    detail = "us-ca-sjc.wg.ivpn.net", terms = { "us-ca-sjc.wg.ivpn.net", "us" },
  }
end

check("a full Mullvad shaped location is accepted", contract.validateLocation(mullvad()) == true)
check("a full IVPN shaped location is accepted", contract.validateLocation(ivpn()) == true)

local empty = mullvad()
empty.terms = {}
check("empty terms are accepted", contract.validateLocation(empty) == true)

local noTerms = mullvad()
noTerms.terms = nil
local ok, gap = contract.validateLocation(noTerms)
check("a location missing terms is refused", ok == false, tostring(gap))
check("the gap names terms", tostring(gap):find("terms", 1, true) ~= nil, tostring(gap))

local badTerms = mullvad()
badTerms.terms = "tia"
ok, gap = contract.validateLocation(badTerms)
check("terms that is not a table is refused", ok == false, tostring(gap))

local numberTerm = mullvad()
numberTerm.terms = { "tia", 7 }
ok = contract.validateLocation(numberTerm)
check("a term that is not a string is refused", ok == false)

local numberLabel = mullvad()
numberLabel.label = 12
ok, gap = contract.validateLocation(numberLabel)
check("a number label is refused", ok == false, tostring(gap))
check("the gap names label", tostring(gap):find("label", 1, true) ~= nil, tostring(gap))

local noDetail = mullvad()
noDetail.detail = nil
ok = contract.validateLocation(noDetail)
check("a location missing detail is refused", ok == false)

local spaced = mullvad()
spaced.terms = { "new york" }
ok, gap = contract.validateLocation(spaced)
check("a term with a space is refused", ok == false, tostring(gap))

local emptyTerm = mullvad()
emptyTerm.terms = { "" }
ok = contract.validateLocation(emptyTerm)
check("an empty term is refused", ok == false)

local holey = mullvad()
holey.terms = { [1] = "tia", [3] = "al" }
ok = contract.validateLocation(holey)
check("terms that are not a sequence are refused", ok == false)

local keyed = mullvad()
keyed.terms = { "tia", name = "x" }
ok = contract.validateLocation(keyed)
check("terms with a string key are refused", ok == false)

local upper = mullvad()
upper.countryCode = "AL"
ok, gap = contract.validateLocation(upper)
check("an upper case country code is refused", ok == false, tostring(gap))

local longCode = mullvad()
longCode.countryCode = "alb"
ok = contract.validateLocation(longCode)
check("a three letter country code is refused", ok == false)

local emptyLabel = mullvad()
emptyLabel.label = ""
ok, gap = contract.validateLocation(emptyLabel)
check("an empty label is refused", ok == false, tostring(gap))

local emptyId = mullvad()
emptyId.id = ""
ok = contract.validateLocation(emptyId)
check("an empty id is refused", ok == false)

local emptyDetail = mullvad()
emptyDetail.detail = ""
ok = contract.validateLocation(emptyDetail)
check("an empty detail is accepted", ok == true)

ok = contract.validateLocation("not a table")
check("a non table location is refused", ok == false)

ok = contract.validateLocations({ mullvad(), ivpn() })
check("a good listing is accepted", ok == true)

local bad = mullvad()
bad.terms = nil
local index
ok, index, gap = contract.validateLocations({ mullvad(), ivpn(), bad, numberLabel })
check("a bad listing is refused", ok == false)
check("the first bad entry is named by its index", index == 3, tostring(index))
check("the listing gap is the entry's gap", tostring(gap):find("terms", 1, true) ~= nil, tostring(gap))

ok = contract.validateLocations({})
check("an empty listing is accepted", ok == true)
