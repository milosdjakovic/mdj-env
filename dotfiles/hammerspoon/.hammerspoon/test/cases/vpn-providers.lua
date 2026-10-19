-- Unit case for the two VPN providers' relay parsers, which are local functions and so are
-- driven through listLocations over a stand in hs.task that answers a fixed CLI output. The
-- case loads each provider from this checkout, hands it a path through configure, and checks
-- every listed location against the contract and the terms each adapter declares. No absolute
-- path is written down here.
--
-- Each check prints one line, PASS or FAIL followed by a plain description.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local vpnDir = caseDir .. "/../../Spoons/Olm.spoon/plugins/vpn/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local contractChunk, contractErr = loadfile(vpnDir .. "contract.lua")
if not contractChunk then
  print("FAIL load the vpn contract, " .. tostring(contractErr))
  return
end
local contract = contractChunk()

-- Load a provider with hs standing in, then put the real hs back. The task stand in runs its
-- callback at once with the output it was given.
local function listed(file, output)
  local realHs = hs
  hs = {
    logger = { new = function()
      return setmetatable({}, { __index = function() return function() end end })
    end },
    task = { new = function(_, cb)
      return { start = function() cb(0, output, "") return true end }
    end },
  }
  local chunk, err = loadfile(vpnDir .. file)
  if not chunk then
    hs = realHs
    print("FAIL load " .. file .. ", " .. tostring(err))
    return nil
  end
  local provider = chunk()
  provider.configure({ path = "stand-in" })
  local result
  provider.listLocations(function(list) result = list end)
  hs = realHs
  return result
end

local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

local relays = "Albania (al)\n\tTirana (tia) @ 41.32795°N, 19.81902°W\n\t\tal-tia-wg-001 (1.2.3.4) - WireGuard\nSweden (se)\n\tStockholm (sto) @ 59.32°N, 18.06°E\n"
local mullvad = listed("providers/mullvad.lua", relays)
if mullvad then
  check("mullvad lists both cities", #mullvad == 2, tostring(#mullvad))
  local ok, index, gap = contract.validateLocations(mullvad)
  check("every mullvad location passes the contract", ok == true, tostring(index) .. " " .. tostring(gap))
  local tirana = mullvad[1] or {}
  check("mullvad terms are the city code then the country code",
    type(tirana.terms) == "table" and same(tirana.terms, { "tia", "al" }))
  check("mullvad detail is the country and city code", tirana.detail == "al tia", tostring(tirana.detail))
  check("mullvad label is the city and country", tirana.label == "Tirana, Albania", tostring(tirana.label))
end

local servers = table.concat({
  " WireGuard| us-ca-sjc.wg.ivpn.net|         San Jose, CA (US)|   United States|           Tzulo|   IPv4/IPv6|",
  " OpenVPN| us-ca-sjc.gw.ivpn.net|         San Jose, CA (US)|   United States|           Tzulo|   IPv4|",
  " WireGuard| se-sto.wg.ivpn.net|         Stockholm (SE)|   Sweden|           Datapacket|   IPv4/IPv6|",
}, "\n") .. "\n"
local ivpn = listed("providers/ivpn.lua", servers)
if ivpn then
  check("ivpn lists the two WireGuard servers", #ivpn == 2, tostring(#ivpn))
  local ok, index, gap = contract.validateLocations(ivpn)
  check("every ivpn location passes the contract", ok == true, tostring(index) .. " " .. tostring(gap))
  local sjc = ivpn[1] or {}
  check("ivpn terms are the host's first label then the country code",
    type(sjc.terms) == "table" and same(sjc.terms, { "us-ca-sjc", "us" }))
  local dotted = false
  for _, list in ipairs({ mullvad or {}, ivpn }) do
    for _, loc in ipairs(list) do
      for _, term in ipairs(loc.terms or {}) do
        if term:find(".", 1, true) then dotted = true end
      end
    end
  end
  check("no term of either provider contains a dot", dotted == false)
  check("ivpn detail is the gateway host", sjc.detail == "us-ca-sjc.wg.ivpn.net", tostring(sjc.detail))
  check("ivpn city code is the gateway host", sjc.cityCode == "us-ca-sjc.wg.ivpn.net", tostring(sjc.cityCode))
end
