-- Unit case for Olm.spoon/lib/chooser/contract.lua, the picker provider contract the
-- contract freeze phase adds, docs/BRIEF-CONTRACT-FREEZE.md. The runner reaches this file
-- with a dofile call carrying an absolute path, so this file in turn locates itself the
-- same way, through debug.getinfo, and derives the module path from there. No absolute
-- path is ever written down here, and the module under test is only loaded, never edited.
--
-- Each check prints one line, PASS or FAIL followed by a plain description, and the
-- runner counts and reports from those lines alone, the same convention every other case
-- file already follows. This case needs no Hammerspoon behind it at all, since
-- contract.lua only reads debug.getinfo against hand built functions, so it never loads
-- the native provider, which does need hs.
--
-- The required names and their arities are typed here independently of contract.lua's own
-- table, from docs/CONTRACT-PICKER.md's own "The methods" section, so this stays an honest
-- check of what the module answers rather than a mirror of what it declares.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/lib/chooser/contract.lua"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    if detail then
      print("FAIL " .. description .. ", " .. detail)
    else
      print("FAIL " .. description)
    end
  end
end

local function freshModule()
  local chunk, err = loadfile(modulePath)
  if not chunk then
    error("could not load Olm.spoon/lib/chooser/contract.lua, " .. tostring(err))
  end
  return chunk()
end

-- Arity excludes self, matching how docs/CONTRACT-PICKER.md states every one of the
-- twenty five names.
local ARITY = {
  show = 0, hide = 0, isShowing = 0, isActive = 0,
  refresh = 1, query = 0, setQuery = 1, setPlaceholder = 1, setRows = 1, rowCount = 0,
  selectNext = 0, selectPrev = 0, selectRow = 1, selectedRow = 0, selectedItem = 0,
  insertSelected = 0,
  textBudget = 0, textWidth = 2,
  reposition = 1, settleDelay = 0,
  matcher = 0, setMatcher = 1, titleLineBreak = 0, setTitleLineBreak = 1, setPaneWidth = 1,
}

-- A plain stub declaring exactly n parameters beyond a leading self, the shape every real
-- provider method takes once instance:name(args) desugars to instance.name(instance, args).
local function stub(n)
  if n == 0 then return function(self) end end
  if n == 1 then return function(self, a) end end
  return function(self, a, b) end
end

-- A correctly shaped instance, built fresh on every call so one block's mutation can never
-- leak into another's expectations, the same isolation cases/registry.lua already keeps.
local function freshValid()
  local instance = {}
  for name, n in pairs(ARITY) do
    instance[name] = stub(n)
  end
  return instance
end

-- A correct shape passes outright.
do
  local Contract = freshModule()
  local instance = freshValid()
  local ok, reason = Contract.validate(instance)
  check("a correctly shaped instance passes validation", ok == true, tostring(reason))
end

-- Not a table at all is refused before any method is even asked for.
do
  local Contract = freshModule()
  local ok, reason = Contract.validate("not an instance")
  check("a non table instance is refused", ok == false, tostring(reason))
end

-- A missing method is refused, and the reason names it.
do
  local Contract = freshModule()
  local instance = freshValid()
  instance.hide = nil
  local ok, reason = Contract.validate(instance)
  check("a missing method is refused", ok == false)
  check("the refusal for a missing method names hide",
    type(reason) == "string" and reason:find("hide", 1, true) ~= nil, tostring(reason))
end

-- A member that is not a function is refused, and the reason names it.
do
  local Contract = freshModule()
  local instance = freshValid()
  instance.query = "not a function"
  local ok, reason = Contract.validate(instance)
  check("a non function member is refused", ok == false)
  check("the refusal for a non function member names query",
    type(reason) == "string" and reason:find("query", 1, true) ~= nil, tostring(reason))
end

-- A method declaring fewer parameters than the contract states is refused, and the reason
-- names it. refresh wants one argument beyond self, resetRow, and this declares none.
do
  local Contract = freshModule()
  local instance = freshValid()
  instance.refresh = function(self) end
  local ok, reason = Contract.validate(instance)
  check("a method declaring too few parameters is refused", ok == false)
  check("the refusal for too few parameters names refresh",
    type(reason) == "string" and reason:find("refresh", 1, true) ~= nil, tostring(reason))
end

-- A variadic method is accepted whatever it declares, since a provider forwarding its own
-- arguments cannot state a count.
do
  local Contract = freshModule()
  local instance = freshValid()
  instance.refresh = function(self, ...) end
  local ok, reason = Contract.validate(instance)
  check("a variadic method is accepted", ok == true, tostring(reason))
end

-- A method declaring more parameters than required is accepted, since ignoring a trailing
-- argument is that provider's own business. selectRow wants one argument beyond self and
-- this declares two.
do
  local Contract = freshModule()
  local instance = freshValid()
  instance.selectRow = function(self, n, extra) end
  local ok, reason = Contract.validate(instance)
  check("a method declaring more parameters than required is accepted", ok == true, tostring(reason))
end
