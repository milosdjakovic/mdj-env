--- The VPN provider contract. The engine calls only these methods and names no
--- backend, so adding a provider is a new file in providers plus one line in
--- init.lua. It is added now because the engine is a real consumer, not up front. In
--- a dynamic language a contract is a documented set of required methods plus a
--- validation step, not a compiled interface, so validate checks the shape once at
--- load. It returns (ok, missing) rather than throwing, a soft shape the composition root
--- in init.lua acts on to decide what a gap means. There a gap is a hard load time failure,
--- since a provider that cannot answer the five required methods is not a backend this
--- engine can drive at all.
---
--- The methods a provider must implement.
---   available()                     returns whether the backend is installed, checked
---                                   once at load.
---   status()                        returns a plain table read now, { state, country,
---                                   city, hostname }. state is connected, connecting,
---                                   disconnected, disconnecting, or unavailable when
---                                   the daemon does not answer. Fast, so synchronous.
---   connect(target, cb)             bring the tunnel up at target, then cb(ok, err) on the
---                                   main thread. target is { countryCode, cityCode } off an
---                                   entry this same provider produced, so a provider is
---                                   free to put whatever identifies a location in its own
---                                   vocabulary there and read it back here, cityCode being
---                                   absent for a country only target. A nil target means go
---                                   wherever this backend would go on its own, which is the
---                                   only thing left for a backend whose caller has never
---                                   named a place.
---   disconnect(cb)                  take the tunnel down, then cb(ok, err).
---   listLocations(cb)               fetch the relays and call cb(list), each entry
---                                   { id, label, countryCode, cityCode } required, and
---                                   { country, city, detail } optional. detail is the
---                                   row's own subtitle text when the provider wants to
---                                   describe a location in its own terms rather than let
---                                   the caller assume every backend spells one the same way.
---
--- Optional methods, each probed for by name before it is called, so a provider that has
--- no honest answer simply omits it and the caller degrades.
---   selectedLocation()              the relay this backend would use for a nil target, read
---                                   now from whatever it persists, { countryCode, cityCode }
---                                   with cityCode nil for a country only constraint, or nil
---                                   when nothing is set. Fast, so synchronous.
---   statusAsync(cb)                 status read off the main thread.
---   selectedLocationAsync(cb)       selectedLocation read off the main thread.
---
--- connect takes the target rather than a separate setLocation setting it first, and that
--- is what makes the two backends answer the same question the same way. Where a connect is
--- going is now something the caller states rather than something it has to read back, so a
--- row can promise a place before it is pressed and then hand that exact place to the action
--- it named. A backend that persists a selection of its own still says so through
--- selectedLocation, which is the caller's preferred source when it has one, but nothing
--- depends on a backend having one any more.
---
--- selectedLocation used to be required and is not any more, and that change is what a
--- second backend bought. Mullvad holds a persistent location constraint that can be read
--- while the tunnel is down, so it can say where a connect would go. IVPN holds no such
--- thing and exposes no reader for one, its own answer living in a root owned settings file
--- this layer may not read. A method only one backend can answer is not a contract, it is an
--- interface extracted from a single implementation, so requiring it would force every
--- future provider to invent an answer it does not have. What stayed required is the five
--- things every VPN genuinely has, whether it is installed, what it is doing, go to a place,
--- come back down, and list the places.
---
--- A provider may also carry optional metadata beside these methods, which the control
--- surface renders and validate does not require. name is the human backend name. install
--- is { note } naming what provides the backend when available() is false, so the surface
--- can explain the gap without learning the concrete tool or the platform.

local M = {}

M.requiredMethods = { "available", "status", "connect", "disconnect", "listLocations" }

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
