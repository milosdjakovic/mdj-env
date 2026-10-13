--- Ranks a supplier's candidate rows against the live query and matching strategy, the
--- policy lib/chooser/providers/native.lua's own _build used to hold entirely by itself.
--- Moved out to this pure module during the canvas provider phase,
--- docs/BRIEF-CANVAS-PROVIDER.md section zero, once a second provider needed the exact
--- same order rather than a ranking policy of its own. Nothing in here touches
--- hs.chooser or any other Hammerspoon surface, so both providers answer the same
--- question, what order a query puts a list in, and styling or drawing the survivors is
--- left entirely to the caller.
---
--- This is a pure move out of native.lua's own _build, not a redesign. The order
--- M.apply answers for a given items, query, and matcher is the same order that
--- function answered before the move, tie break included, and holding that identity is
--- the whole reason this lives in one place now rather than the canvas provider
--- carrying a second copy of the same policy.

local M = {}

-- The text a matcher searches for a row, the row's own filterText when it carries one,
-- otherwise its title and subtitle joined with a space. A supplier that sets no
-- filterText still matches on what it shows, the same haystack every consumer's own
-- substring test relied on before this policy had a name.
local function haystackOf(it)
  return it.filterText or ((it.title or "") .. " " .. (it.subTitle or ""))
end

--- M.apply(items, query, matcher) -> a new list, the ranked items.
--- With matcher a function and query not empty, this owns filtering. Every candidate is
--- scored through matcher(query, haystackOf(item)), a nil score drops the candidate, and
--- the survivors are sorted by score descending, a tie broken on the original index
--- ascending, so a stable order the supplier already carries, the launcher's own
--- recency for one example, still shows through equal scores. With no matcher, an empty
--- query, or matcher set to false, every candidate is kept in the order the supplier
--- gave them, since false means the supplier already owns its own filtering and an
--- empty query has nothing yet to score against.
function M.apply(items, query, matcher)
  if type(matcher) ~= "function" or query == "" then
    local out = {}
    for i = 1, #items do
      out[i] = items[i]
    end
    return out
  end

  local ranked = {}
  for i = 1, #items do
    local score = matcher(query, haystackOf(items[i]))
    if score ~= nil then
      ranked[#ranked + 1] = { it = items[i], score = score, idx = i }
    end
  end
  table.sort(ranked, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.idx < b.idx
  end)

  local out = {}
  for i = 1, #ranked do
    out[i] = ranked[i].it
  end
  return out
end

return M
