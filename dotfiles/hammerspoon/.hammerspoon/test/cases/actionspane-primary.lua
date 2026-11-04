-- Unit case for the one key the actions pane never claims. While the pane is open a key whose
-- action the pane lists chooses that row, through the root's claim in the dispatch table, which
-- asks ActionsPane:chooseAction. The primary verb is the exception, since over an open pane it is
-- Return, choosing the highlighted pane row at the top level and inside a level alike, so the
-- claim must not ask the pane about it. Claimed, it chose the pane's primary row whatever was
-- highlighted and did nothing inside a level, which is what Milos found on 2026-11-03.
--
-- It runs against the live composition, spoon.Olm._composed, and stands a recorder in for the
-- pane's chooseAction for the length of the case, so nothing opens on screen and no verb runs.
--
-- Each check prints one line, PASS or FAIL followed by a plain description.

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local composed = spoon and spoon.Olm and spoon.Olm._composed
check("the live composition is recorded", composed ~= nil and composed.dispatch ~= nil and composed.plan ~= nil)
if not (composed and composed.dispatch and composed.plan) then return end

local plan = composed.plan
local pane = composed.modules and composed.modules[plan.identity.actionspane or "actionspane"]
check("the actions pane module is wired", pane ~= nil and type(pane.chooseAction) == "function")
if not pane then return end

-- One action some list binds as its primary verb, and one verb a list binds that is not shared,
-- the kind the pane lists and a key may claim.
local primary, verb
for _, block in pairs(plan.contexts or {}) do
  for _, b in ipairs(block.bindings or {}) do
    if b.shared == "primary" and b.action and not primary then primary = b.action end
  end
end
local primaries = {}
for _, block in pairs(plan.contexts or {}) do
  for _, b in ipairs(block.bindings or {}) do
    if b.shared == "primary" and b.action then primaries[b.action] = true end
  end
end
for _, block in pairs(plan.contexts or {}) do
  for _, b in ipairs(block.bindings or {}) do
    if b.shared == nil and b.action and not primaries[b.action] and composed.dispatch[b.action]
      and not verb then verb = b.action end
  end
end
check("a primary action is bound", primary ~= nil and composed.dispatch[primary] ~= nil, tostring(primary))
check("a list verb is bound", verb ~= nil, tostring(verb))
if not (primary and verb) then return end

local asked = {}
local original = pane.chooseAction
-- The recorder answers true, so a claimed key stops at the claim and its verb never runs.
pane.chooseAction = function(_, name)
  asked[#asked + 1] = name
  return true
end
local ok, err = pcall(function()
  composed.dispatch[verb]()
  composed.dispatch[primary]()
end)
pane.chooseAction = original

check("the dispatch ran", ok, tostring(err))
local askedVerb, askedPrimary = false, false
for _, name in ipairs(asked) do
  if name == verb then askedVerb = true end
  if name == primary then askedPrimary = true end
end
check("a list verb's key asks the pane to claim it, " .. verb, askedVerb)
check("the primary key is never claimed by the pane, it is Return there, " .. primary, not askedPrimary)
check("the pane's chooseAction is given back", pane.chooseAction == original)
