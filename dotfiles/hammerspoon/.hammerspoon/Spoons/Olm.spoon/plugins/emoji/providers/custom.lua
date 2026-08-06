--- === Emoji.custom backend ===
---
--- A backend whose behavior is fully injected, so any external picker becomes an emoji
--- backend with no file of its own. This is the Strategy pattern with the strategy passed
--- in as a callback, the same command as data idea the rows use. Raycast through its deep
--- link, Alfred through a workflow trigger, a remapped key, a shell command, or a remote
--- trigger all fit here, since show just runs whatever you hand it.
---
--- This file returns a factory, not a backend. The composition root calls it with the
--- behavior to run and gets back a backend honoring the same contract as the others,
--- isAvailable, configure, show, isShowing, and surface.
---
--- Two shapes are accepted. A bare function is the trigger run on show,
---   providers.custom(function() hs.urlevent.openURL("raycast://...") end)
--- and a table describes the backend more fully,
---   providers.custom({
---     name = "alfred",
---     isAvailable = function() return hs.application.pathForBundleID("com.runningwithcrocodiles.alfred") ~= nil end,
---     show = function() hs.eventtap.keyStroke({ "alt" }, "space") end,
---   })
--- so a backend that should be skipped when its app is missing can say so, and the facade
--- logs the fall through to the next backend in the priority order.

-- A navigation surface that reports itself closed and does nothing, since an injected
-- external picker drives its own keys and must stay out of the shared navigation registry.
local NOOP_SURFACE = {
  isShowing = function() return false end,
  selectNext = function() end,
  selectPrev = function() end,
  insertSelected = function() end,
  hide = function() end,
}

return function(spec)
  -- Accept a bare trigger function or a table describing the backend.
  if type(spec) == "function" then spec = { show = spec } end
  spec = spec or {}
  local trigger = spec.show or spec.trigger or function() end

  local p = { name = spec.name or "custom" }

  -- Available unless the spec gives a predicate that says otherwise, which is how a
  -- backend fronting an app that may be absent declines and lets the facade fall through.
  function p:isAvailable()
    if type(spec.isAvailable) == "function" then return spec.isAvailable() end
    return true
  end

  -- Nothing shared to wire, the injected trigger is the whole behavior.
  function p:configure(_)
    return self
  end

  -- Run the injected trigger.
  function p:show()
    trigger()
  end

  -- Opaque by default, so it stays out of the navigation registry, unless the spec can
  -- report the external picker's open state.
  function p:isShowing()
    if type(spec.isShowing) == "function" then return spec.isShowing() end
    return false
  end

  function p:surface()
    return NOOP_SURFACE
  end

  return p
end
