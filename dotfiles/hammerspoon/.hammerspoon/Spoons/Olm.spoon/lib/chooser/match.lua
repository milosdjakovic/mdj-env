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

-- ASCII punctuation that ends a phrase, so the pieces of a name never span a comma. The non
-- ASCII separators above end one too.
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
-- cheap.
--
-- The memo is two generations bounded by how many bodies each holds, not by their bytes. A
-- byte budget, eight megabytes until 2026-10-17, thrashed on a real clipboard history, a
-- thousand bodies with a long tail coming to fourteen megabytes, since every keystroke lowered
-- the whole list again once the budget was passed and a keystroke cost fifteen times the words
-- strategy, decisions/olm-unified-search.md. What a list asks is what it needs, so the bound
-- is a count generous enough for the longest list, FOLD_LIMIT bodies a generation. When the
-- current generation fills it becomes the previous one and a body found there moves back to
-- the current one, so a body every keystroke asks is never lowered again, and a body no list
-- asks any more is gone after two turns. The copies cost what the bodies cost, which is what
-- the clipboard's own lowered cache held for the words strategy before.
--
-- A Lua pattern with a class of both cases per letter would avoid the copy altogether, and
-- was measured and rejected on 2026-10-17, decisions/olm-unified-search.md. The pattern
-- matcher steps through the body a byte at a time in Lua's own matcher, where a plain find
-- is a C level scan, and it came out four times slower than lowering on every call.
local FOLD_LIMIT = 4096
local folded, foldedOld, foldedCount = {}, {}, 0
local function lowered(hay)
  local low = folded[hay]
  if low then return low end
  low = foldedOld[hay] or hay:lower()
  if foldedCount >= FOLD_LIMIT then
    foldedOld, folded, foldedCount = folded, {}, 0
  end
  folded[hay] = low
  foldedCount = foldedCount + 1
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
  -- The phrases, runs of words with no break between them, each with its first word and its
  -- text lowered with the spaces taken out, which is what a phrase typed run together is
  -- compared with. Every word knows its phrase.
  local phrases = {}
  local k = 1
  while k <= #words do
    local last = k
    while last < #words and not words[last].breakAfter do last = last + 1 end
    local compact = low:sub(words[k].s, words[last].e):gsub("%s+", "")
    phrases[#phrases + 1] = { first = k, last = last, compact = compact }
    for x = k, last do words[x].phrase = #phrases end
    k = last + 1
  end
  p = { low = low, words = words, byFirst = byFirst, wb = wb, phrases = phrases }
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
  local find, byte = string.find, string.byte
  while true do
    local pos = find(low, w, init, true)
    if not pos then break end
    -- A word with no word start in a long body tries every occurrence, so the common case,
    -- an ASCII byte before an ASCII byte, is answered here without the general check. The
    -- byte at pos is a word byte, since a query word's core starts with one.
    local bonus
    local prev = pos > 1 and byte(s, pos - 1) or nil
    local here = byte(s, pos)
    if prev and prev < 128 and here < 128 then
      if not ALNUM[prev] then
        bonus = BOUND
      elseif isLower(prev) and isUpper(here) then
        bonus = CAMEL
      else
        bonus = 0
      end
    else
      bonus = startBonus(s, pos, wordByteAt)
    end
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

-- One lowered word against the name and the row's further names, its best level and, at that
-- level, its best score, or nil. Each name is matched alone, so a word never spans two names and
-- pieces stay inside one. The best is taken and never a sum, which is what keeps a row with more
-- names from scoring above an equal row with fewer. A name that matches no better than the ones
-- before it changes nothing, and every name is bounded exactly as the title is, so the spread
-- the step is derived from holds whatever the number of names.
local function matchNames(w, name, names)
  local level, score = matchName(w, name)
  if names then
    for i = 1, #names do
      local n = names[i]
      if type(n) == "string" then
        local l, sc = matchName(w, n)
        if l and (level == nil or l > level or (l == level and sc > score)) then
          level, score = l, sc
        end
      end
    end
  end
  return level, score
end

-- A phrase typed run together, the lowered word a prefix of a declared phrase with its spaces
-- taken out, counted from the phrase's start. nomore and nomo find "no more", donotd finds "do
-- not disturb", ore and otdisturb find nothing, and a comma ends a phrase so nothing runs across
-- one. Scored like a word start run of the word's length at the phrase's first word, which keeps
-- it inside the range the step is derived for.
local function runTogether(w, text, p)
  local best, m = nil, #text
  for _, ph in ipairs(p.phrases) do
    if ph.compact:sub(1, #w) == w then
      local first = p.words[ph.first]
      local sc = framed(m, first.s, math.min(m, first.s + #w - 1), pieceScore(first.bonus, #w))
      if best == nil or sc > best then best = sc end
    end
  end
  return best
end

-- One lowered word against the secondary fields, level E. A word of the field must start
-- with it, no pieces across words, no edit and nothing inside a word, which is Milos's call
-- on 2026-10-17. A subtitle or a keyword is what a row also answers to, never a second name to
-- spell out. A declared field, keywords and alias words, also answers a phrase typed run
-- together, the subtitle a row shows does not. The best field is kept.
local function matchDeclared(w, secondary)
  local best
  for _, f in ipairs(secondary or {}) do
    local text = f.text
    if type(text) == "string" and text ~= "" then
      local s
      if #text > LONG then
        local atStart, sc = longField(w, text, lowered(text), false)
        if atStart then s = sc end
      else
        local p = prepare(text)
        s = atWordStart(w, text, p)
        if f.declared then
          local r = runTogether(w, text, p)
          if r and (s == nil or r > s) then s = r end
        end
      end
      if s and (best == nil or s > best) then best = s end
    end
  end
  return best
end

-- Whether every word of a query of two or more starts a word of one secondary phrase, in the
-- order typed, focus disturb never, do not d inside "do not disturb" always. Such a row was
-- found by one thing a person declared, not by words that happen to sit apart, so it earns the
-- phrase bonus below.
local function inOnePhrase(cores, secondary)
  if #cores < 2 then return false end
  for _, f in ipairs(secondary or {}) do
    local text = f.text
    if type(text) == "string" and text ~= "" and #text <= LONG then
      local p = prepare(text)
      for _, ph in ipairs(p.phrases) do
        local k, ok = ph.first, true
        for _, c in ipairs(cores) do
          while k <= ph.last and not prefixAt(p.low, p.words[k].s, c) do k = k + 1 end
          if k > ph.last then ok = false; break end
          k = k + 1
        end
        if ok then return true end
      end
    end
  end
  return false
end

-- Whether a field holds the lowered text t anywhere, for the symbol part of a query word.
local function holdsIn(t, text)
  return text ~= "" and ((#text > LONG) and lowered(text) or prepare(text).low):find(t, 1, true) ~= nil
end
local function holds(t, name, names, secondary)
  if name and holdsIn(t, name) then return true end
  for _, n in ipairs(names or {}) do
    if type(n) == "string" and holdsIn(t, n) then return true end
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

--- M.fuzzy(query, hay, fields) -> score, level, within, atStart, phrase, or nil
--- The one search, docs/PLAN-UNIFIED-SEARCH.md phase one, as Milos settled it on 2026-10-17
--- after the live test and the review that followed. A row has a primary field, its name, and
--- secondary fields, the text it shows or declares on purpose. fields is { primary = string,
--- names = { string, ... } or nil, secondary = { { text, declared }, ... } } as
--- lib/chooser/rank.lua builds it. Without fields, hay is the name and there is nothing
--- secondary, which is how a plugin scoring its own strings calls it.
---
--- names are further names of the row, a tab's host and address beside its title, a clipboard
--- entry's body, matched at levels A to D exactly like the primary. Each word takes its best
--- level, and at that level its best score, across the primary and the names, so github pull
--- finds a tab titled Pull request on github.com with each word in a different name, while one
--- word never spans two names and pieces stay inside one. The best is taken, never a sum, so a
--- row never scores higher for having more names than an equal row with fewer.
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
---   E. In a secondary field, at the start of a word only, below every name level. A declared
---      field, keywords and alias words, also answers a phrase typed run together, nomore for
---      "no more".
--- There is no scattered match and so no relevance floor.
---
--- A query word with no letter or digit, an ampersand, a plus, a percent sign, matches as a
--- plain substring of any field and adds no level and no score, so date & time and 10 % of 50
--- still find what they name. A word starting with symbols, $5 or #1, is matched on its word
--- part, and its symbol part must appear somewhere in the row.
---
--- Every word is required, scored on its own, and summed, so google chrome finds nothing in a
--- row titled Chrome. A row's level is the sum of its words' levels. A word of n letters scores
--- at most n times TOP, an edit or a phrase typed run together never adding a letter to what is
--- scored, and more than minus LONG times the near free gap, since a short field pays at most
--- its length in gap and a long one has its gap capped. So two rows at one level sum differ by
--- less than the spread, the sum over the words of n times TOP plus that gap. A query of two or
--- more words whose words all start words of one secondary phrase, in order, adds one spread,
--- the phrase bonus, so such a row leads every row at its level sum, and the step between level
--- sums is two spreads, so the bonus never lifts a row past a higher level sum. Each word still
--- matches on its own, focus disturb finds Focus with focus in its name and disturb in a
--- keyword, only without the bonus.
---
--- The later answers are for consumers. level is the row's level sum, within its score
--- inside the level, atStart whether every word matched the name at a word start, which the
--- launcher's memory gate reads, and phrase whether the phrase bonus was earned. Two rows with
--- the same level and the same phrase are equally good, and only the near free gaps and the
--- bonuses of where a word landed tell them apart, which is what lib/chooser/rank.lua lets a
--- row's own bonus decide. phrase is answered on its own because within folds it in, and one
--- spread cannot be read back out of within without restating the spread here.
function M.fuzzy(query, hay, fields)
  local name = fields and fields.primary or hay
  local names = fields and fields.names
  local secondary = fields and fields.secondary
  local level, within, spread, atStart = 0, 0, 0, true
  local any, cores = false, {}
  for word in query:lower():gmatch("%S+") do
    any = true
    local lead = word:match("^[%p%c]*")
    local core = word:sub(#lead + 1)
    if core == "" then
      -- No letter or digit at all, a plain substring anywhere in the row.
      if not holds(word, name, names, secondary) then return nil end
    else
      if lead ~= "" and not holds(lead, name, names, secondary) then return nil end
      local wordLevel, score = matchNames(core, name, names)
      if not wordLevel then
        score = matchDeclared(core, secondary)
        if not score then return nil end
        wordLevel = LEVEL.declared
      end
      level = level + wordLevel
      within = within + score
      if wordLevel ~= LEVEL.nameStart then atStart = false end
      spread = spread + #core * TOP + LONG * math.max(-GAP_LEAD, -GAP_TRAIL)
      cores[#cores + 1] = core
    end
  end
  if not any then return 0, 0, 0, true, false end
  -- The phrase bonus is one spread, so a row whose words all sit in one declared phrase leads
  -- every row at its level sum, and the step is two spreads, so the bonus never reaches the
  -- next level.
  local phrase = inOnePhrase(cores, secondary)
  if phrase then within = within + spread end
  return level * 2 * spread + within, level, within, atStart, phrase
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
--- The clipboard's strategy until 2026-10-17, a word tokenizer rather than a subsequence scorer. The query
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
--- now carries the same rule for any haystack past its long body bound, and since phase three
--- of docs/PLAN-UNIFIED-SEARCH.md moved the clipboard and FileSearch on 2026-10-17 no list or
--- manifest names this strategy. It stays because test/search-timing.lua measures the shared
--- search against it, the baseline the numbers in decisions/olm-unified-search.md compare with,
--- and test/cases/match.lua covers it while it is exported.
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
