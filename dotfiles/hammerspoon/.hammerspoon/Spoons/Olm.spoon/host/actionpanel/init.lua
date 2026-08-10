--- === ActionPanel ===
---
--- The measurement phase eight's action panel is built on. It answers one question, given a
--- context's bindings, which of them are verbs, the things a person forgets the chord for,
--- rather than navigation, the shared moving up and down, inserting, closing, and scrolling
--- the preview that every context already carries and a panel must never list.
---
--- This is a configured singleton, colon called, in the shape host/launcher and
--- host/queryscope already use, never a dot called factory like lib/registry.lua, since there
--- is exactly one classification policy for this whole configuration rather than one per
--- caller. It knows nothing about a chooser, about needs, about when, or about whether
--- anything is open. Those are the root's own filters, already named bindingApplies and
--- bindingActive, and composing them with this is later work. Keeping them out is what makes
--- this module a statement about the declarations themselves rather than about a moment, which
--- is what lets the measurement in test/inventory.lua stay true between one run and the next.
---
--- It names no action and no context. The composition root owns the map from an action name to
--- a kind, since config/keys.lua already knows what every action name means, and injects that
--- map through configure as deps.kindOf. This module only asks the question and only knows the
--- two answers a kind may be.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "ActionPanel"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("ActionPanel", "info")

-- The named set of kinds a binding's action may classify as. Two members, closed, named here
-- so the composition root and this module both write spoon.ActionPanel.kinds.verb or
-- spoon.ActionPanel.kinds.navigation rather than a bare string either side could misspell with
-- nothing to catch it. verbsIn below checks a kind against these two members directly, so a
-- third member added later needs no second place taught about it.
obj.kinds = {
  navigation = "navigation",
  verb = "verb",
}

-- Injected via configure
obj._kindOf = nil -- function(action) -> a member of obj.kinds or nil, required
obj._log = nil -- w(message), defaults to this module's own hs.logger instance

--- ActionPanel:init()
--- Method
--- Initialize the spoon. Nothing is built until configure runs, since the whole of this
--- module's behaviour comes from the one function configure injects.
function obj:init()
  return self
end

--- ActionPanel:configure(deps)
--- Method
--- deps.kindOf  required, a function taking an action name and answering a member of
---              obj.kinds or nil. A missing or non function value raises, since that is a
---              caller misusing this module rather than a tool's own data, the same line
---              lib/registry.lua draws between the two for its own required opts.apiVersion.
--- deps.log     optional, the logger every warning below is written through, defaulting to
---              this module's own hs.logger instance. It exists only so a unit case can hand
---              in a small table answering w(message) and read a warning back directly,
---              without going through hs.logger's own global, shared, process wide history
---              buffer, the same reason and the same wording lib/registry.lua gives for its
---              own opts.log. The composition root never passes it.
function obj:configure(deps)
  deps = deps or {}
  if type(deps.kindOf) ~= "function" then
    error("ActionPanel configure requires deps.kindOf, a function from an action name to a member of obj.kinds")
  end
  self._kindOf = deps.kindOf
  self._log = deps.log or log
  return self
end

--- ActionPanel:verbsIn(bindings) -> list
--- Method
--- A context's binding list in, a new ordered list holding only the bindings whose action
--- classifies as a verb, in declaration order, out. The list handed in is never mutated,
--- since the caller may be holding the very table config/keys.lua built.
---
--- A binding whose action classifies as navigation is dropped in silence, which is the entire
--- point of this function, a panel that lists it would break the one promise it makes. A
--- binding whose action classifies as neither, because deps.kindOf answered nil or answered
--- something that is not a member of obj.kinds, is dropped as well, and costs one warning
--- naming the action, since an unclassified action is a defect rather than a legitimate
--- absence. Dropping rather than keeping either way is the safer of the two answers open to an
--- unclassified action, since keeping one that turns out to be navigation would break the
--- panel's whole promise where dropping one that turns out to be a verb only goes missing
--- loudly, and loudly is recoverable.
function obj:verbsIn(bindings)
  local out = {}
  for _, b in ipairs(bindings or {}) do
    local kind = self._kindOf(b.action)
    if kind == obj.kinds.verb then
      out[#out + 1] = b
    elseif kind == obj.kinds.navigation then
      -- Dropped in silence, on purpose, see the note above.
    else
      self._log.w(string.format(
        "ActionPanel dropped '%s', it classifies as neither a verb nor navigation", tostring(b.action)))
    end
  end
  return out
end

return obj
