--- The VPN provider contract. The engine calls only these methods and names no
--- backend, so adding a provider is a new file in providers plus one line in
--- init.lua. It is added now because the engine is a real consumer, not up front. In
--- a dynamic language a contract is a documented set of required methods plus a
--- validation step, not a compiled interface, so validate checks the shape once at
--- load. It returns (ok, missing) rather than throwing, the same soft shape Capture's
--- contract uses, and the composition root in init.lua decides what a gap means. There
--- it is a hard load-time failure, since the single provider is not optional.
---
--- The methods a provider must implement.
---   available()                     returns whether the backend is installed, checked
---                                   once at load.
---   status()                        returns a plain table read now, { state, country,
---                                   city, hostname }. state is connected, connecting,
---                                   disconnected, disconnecting, or unavailable when
---                                   the daemon does not answer. Fast, so synchronous.
---   connect(cb), disconnect(cb)     run the action off the main thread and call
---                                   cb(ok, err) on the main thread when it lands.
---   setLocation(country, city, cb)  select that relay and connect to it, then cb(ok, err).
---   listLocations(cb)               fetch the relays and call cb(list), each entry
---                                   { id, label, country, countryCode, city, cityCode }.
---   selectedLocation()              the relay the tunnel would use on connect, read now
---                                   from the location constraint, { countryCode, cityCode }
---                                   with cityCode nil for a country only constraint, or nil
---                                   when nothing is set. Fast, so synchronous.

local M = {}

M.requiredMethods = { "available", "status", "connect", "disconnect", "setLocation", "listLocations", "selectedLocation" }

--- contract.validate(provider) -> ok, missing
--- Return true when the provider is a table carrying every required method, or false
--- and the name of the first gap (or "not a table"). Never throws, so the caller owns
--- the failure policy.
function M.validate(provider)
  if type(provider) ~= "table" then return false, "not a table" end
  for _, name in ipairs(M.requiredMethods) do
    if type(provider[name]) ~= "function" then
      return false, name
    end
  end
  return true
end

return M
