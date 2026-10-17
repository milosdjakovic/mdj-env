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
-- strings, each a secondary field, written as comma separated phrases, "focus, do not
-- disturb, dnd". A secondary field matches a query word only where one of its words starts
-- with it. A row always shows exactly the subtitle its supplier gave, whatever matched.
-- filterText, when a row sets it, replaces both the name and the subtitle. It becomes the
-- primary field and the subtitle is not searched, so a row whose subtitle is a category, a
-- status or a chord sets filterText to its title, a menu item sets it to its title and
-- declares its parents as keywords, and a row setting it empty never matches by its name.
-- keywords are searched either way. Prose is never a search term, a description sentence
-- matches words nobody meant.
--
-- Three fields say where a row goes rather than what it answers to, settled 2026-10-17 for
-- phase two. A field of the wrong type is read as absent.
-- pinned, when true, means the row is never scored and never dropped. A pinned row the
-- supplier gives before every unpinned row leads, any other trails after every ranked row,
-- both in the supplier's order. A row that is the query itself, a calculator answer or a save
-- row, is pinned too, since its supplier already decided it exists for this query.
-- tier is a number, zero when absent, and a smaller tier sorts first among ranked rows, ahead
-- of how well a row matched, so a list can keep one kind of row above another.
-- bonus is a number from zero to one, clamped, zero when absent. It orders only rows the
-- matcher calls equally good, the same tier, the same level sum and the same phrase bonus,
-- and there it leads before where a word landed. It never lifts a row over a better match,
-- which is what makes it safe to feed from recency or frecency.

-- tier and bonus as M.before reads them, a wrong type being the default. A NaN fails both
-- comparisons below and so reads as the default too, since it would break the sort's order.
local function tierOf(it)
  local t = it.tier
  if type(t) == "number" and t == t then return t end
  return 0
end
local function bonusOf(it)
  local b = it.bonus
  if type(b) ~= "number" or b ~= b then return 0 end
  if b < 0 then return 0 end
  if b > 1 then return 1 end
  return b
end

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
-- { primary, secondary = { { text, declared }, ... } }, declared marking keywords, which also
-- answer a phrase typed run together where the subtitle does not.
local function fieldsOf(it)
  local secondary = {}
  local primary = it.filterText
  if primary == nil then
    primary = it.title or ""
    if type(it.subTitle) == "string" and it.subTitle ~= "" then
      secondary[#secondary + 1] = { text = it.subTitle }
    end
  end
  local kw = it.keywords
  if type(kw) == "string" then kw = { kw } end
  if type(kw) == "table" then
    for _, k in ipairs(kw) do
      if type(k) == "string" and k ~= "" then secondary[#secondary + 1] = { text = k, declared = true } end
    end
  end
  return { primary = type(primary) == "string" and primary or "", secondary = secondary }
end

--- M.fieldsOf(item) -> the fields the shared search reads for one row.
M.fieldsOf = fieldsOf

--- M.score(items, query, matcher) -> a new list of entries, unsorted.
--- Every candidate scored through matcher(query, haystackOf(item), fieldsOf(item)), a nil
--- score dropping it. An entry is { item, score, idx, level, within, atStart, phrase, graded,
--- tier, bonus }, idx the candidate's place in items. level, within, atStart and phrase are
--- the later answers lib/chooser/match.lua's fuzzy gives, the row's level sum, its score
--- inside that level, whether every word matched the name at a word start, and whether it
--- earned the phrase bonus. A matcher answering only a score reads as level zero, within equal
--- to the score, not at a word start and no phrase, and graded is false for it, so M.before
--- knows it was told nothing about the kind of match. They exist for a consumer that orders by
--- something besides the score and needs to know what kind of match a row is, the launcher's
--- nearness rule today. tier and bonus are the row's own, read as the vocabulary above says.
--- pinned is not read here, M.apply keeps pinned rows out of the loop. This is the one scoring
--- loop, so no host or list keeps a copy of it, docs/PLAN-UNIFIED-SEARCH.md phase one.
function M.score(items, query, matcher)
  local entries = {}
  for i = 1, #items do
    local it = items[i]
    local score, level, within, atStart, phrase = matcher(query, haystackOf(it), fieldsOf(it))
    if score ~= nil then
      entries[#entries + 1] = {
        item = it, score = score, idx = i, level = level or 0, within = within or score,
        atStart = atStart == true, phrase = phrase == true, graded = level ~= nil,
        tier = tierOf(it), bonus = bonusOf(it),
      }
    end
  end
  return entries
end

--- M.before(a, b) -> true when entry a sorts ahead of entry b.
--- The one comparison, exposed for a consumer that puts something of its own ahead of it.
--- Tier ascending first. Then how good the match is, the level sum descending and the phrase
--- bonus ahead of none, which is exactly what the score already orders by, since the score
--- steps two spreads per level sum and one for the phrase. Then the row's bonus descending
--- inside that group, then the score descending, which is where a word landed, and the
--- original index ascending last, so a stable order the supplier already carries, the
--- launcher's own recency for one example, still shows through equal scores. Lua's sort is
--- not stable, which is why the index is folded in rather than relied on.
---
--- A matcher that answered only a score said nothing about the kind of match, so for its
--- rows only an equal score is equally good and the score decides before the bonus does.
--- Rows setting no tier and no bonus therefore order exactly as score then index did before
--- the fields existed. A field missing from an entry built elsewhere reads as its default.
function M.before(a, b)
  local ta, tb = a.tier or 0, b.tier or 0
  if ta ~= tb then return ta < tb end
  if a.graded and b.graded then
    if a.level ~= b.level then return a.level > b.level end
    if (a.phrase == true) ~= (b.phrase == true) then return a.phrase == true end
  elseif a.score ~= b.score then
    return a.score > b.score
  end
  local ba, bb = a.bonus or 0, b.bonus or 0
  if ba ~= bb then return ba > bb end
  if a.score ~= b.score then return a.score > b.score end
  return a.idx < b.idx
end

--- M.apply(items, query, matcher) -> a new list, the ranked items.
--- With matcher a function and query not empty, this owns filtering. Pinned rows are set
--- aside, the leading ones and the trailing ones, every other candidate is scored through
--- M.score, a nil score drops it, and the survivors are sorted by M.before. The answer is the
--- leading pinned rows, the ranked rows, then the trailing pinned rows. With no matcher, an
--- empty query, or matcher set to false, every candidate is kept in the order the supplier
--- gave them, pinned or not, since false means the supplier already owns its own filtering
--- and an empty query has nothing yet to score against.
function M.apply(items, query, matcher)
  if type(matcher) ~= "function" or query == "" then
    local out = {}
    for i = 1, #items do
      out[i] = items[i]
    end
    return out
  end

  -- The leading pinned rows are the run before the first unpinned one. A list without a
  -- pinned row hands M.score its own items, so the common case builds nothing extra.
  local lead, trail, rest = {}, {}, items
  local anyPinned = false
  for i = 1, #items do
    if items[i].pinned == true then anyPinned = true; break end
  end
  if anyPinned then
    rest = {}
    for i = 1, #items do
      local it = items[i]
      if it.pinned ~= true then
        rest[#rest + 1] = it
      elseif #rest == 0 then
        lead[#lead + 1] = it
      else
        trail[#trail + 1] = it
      end
    end
  end

  local ranked = M.score(rest, query, matcher)
  table.sort(ranked, M.before)

  local out = {}
  for i = 1, #lead do out[#out + 1] = lead[i] end
  for i = 1, #ranked do out[#out + 1] = ranked[i].item end
  for i = 1, #trail do out[#out + 1] = trail[i] end
  return out
end

return M
