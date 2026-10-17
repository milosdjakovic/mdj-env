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
-- names is a list of strings, further names of the row that are never shown, a tab's host and
-- address beside its title, a clipboard entry's body, settled 2026-10-17 for phase three. Each
-- is matched at the name levels A to D exactly like the title, or like filterText when the row
-- sets it, since names add to the primary rather than replace it. Each query word takes its
-- best level across the primary and the names, so two words may land in two names, but one
-- word never spans two names and pieces stay inside one. The best is taken and never a sum, so
-- a row never scores higher for having more names than an equal row with fewer. A long name
-- follows the 256 byte rule in lib/chooser/match.lua. A strategy that reads one string, words
-- or substring, never sees names, since joining a body of megabytes into one string on every
-- key is the cost the shared search exists to avoid.
--
-- Four fields say where a row goes rather than what it answers to, settled 2026-10-17 for
-- phase two. A field of the wrong type is read as absent.
-- pinned, when true, means the row is never scored and never dropped. It is a row that always
-- shows whatever is typed, Back, New snapshot, Apply now, a placeholder. On an empty query it
-- keeps its place in the supplier's order like every row. Under a typed query every pinned row
-- trails, after every ranked row, in the supplier's order, wherever the supplier put it, so the
-- first row, which takes the highlight and Enter, is always the best match and never a door.
-- fromQuery, when true, means the row was made from what was typed, a calculator answer, a
-- conversion, a window size, a scope's rows already filtered by its own query, a waiting row
-- for that query. It is never scored and never dropped either, and under a typed query every
-- such row leads, ahead of every ranked row, in the supplier's order, since its supplier
-- already decided it is the answer to this query. On an empty query it keeps its place like
-- every row. A row setting both is a fromQuery row.
-- tier is a number, zero when absent, and a smaller tier sorts first among ranked rows, ahead
-- of how well a row matched, so a list can keep one kind of row above another.
-- bonus is a number from zero to one, clamped, zero when absent. It orders only rows the
-- matcher calls equally good, the same tier, the same level sum and the same phrase bonus,
-- and there it leads before where a word landed. It never lifts a row over a better match,
-- which is what makes it safe to feed from recency or frecency.
--
-- Two more belong to the list rather than to a row, settled 2026-10-17 for phase three, and
-- reach M.apply as its search argument, see searchTextOf below. searchText turns the raw field
-- text into the text ranked by, so a field's own grammar stays in its plugin, and rowLimit cuts
-- the rows that are neither pinned nor fromQuery after ranking, for a list of thousands.

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
-- { primary, names, secondary = { { text, declared }, ... } }, declared marking keywords,
-- which also answer a phrase typed run together where the subtitle does not. names is the
-- row's own list handed over as it is, never copied, since a clipboard body in it can run to
-- megabytes and this runs for every row on every key. The search skips an entry that is not
-- a string.
local function fieldsOf(it)
  local names = type(it.names) == "table" and it.names or nil
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
  return { primary = type(primary) == "string" and primary or "", names = names, secondary = secondary }
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
--- pinned and fromQuery are not read here, M.apply keeps those rows out of the loop. This is
--- the one scoring loop, so no host or list keeps a copy of it, docs/PLAN-UNIFIED-SEARCH.md
--- phase one.
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

-- How good a match an entry is, as two numbers compared descending, the first key and whether
-- the phrase bonus was earned. A graded entry answers its level sum and its phrase. An ungraded
-- one, from a matcher that answered only a score, was told nothing about the kind of match, so
-- its score stands in for the level and it never has the phrase. Every entry maps to the same
-- fixed pair whoever it is compared with, which is what keeps M.before a strict weak ordering
-- when graded and ungraded entries meet in one sort.
local function matchKey(e)
  if e.graded then return e.level or 0, e.phrase == true and 1 or 0 end
  return e.score or 0, 0
end

--- M.before(a, b) -> true when entry a sorts ahead of entry b.
--- The one comparison, exposed for a consumer that puts something of its own ahead of it. It is
--- lexicographic over one fixed tuple per entry, tier ascending, the match key descending, the
--- phrase descending, the row's bonus descending, the score descending, which is where a word
--- landed, and the original index ascending last. The match key is the level sum for a graded
--- entry and the score for an ungraded one, matchKey above.
---
--- For a graded list that orders by level sum and phrase first, which is exactly what the score
--- already orders by, since the score steps two spreads per level sum and one for the phrase,
--- then lets the bonus decide among equally good rows. For an ungraded list the score comes
--- first, so only an equal score is equally good and the bonus orders only those. Rows setting
--- no tier and no bonus therefore order exactly as score then index did before the fields
--- existed. The index keeps a stable order the supplier already carries, the launcher's own
--- recency for one example, showing through equal scores, and Lua's sort is not stable, which
--- is why it is folded in rather than relied on. A field missing from an entry built elsewhere
--- reads as its default.
function M.before(a, b)
  local ta, tb = a.tier or 0, b.tier or 0
  if ta ~= tb then return ta < tb end
  local ka, pa = matchKey(a)
  local kb, pb = matchKey(b)
  if ka ~= kb then return ka > kb end
  if pa ~= pb then return pa > pb end
  local ba, bb = a.bonus or 0, b.bonus or 0
  if ba ~= bb then return ba > bb end
  local sa, sb = a.score or 0, b.score or 0
  if sa ~= sb then return sa > sb end
  return a.idx < b.idx
end

-- How the presentation asks its rows to be searched, beside the matcher, settled 2026-10-17 for
-- phase three. search is a table or nil, and a field of the wrong type is read as absent.
-- searchText is a function taking the raw text of the field and answering the text the engine
-- ranks by, for a list whose field carries its own grammar, FileSearch ranking ~/dev .js foo by
-- foo, the clipboard ranking img cat by cat. The grammar stays in the plugin. An empty answer,
-- or one of spaces only, ranks nothing and keeps the supplier's order, the same as an empty
-- query. An answer that raises or is not a string is treated as empty, and M.apply hands the
-- reason back so the caller can say so, since the list must never stop working over it.
-- rowLimit is a positive whole number, the most rows a list shows that are neither pinned nor
-- fromQuery, taken after ranking, so the best rows are the ones kept and a pinned or fromQuery
-- row is never cut. It bounds what a provider builds for a list of thousands of rows, the
-- emoji set among them, since a provider styles every row it is handed.
local function searchTextOf(search)
  local f = type(search) == "table" and search.searchText or nil
  return type(f) == "function" and f or nil
end
local function rowLimitOf(search)
  local n = type(search) == "table" and search.rowLimit or nil
  if type(n) == "number" and n >= 1 and n % 1 == 0 then return n end
  return nil
end

-- The list cut to at most limit rows that are neither pinned nor fromQuery, every kept row
-- left where it stands. A list within the limit is answered as it is.
local function limited(list, limit)
  if not limit or #list <= limit then return list end
  local out, counted = {}, 0
  for i = 1, #list do
    local it = list[i]
    if it.fromQuery == true or it.pinned == true then
      out[#out + 1] = it
    elseif counted < limit then
      counted = counted + 1
      out[#out + 1] = it
    end
  end
  return out
end

-- The supplier's order, a copy, cut to the limit.
local function supplierOrder(items, limit)
  local out = {}
  for i = 1, #items do
    out[i] = items[i]
  end
  return limited(out, limit)
end

--- M.apply(items, query, matcher, search) -> a new list, the ranked items, and a reason or nil.
--- With matcher a function and query not empty, this owns filtering. search, when given, says
--- how, see searchTextOf above. The query is first turned into the text to rank by through
--- searchText when the search declares one, and an empty answer keeps the supplier's order. The
--- fromQuery rows and the pinned rows are set aside, every other candidate is scored through
--- M.score, a nil score drops it, and the survivors are sorted by M.before. The answer is the
--- fromQuery rows, the ranked rows, then the pinned rows, each kept group in the supplier's
--- order. With no matcher, an empty query, or matcher set to false, every candidate is kept in
--- the order the supplier gave them, whatever it sets, since false means the supplier already
--- owns its own filtering and an empty query has nothing yet to score against. Either way a
--- search's rowLimit then cuts the rows that are neither pinned nor fromQuery. The second
--- answer is the reason a searchText failed, nil when nothing did.
function M.apply(items, query, matcher, search)
  local limit = rowLimitOf(search)
  if type(matcher) ~= "function" or query == "" then
    return supplierOrder(items, limit)
  end

  local reason
  local searchText = searchTextOf(search)
  if searchText then
    local ok, answer = pcall(searchText, query)
    if not ok then
      reason = "searchText raised, " .. tostring(answer)
      answer = ""
    elseif type(answer) ~= "string" then
      reason = "searchText answered a " .. type(answer) .. ", not a string"
      answer = ""
    end
    if not answer:find("%S") then return supplierOrder(items, limit), reason end
    query = answer
  end

  -- A list with no kept row hands M.score its own items, so the common case builds nothing
  -- extra.
  local lead, trail, rest = {}, {}, items
  local anyKept = false
  for i = 1, #items do
    local it = items[i]
    if it.fromQuery == true or it.pinned == true then anyKept = true; break end
  end
  if anyKept then
    rest = {}
    for i = 1, #items do
      local it = items[i]
      if it.fromQuery == true then
        lead[#lead + 1] = it
      elseif it.pinned == true then
        trail[#trail + 1] = it
      else
        rest[#rest + 1] = it
      end
    end
  end

  local ranked = M.score(rest, query, matcher)
  table.sort(ranked, M.before)

  local out = {}
  for i = 1, #lead do out[#out + 1] = lead[i] end
  for i = 1, #ranked do
    if limit and i > limit then break end
    out[#out + 1] = ranked[i].item
  end
  for i = 1, #trail do out[#out + 1] = trail[i] end
  return out, reason
end

return M
