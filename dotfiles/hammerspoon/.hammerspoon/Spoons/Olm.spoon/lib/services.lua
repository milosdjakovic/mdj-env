-- What every plugin gets for free, and what each plugin gets because of who it is.
--
-- wire.lua already decides WHEN a plugin receives a service and WHICH services a
-- declaration earns. It reads two things to do that. A flat table called services, read
-- by its own ENTITLEMENTS and UNIVERSAL rules, and a per plugin data table, read last and
-- unconditionally, which is the one channel that can hand twelve plugins twelve different
-- values for the same field name. This file builds both of those tables. It names no
-- plugin anywhere in it. Every answer comes from what a manifest declared, never from a
-- string this file recognises on its own.
--
-- obj.ambient builds the flat table. obj.fanOut and obj.perPlugin both build slices of the
-- per plugin data table, one from the user's own shared configuration and one from what a
-- plugin's own declarations earn structurally, and obj.merge is what layers those slices,
-- and whatever the composition root adds beyond them, into one table with a fixed winning
-- order. Nothing here starts a watcher, binds a key, or configures a plugin. It only
-- decides what a plugin is handed once wire.lua's stage two runs.
--
-- THE RULE THAT MATTERS MOST FOR THIS FILE. obj.ambient must never carry onPositioned,
-- onActivity, or onClose. wire.lua's own ENTITLEMENTS table grants a surfaced plugin only
-- chooser, theme, and placeholder ambiently, and it reads the panel triple as a separate
-- question, straight off the same flat services table, so leaving those three keys out of
-- it is what makes the panel triple's real home the per plugin data table instead. That is
-- also why the panel triple is built here, in obj.perPlugin, rather than being one more key
-- in obj.ambient. Twelve plugins wanting twelve different panels can only ever be answered
-- by the one channel that is per plugin by construction.

local obj = {}

--- obj.ambient(deps)
--- Function
--- The flat table wire.lua's own ENTITLEMENTS and UNIVERSAL rules read from, once per
--- reload rather than once per plugin, since every plugin that earns one of these fields
--- earns the exact same value.
---
--- deps.chooser       the shared chooser factory every surfaced plugin's own configure
---                     builds its picker from.
--- deps.theme         the shared theme table every surfaced plugin's own picker paints with.
--- deps.placeholder   the shared default placeholder string a plugin's own field falls back
---                     to when it names none of its own.
--- deps.matcher       the shared default matching strategy, handed to a plugin whose
---                     surface names no matcher of its own.
--- deps.matchers      the table of named strategies, fuzzy, substring, words and the rest,
---                     so a plugin naming a strategy by that name in its own surface
---                     declaration resolves against the real function rather than the word.
--- deps.paneElements  the shared docked companion pane elements, handed to a plugin whose
---                     surface asks for the pane.
--- deps.log           the shared logger, granted to any plugin whether it declared anything
---                     or not, since UNIVERSAL treats every plugin as free to ask for one.
---
--- after is not read off deps. It is built right here, inline, because it has exactly one
--- consumer, this table, and a wrapper module for eight lines with one caller is a cost this
--- design principles ask not to pay. It is the deferred call helper ported from the live
--- read only root, unchanged in shape. A Hammerspoon timer is userdata whose finalizer stops
--- it, so a pending timer nothing refers to can be collected before it ever fires, and the
--- delayed call then simply never happens, with no error anywhere and nothing to grep for.
--- Holding the timer in pendingCalls until it fires is what makes a delayed call reliable.
--- Every call gets its own slot, so several may be outstanding at once and each releases
--- only its own entry when it fires, never another caller's.
function obj.ambient(deps)
  deps = deps or {}

  local pendingCalls = {}
  local function after(delay, fn)
    local slot = {}
    pendingCalls[slot] = hs.timer.doAfter(delay, function()
      pendingCalls[slot] = nil
      fn()
    end)
  end

  return {
    chooser = deps.chooser,
    theme = deps.theme,
    placeholder = deps.placeholder,
    matcher = deps.matcher,
    matchers = deps.matchers,
    paneElements = deps.paneElements,
    log = deps.log,
    after = after,
  }
end

--- obj.fanOut(manifests, shared)
--- Function
--- The user's own shared configuration, fanned out to whichever manifest asked for a field
--- of that name. This is what shrinks the person's own file down to one apps table, one
--- keys catalog, one settings block, one displays list, rather than one copy repeated under
--- every plugin that reads a slice of it.
---
--- A plugin earns a copy by declaring needs.data on that field name with source equal to
--- "user". Nothing else about the plugin matters here, not its policy, not its breaks
--- sentence, only whether the field it named and the field shared carries are the same word.
--- A plugin naming a field shared does not carry gets nothing from this function and is left
--- for resolve.lua's own rules to answer, blocked, degraded, or simply absent, exactly as it
--- would be with no fan out at all.
---
--- Returns a table keyed by plugin name, each value a table of field to value, shaped
--- exactly like the per plugin data table wire.lua reads last, so this answer is one of the
--- layers obj.merge combines rather than a table with a shape of its own to translate.
---
--- Must run before resolve.lua's own plan is built, since resolve.lua reads this same shape
--- to decide whether a required user sourced field actually arrived, and a plan built with
--- nothing supplied would report every one of these plugins blocked on a fresh install where
--- nothing is actually wrong.
function obj.fanOut(manifests, shared)
  shared = shared or {}
  local data = {}
  for name, manifest in pairs(manifests or {}) do
    local fields = ((manifest or {}).needs or {}).data or {}
    for field, decl in pairs(fields) do
      if type(decl) == "table" and decl.source == "user" and shared[field] ~= nil then
        data[name] = data[name] or {}
        data[name][field] = shared[field]
      end
    end
  end
  return data
end

--- obj.perPlugin(plan, manifests, deps)
--- Function
--- What a plugin earns because of who it is, once the plan already knows what was built for
--- it. Three questions, each answered independently, and a plugin may earn all three, one,
--- or none.
---
--- deps.hints   the lib/hints.lua module, injected rather than required, since this file
---              names no sibling lib by path and calls it only through what the composition
---              root handed in. Read for its shortcutPanelFor(contextName, plan, deps)
---              function, presentation this file has no business computing itself.
--- deps.libs    the lib module set by name, the same table resolve.lua and wire.lua already
---              read capabilities off, so a plugin declaring needs.lib.recency gets an
---              instance built off the real recency.lua module rather than off a stand in.
--- deps.deps    the shared scoped tool path adapter, already built and already probed by
---              whatever the composition root uses to answer a tool's presence. Handed out
---              whole to every plugin that earns it, the same single adapter every earning
---              plugin already shares in the live root today, never rebuilt per plugin here.
---
--- The docked hint panel. wire.lua's own ambient grant for onPositioned, onActivity and
--- onClose reads them straight off the flat services table, and obj.ambient never puts them
--- there on purpose, so this is their only real home. Built for a plugin only once its
--- surface actually produced a context, checked by asking the plan rather than by trusting
--- the manifest declared one, since a surface that failed validation earns nothing back from
--- resolve.lua and building a panel for a context that does not exist is a panel nothing can
--- ever show. Shaped flat, three separate fields, or nested under manifest.surface.panelAs
--- when that field names one, the one axis PLUGIN-CONTRACT.md documents as a real
--- disagreement between plugins' own configure contracts rather than a shape this file gets
--- to pick for all of them.
---
--- The scoped tool path adapter. Earned only once needs.tools carries at least one entry
--- whose stage is runtime or carries no stage at all, since an absent stage already means
--- runtime by the same convention lib/plugins.lua's own install list uses. A plugin whose
--- only declared tools build a dataset or drive a test harness has nothing at wiring time to
--- resolve a path for, and handing it the adapter anyway is exactly the defect the audit
--- found twice, once as a plugin gaining a field it never had and once as a plugin genuinely
--- needing one going without.
---
--- One recency instance per plugin declaring needs.lib.recency, each opened fresh here
--- rather than read off wire.lua's own generic lib grant, because that grant hands over the
--- recency MODULE, the thing with a new function on it, and every real consumer reads
--- opts.recency as though it already were an instance with touch, rankOf and order on it. A
--- shared instance across two plugins would merge two tools' remembered orderings into one,
--- so each plugin's slot is keyed to its own name.
---
--- Runs after resolve.lua's own plan, since it reads plan.contexts and plan.identity, both
--- of which only exist once the plan has been built.
function obj.perPlugin(plan, manifests, deps)
  plan = plan or {}
  manifests = manifests or {}
  deps = deps or {}

  local data = {}
  local function slot(name)
    data[name] = data[name] or {}
    return data[name]
  end

  for _, name in ipairs(plan.order or {}) do
    local manifest = manifests[name] or {}
    local needs = manifest.needs or {}

    -- The panel triple, only for a plugin whose surface actually produced a context.
    -- Surface declarations name their context after the plugin's own identity, and
    -- resolve.lua's own default agrees, so that identity is the one name asked of the
    -- plan rather than a second guess of what resolve.lua already decided.
    if manifest.surface and deps.hints and plan.contexts then
      local contextName = (plan.identity or {})[name] or name
      if plan.contexts[contextName] then
        local panel = deps.hints.shortcutPanelFor(contextName, plan, deps)
        if panel then
          local panelAs = manifest.surface.panelAs
          if panelAs then
            slot(name)[panelAs] = panel
          else
            local s = slot(name)
            s.onPositioned = panel.onPositioned
            s.onActivity = panel.onActivity
            s.onClose = panel.onClose
          end
        end
      end
    end

    -- The scoped tool path adapter, earned by a runtime stage tool and never by a dev or
    -- test only one.
    if deps.deps ~= nil then
      local earnsAdapter = false
      for _, tool in ipairs(needs.tools or {}) do
        if (tool.stage or "runtime") == "runtime" then
          earnsAdapter = true
          break
        end
      end
      if earnsAdapter then
        slot(name).deps = deps.deps
      end
    end

    -- One recency instance, keyed to this plugin's own settings slot.
    if needs.lib and needs.lib.recency and deps.libs and deps.libs.recency then
      slot(name).recency = deps.libs.recency.new({ settingsKey = "olm.recency." .. name })
    end
  end

  return data
end

--- obj.merge(...)
--- Function
--- Layers any number of name keyed data tables, each shaped { [pluginName] = { field =
--- value } }, with a later argument winning per field over an earlier one. This is what
--- lets obj.fanOut's answer, obj.perPlugin's answer, and whatever the composition root
--- itself assembles for a field none of these two could ever know about, such as
--- ActionPanel's own kindOf and rowsFor, sit in one table with a fixed order rather than
--- three tables the caller has to reconcile by hand.
---
--- The order that order matters follows one sentence. Mechanism derived data, what a
--- plugin earns by declaring a role, sits under root computed data, what the composition
--- root alone can build. Root computed data sits under the person's own choice. So a
--- caller passes obj.perPlugin's answer first, whatever the root assembled next, and the
--- person's own configuration last, and a field only one of the three ever names simply
--- passes through untouched.
---
--- Every layer is read, never written to. A fresh table is returned so the caller's own
--- copies of an earlier layer are never mutated by a later one, which matters because
--- obj.perPlugin's own answer is exactly the kind of table a caller might reasonably want
--- to inspect again afterward.
function obj.merge(...)
  local out = {}
  for i = 1, select("#", ...) do
    local layer = select(i, ...)
    for name, fields in pairs(layer or {}) do
      out[name] = out[name] or {}
      for field, value in pairs(fields or {}) do
        out[name][field] = value
      end
    end
  end
  return out
end

return obj
