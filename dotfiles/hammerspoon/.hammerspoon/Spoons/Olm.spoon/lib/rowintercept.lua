--- === rowintercept ===
---
--- What choosing a launcher row does in place of closing the launcher and running it, answered as
--- a function the launcher runs, or nil to run the row the ordinary way. The launcher promotes any
--- row this answers a function for to recency, one level up in host/launcher/init.lua, so nothing
--- here knows about recency.
---
--- It moved here from the composition root, which hands in the calls it alone can make and
--- answers the launcher's actions.rowIntercept with this. Pure, no state and no hs. The contract
--- is the deps table, every field a function, the scope ones absent when no scope host loaded.
---
---   aliasQuery       a row to the word the alias directory answers to when the row is the
---                    launcher's own Aliases row, else nil
---   seed             types a word into the open launcher's field
---   presentationFor  a registered tool's name to the presentation it put on the shared stage,
---                    nil for one that does not present there
---   push             pushes a presentation onto the shared stage over the open list
---   actFor           a scope row to the function that acts on it, else nil
---   redirectFor      a scope row to the word that narrows the launcher to it, else nil

local obj = {}

--- rowintercept.forRow(item, deps) -> function or nil
--- In order. A row a plugin contributed belongs to that plugin alone, never taken for a registered
--- tool of the same name nor for a scope, so only its owner's runner acts on it. The Aliases row has
--- no presentation in the registry, so it seeds its word, which replaces the open list instead of
--- closing the launcher first. A special row naming a tool that presents on the stage pushes that
--- presentation and does nothing else, since the push already clears the query and redraws. A scope
--- row acts, or narrows the launcher by seeding its word.
function obj.forRow(item, deps)
  if item.owner ~= nil then return nil end
  local aliasQuery = deps.aliasQuery(item)
  if aliasQuery then return function() deps.seed(aliasQuery) end end
  if item.kind == "special" and deps.presentationFor then
    local presentation = deps.presentationFor(item.name)
    if presentation then
      return function() deps.push(presentation) end
    end
  end
  if item.kind ~= "scope" or not deps.actFor then return nil end
  local act = deps.actFor(item)
  if act then return act end
  local query = deps.redirectFor(item)
  if not query then return nil end
  return function() deps.seed(query) end
end

--- rowintercept.presentationFor(item, deps) -> presentation or nil
--- The presentation choosing this row pushes onto the stage and nothing else, the special row
--- naming a tool forRow answers a push for, or nil for any other row. A question with no effect, so
--- the app's launcher can ask what a row would show before it shows it there, step 3.3 of
--- docs/PLAN-STANDALONE.md.
function obj.presentationFor(item, deps)
  if type(item) ~= "table" or item.owner ~= nil or deps.aliasQuery(item) then return nil end
  if item.kind ~= "special" or not deps.presentationFor then return nil end
  return deps.presentationFor(item.name)
end

--- rowintercept.inPlace(item, deps) -> { present = p } | { seed = word } | { act = fn } | nil
--- What forRow's callable would do, said rather than done, step 3.6 of docs/PLAN-STANDALONE.md, so
--- the app's launcher can do the same in its own list. A row forRow leaves alone answers nil. The
--- act is the scope's own callable, handed back uncalled.
function obj.inPlace(item, deps)
  if type(item) ~= "table" or item.owner ~= nil then return nil end
  local aliasQuery = deps.aliasQuery(item)
  if aliasQuery then return { seed = aliasQuery } end
  if item.kind == "special" and deps.presentationFor then
    local presentation = deps.presentationFor(item.name)
    if presentation then return { present = presentation } end
  end
  if item.kind ~= "scope" or not deps.actFor then return nil end
  local act = deps.actFor(item)
  if act then return { act = act } end
  local query = deps.redirectFor and deps.redirectFor(item)
  if not query then return nil end
  return { seed = query }
end

return obj
