--- The picker provider contract. lib/chooser/init.lua is the facade and names the concrete
--- provider, host/stage/init.lua and host/actionpanel/init.lua are the engine and know only
--- this contract, so a second provider is a new file plus one branch in the facade and no
--- consumer changes. Full reasoning lives in docs/CONTRACT-PICKER.md, read that first, this
--- file only encodes what it already decided.
---
--- Lua has no compiled interface, so this is a documented set of required method names with
--- their arities and a validate(instance) answering ok plus a reason, matching the shape
--- commit 3c8ad9d gave the VPN provider contract at plugins/vpn/contract.lua. What validation
--- proves is presence and declared arity. What it cannot prove is that a method HONOURS its
--- meaning, so the semantics documented in docs/CONTRACT-PICKER.md are the part a person has
--- to read and a reviewer has to check.
---
--- Arity here counts arguments and excludes the implicit self, since every method is called
--- as instance:name(args), which Lua desugars to instance.name(instance, args). A validator
--- reading debug.getinfo(fn, "u").nparams sees self as the function's own first declared
--- parameter, so it compares nparams against the stated arity plus one.
---
--- The rules. A missing method is refused. A method that is not a function is refused. A
--- variadic method is accepted whatever it declares, since a provider forwarding its
--- arguments cannot state a count. A method declaring more parameters than required is
--- accepted, since ignoring a trailing argument is that provider's own business. Only
--- declaring too few is refused, since that is the one shape that reads a caller's
--- arguments in the wrong slots. A refusal reads as a phrase naming the method and what it
--- declares rather than a bare name, so a reader learns what is wrong and not only where.

local M = {}

-- Twenty five names, every one of them required. Zero means the method takes no argument
-- beyond self.
M.requiredMethods = {
  "show", "hide", "isShowing", "isActive",
  "refresh", "query", "setQuery", "setPlaceholder", "setRows", "rowCount",
  "selectNext", "selectPrev", "selectRow", "selectedRow", "selectedItem", "insertSelected",
  "textBudget", "textWidth",
  "reposition", "settleDelay",
  "matcher", "setMatcher", "titleLineBreak", "setTitleLineBreak", "setPaneWidth",
}

-- The stated arity for every required method, excluding self, from docs/CONTRACT-PICKER.md's
-- own "The methods" section. Read alongside requiredMethods above rather than in place of it,
-- since every name is required regardless of how many arguments it takes.
M.requiredArity = {
  show = 0, hide = 0, isShowing = 0, isActive = 0,
  refresh = 1, query = 0, setQuery = 1, setPlaceholder = 1, setRows = 1, rowCount = 0,
  selectNext = 0, selectPrev = 0, selectRow = 1, selectedRow = 0, selectedItem = 0,
  insertSelected = 0,
  textBudget = 0, textWidth = 2,
  reposition = 1, settleDelay = 0,
  matcher = 0, setMatcher = 1, titleLineBreak = 0, setTitleLineBreak = 1, setPaneWidth = 1,
}

--- M.validate(instance) -> ok, reason
--- Answers true when instance carries every required method at the arity that method is
--- stated to take, or false and one phrase naming the first gap, written to read as the tail
--- of a sentence the caller opens. Never throws, so the caller owns the failure policy.
function M.validate(instance)
  if type(instance) ~= "table" then return false, "the instance is not a table" end
  for _, name in ipairs(M.requiredMethods) do
    local fn = instance[name]
    if fn == nil then
      return false, name .. "() is missing"
    end
    if type(fn) ~= "function" then
      return false, name .. "() is not a function"
    end
    local wanted = M.requiredArity[name]
    local info = debug.getinfo(fn, "u")
    if info and not info.isvararg and (info.nparams or 0) < wanted + 1 then
      local declared = (info.nparams or 0) - 1
      if declared < 0 then declared = 0 end
      return false, string.format(
        "%s() must accept %d argument(s) beyond self and declares %d",
        name, wanted, declared)
    end
  end
  return true
end

return M
