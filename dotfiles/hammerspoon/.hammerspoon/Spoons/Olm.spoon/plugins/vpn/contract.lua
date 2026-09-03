--- The VPN provider contract. The engine calls only these methods and names no
--- backend, so adding a provider is a new file in providers plus one line in
--- init.lua. It is added now because the engine is a real consumer, not up front. In
--- a dynamic language a contract is a documented set of required methods plus a
--- validation step, not a compiled interface, so validate checks the shape once at
--- load. It returns (ok, missing) rather than throwing, a soft shape the composition root
--- in init.lua acts on to decide what a gap means. There a gap is a hard load time failure,
--- since a provider that cannot answer the six required methods is not a backend this
--- engine can drive at all.
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
---                                   The two arguments are the countryCode and cityCode off
---                                   an entry this same provider produced, so a provider is
---                                   free to put whatever identifies a location in its own
---                                   vocabulary there and read it back here.
---   listLocations(cb)               fetch the relays and call cb(list), each entry
---                                   { id, label, countryCode, cityCode } required, and
---                                   { country, city, detail } optional. detail is the
---                                   row's own subtitle text when the provider wants to
---                                   describe a location in its own terms rather than let
---                                   the caller assume every backend spells one the same way.
---
--- Optional methods, each probed for by name before it is called, so a provider that has
--- no honest answer simply omits it and the caller degrades.
---   selectedLocation()              the relay the tunnel would use on connect, read now
---                                   from the location constraint, { countryCode, cityCode }
---                                   with cityCode nil for a country only constraint, or nil
---                                   when nothing is set. Fast, so synchronous.
---   statusAsync(cb)                 status read off the main thread.
---   selectedLocationAsync(cb)       selectedLocation read off the main thread.
---
--- selectedLocation used to be required and is not any more, and that change is what a
--- second backend bought. Mullvad holds a persistent location constraint that can be read
--- while the tunnel is down, so it can say where a connect would go. IVPN holds no such
--- thing and exposes no reader for one. A method only one backend can answer is not a
--- contract, it is an interface extracted from a single implementation, so requiring it
--- would force every future provider to invent an answer it does not have. What stayed
--- required is the six things every VPN genuinely has, whether it is installed, what it is
--- doing, connect, disconnect, go to a place, and list the places.
---
--- A provider may also carry optional metadata beside these methods, which the control
--- surface renders and validate does not require. name is the human backend name. install
--- is { note } naming what provides the backend when available() is false, so the surface
--- can explain the gap without learning the concrete tool or the platform.

local M = {}

M.requiredMethods = { "available", "status", "connect", "disconnect", "setLocation", "listLocations" }

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
