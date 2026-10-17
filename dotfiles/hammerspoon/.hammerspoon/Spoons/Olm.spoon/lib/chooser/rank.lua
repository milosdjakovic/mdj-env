--- Ranks a supplier's candidate rows against the live query and matching strategy, the
--- policy lib/chooser/providers/legacy.lua's own _build used to hold entirely by itself.
--- Moved out to this pure module during the canvas provider phase,
--- docs/BRIEF-CANVAS-PROVIDER.md section zero, once a second provider needed the exact
--- same order rather than a ranking policy of its own. Nothing in here touches
--- hs.chooser or any other Hammerspoon surface, so both providers answer the same
--- question, what order a query puts a list in, and styling or drawing the survivors is
--- left entirely to the caller.
---
--- This is a pure move out of legacy.lua's own _build, not a redesign. The order
--- M.apply answers for a given items, query, and matcher is the same order that
--- function answered before the move, tie break included, and holding that identity is
--- the whole reason this lives in one place now rather than the canvas provider
--- carrying a second copy of the same policy.
---
--- It is the one rank engine, docs/PLAN-UNIFIED-SEARCH.md. Phase one on 2026-10-17 deleted
--- the four copies of this loop that had grown elsewhere, in host/queryscope, in the default
--- provider's list model, in host/actionpanel and in the launcher's catalog ranking, and
--- each now scores and sorts through here. A host reaches it as the rank value the
--- composition root hands over, never by loading this file itself.

local M = {}

-- The text a matcher searches for a row, the row's own filterText when it carries one,
-- otherwise its title and subtitle joined with a space. A supplier that sets no
-- filterText still matches on what it shows, the same haystack every consumer's own
-- substring test relied on before this policy had a name.
local function haystackOf(it)
  return it.filterText or ((it.title or "") .. " " .. (it.subTitle or ""))
end

--- M.haystackOf(item) -> the text a matcher searches for one row, exposed so a consumer
--- scoring rows through M.score below never restates the rule.
M.haystackOf = haystackOf

--- M.score(items, query, matcher) -> a new list of entries, unsorted.
--- Every candidate scored through matcher(query, haystackOf(item)), a nil score dropping
--- it. An entry is { item, score, idx, tier, within }, idx the candidate's place in items.
--- tier and within are the second and third answers lib/chooser/match.lua's fuzzy gives,
--- the count of words found whole and the score inside that tier, and a matcher answering
--- only a score reads as tier zero with within equal to the score. They exist for a
--- consumer that orders by something besides the score and needs to know which rows are a
--- comparable kind of match, the launcher's nearness rule today. This is the one scoring
--- loop, so no host or list keeps a copy of it, docs/PLAN-UNIFIED-SEARCH.md phase one.
function M.score(items, query, matcher)
  local entries = {}
  for i = 1, #items do
    local score, tier, within = matcher(query, haystackOf(items[i]))
    if score ~= nil then
      entries[#entries + 1] = {
        item = items[i], score = score, idx = i, tier = tier or 0, within = within or score,
      }
    end
  end
  return entries
end

--- M.before(a, b) -> true when entry a sorts ahead of entry b.
--- Score descending, a tie broken on the original index ascending, so a stable order the
--- supplier already carries, the launcher's own recency for one example, still shows
--- through equal scores. Lua's sort is not stable, which is why the index is folded in
--- rather than relied on. Exposed as the one tie rule, for a consumer that puts something
--- of its own ahead of it.
function M.before(a, b)
  if a.score ~= b.score then return a.score > b.score end
  return a.idx < b.idx
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

  local ranked = M.score(items, query, matcher)
  table.sort(ranked, M.before)

  local out = {}
  for i = 1, #ranked do
    out[i] = ranked[i].item
  end
  return out
end

return M
