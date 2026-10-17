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

-- A byte that is part of a word. An ASCII letter or digit, or a byte of a non ASCII character
-- that is not one of the separators below. Every other byte ends a word, a space, a hyphen, a
-- slash, an ampersand, a dollar sign, so the next word byte starts one.
local ALNUM = {}
for b = 0, 127 do ALNUM[b] = string.char(b):match("%w") ~= nil end

-- Non ASCII characters that separate rather than spell, by their UTF-8 bytes. The middle dot
-- and the triangle are how subtitles and menu paths here join their parts, and the others are
-- their usual neighbours. Each of them also ends a phrase, see BREAK.
local MULTI_SEP = { "\u{00B7}", "\u{25B8}", "\u{2022}", "\u{2014}", "\u{2013}", "\u{203A}", "\u{2192}" }

-- ASCII punctuation that ends a phrase, so pieces never span "disconnect, or" and a declared
-- string "a, b" holds two phrases. The non ASCII separators above end one too, the same set
-- for matching and for the phrase a row shows, so the two never disagree.
local BREAK = { [string.byte(",")] = true, [string.byte(";")] = true,
                [string.byte("!")] = true, [string.byte("?")] = true }

-- The length of the non ASCII separator starting at byte j of s, or nil.
local function multiSepAt(s, j)
  local b = s:byte(j)
  if b == nil or b < 128 then return nil end
  for _, seq in ipairs(MULTI_SEP) do
    local ok = true
    for k = 1, #seq do
      if s:byte(j + k - 1) ~= seq:byte(k) then ok = false; break end
    end
    if ok then return #seq end
  end
  return nil
end

-- Whether byte j of s is a word byte, for a field that has not been prepared. A non ASCII
-- byte is looked at in the context of the separators that could hold it.
local function wordByteAt(s, j)
  local b = s:byte(j)
  if b == nil then return false end
  if b < 128 then return ALNUM[b] end
  for back = 0, 2 do
    local len = (j - back >= 1) and multiSepAt(s, j - back) or nil
    if len and len > back then return false end
  end
  return true
end

-- Scoring weights, which order rows inside one level. A matched character is worth MATCH plus
-- a bonus for where it lands. Extending a run (CONSEC) is worth the most, so a word matched
-- in one piece beats the same word split over several words. START rewards the very first
-- character of the field, BOUND a word start after anything that is no word byte, CAMEL a
-- camel hump. The gap before the first matched character and after the last is nearly free,
-- GAP_LEAD and GAP_TRAIL, so an earlier word and a shorter field win a tie and nothing more.
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

-- The long field bound, in bytes. A field longer than this matches a word only at a word
-- start or, from INSIDE_MIN letters, inside a word, its best occurrence, never by pieces or
-- with an edit, which is what the words strategy did for clipboard bodies and file paths and
-- why this one search can replace it. Every launcher row's fields measured under 200 bytes on
-- 2026-10-17, so no name loses its pieces or its typo.
local LONG = 256

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

-- The bonus a word starting at byte j earns, or zero when no word starts there. The first
-- byte, a byte after anything that is no word byte, or a camel hump.
local function startBonus(s, j, isWord)
  if not isWord(s, j) then return 0 end
  if j == 1 then return START end
  if not isWord(s, j - 1) then return BOUND end
  if isLower(s:byte(j - 1)) and isUpper(s:byte(j)) then return CAMEL end
  return 0
end

-- A short field read once and kept, the same idea as the lowered memo and for the same reason,
-- a list asks the same names on every key. A field becomes its lowered text, its words each
-- { s, e, bonus }, the words by their first lowered byte, and for each word whether a phrase
-- ends after it and whether the next word follows with nothing between, a camel hump. Short
-- strings are interned in Lua, so the key is cheap. PREP_LIMIT bounds the memo by entries and
-- it starts over when full.
local PREP_LIMIT = 20000
local prepared, preparedCount = {}, 0
local function prepare(s)
  local p = prepared[s]
  if p then return p end
  local m = #s
  -- Which bytes are word bytes, worked out once so a separator's bytes are known everywhere.
  local wb = {}
  local j = 1
  while j <= m do
    local len = multiSepAt(s, j)
    if len then
      for k = j, j + len - 1 do wb[k] = false end
      j = j + len
    else
      local b = s:byte(j)
      wb[j] = (b >= 128) or ALNUM[b]
      j = j + 1
    end
  end
  local function isWord(_, k) return wb[k] == true end
  local words, byFirst = {}, {}
  local low = s:lower()
  j = 1
  while j <= m do
    local bonus = startBonus(s, j, isWord)
    if bonus > 0 then
      local e = j
      while e < m and wb[e + 1] and startBonus(s, e + 1, isWord) == 0 do e = e + 1 end
      local w = { s = j, e = e, bonus = bonus }
      words[#words + 1] = w
      local fb = low:byte(j)
      local list = byFirst[fb]
      if not list then list = {}; byFirst[fb] = list end
      list[#list + 1] = #words
      j = e + 1
    else
      j = j + 1
    end
  end
  -- Between each word and the next, whether a phrase ends and whether they touch.
  for k = 1, #words - 1 do
    local w, nx = words[k], words[k + 1]
    w.joined = (nx.s == w.e + 1)
    local broken = false
    local g = w.e + 1
    while g < nx.s do
      local b = s:byte(g)
      if BREAK[b] or multiSepAt(s, g) then broken = true; break end
      g = g + 1
    end
    w.breakAfter = broken
  end
  p = { low = low, words = words, byFirst = byFirst, wb = wb }
  preparedCount = preparedCount + 1
  if preparedCount > PREP_LIMIT then prepared, preparedCount = {}, 1 end
  prepared[s] = p
  return p
end

-- The score of a match from its pieces, the sum of the pieces plus the near free gaps before
-- the first and after the last.
local function framed(m, first, lastEnd, sum)
  return sum + (first - 1) * GAP_LEAD + (m - lastEnd) * GAP_TRAIL
end
local function pieceScore(bonus, len)
  return bonus + MATCH + (len - 1) * (CONSEC + MATCH)
end

-- Whether the lowered word w sits at byte s of the lowered text low.
local function prefixAt(low, s, w)
  for i = 1, #w do
    if low:byte(s + i - 1) ~= w:byte(i) then return false end
  end
  return true
end

-- Level A, the word at the start of a word of the field, the best such place. Answers the
-- score and where it starts, or nil.
local function atWordStart(w, s, p)
  local list = p.byFirst[w:byte(1)]
  if not list then return nil end
  local best, at, m = nil, nil, #s
  for _, k in ipairs(list) do
    local word = p.words[k]
    if prefixAt(p.low, word.s, w) then
      local sc = framed(m, word.s, word.s + #w - 1, pieceScore(word.bonus, #w))
      if best == nil or sc > best then best, at = sc, word.s end
    end
  end
  return best, at
end

-- Level B, the word in two or more pieces, each the start of a word, the words consecutive and
-- in one phrase, initials being every piece one letter. After a piece the next may start at
-- the next word, or further along the same camel joined token up to the first word of the
-- next token, so a camel hump offers a piece start without demanding one, DaVinci Control
-- Panels answering dcp. The best split is kept, and since a piece's first letter earns a word
-- start bonus where a continued run earns more, fewer pieces score higher. The work is a memo
-- over the query position and the word, so it is bounded by the word length times the number
-- of words times the longest word, linear in the field for a fixed query.
local function inPieces(w, s, p)
  local first = p.byFirst[w:byte(1)]
  if not first then return nil end
  local n, words, low, m = #w, p.words, p.low, #s
  local memo = {}
  local rest
  -- The best for the next piece after word k, starting the query at qi.
  local function after(qi, k)
    local best = nil
    local j = k + 1
    while j <= #words do
      local prev = words[j - 1]
      if prev.breakAfter then break end
      local r = rest(qi, j)
      if r and (best == nil or r > best) then best = r end
      -- A word that does not touch the next ended its token, so the word after it was the
      -- last candidate.
      if not prev.joined then break end
      j = j + 1
    end
    return best
  end
  rest = function(qi, k)
    local key = qi * 1024 + k
    local hit = memo[key]
    if hit ~= nil then return hit or nil end
    local word = words[k]
    local best = nil
    local len = word.e - word.s + 1
    local L = 0
    while L < len and qi + L <= n and low:byte(word.s + L) == w:byte(qi + L) do
      L = L + 1
      local here = pieceScore(word.bonus, L)
      local total
      if qi + L - 1 == n then
        total = here + (m - (word.s + L - 1)) * GAP_TRAIL
      else
        local a = after(qi + L, k)
        if a then total = here + a end
      end
      if total and (best == nil or total > best) then best = total end
    end
    memo[key] = best or false
    return best
  end
  local best, at = nil, nil
  for _, k in ipairs(first) do
    local word = words[k]
    local len = word.e - word.s + 1
    local L = 0
    while L < len and L < n - 1 and low:byte(word.s + L) == w:byte(1 + L) do
      L = L + 1
      local a = after(1 + L, k)
      if a then
        local total = pieceScore(word.bonus, L) + a + (word.s - 1) * GAP_LEAD
        if best == nil or total > best then best, at = total, word.s end
      end
    end
  end
  return best, at
end

-- Whether the lowered word w matches at byte s of low with exactly one edit, as a word start
-- match, level C. The first letter is never edited, it is already known to match. Allowed are
-- two neighbours swapped anywhere after the first letter, docekr for Docker, and a letter
-- wrong, extra or missing strictly inside the word, dokcer and dcoker. A wrong or extra last
-- letter is not allowed, since dropping it leaves a shorter prefix that already reads as a word
-- start, note would find Notifications and show Shortcuts. A letter standing in or inserted
-- must be a word byte, so an edit never reaches across a space.
local function oneEditAt(low, s, w, wb)
  local n = #w
  local i = 2
  while i <= n and low:byte(s + i - 1) == w:byte(i) do i = i + 1 end
  if i > n then return false end
  local function restEq(wi, ti)
    for x = 0, n - wi do
      if low:byte(ti + x) ~= w:byte(wi + x) then return false end
    end
    return true
  end
  local here = s + i - 1
  if i < n then
    if wb(here) and restEq(i + 1, here + 1) then return true end
    if restEq(i + 1, here) then return true end
    if low:byte(here) == w:byte(i + 1) and low:byte(here + 1) == w:byte(i) and restEq(i + 2, here + 2) then
      return true
    end
  end
  return wb(here) and restEq(i, here + 1)
end

-- Level C, the best word start where the word matches with one edit.
local function withOneEdit(w, s, p)
  local list = p.byFirst[w:byte(1)]
  if not list then return nil end
  local best, m = nil, #s
  local function wb(k) return p.wb[k] == true end
  for _, k in ipairs(list) do
    local word = p.words[k]
    if oneEditAt(p.low, word.s, w, wb) then
      local sc = framed(m, word.s, math.min(m, word.s + #w - 1), pieceScore(word.bonus, #w))
      if best == nil or sc > best then best = sc end
    end
  end
  return best
end

-- Level D, the word whole inside a word, its earliest place, which earns the most.
local function insideWord(w, low, m)
  local pos = low:find(w, 1, true)
  if not pos then return nil end
  return framed(m, pos, pos + #w - 1, pieceScore(0, #w))
end

-- A long field. Only a word start, its best occurrence, or from INSIDE_MIN letters the word
-- inside a word, its first. The leading gap is counted only up to LONG and the trailing gap
-- not at all, which keeps every score inside the range the step is derived for. Answers
-- whether it was a word start, the score and where it matched.
local function longField(w, s, low, allowInside)
  local n, first, init = #w, nil, 1
  local function scored(pos, bonus)
    return math.min(pos - 1, LONG) * GAP_LEAD + pieceScore(bonus, n)
  end
  while true do
    local pos = low:find(w, init, true)
    if not pos then break end
    local bonus = startBonus(s, pos, wordByteAt)
    if bonus > 0 then return true, scored(pos, bonus), pos end
    first = first or pos
    init = pos + 1
  end
  if first and allowInside and n >= INSIDE_MIN then return false, scored(first, 0), first end
  return nil
end

-- The levels a word can match at, strongest first. The number is what a word adds to its
-- row's level sum, so a stronger level is a larger number. Every name level outranks the
-- declared one.
local LEVEL = { nameStart = 4, namePieces = 3, nameEdit = 2, nameInside = 1, declared = 0 }
M.LEVEL = LEVEL

-- One lowered word against the name, answering its level and score, or nil. A, B and C all
-- begin at a word start with the word's own first letter, so a name with no word starting with
-- that letter skips straight to D.
local function matchName(w, name)
  if name == nil or name == "" then return nil end
  if #name > LONG then
    local atStart, score = longField(w, name, lowered(name), true)
    if atStart == nil then return nil end
    return atStart and LEVEL.nameStart or LEVEL.nameInside, score
  end
  local p = prepare(name)
  if p.byFirst[w:byte(1)] then
    local s = atWordStart(w, name, p)
    if s then return LEVEL.nameStart, s end
    s = inPieces(w, name, p)
    if s then return LEVEL.namePieces, s end
    if #w >= TYPO_MIN then
      s = withOneEdit(w, name, p)
      if s then return LEVEL.nameEdit, s end
    end
  end
  if #w >= INSIDE_MIN then
    local s = insideWord(w, p.low, #name)
    if s then return LEVEL.nameInside, s end
  end
  return nil
end

-- The phrase of a field holding byte pos, the text between the phrase breaks around it,
-- trimmed. The same breaks the pieces respect, so what a row shows is what was matched in.
local function phraseAt(text, pos)
  local from, to, j, m = 1, #text, 1, #text
  while j <= m do
    local b = text:byte(j)
    local len = BREAK[b] and 1 or multiSepAt(text, j)
    if len then
      if j < pos then from = j + len else to = j - 1; break end
      j = j + len
    else
      j = j + 1
    end
  end
  return (text:sub(from, to):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- One lowered word against the secondary fields, word start or pieces only, the best field
-- kept, answering its score and, when that field is not shown on the row, the phrase that
-- matched.
local function matchDeclared(w, secondary)
  local best, shown
  for _, f in ipairs(secondary or {}) do
    local text = f.text
    if type(text) == "string" and text ~= "" then
      local s, pos
      if #text > LONG then
        local atStart, sc, at = longField(w, text, lowered(text), false)
        if atStart then s, pos = sc, at end
      else
        local p = prepare(text)
        s, pos = atWordStart(w, text, p)
        if not s then s, pos = inPieces(w, text, p) end
      end
      if s and (best == nil or s > best) then
        best = s
        shown = (not f.visible and pos) and phraseAt(text, pos) or nil
      end
    end
  end
  return best, shown
end

-- Whether a field holds the lowered text t anywhere, for the symbol part of a query word.
local function holds(t, name, secondary)
  if name and name ~= "" and ((#name > LONG) and lowered(name) or prepare(name).low):find(t, 1, true) then
    return true
  end
  for _, f in ipairs(secondary or {}) do
    local text = f.text
    if type(text) == "string" and text ~= "" then
      local low = (#text > LONG) and lowered(text) or prepare(text).low
      if low:find(t, 1, true) then return true end
    end
  end
  return false
end

--- M.fuzzy(query, hay, fields) -> score, level, within, atStart, shown, or nil
--- The one search, docs/PLAN-UNIFIED-SEARCH.md phase one, as Milos settled it on 2026-10-17
--- after the live test and the review that followed. A row has a primary field, its name, and
--- secondary fields, the text it shows or declares on purpose. fields is { primary = string,
--- secondary = { { text, visible }, ... } } as lib/chooser/rank.lua builds it. Without fields,
--- hay is the name and there is nothing secondary, which is how a plugin scoring its own
--- strings calls it.
---
--- A word never matches across fields. Each query word, lowered, matches at the strongest of
--- five levels.
---   A. In the name, at the start of a word. lose in Loser, se in Settings.
---   B. In the name, in pieces, each the start of one of a run of consecutive words in one
---      phrase. lose in LOcal SErvers, os in OLM settings, initials being every piece one
---      letter. A standalone symbol such as an ampersand is no word.
---   C. In the name, A with exactly one edit, from four letters on, never on the first letter
---      and never a wrong or extra last letter. dokcer and docekr find Docker.
---   D. In the name, whole inside a word, from three letters on. Two letters never do, so do
---      does not find Window.
---   E. In a secondary field, A or B only, below every name level.
--- There is no scattered match and so no relevance floor.
---
--- A query word with no letter or digit, an ampersand, a plus, a percent sign, matches as a
--- plain substring of any field and adds no level and no score, so date & time and 10 % of 50
--- still find what they name. A word starting with symbols, $5 or #1, is matched on its word
--- part, and its symbol part must appear somewhere in the row.
---
--- Every word is required, scored on its own, and summed, so google chrome finds nothing in a
--- row titled Chrome. A row's level is the sum of its words' levels. The step between level
--- sums is derived per query from the weights. A word of n letters scores at most n times TOP,
--- an edit never adding a letter to what is scored, and more than minus LONG times the near
--- free gap, since a short field pays at most its length in gap and a long one has its gap
--- capped. So two rows at one level sum differ by less than the sum over the words of that
--- spread, the step is that sum, and a row with a higher level sum always scores higher.
---
--- The later answers are for consumers. level is the row's level sum, within its score
--- inside the level, atStart whether every word matched the name at a word start, which the
--- launcher's memory gate reads, and shown the list of declared phrases, each once, that a
--- word matched in where the field is not shown, which rank.lua puts into the subtitle so a
--- person sees why the row is listed.
function M.fuzzy(query, hay, fields)
  local name = fields and fields.primary or hay
  local secondary = fields and fields.secondary
  local level, within, step, atStart = 0, 0, 0, true
  local shownList, shownSeen = nil, nil
  local any = false
  for word in query:lower():gmatch("%S+") do
    any = true
    local lead = word:match("^[%p%c]*")
    local core = word:sub(#lead + 1)
    if core == "" then
      -- No letter or digit at all, a plain substring anywhere in the row.
      if not holds(word, name, secondary) then return nil end
    else
      if lead ~= "" and not holds(lead, name, secondary) then return nil end
      local wordLevel, score = matchName(core, name)
      local shown
      if not wordLevel then
        score, shown = matchDeclared(core, secondary)
        if not score then return nil end
        wordLevel = LEVEL.declared
      end
      level = level + wordLevel
      within = within + score
      if wordLevel ~= LEVEL.nameStart then atStart = false end
      if shown and shown ~= "" then
        shownSeen = shownSeen or {}
        if not shownSeen[shown] then
          shownSeen[shown] = true
          shownList = shownList or {}
          shownList[#shownList + 1] = shown
        end
      end
      step = step + #core * TOP + LONG * math.max(-GAP_LEAD, -GAP_TRAIL)
    end
  end
  if not any then return 0, 0, 0, true, nil end
  return level * step + within, level, within, atStart, shownList
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
