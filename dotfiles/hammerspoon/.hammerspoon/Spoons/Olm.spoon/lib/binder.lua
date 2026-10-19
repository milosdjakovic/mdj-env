-- The binder, the one place a global key is bound.
--
-- lib/keymap.lua writes every chord down as a row, each global row carrying the function its
-- source answers, and hands the global rows over a second time as a list in the order the
-- engines receive them. This walks that list as it stands and hands each row to the engine its
-- leader resolves to, or to the plain combo binder for a row with no leader. Nothing else binds a global key, so a plugin never calls a bind
-- function and the keymap is the whole answer to what is bound.
--
-- The order is the part that matters. An engine keeps every binding on a key in the order it
-- received them, and both leaders resolve a press by walking that list, the window leader taking
-- the first exact match and the last passing catch all, Hyper the best priority within a tier.
-- So two rows on one key must arrive in the order the paths this replaced bound them in, which is
-- the order the keymap's bound list is in, and this never reorders it.
--
-- A list's own keys are not bound here. They are live only while their list is open and the
-- root binds them through its contexts, so a row outside the global layer is skipped.
--
-- It is pure Lua. The engines and the plain combo binder arrive through its inputs, which is
-- what lets a plain test record every call, and it names no plugin and no leader. A leader is
-- whatever name the engines table is keyed by.

local obj = {}

local GLOBAL = "global"

--- obj.bind(rows, deps) -> problems
---   rows     the keymap's bound list, bound in the order given.
---   engines  a table from a leader name, as a row spells it, to the engine binding on that
---            leader. An engine answers bind(self, key, fn, mods, opts).
---   hotkey   function(mods, key, fn), the plain combo binder, for a row with no leader.
---
--- Each row is bound with its key, its modifiers, nil for a catch all, and its gate, priority
--- and repeat in the options. A row whose source answered no function, or whose leader has no
--- engine, is not bound and comes back as a problem, the where and the why the wiring report
--- takes. A row whose action was refused at validation is left unbound in silence, since the
--- refusal already said so, and so is a row marked quiet, a host with nothing to show. A raise from one engine costs that row and is reported, and every
--- other row still binds.
function obj.bind(rows, deps)
  deps = deps or {}
  local engines = deps.engines or {}
  local problems = {}
  local function problem(row, why)
    local chord = tostring(row.leader or "plain") .. " " .. tostring(row.key)
    problems[#problems + 1] = {
      where = tostring(row.owner) .. " " .. tostring(row.action),
      why = why .. ", so " .. chord .. " is not bound",
    }
  end

  for _, row in ipairs(rows or {}) do
    local mods = (not row.anyMods) and row.mods or nil
    if row.layer ~= GLOBAL then
      -- A list's own key, which the contexts bind.
    elseif type(row.run) ~= "function" then
      if not row.refused and not row.quiet then
        problem(row, "the " .. tostring(row.source) .. " row answers no function to run")
      end
    elseif row.leader == nil then
      if type(deps.hotkey) ~= "function" then
        problem(row, "no plain combo binder was handed over")
      else
        local ok, err = pcall(deps.hotkey, mods or {}, row.key, row.run)
        if not ok then problem(row, "binding it raised, " .. tostring(err)) end
      end
    else
      local engine = engines[row.leader]
      if not engine then
        problem(row, "no engine binds on the leader " .. tostring(row.leader))
      else
        -- A global row's predicate travels as a gate, never as when, since on Hyper a when
        -- makes a context and a context makes the leader modal, which would silence every
        -- other global key while the predicate holds.
        local ok, err = pcall(engine.bind, engine, row.key, row.run, mods, {
          gate = row.when, priority = row.priority, repeats = row.repeats,
        })
        if not ok then problem(row, "binding it raised, " .. tostring(err)) end
      end
    end
  end
  return problems
end

return obj
