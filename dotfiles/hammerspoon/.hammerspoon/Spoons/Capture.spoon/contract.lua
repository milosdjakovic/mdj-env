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
---   available(self) -> boolean[, reason]
---       Is this backend usable right now. Checked LIVE on every dispatch, since
---       an app can be quit or reconfigured after load. Return false plus a short
---       reason string on failure, which the engine logs so you can see why it
---       stepped aside.
---   supports(self, action) -> boolean
---       Does this backend implement this action.
---   trigger(self, action) -> boolean
---       Run the action. Return false to fall through to the next provider;
---       nil or true means handled and stops the chain.

local M = {}

M.requiredMethods = { "available", "supports", "trigger" }

--- contract.validate(provider) -> ok, missingMethod
--- Return true when the provider carries every required method, or false and the
--- name of the first missing one.
function M.validate(provider)
  for _, method in ipairs(M.requiredMethods) do
    if type(provider[method]) ~= "function" then
      return false, method
    end
  end
  return true
end

return M
