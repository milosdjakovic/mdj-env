--- Capture provider contract.
---
--- The interface every provider must satisfy. This is the one named place that
--- declares what a provider is, so a new backend author reads this file and
--- nothing else to know the shape. It is a runtime checklist, not a base class,
--- Lua has no interfaces, so a provider conforms by carrying these methods, not
--- by inheriting anything. The engine calls validate() at load to drop anything
--- that does not conform.
---
--- A provider is a plain table with an optional `name` and these methods.
---   available(self, deps) -> boolean[, reason]
---       Is this backend usable right now. Checked LIVE on every dispatch, since
---       an app can be quit or reconfigured after load. Return false plus a short
---       reason string on failure, which the engine logs so you can see why it
---       stepped aside. `deps` is the per consumer dependency adapter the engine was
---       given, so a provider backed by an external tool asks it by the name this
---       spoon declared rather than probing, and a provider that needs nothing
---       outside Hammerspoon ignores the argument. A reason names what is wrong and
---       never how to install anything, since a provider knows no installer.
---   supports(self, action) -> boolean
---       Does this backend implement this action.
---   trigger(self, action) -> boolean
---       Run the action. Return false to fall through to the next provider;
---       nil or true means handled and stops the chain.

local M = {}

M.requiredMethods = { "available", "supports", "trigger" }

--- contract.validate(provider) -> ok, missing
--- Return true when the provider is a table carrying every required method, or false
--- and the name of the first gap (or "not a table"). Never throws; the engine drops a
--- non-conforming provider and logs.
function M.validate(provider)
  if type(provider) ~= "table" then return false, "not a table" end
  for _, method in ipairs(M.requiredMethods) do
    if type(provider[method]) ~= "function" then
      return false, method
    end
  end
  return true
end

return M
