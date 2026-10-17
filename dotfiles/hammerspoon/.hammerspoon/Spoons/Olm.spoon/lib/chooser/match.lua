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
--- scattered letters at all. It answers five more values after the score, see M.fuzzy, which
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

-- Latin letters with diacritics folded to their base letters, Milos's decision on 2026-10-17, so
-- resume finds Résumé, cafe finds Café and zurich finds Zürich, and typing the accent still
-- matches, since the query is folded the same way. The table maps the two byte UTF-8 form of
-- each letter in Latin-1 and Latin Extended-A, and the Romanian comma letters, to its base, an
-- upper case letter to an upper case base so a camel hump survives the fold. A combining mark,
-- the decomposed form macOS gives many file names, is dropped. Every text is folded before it
-- is lowered, the query and every field alike, so the matcher compares base letters only.
local FOLD = {}
do
  local groups = {
    { "ÀÁÂÃÄÅĀĂĄ", "A" }, { "àáâãäåāăą", "a" }, { "Æ", "AE" }, { "æ", "ae" },
    { "ÇĆĈĊČ", "C" }, { "çćĉċč", "c" }, { "ÐĎĐ", "D" }, { "ðďđ", "d" },
    { "ÈÉÊËĒĔĖĘĚ", "E" }, { "èéêëēĕėęě", "e" }, { "ĜĞĠĢ", "G" }, { "ĝğġģ", "g" },
    { "ĤĦ", "H" }, { "ĥħ", "h" }, { "ÌÍÎÏĨĪĬĮİ", "I" }, { "ìíîïĩīĭįı", "i" },
    { "Ĳ", "IJ" }, { "ĳ", "ij" }, { "Ĵ", "J" }, { "ĵ", "j" }, { "Ķ", "K" }, { "ķĸ", "k" },
    { "ĹĻĽĿŁ", "L" }, { "ĺļľŀł", "l" }, { "ÑŃŅŇŊ", "N" }, { "ñńņňŉŋ", "n" },
    { "ÒÓÔÕÖØŌŎŐ", "O" }, { "òóôõöøōŏő", "o" }, { "Œ", "OE" }, { "œ", "oe" },
    { "ŔŖŘ", "R" }, { "ŕŗř", "r" }, { "ŚŜŞŠȘ", "S" }, { "śŝşšșſ", "s" }, { "ß", "ss" },
    { "ŢŤŦȚ", "T" }, { "ţťŧț", "t" }, { "Þ", "TH" }, { "þ", "th" },
    { "ÙÚÛÜŨŪŬŮŰŲ", "U" }, { "ùúûüũūŭůűų", "u" }, { "Ŵ", "W" }, { "ŵ", "w" },
    { "ÝŶŸ", "Y" }, { "ýÿŷ", "y" }, { "ŹŻŽ", "Z" }, { "źżž", "z" },
  }
  for _, g in ipairs(groups) do
    for ch in g[1]:gmatch("[\192-\223][\128-\191]") do FOLD[ch] = g[2] end
  end
end

-- The lead bytes of every sequence FOLD names or a combining mark starts with. A text holding
-- none of them is answered as it is, found by plain finds, which scan at the speed of a byte
-- search, where a pattern for any byte above 127 steps through Lua's matcher and measured near
-- six milliseconds a megabyte. So ASCII text, nearly every row, pays six byte scans and nothing
-- else.
local FOLD_LEADS = { "\195", "\196", "\197", "\200", "\204", "\205" }

local function fold(s)
  local find = string.find
  local any = false
  for i = 1, #FOLD_LEADS do
    if find(s, FOLD_LEADS[i], 1, true) then any = true; break end
  end
  if not any then return s end
  s = s:gsub("[\195-\197\200][\128-\191]", FOLD)
  s = s:gsub("\204[\128-\191]", ""):gsub("\205[\128-\175]", "")
  return s
end

--- M.fold(text) -> the text with Latin letters with diacritics folded to their base letters, the
--- fold every query and field goes through before it is lowered, exposed for the cases.
M.fold = fold

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

-- A long body folded and lowered once rather than on every keystroke. Lowering a body costs an
-- allocation the size of the body, which the words strategy measured as four fifths of its
-- work, and a list asks the same bodies again on every key, so the lowered copy is kept,
-- keyed by the body itself. Lua does not intern a long string, but it computes a long
-- string's hash once and keeps it in the string, and a lookup compares the very string the
-- row already holds by identity before it would compare bytes, so finding the copy again is
-- cheap. A body holding a letter with a diacritic also keeps its folded text before lowering,
-- since a word start is read from the case of the folded text and its positions differ from
-- the body's.
--
-- The memo is two generations, each bounded both by how many bodies it holds and by their
-- bytes, the body, its folded text and its lowered copy all counted, since the memo is what
-- keeps a body alive once no row holds it. When the current generation passes either bound it
-- becomes the previous one, the previous one is let go, and a body found there moves back to
-- the current one, so a body every keystroke asks is never lowered again, and a body no list
-- asks any more is gone after two turns. So the memo holds at most two generations of
-- FOLD_BYTES each, plus the one body that passed the bound.
--
-- Both bounds have a history, decisions/olm-unified-search.md. A single byte budget of eight
-- megabytes, until 2026-10-17, thrashed on a real clipboard history, a thousand bodies with a
-- long tail coming to fourteen megabytes, since every keystroke lowered the whole list again
-- once the budget was passed. A count alone, four thousand bodies a generation, fixed that and
-- kept every body alive until four thousand distinct ones had arrived, so an append
-- accumulator growing one entry to six megabytes left 540 megabytes behind. FOLD_BYTES is
-- forty eight megabytes, so a history whose bodies and copies come to that fits in one
-- generation and is never lowered twice, which holds the measured history, twenty eight
-- megabytes counted, with room to grow, and the memo never holds more than about a hundred.
--
-- A Lua pattern with a class of both cases per letter would avoid the copy altogether, and
-- was measured and rejected on 2026-10-17, decisions/olm-unified-search.md. The pattern
-- matcher steps through the body a byte at a time in Lua's own matcher, where a plain find
-- is a C level scan, and it came out four times slower than lowering on every call.
local FOLD_LIMIT = 4096
local FOLD_BYTES = 48 * 1024 * 1024
local folded, foldedOld, foldedCount, foldedBytes = {}, {}, 0, 0

-- The memo's entry for a long body, the lowered copy alone when folding changed nothing, so
-- the common case keeps one string, or { text, low } when it did. Answers the folded text,
-- the body itself when nothing was folded, and its lowered copy.
local function longOf(hay)
  local hit = folded[hay]
  if not hit then
    hit = foldedOld[hay]
    if not hit then
      local f = fold(hay)
      local low = f:lower()
      if f == hay then hit = low else hit = { f, low } end
    end
    local bytes = #hay + ((type(hit) == "table") and (#hit[1] + #hit[2]) or #hit)
    if foldedCount >= FOLD_LIMIT or foldedBytes + bytes > FOLD_BYTES then
      foldedOld, folded, foldedCount, foldedBytes = folded, {}, 0, 0
    end
    folded[hay] = hit
    foldedCount = foldedCount + 1
    foldedBytes = foldedBytes + bytes
  end
  if type(hit) == "table" then return hit[1], hit[2] end
  return hay, hit
end

--- M._memo([bound]) -> the bytes the long field memo's current generation counts, and its
--- bound, so a case can prove the memo stays bounded without reaching into the module. A case
--- may lower the bound on its own loaded copy, so the proof needs megabytes rather than the
--- hundreds the real bound would. The previous generation is at most the bound plus the one
--- body that passed it.
function M._memo(bound)
  if type(bound) == "number" and bound > 0 then FOLD_BYTES = bound end
  return foldedBytes, FOLD_BYTES
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
-- it starts over when full. The field is folded first, so everything below reads base letters,
-- and the positions in a prepared field are positions in the folded text.
local PREP_LIMIT = 20000
local prepared, preparedCount = {}, 0
local function prepare(key)
  local p = prepared[key]
  if p then return p end
  local s = fold(key)
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
  -- compared with. Every word knows its phrase. A standalone ampersand is taken out of that key
  -- too, since it joins words rather than spelling one, so smileysemo finds smileys & emotion.
  -- The key as it was, with the ampersand, is kept beside it when they differ, so typing the
  -- ampersand still finds the phrase.
  local phrases = {}
  local k = 1
  while k <= #words do
    local last = k
    while last < #words and not words[last].breakAfter do last = last + 1 end
    local text = low:sub(words[k].s, words[last].e)
    local withAmp = text:gsub("%s+", "")
    local compact = text:gsub("%S+", function(tok)
      if tok:find("^&+$") then return "" end
    end):gsub("%s+", "")
    phrases[#phrases + 1] = { first = k, last = last, compact = compact,
      withAmp = (withAmp ~= compact) and withAmp or nil }
    for x = k, last do words[x].phrase = #phrases end
    k = last + 1
  end
  p = { low = low, words = words, byFirst = byFirst, wb = wb, phrases = phrases }
  preparedCount = preparedCount + 1
  if preparedCount > PREP_LIMIT then prepared, preparedCount = {}, 1 end
  prepared[key] = p
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
  local best, at, m = nil, nil, #p.low
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
  local n, words, low, m = #w, p.words, p.low, #p.low
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
  local best, m = nil, #p.low
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

-- How many places a word is tried at in one long field before the search settles for what it
-- has, decided 2026-10-17 after a review measured 405 to 455 milliseconds a keystroke for ng
-- over twenty bodies of a megabyte of words like running and string. A word that sits only
-- inside words is found everywhere and starts a word nowhere, so trying every occurrence for a
-- word start cost a Lua step per occurrence, millions of them. Past this many occurrences with
-- no word start among them the word is read as found inside a word at its first occurrence,
-- which keeps the row from INSIDE_MIN letters in a name and does not match a shorter word or a
-- secondary field, the same answer the field gives when no word start exists at all. So the
-- rows that match are unchanged whenever a word start exists in the first OCCURRENCES places,
-- and a word start found later lands at the inside level rather than the start level. Telling
-- exactly would need the whole body read per keystroke whatever the word, and the cheapest
-- exact form, a frontier pattern, measured twelve milliseconds a megabyte.
local OCCURRENCES = 256

-- A long field. Only a word start, the first found, or from INSIDE_MIN letters the word inside
-- a word, its first. s is the folded field and low its lowered copy, so their positions agree.
-- The leading gap is counted only up to LONG and the trailing gap not at all, which keeps every
-- score inside the range the step is derived for. Answers whether it was a word start, the
-- score and where it matched.
local function longField(w, s, low, allowInside)
  local n, first, init, tried = #w, nil, 1, 0
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
    tried = tried + 1
    if tried >= OCCURRENCES then break end
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
    local f, low = longOf(name)
    local atStart, score = longField(w, f, low, true)
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
    local s = insideWord(w, p.low, #p.low)
    if s then return LEVEL.nameInside, s end
  end
  return nil
end

-- One lowered word against the name and the row's further names, its best level and, at that
-- level, its best score, or nil. Each name is matched alone, so a word never spans two names and
-- pieces stay inside one. The best is taken and never a sum, which is what keeps a row with more
-- names from scoring above an equal row with fewer. A name that matches no better than the ones
-- before it changes nothing, and every name is bounded exactly as the title is, so the spread
-- the step is derived from holds whatever the number of names. The third answer is whether the
-- level came only from a further name, the name itself reaching no level that good, which
-- M.fuzzy ranks below the same level found in the name. A further name the word spells whole
-- counts as the name, since that is the row's name as a person types it, so grin still lists
-- the beaming face whose shortcode is grin before grinning face, Milos's correction of
-- 2026-10-17, while face lists person facepalming before the fist whose shortcode is facepunch.
local function spellsWhole(w, n)
  return #n <= LONG and prepare(n).low == w
end
local function matchNames(w, name, names)
  local level, score = matchName(w, name)
  local fromNames = false
  if names then
    for i = 1, #names do
      local n = names[i]
      if type(n) == "string" then
        local l, sc = matchName(w, n)
        if l and (level == nil or l > level) then
          level, score, fromNames = l, sc, not spellsWhole(w, n)
        elseif l and l == level then
          if sc > score then score = sc end
          if fromNames and spellsWhole(w, n) then fromNames = false end
        end
      end
    end
  end
  return level, score, fromNames
end

-- A phrase typed run together, the lowered word a prefix of a declared phrase with its spaces
-- taken out, counted from the phrase's start. nomore and nomo find "no more", donotd finds "do
-- not disturb", ore and otdisturb find nothing, and a comma ends a phrase so nothing runs across
-- one. A standalone ampersand is out of the key, so smileysemo finds "smileys & emotion", and
-- the key with it still answers smileys&emo. Scored like a word start run of the word's length at the phrase's first word, which keeps
-- it inside the range the step is derived for.
local function runTogether(w, p)
  local best, m = nil, #p.low
  for _, ph in ipairs(p.phrases) do
    if ph.compact:sub(1, #w) == w or (ph.withAmp and ph.withAmp:sub(1, #w) == w) then
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
        local f, low = longOf(text)
        local atStart, sc = longField(w, f, low, false)
        if atStart then s = sc end
      else
        local p = prepare(text)
        s = atWordStart(w, text, p)
        if f.declared then
          local r = runTogether(w, p)
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

-- A field folded and lowered, through whichever memo its length uses.
local function lowOf(text)
  if #text > LONG then
    local _, low = longOf(text)
    return low
  end
  return prepare(text).low
end

-- Whether a field holds the lowered text t anywhere, for the symbol part of a query word.
local function holdsIn(t, text)
  return text ~= "" and lowOf(text):find(t, 1, true) ~= nil
end
local function holds(t, name, names, secondary)
  if name and holdsIn(t, name) then return true end
  for _, n in ipairs(names or {}) do
    if type(n) == "string" and holdsIn(t, n) then return true end
  end
  for _, f in ipairs(secondary or {}) do
    local text = f.text
    if type(text) == "string" and text ~= "" then
      if lowOf(text):find(t, 1, true) then return true end
    end
  end
  return false
end

--- M.fuzzy(query, hay, fields) -> score, level, within, atStart, phrase, fromNames, or nil
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
--- A word never matches across fields. Each query word, folded and lowered like every field, so
--- resume finds Résumé, matches at the strongest of five levels.
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
--- At one level a word found in the name leads the same level found only in a further name,
--- Milos's rule after the review of 2026-10-17, so face lists person facepalming before oncoming
--- fist, whose alias is facepunch, and github pull lists a tab titled Pull request github before
--- one titled Pull request on github.com. Each such word costs the row one spread inside its
--- level, so the score orders by level sum, then the phrase bonus, then how many words came only
--- from further names, fewer first, then where the words landed. That takes room the step did
--- not have, so with k words the phrase bonus inside the score is k plus one spreads and the
--- step twice that. A row with no names pays nothing, so rows without names order exactly as
--- before.
---
--- The later answers are for consumers. level is the row's level sum, within its score
--- inside the level, atStart whether every word matched the name at a word start, which the
--- launcher's memory gate reads, phrase whether the phrase bonus was earned, and fromNames how
--- many words reached their level only in a further name. within carries the phrase bonus as one
--- spread and each further name word as minus one, so a row with no names answers the within it
--- always did, which the launcher's nearness reads as a proportion. Two rows with the same level,
--- the same phrase and the same fromNames are equally good, and only the near free gaps and the
--- bonuses of where a word landed tell them apart, which is what lib/chooser/rank.lua lets a
--- row's own bonus decide. phrase and fromNames are answered on their own because within folds
--- them in, and they cannot be read back out of it without restating the spread here.

-- A query parsed once, its words folded and lowered and split into a symbol lead and a core,
-- since the same query is matched against every row of a list on a keystroke. The last query is
-- kept, which is all a keystroke needs.
local lastQuery, lastWords
local function queryWords(query)
  if query == lastQuery then return lastWords end
  local list = {}
  for word in fold(query):lower():gmatch("%S+") do
    local lead = word:match("^[%p%c]*")
    list[#list + 1] = { word = word, lead = lead, core = word:sub(#lead + 1) }
  end
  lastQuery, lastWords = query, list
  return list
end

function M.fuzzy(query, hay, fields)
  local name = fields and fields.primary or hay
  local names = fields and fields.names
  local secondary = fields and fields.secondary
  local level, within, spread, atStart, fromNames = 0, 0, 0, true, 0
  local cores = {}
  local words = queryWords(query)
  for i = 1, #words do
    local word, lead, core = words[i].word, words[i].lead, words[i].core
    if core == "" then
      -- No letter or digit at all, a plain substring anywhere in the row.
      if not holds(word, name, names, secondary) then return nil end
    else
      if lead ~= "" and not holds(lead, name, names, secondary) then return nil end
      local wordLevel, score, named = matchNames(core, name, names)
      if not wordLevel then
        score = matchDeclared(core, secondary)
        if not score then return nil end
        wordLevel = LEVEL.declared
      end
      level = level + wordLevel
      within = within + score
      if named then fromNames = fromNames + 1 end
      if wordLevel ~= LEVEL.nameStart then atStart = false end
      spread = spread + #core * TOP + LONG * math.max(-GAP_LEAD, -GAP_TRAIL)
      cores[#cores + 1] = core
    end
  end
  if #words == 0 then return 0, 0, 0, true, false, 0 end
  -- Inside one level the words' scores span less than one spread, and each further name word
  -- takes one more below them, so the non phrase band is at most k plus one spreads wide. The
  -- phrase bonus in the score is that width, so a phrase row leads every row at its level sum,
  -- and the step is twice it, so the bonus never reaches the next level. within answers the
  -- phrase as one spread, as it always did.
  local phrase = inOnePhrase(cores, secondary)
  local band = (#cores + 1) * spread
  local inLevel = within - fromNames * spread
  local score = level * 2 * band + inLevel + (phrase and band or 0)
  return score, level, inLevel + (phrase and spread or 0), atStart, phrase, fromNames
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
