--- === Chooser.match ===
---
--- Shared matching strategies for the Chooser atom. Each is a function
--- match(query, hay, fields) -> score or nil. A nil means the row does not match and is
--- dropped. A number is a rank, higher is better, and the atom sorts survivors by it
--- with the original order breaking ties, so a stable secondary order like the
--- launcher's recency still shows through. This is the concrete policy the design
--- principles separate from the mechanism, injected once from the composition root so
--- every chooser shares one matcher and swapping them all is a single edit.
---
--- hay is the row's text joined into one string, which substring and words search. fields,
--- built by lib/chooser/rank.lua, is the same row split into the fields fuzzy searches one at
--- a time, see M.fuzzy. A strategy is free to ignore fields.
---
--- fuzzy is the one search every list is moving onto, docs/PLAN-UNIFIED-SEARCH.md. The name
--- stays because the root and the manifests name it, though since 2026-10-17 it matches no
--- scattered letters at all. It answers four more values after the score, see M.fuzzy, which
--- rank.lua carries along for a consumer that has to tell a better kind of match from a
--- better scored one of the same kind and for the row that has to say why it is listed. A
--- caller reading only the first value loses nothing, the score alone orders every row.

local M = {}

local BYTE_A, BYTE_Z = string.byte("A"), string.byte("Z")
local BYTE_a, BYTE_z = string.byte("a"), string.byte("z")

local function isUpper(b) return b ~= nil and b >= BYTE_A and b <= BYTE_Z end
local function isLower(b) return b ~= nil and b >= BYTE_a and b <= BYTE_z end

-- A character that ends a word, so the next character starts one. Space and the common
-- name separators.
local SEP = {}
for _, ch in ipairs({ " ", "/", "\\", "-", "_", ".", ":", "(", ")", "[", "]", "@" }) do
  SEP[string.byte(ch)] = true
end

-- Scoring weights, which order rows inside one level. A matched character is worth MATCH plus
-- a bonus for where it lands. Extending a run (CONSEC) is worth the most, so a word matched
-- in one piece beats the same word split over several words. START rewards the very first
-- character of the field, BOUND a word start after a separator, CAMEL a camel hump. The gap
-- before the first matched character and after the last is nearly free, GAP_LEAD and
-- GAP_TRAIL, so an earlier word and a shorter field win a tie and nothing more.
local MATCH   = 1
local START   = 10
local BOUND   = 7
local CAMEL   = 6
local CONSEC  = 10
local GAP_LEAD  = -0.02
local GAP_TRAIL = -0.02

-- The most one matched character can ever earn, a match plus the largest bonus there is.
-- No match of a word of n characters scores above n times this, which is what the step
-- between levels below is derived from.
local TOP = MATCH + math.max(START, BOUND, CAMEL, CONSEC)

-- A query word gets one edit only from four letters on, and matches inside a word only from
-- three, Milos's call on 2026-10-17 after do listed every window command. Two letters with an
-- edit or inside a word match almost anything, so a short word must be meant as typed and at
-- a word start.
local TYPO_MIN = 4
local INSIDE_MIN = 3

-- The long body bound, in bytes. A field longer than this matches a word only at a word
-- start or, from INSIDE_MIN letters, inside a word, its best occurrence, never by pieces or
-- with an edit, which is what the words strategy did for clipboard bodies and file paths and
-- why this one search can replace it. Measured on 2026-10-17, decisions/olm-unified-search.md,
-- every launcher row's fields are under 200 bytes, so no name loses its pieces or its typo,
-- and a body past the bound costs about what the words strategy costs once its lowered copy
-- is kept.
local LONG = 256

-- The bonus for matching a query character at haystack position j (one based), read from
-- the original haystack so casing still informs the rank.
local function bonusAt(hay, j)
  if j == 1 then return START end
  local pb = hay:byte(j - 1)
  if SEP[pb] then return BOUND end
  if isLower(pb) and isUpper(hay:byte(j)) then return CAMEL end
  return 0
end

-- A long body lowered once rather than on every keystroke. Lowering a body costs an
-- allocation the size of the body, which the words strategy measured as four fifths of its
-- work, and a list asks the same bodies again on every key, so the lowered copy is kept,
-- keyed by the body itself. Lua does not intern a long string, but it computes a long
-- string's hash once and keeps it in the string, and a lookup compares the very string the
-- row already holds by identity before it would compare bytes, so finding the copy again is
-- cheap. The memo holds the body as its key as well as the copy, which keeps a body alive
-- after its row is gone, so both are counted against FOLD_BUDGET and the memo starts over
-- when it fills. That makes FOLD_BUDGET the real bound on what the memo holds, bodies and
-- copies together, and a list larger than it degrades to lowering per call, still correct.
--
-- A Lua pattern with a class of both cases per letter would avoid the copy altogether, and
-- was measured and rejected on 2026-10-17, decisions/olm-unified-search.md. The pattern
-- matcher steps through the body a byte at a time in Lua's own matcher, where a plain find
-- is a C level scan, and it came out four times slower than lowering on every call.
local FOLD_BUDGET = 8 * 1024 * 1024
local folded, foldedBytes = {}, 0
local function lowered(hay)
  local low = folded[hay]
  if low then return low end
  low = hay:lower()
  local cost = #hay + #low
  foldedBytes = foldedBytes + cost
  if foldedBytes > FOLD_BUDGET then
    folded, foldedBytes = {}, cost
  end
  folded[hay] = low
  return low
end

-- Whether a word of the field starts at position j, the very first byte, a byte after a
-- separator, or a camel hump. The same three places bonusAt rewards, so the levels and the
-- scoring never disagree about where a word begins.
local function startsWord(hay, j)
  return bonusAt(hay, j) > 0
end

-- Whether a byte can be part of a word. A letter, a digit, or any byte of a non ASCII
-- character. A standalone symbol such as the ampersand in Printers & Scanners is not a word,
-- so ps finds it, since nobody types the ampersand when spelling a name by its pieces.
local function wordByte(b)
  return b ~= nil and (b >= 128 or string.char(b):match("%w") ~= nil)
end

-- The words of a field, each { s, e } by byte position. A word begins where startsWord says
-- and runs until a byte that is no word byte or begins the next word, so a camel hump splits
-- one, macOS Settings reads as mac, OS, Settings.
local function wordsOf(hay)
  local list, m, j = {}, #hay, 1
  while j <= m do
    if wordByte(hay:byte(j)) and startsWord(hay, j) then
      local e = j
      while e < m and wordByte(hay:byte(e + 1)) and not startsWord(hay, e + 1) do e = e + 1 end
      list[#list + 1] = { s = j, e = e }
      j = e + 1
    else
      j = j + 1
    end
  end
  return list
end

-- Where the piece after one at word wi may start. The next word always, and past it any later
-- word of the same token, the run of words a camel hump splits with nothing between them, up to
-- and including the first word of the next token. So a camel hump offers a piece start without
-- demanding one, DaVinci Control Panels answers dcp and dvcp alike, and YouTube Music answers
-- ym as well as ytm.
local function nextStarts(hay, words, wi)
  local out = {}
  local k = wi + 1
  while k <= #words do
    out[#out + 1] = k
    if words[k].s ~= words[k - 1].e + 1 then break end
    k = k + 1
  end
  return out
end

-- Whether two neighbouring words belong to one phrase. Clause punctuation between them, a
-- comma, a semicolon, a question or exclamation mark, ends a phrase, so pieces never span
-- "disconnect, or join" in a sentence and a declared list "a, b" keeps its phrases apart.
local function samePhrase(hay, left, right)
  return hay:sub(left.e + 1, right.s - 1):find("[,;!?]") == nil
end

-- A query word as a list of bytes, where 0 stands for any one byte of a word, which is how
-- the one edit variants below say a letter is wrong or missing.
local WILD = 0
local function bytesOf(word)
  local q = {}
  for i = 1, #word do q[i] = word:byte(i) end
  return q
end
local function same(qb, hb)
  return qb == hb or (qb == WILD and wordByte(hb))
end

-- The score of the pieces of one match, each { pos, len }, the first character of a piece
-- earning its word start bonus and every later one extending the run, plus the near free
-- gaps before the first piece and after the last.
local function piecesScore(hay, first, lastEnd, sum)
  return sum + (first - 1) * GAP_LEAD + (#hay - lastEnd) * GAP_TRAIL
end
local function pieceScore(hay, pos, len)
  return bonusAt(hay, pos) + MATCH + (len - 1) * (CONSEC + MATCH)
end

-- Level A, the word at the start of a word of the field, the best such place, answering its
-- score or nil.
local function atWordStart(q, hay, hlow, words)
  local n, best = #q, nil
  for _, w in ipairs(words) do
    local ok = w.s + n - 1 <= #hay
    for i = 1, n do
      if not ok then break end
      ok = same(q[i], hlow:byte(w.s + i - 1))
    end
    if ok then
      local s = piecesScore(hay, w.s, w.s + n - 1, pieceScore(hay, w.s, n))
      if best == nil or s > best then best = s end
    end
  end
  return best
end

-- Level B, the word split into two or more pieces, each the start of one of a run of
-- consecutive words in one phrase, in order, every piece at least one letter. Initials are
-- the case where every piece is one letter. The best split is kept, and since a piece's first
-- letter earns a word start bonus where a continued run earns more, fewer pieces score higher.
local function inPieces(q, hay, hlow, words)
  local n = #q
  local memo = {}
  -- The best score for q[qi..n] with its first piece at word wi, the trailing gap included,
  -- or nil.
  local function rest(qi, wi)
    local key = qi * 4096 + wi
    if memo[key] ~= nil then return memo[key] or nil end
    local w, best = words[wi], nil
    local len = w.e - w.s + 1
    for L = 1, math.min(n - qi + 1, len) do
      if not same(q[qi + L - 1], hlow:byte(w.s + L - 1)) then break end
      local here = pieceScore(hay, w.s, L)
      local total
      if qi + L - 1 == n then
        total = here + (#hay - (w.s + L - 1)) * GAP_TRAIL
      else
        for _, k in ipairs(nextStarts(hay, words, wi)) do
          if samePhrase(hay, words[k - 1], words[k]) then
            local after = rest(qi + L, k)
            if after and (total == nil or here + after > total) then total = here + after end
          end
        end
      end
      if total and (best == nil or total > best) then best = total end
    end
    memo[key] = best or false
    return best
  end
  local best = nil
  for wi = 1, #words - 1 do
    local w = words[wi]
    local len = w.e - w.s + 1
    for L = 1, math.min(n - 1, len) do
      if not same(q[L], hlow:byte(w.s + L - 1)) then break end
      for _, k in ipairs(nextStarts(hay, words, wi)) do
        if samePhrase(hay, words[k - 1], words[k]) then
          local after = rest(L + 1, k)
          if after then
            local total = pieceScore(hay, w.s, L) + after + (w.s - 1) * GAP_LEAD
            if best == nil or total > best then best = total end
          end
        end
      end
    end
  end
  return best
end

-- Level A then B, the two forms a name and a declared term are both matched in.
local function startOrPieces(q, hay, hlow, words)
  return atWordStart(q, hay, hlow, words) or inPieces(q, hay, hlow, words)
end

-- Level C, A or B with exactly one edit, a letter dropped, doubled, wrong, or two neighbours
-- swapped. Each edit becomes a variant of the word, a wrong or missing letter written as a
-- wildcard, and the best variant matching as A or B is kept.
local function withOneEdit(word, hay, hlow, words)
  local q = bytesOf(word)
  local n = #q
  local variants = {}
  for i = 1, n do
    local d, s = {}, {}
    for k = 1, n do
      if k ~= i then d[#d + 1] = q[k] end
      s[k] = (k == i) and WILD or q[k]
    end
    variants[#variants + 1] = d
    variants[#variants + 1] = s
    if i < n then
      local t = {}
      for k = 1, n do t[k] = q[k] end
      t[i], t[i + 1] = q[i + 1], q[i]
      variants[#variants + 1] = t
    end
  end
  for i = 1, n + 1 do
    local ins = {}
    for k = 1, n do
      if k == i then ins[#ins + 1] = WILD end
      ins[#ins + 1] = q[k]
    end
    if i == n + 1 then ins[#ins + 1] = WILD end
    variants[#variants + 1] = ins
  end
  -- Every form here starts at the start of a word, so a variant whose first letter starts no
  -- word is skipped before it is tried, which is most of them on a long name.
  local starts = {}
  for _, w in ipairs(words) do starts[hlow:byte(w.s)] = true end
  local best = nil
  for _, v in ipairs(variants) do
    if v[1] == WILD or starts[v[1]] then
      local s = startOrPieces(v, hay, hlow, words)
      if s and (best == nil or s > best) then best = s end
    end
  end
  return best
end

-- Level D, the word whole inside a word, its earliest place, which earns the most.
local function insideWord(word, hay, hlow)
  local pos = hlow:find(word, 1, true)
  if not pos then return nil end
  local n = #word
  return piecesScore(hay, pos, pos + n - 1, pieceScore(hay, pos, n))
end

-- A long field. Only a word start, its best occurrence, or from INSIDE_MIN letters the word
-- inside a word, its first. The leading gap is counted only up to LONG and the trailing gap
-- not at all, which keeps every score inside the range the step is derived for.
local function longField(word, hay, hlow, allowInside)
  local n, first, init = #word, nil, 1
  local function scored(pos)
    local lead = math.min(pos - 1, LONG)
    return lead * GAP_LEAD + pieceScore(hay, pos, n)
  end
  while true do
    local pos = hlow:find(word, init, true)
    if not pos then break end
    if startsWord(hay, pos) then return true, scored(pos) end
    first = first or pos
    init = pos + 1
  end
  if first and allowInside and n >= INSIDE_MIN then return false, scored(first) end
  return nil
end

-- The levels a word can match at, strongest first. The number is what a word adds to its
-- row's level sum, so a stronger level is a larger number. Every name level outranks the
-- declared one.
local LEVEL = { nameStart = 4, namePieces = 3, nameEdit = 2, nameInside = 1, declared = 0 }
M.LEVEL = LEVEL

-- One lowered word against the name, answering its level and score, or nil.
local function matchName(word, name)
  if name == nil or name == "" then return nil end
  if #name > LONG then
    local atStart, score = longField(word, name, lowered(name), true)
    if atStart == nil then return nil end
    return atStart and LEVEL.nameStart or LEVEL.nameInside, score
  end
  local hlow = name:lower()
  local words = wordsOf(name)
  local q = bytesOf(word)
  local s = atWordStart(q, name, hlow, words)
  if s then return LEVEL.nameStart, s end
  s = inPieces(q, name, hlow, words)
  if s then return LEVEL.namePieces, s end
  if #word >= TYPO_MIN then
    s = withOneEdit(word, name, hlow, words)
    if s then return LEVEL.nameEdit, s end
  end
  if #word >= INSIDE_MIN then
    s = insideWord(word, name, hlow)
    if s then return LEVEL.nameInside, s end
  end
  return nil
end

-- The phrase of a declared field holding position pos, the text between the clause
-- punctuation around it, trimmed, which is what a row shows to say why it is listed.
local function phraseAt(text, pos)
  local from = 1
  for p in text:gmatch("()[,;]") do
    if p < pos then from = p + 1 else
      return (text:sub(from, p - 1):gsub("^%s+", ""):gsub("%s+$", ""))
    end
  end
  return (text:sub(from):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- One lowered word against the secondary fields, word start or pieces only, the best field
-- kept, answering its score and, when that field is not shown on the row, the phrase that
-- matched.
local function matchDeclared(word, secondary)
  local best, shown
  for _, f in ipairs(secondary or {}) do
    local text = f.text
    if type(text) == "string" and text ~= "" then
      local s, pos
      if #text > LONG then
        local atStart
        atStart, s = longField(word, text, lowered(text), false)
        if atStart then pos = lowered(text):find(word, 1, true) end
      else
        local hlow, words = text:lower(), wordsOf(text)
        local q = bytesOf(word)
        s = atWordStart(q, text, hlow, words)
        if s then
          for _, w in ipairs(words) do
            if hlow:sub(w.s, w.s + #word - 1) == word then pos = w.s; break end
          end
        else
          s = inPieces(q, text, hlow, words)
          if s then
            for _, w in ipairs(words) do
              if hlow:byte(w.s) == word:byte(1) then pos = w.s; break end
            end
          end
        end
      end
      if s and (best == nil or s > best) then
        best = s
        shown = (not f.visible and pos) and phraseAt(text, pos) or nil
      end
    end
  end
  return best, shown
end

--- M.fuzzy(query, hay, fields) -> score, level, within, atStart, shown, or nil
--- The one search, docs/PLAN-UNIFIED-SEARCH.md phase one, as Milos settled it on 2026-10-17
--- after the live test. A row has a primary field, its name, and secondary fields, the text it
--- shows or declares on purpose. fields is { primary = string, secondary = { { text, visible
--- }, ... } } as lib/chooser/rank.lua builds it. Without fields, hay is the name and there is
--- nothing secondary, which is how a plugin scoring its own strings calls it.
---
--- A word never matches across fields. Each query word, lowered, matches at the strongest of
--- five levels.
---   A. In the name, at the start of a word. lose in Loser, se in Settings.
---   B. In the name, in pieces, each the start of one of a run of consecutive words in one
---      phrase. lose in LOcal SErvers, os in OLM settings, initials being every piece one
---      letter. A standalone symbol such as an ampersand is no word.
---   C. In the name, A or B with exactly one edit, from four letters on. dokcer finds Docker.
---   D. In the name, whole inside a word, from three letters on. Two letters never do, so do
---      does not find Window.
---   E. In a secondary field, A or B only, below every name level.
--- There is no scattered match and so no relevance floor, since everything the levels accept
--- is a deliberate way of naming a row, and the floor existed only to cut scattered noise.
---
--- Every word is required, scored on its own, and summed, so google chrome finds nothing in a
--- row titled Chrome. A row's level is the sum of its words' levels. The step between level
--- sums is derived per query from the weights. A word of n letters matched by any variant
--- scores at most n plus one times TOP, the one being an inserted letter, and more than minus
--- LONG times the near free gap, since a short field pays at most its length in gap and a long
--- one has its gap capped. So two rows at one level sum differ by less than the sum over the
--- words of that spread, the step is that sum, and a row with a higher level sum always
--- scores higher. The score stays the single number lib/chooser/rank.lua sorts on.
---
--- The later answers are for consumers. level is the row's level sum, within its score
--- inside the level, atStart whether every word matched the name at a word start, which the
--- launcher's memory gate reads, and shown the declared phrase a word matched in when that
--- phrase is not on the row already, which rank.lua puts into the subtitle so a person sees
--- why the row is listed.
function M.fuzzy(query, hay, fields)
  local words = {}
  for word in query:lower():gmatch("%S+") do words[#words + 1] = word end
  if #words == 0 then return 0, 0, 0, true, nil end
  local name = fields and fields.primary or hay
  local secondary = fields and fields.secondary

  local level, within, step, atStart, shownList = 0, 0, 0, true, nil
  for _, word in ipairs(words) do
    local wordLevel, score = matchName(word, name)
    local shown
    if not wordLevel then
      score, shown = matchDeclared(word, secondary)
      if not score then return nil end
      wordLevel = LEVEL.declared
    end
    level = level + wordLevel
    within = within + score
    if wordLevel ~= LEVEL.nameStart then atStart = false end
    if shown then
      shownList = shownList or {}
      shownList[#shownList + 1] = shown
    end
    step = step + (#word + 1) * TOP + LONG * math.max(-GAP_LEAD, -GAP_TRAIL)
  end
  local shownText = shownList and table.concat(shownList, ", ") or nil
  return level * step + within, level, within, atStart, shownText
end

--- M.substring(query, hay) -> score or nil
--- The pre fuzzy behaviour, kept as the second strategy behind the same seam. A plain
--- case insensitive substring test, no typo tolerance and no floor. Every match scores
--- zero, so the atom leaves matches in their natural order, exactly what the choosers
--- did before, so injecting this at the root reproduces the old lists. Phase three of
--- docs/PLAN-UNIFIED-SEARCH.md retires it.
function M.substring(query, hay)
  local q = query:lower()
  if q == "" then return 0 end
  return (hay:lower():find(q, 1, true) and 0) or nil
end

--- M.words(query, hay) -> score or nil
--- The clipboard strategy, a word tokenizer rather than a subsequence scorer. The query
--- is split on whitespace and the row is kept only when every word appears as a case
--- insensitive substring of the haystack, in any order. So the words need not be adjacent,
--- "hello there" finds "hello everyone there", and a partial word or a prefix still hits,
--- "hel" finds "hello". There is no typo tolerance and no ranking, every match scores zero
--- so the consumer's own order is kept. It is a handful of plain byte scans with no dynamic
--- program and no allocation, which is why it can search the full body of a long clipboard
--- entry on every keystroke where fuzzy could not without a cut. Clipboard entries are prose
--- and code searched from the inside, where you type a real word you remember, so this fits
--- them and fuzzy does not. The one thing it will not forgive is a wrong letter inside a
--- word, the deliberate trade for searching the whole body with nothing truncated. fuzzy
--- now carries the same rule for any haystack past its long body bound, and phase three of
--- docs/PLAN-UNIFIED-SEARCH.md retires this strategy once the lists naming it move over.
---
--- Unlike fuzzy and substring, this folds case only on the query, not the haystack. The
--- haystack is compared verbatim, so the caller must lower it once when it builds it, as the
--- clipboard does in its cached searchable text. Re folding a long body on every keystroke
--- is exactly the cost this strategy exists to avoid, and it measured as four fifths of the
--- work, so a matcher meant for big bodies must never do it per call.
function M.words(query, hay)
  for word in query:lower():gmatch("%S+") do
    if not hay:find(word, 1, true) then return nil end
  end
  return 0
end

return M
