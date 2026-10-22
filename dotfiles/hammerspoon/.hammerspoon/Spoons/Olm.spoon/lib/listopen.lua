--- === listopen ===
---
--- Whether an Olm list is open, one named list or any of them. Every leader asks the second before
--- a hold reveals a sheet and before a quiet leader acts, the leader with contexts asks it to seal
--- itself over a list, and the wiring, the action panel and the surface adapters ask the first.
--- Both read the same table of context owners the predicates route through, so the gate and the
--- modal rule on the leader with contexts can never disagree about what an open list is.
---
--- It moved here from the composition root, which hands in what it alone holds and wraps the two
--- answers as the closures it gives out. Pure, no state and no hs. The contract is the deps table.
---
---   owners           context name to the directory of the plugin or host that owns the list
---   identity         directory to identity, plan.identity, a directory missing from it being its
---                    own identity
---   presentationFor  identity to the presentation it put on the shared stage, nil for an owner
---                    that does not present there. Asked at every call, since the registry it reads
---                    is built after the leaders that close over this.
---   stage            the shared stage, answering current and isShowing, or nil
---   modules          directory to the loaded module
---   manifests        directory to the manifest, read for where the module keeps its surface

local obj = {}

--- listopen.surfaceOf(module, spec) -> table or nil
--- Walks to wherever a plugin keeps its picker, which its manifest says through registry.surface,
--- a dotted member path. Five plugins keep it on a submodule, the clipboard on manager and four
--- more on chooser, and asking their root alone answered nothing. A surface may be a member that
--- ANSWERS the adapter rather than being it, which is how three are written, so a function is
--- called, both calling conventions tried, since no manifest says which one a plugin picked.
function obj.surfaceOf(module, spec)
  if spec == nil or spec == true then return module end
  local owner, value = module, module
  for part in tostring(spec):gmatch("[^.]+") do
    if type(value) ~= "table" then return nil end
    owner, value = value, value[part]
  end
  if type(value) == "function" then
    local ok, answer = pcall(value, owner)
    if ok and type(answer) == "table" then return answer end
    local dotOk, dotAnswer = pcall(value)
    if dotOk and type(dotAnswer) == "table" then return dotAnswer end
    return nil
  end
  return value
end

--- listopen.isShowing(contextName, deps) -> boolean
--- Whether that context's list is open. An owner presenting on the shared stage is open while the
--- stage shows it, asked first since its module may carry no isShowing at all once the stage owns
--- the list, and the same answer the stage's own surfaceFor gives the nav registry. Any other owner
--- is asked through its surface, both calling conventions tried, since getting the arity wrong
--- fails rather than answering and that shipped once for three surfaces.
---
--- This used to ask the plugin root and stop there, and for five of the twelve pickers the root
--- has no isShowing, so every chord gated on it inside those five was dead and the plain Hyper
--- binding on the same key fired instead, j in the clipboard opening the emoji picker, with
--- nothing logged.
function obj.isShowing(contextName, deps)
  local owner = deps.owners[contextName]
  if not owner then return false end
  local ownerIdentity = deps.identity[owner] or owner
  local stage = deps.stage
  if stage and deps.presentationFor(ownerIdentity) then
    return stage:current() == ownerIdentity and stage:isShowing() == true
  end
  local module = deps.modules[owner]
  if not module then return false end
  local manifest = deps.manifests[owner] or {}
  local spec = (manifest.surface or {}).member or (manifest.registry or {}).surface
  local holder = module
  if type(module.isShowing) ~= "function" then
    holder = obj.surfaceOf(module, spec)
  end
  if type(holder) ~= "table" or type(holder.isShowing) ~= "function" then return false end
  local ok, answer = pcall(holder.isShowing, holder)
  if ok then return answer == true end
  local dotOk, dotAnswer = pcall(holder.isShowing)
  return dotOk and dotAnswer == true
end

--- listopen.anyShowing(deps) -> boolean
--- Whether any list is open right now, the launcher and every plugin picker alike.
function obj.anyShowing(deps)
  for contextName in pairs(deps.owners) do
    if obj.isShowing(contextName, deps) then return true end
  end
  return false
end

return obj
