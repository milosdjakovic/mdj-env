--- The VPN provider contract. The engine calls only these methods and names no
--- backend, so adding a provider is a new file in providers plus one line in
--- init.lua. It is added now because the engine is a real consumer, not up front. In
--- a dynamic language a contract is a documented set of required methods plus a
--- validation step, not a compiled interface, so validate checks the shape once at
--- load and fails loudly on a gap rather than at the first missing call.
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

M.methods = { "available", "status", "connect", "disconnect", "setLocation", "listLocations", "selectedLocation" }

function M.validate(provider)
  assert(type(provider) == "table", "vpn provider must be a table")
  for _, name in ipairs(M.methods) do
    assert(type(provider[name]) == "function", "vpn provider missing method " .. name)
  end
  return provider
end

return M
