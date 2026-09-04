--- The VPN provider contract. The engine calls only these methods and names no
--- backend, so adding a provider is a new file in providers plus one line in
--- init.lua. It is added now because the engine is a real consumer, not up front. In
--- a dynamic language a contract is a documented set of required methods plus a
--- validation step, not a compiled interface, so validate checks the shape once at
--- load. It returns (ok, gap) rather than throwing, a soft shape the composition root
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

-- How many arguments a required method must accept, for the ones that take any. A name absent
-- from this table takes none and is checked for existence alone.
--
-- Arity is checked because existence alone let the one mistake that matters through silently.
-- connect used to take the callback first, and a provider still written that way, or a new one
-- copied from an older example, declares connect(cb) and passes every existence check there is.
-- Nothing then goes wrong loudly. The caller hands it a target and a callback, the provider
-- reads the target as its callback, and a connect either aims at a callback or calls a place,
-- with no error and nothing in the console. The same silence applies to a callback taking method
-- declared with no parameters at all, which simply never reports and leaves the status line
-- standing on whatever it last read.
--
-- This is what a contract can actually enforce in a dynamic language, the shape of the call
-- rather than the meaning of it. It cannot prove a provider HONOURS the target it accepts, only
-- that it accepts one, so a provider that takes the argument and ignores it is still possible
-- and is a defect no load time check will find. What is checkable is checked, and the gap is
-- named here rather than left to be discovered.
M.requiredArity = {
  connect = 2,        -- target, cb
  disconnect = 1,     -- cb
  listLocations = 1,  -- cb
}

--- contract.validate(provider) -> ok, gap
--- Return true when the provider is a table carrying every required method at the arity that
--- method is stated to take, or false and one phrase naming the first gap, written to read as
--- the tail of a sentence the caller opens. Never throws, so the caller owns the failure policy.
---
--- A variadic method is accepted whatever it declares, since a provider forwarding its
--- arguments cannot state a count, and a method declaring MORE parameters than required is
--- accepted too, since ignoring a trailing argument is that provider's own business. Only
--- declaring too few is refused, which is the one shape that reads a caller's arguments in the
--- wrong slots.
function M.validate(provider)
  if type(provider) ~= "table" then return false, "the provider is not a table" end
  for _, name in ipairs(M.requiredMethods) do
    local fn = provider[name]
    if type(fn) ~= "function" then
      return false, name .. "() is missing"
    end
    local wanted = M.requiredArity[name]
    if wanted then
      local info = debug.getinfo(fn, "u")
      if info and not info.isvararg and (info.nparams or 0) < wanted then
        return false, string.format("%s() must accept %d argument(s) and declares %d",
                                    name, wanted, info.nparams or 0)
      end
    end
  end
  return true
end

return M
