--- ClipboardHistory provider: Hammerspoon
---
--- The contract face over our own clipboard manager, the mechanism in manager/.
--- It reads like the Raycast and Spotlight adapters, a thin table satisfying the
--- provider contract, except its backend is our in-process manager rather than an
--- external app, so it is always available.
---
--- This file is a factory. The composition root loads the manager mechanism and
--- passes it in, and this returns the provider face whose show and isShowing just
--- delegate to the mechanism's API. start and clear are re-exposed on the same
--- table so the root can drive the lifecycle through this one handle, keeping the
--- mechanism itself ignorant of the contract.
return function(manager)
  return {
    name = "Hammerspoon",
    -- Opens its own chooser, not a swallowed keystroke, so fire while Hyper is
    -- still held (same as Raycast). This is what lets a second tap toggle.
    deferUntilHyperRelease = false,
    available = function()
      return true -- a pure-Lua backend has nothing external to be missing
    end,
    isShowing = function()
      return manager.isShowing()
    end,
    -- Toggle, like the Raycast provider. Firing while Hyper is still held (see
    -- deferUntilHyperRelease above) is what lets a second Hyper+X close the
    -- chooser this same press opened.
    show = function()
      if manager.isShowing() then
        manager.hide()
      else
        manager.show()
      end
    end,
    -- Lifecycle passthrough for the composition root.
    start = manager.start,
    clear = manager.clear,
  }
end
