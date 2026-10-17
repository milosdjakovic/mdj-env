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

-- The row vocabulary for search, settled 2026-10-17.
--
-- title is the name, the primary field the shared search ranks first.
-- subTitle is what the row shows under its name, searched as a secondary field.
-- keywords is what the row declares it answers to without showing it, a string or a list of
-- strings, each a secondary field. Inside one string a comma, a semicolon, a question or
-- exclamation mark, or a separator such as the middle dot or the triangle ends a phrase, so
-- "focus, do not disturb, dnd" holds three phrases and a match shows the one it was in.
-- filterText, when a row sets it, replaces both the name and the subtitle. It becomes the
-- primary field and the subtitle is not searched, so a row whose subtitle is a category, a
-- status or a chord sets filterText to its title, a menu item sets it to its title and
-- declares its parents as keywords, a computed row sets it to the query, and a row setting it
-- empty never matches by its name. keywords are searched either way. Prose is never a search
-- term, a description sentence matches words nobody meant.

-- The text a strategy that reads one string searches for a row, substring and words, the
-- row's own filterText when it carries one, otherwise its title and subtitle joined with a
-- space, exactly what it was before the fields existed.
local function haystackOf(it)
  return it.filterText or ((it.title or "") .. " " .. (it.subTitle or ""))
end

--- M.haystackOf(item) -> the text a one string matcher searches for one row, exposed so a
--- consumer scoring rows through M.score below never restates the rule.
M.haystackOf = haystackOf

-- The fields the shared search reads for a row, the vocabulary above as one table,
-- { primary, secondary = { { text, visible }, ... } }.
local function fieldsOf(it)
  local secondary = {}
  local primary = it.filterText
  if primary == nil then
    primary = it.title or ""
    if type(it.subTitle) == "string" and it.subTitle ~= "" then
      secondary[#secondary + 1] = { text = it.subTitle, visible = true }
    end
  end
  local kw = it.keywords
  if type(kw) == "string" then kw = { kw } end
  if type(kw) == "table" then
    for _, k in ipairs(kw) do
      if type(k) == "string" and k ~= "" then secondary[#secondary + 1] = { text = k, visible = false } end
    end
  end
  return { primary = type(primary) == "string" and primary or "", secondary = secondary }
end

--- M.fieldsOf(item) -> the fields the shared search reads for one row.
M.fieldsOf = fieldsOf

--- M.score(items, query, matcher) -> a new list of entries, unsorted.
--- Every candidate scored through matcher(query, haystackOf(item), fieldsOf(item)), a nil
--- score dropping it. An entry is { item, score, idx, level, within, atStart, shown }, idx
--- the candidate's place in items. The later fields are the later answers
--- lib/chooser/match.lua's fuzzy gives, the row's level sum, its score inside that level,
--- whether every word matched the name at a word start, and the declared phrase it matched
--- in. A matcher answering only a score reads as level zero, within equal to
--- the score, and not at a word start. They exist for a consumer that orders by something
--- besides the score and needs to know what kind of match a row is, the launcher's nearness
--- rule today. This is the one scoring
--- loop, so no host or list keeps a copy of it, docs/PLAN-UNIFIED-SEARCH.md phase one.
function M.score(items, query, matcher)
  local entries = {}
  for i = 1, #items do
    local score, level, within, atStart, shown =
      matcher(query, haystackOf(items[i]), fieldsOf(items[i]))
    if score ~= nil then
      entries[#entries + 1] = {
        item = items[i], score = score, idx = i, level = level or 0, within = within or score,
        atStart = atStart == true, shown = shown,
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

-- Whether the lowered text holds the lowered phrase as whole words, so time is not taken as
-- shown by Sometimes. A letter or a digit on either side means it is part of a longer word.
local function holdsWhole(text, phrase)
  local init = 1
  while true do
    local i, j = text:find(phrase, init, true)
    if not i then return false end
    local before, after = text:sub(i - 1, i - 1), text:sub(j + 1, j + 1)
    if not before:match("%w") and not after:match("%w") then return true end
    init = i + 1
  end
end

--- M.present(entry) -> the row to show for one scored entry.
--- A row listed only through a phrase it declares and does not show would be listed with no
--- visible reason, so the phrase joins its subtitle, Focus for do reading System Settings ·
--- do not disturb. entry.shown is the list of such phrases the matcher answered, each once. A
--- phrase the subtitle already shows as whole words is not repeated, and the row is copied
--- for the rest, never changed, since a supplier may hand the same table back on the next
--- keystroke. Every list ranked by this engine gets this, while a query is typed, because an
--- empty query never scores and so never presents.
function M.present(entry)
  local it, shown = entry.item, entry.shown
  if type(shown) == "string" then shown = { shown } end
  if type(shown) ~= "table" or #shown == 0 then return it end
  local sub = type(it.subTitle) == "string" and it.subTitle or ""
  local lowSub = sub:lower()
  local add, seen = {}, {}
  for _, phrase in ipairs(shown) do
    local low = phrase:lower()
    if phrase ~= "" and not seen[low] and not holdsWhole(lowSub, low) then
      seen[low] = true
      add[#add + 1] = phrase
    end
  end
  if #add == 0 then return it end
  local copy = {}
  for k, v in pairs(it) do copy[k] = v end
  copy.subTitle = (sub ~= "" and (sub .. " · ") or "") .. table.concat(add, ", ")
  return copy
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
    out[i] = M.present(ranked[i])
  end
  return out
end

return M
