--- === Chooser.match ===
---
--- Shared matching strategies for the Chooser atom. Each is a pure function
--- match(query, hay) -> score or nil. A nil means the row does not match and is
--- dropped. A number is a rank, higher is better, and the atom sorts survivors by it
--- with the original order breaking ties, so a stable secondary order like the
--- launcher's recency still shows through. This is the concrete policy the design
--- principles separate from the mechanism, injected once from the composition root so
--- every chooser shares one matcher and swapping them all is a single edit.
---
--- fuzzy is the one search every list is moving onto, docs/PLAN-UNIFIED-SEARCH.md. It may
--- answer three more values after the score, the level, the score inside that level and
--- whether every word matched at a word start, which lib/chooser/rank.lua carries along for
--- a consumer that has to tell a better kind of match from a better scored one of the same
--- kind. A caller reading only the first value
--- loses nothing, the score alone already orders every row correctly.

local M = {}

local BYTE_A, BYTE_Z = string.byte("A"), string.byte("Z")
local BYTE_a, BYTE_z = string.byte("a"), string.byte("z")

local function isUpper(b) return b ~= nil and b >= BYTE_A and b <= BYTE_Z end
local function isLower(b) return b ~= nil and b >= BYTE_a and b <= BYTE_z end

-- A character that ends a word, so the next matched character sits on a boundary and
-- scores like the start of a word. Space and the common name separators.
local SEP = {}
for _, ch in ipairs({ " ", "/", "\\", "-", "_", ".", ":", "(", ")", "[", "]", "@" }) do
  SEP[string.byte(ch)] = true
end

-- Scoring weights. A matched character is worth MATCH plus a bonus for where it lands.
-- Extending a run (CONSEC) is the strongest signal and must beat a word start (BOUND) or
-- a camel hump (CAMEL), so a near contiguous match like dspl over "Displays" outranks the
-- same letters scattered across the separate words of a keyword bag, which was the bug
-- that surfaced Device Management above Displays. START rewards the very first character.
-- Gaps come in three kinds, following fzy. A leading gap before the first match and a
-- trailing gap after the last are nearly free, so a term sitting deep in a long body is
-- not crushed by the text around it. An inner gap between two matched characters costs
-- real points, so spreading a query across a wide span loses, which is what pulls the
-- scattered keyword bag matches down and, past a point, under the floor. A skipped query
-- character is a typo and costs TYPO, see below.
local MATCH   = 1
local START   = 10
local BOUND   = 7
local CAMEL   = 6
local CONSEC  = 10
local GAP_LEAD  = -0.02
local GAP_INNER = -0.4
local GAP_TRAIL = -0.02
local NEG       = -1e9

-- The most one matched character can ever earn, a match plus the largest bonus there is.
-- No alignment of a word of n characters scores above n times this, which is what the
-- step between levels below is derived from.
local TOP = MATCH + math.max(START, BOUND, CAMEL, CONSEC)

-- Typo tolerance. The matcher may skip a query character it cannot place, so a missed,
-- misspelled, or swapped letter still hits, each skip costing TYPO. There is no hard
-- budget, enough skips simply sink the score beneath the floor, which is what keeps a
-- query full of wrong letters from matching everything.
local TYPO = 6

-- The relevance floor. A subsequence match over a long searchable text, an app label
-- plus its hidden keyword bag, can line up by scattering letters across unrelated words
-- (typing dspl finds Trackpad through "...pa[d] [S]ystem ... track[p]ad ... c[l]ick").
-- Such a match earns few bonuses, so it scores low, and a minimum score scaled to the
-- word length, since a longer word naturally scores higher, drops the scattered tail
-- while every real match clears it easily. Raise FLOOR_STEP to cut more, lower it to
-- keep more. It applies to a word matched inside a word or scattered. A word at a word start
-- or spelled by initials is a match however little its position earns, see the levels below.
local FLOOR_BASE = 2
local FLOOR_STEP = 3.5
local function minScore(n) return FLOOR_BASE + (n - 1) * FLOOR_STEP end

-- The long body bound, in bytes. A haystack longer than this matches a word only where
-- the word sits in it whole, with no subsequence and no typo tolerance, which is what the
-- words strategy did for clipboard bodies and file paths and why this one search can
-- replace it. Two measurements set it, both recorded in decisions/olm-unified-search.md on
-- 2026-10-17. The subsequence scorer costs the word length times the haystack length, and
-- an eight letter word measured 35 microseconds over 64 bytes, 57 over 128 and 102 over
-- 256, so this is the most one row may cost, and a four kilobyte clipboard body would cost
-- sixteen times that on every key. A body past the bound costs about two microseconds once
-- its lowered copy is kept, the same as the words strategy. And every launcher row, a
-- title, its subtitle and its keyword bag, adds up to under 200 bytes from the longest
-- declared strings, so no row whose typo tolerance anyone relies on loses it. Past this
-- length a scattered alignment is letters picked off a page of text, noise rather than a
-- match.
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

-- The best alignment of one lowercased word q over a haystack, raw, with no floor applied.
-- A dynamic programming subsequence scorer in the spirit of fzy, with typo tolerance. Two
-- rolling rows carry D, the best score of an alignment whose last query character is
-- matched at this haystack position, and Mrow, the best score of matching the word prefix
-- within this haystack prefix. A match opens a run with a boundary or camel bonus or
-- extends one with the consecutive bonus, and Mrow then takes the best of matching here,
-- skipping this haystack character for a gap, or skipping this query character as a typo.
-- The gap is leading before the first match, trailing on the last query character, or
-- inner between matches, and only the inner gap costs much, so span is penalized while
-- position is not. Because it explores every alignment rather than greedily taking the
-- leftmost letter, it tolerates a swapped or wrong letter where a greedy scan would lock
-- onto the wrong occurrence and starve the rest. hlow is the haystack lowered once by the
-- caller, hay the original, read for the casing bonus.
local function align(q, hay, hlow)
  local n, m = #q, #hay

  -- Row 0, no query characters consumed yet. Mrow is zero everywhere so a match may open
  -- at any position, and D is impossible.
  local Mprev, Dprev = {}, {}
  for j = 0, m do Mprev[j] = 0; Dprev[j] = NEG end

  for i = 1, n do
    local qb = q:byte(i)
    -- The gap that trails the final query character is nearly free, so a match near the
    -- front of a long text is not punished for the text after it, while inner gaps between
    -- earlier characters carry the span penalty.
    local gap = (i == n) and GAP_TRAIL or GAP_INNER
    local Mcur, Dcur = {}, {}
    Mcur[0] = Mprev[0] - TYPO -- matching i chars in no haystack means i skipped query chars
    Dcur[0] = NEG
    local prev = Mcur[0]      -- running Mcur[j-1]
    for j = 1, m do
      local d = NEG
      if hlow:byte(j) == qb then
        if i == 1 then
          -- The first character pays only a near free leading gap for how far in it sits.
          d = (j - 1) * GAP_LEAD + bonusAt(hay, j) + MATCH
        else
          local open = Mprev[j - 1] + bonusAt(hay, j) + MATCH -- open a run here
          local extend = Dprev[j - 1] + CONSEC + MATCH        -- extend the previous run
          d = (open > extend) and open or extend
        end
      end
      Dcur[j] = d
      local viaGap = prev + gap          -- leave this haystack character unmatched
      local best = (d > viaGap) and d or viaGap
      local viaTypo = Mprev[j] - TYPO    -- leave this query character unmatched, a typo
      if viaTypo > best then best = viaTypo end
      Mcur[j] = best
      prev = best
    end
    Mprev, Dprev = Mcur, Dcur
  end

  return Mprev[m]
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

-- Whether a word of the haystack starts at position j, the very first byte, a byte after a
-- separator, or a camel hump. The same three places bonusAt rewards, so a level and the
-- scoring never disagree about where a word begins.
local function startsWord(hay, j)
  return bonusAt(hay, j) > 0
end

-- Whether a byte can begin a word for initials. A letter, a digit, or any byte of a non
-- ASCII character. A standalone symbol such as the ampersand in Printers & Scanners is not a
-- word, so ps finds it, since nobody types the ampersand when spelling a name by its
-- initials, and counting it would make the one name that carries it unreachable that way.
local function wordByte(b)
  return b ~= nil and (b >= 128 or string.char(b):match("%w") ~= nil)
end

-- The four levels a word can match at, strongest first. The number is what the level adds to
-- a row's level sum, so a stronger level is a larger number.
local LEVEL = { start = 3, initials = 2, inside = 1, scattered = 0 }

-- Whether a lowered word occurs whole at a word start, or else where it first occurs at all,
-- answering the position and whether it was a word start. Every occurrence is tried until one
-- sits at a word start, so a long body's best occurrence is found rather than its first hit.
local function wholeAt(word, hay, hlow)
  local first
  local init = 1
  while true do
    local pos = hlow:find(word, init, true)
    if not pos then return first, false end
    if startsWord(hay, pos) then return pos, true end
    first = first or pos
    init = pos + 1
  end
end

-- Whether a lowered word is spelled by the first letters of consecutive words, os in OLM
-- settings, dd in Docker Desktop. Words begin where startsWord says, and only at a byte that
-- can begin a word.
local function isInitials(word, hay, hlow)
  local starts = {}
  for j = 1, #hay do
    if wordByte(hay:byte(j)) and startsWord(hay, j) then starts[#starts + 1] = j end
  end
  local n = #word
  for k = 1, #starts - n + 1 do
    local all = true
    for i = 1, n do
      if hlow:byte(starts[k + i - 1]) ~= word:byte(i) then all = false; break end
    end
    if all then return true end
  end
  return false
end

-- What a word found whole at position pos scores in a long body, the score the dynamic
-- program gives the same contiguous run, a first character with its boundary bonus and
-- every later one extending the run. The leading gap is counted only up to LONG, so a word
-- deep in a long body costs no more than one at the end of a short one, which keeps every
-- score inside the range the step below is derived for.
local function runScore(hay, pos, n)
  local lead = pos - 1
  if lead > LONG then lead = LONG end
  return lead * GAP_LEAD + bonusAt(hay, pos) + MATCH + (n - 1) * (CONSEC + MATCH)
end

-- One word against one haystack, answering its level and its score inside the level, or nil
-- when it does not match. Levels start and initials skip the floor, since each is a deliberate
-- way of naming a row however little its position earns. inside and scattered must clear it,
-- which is what keeps one typed letter from matching every row that holds it somewhere.
local function matchWord(word, hay, hlow, long)
  local n = #word
  local floor = minScore(n)
  if long then
    -- Past the bound only a word found whole matches, at a word start or inside a word.
    local pos, atStart = wholeAt(word, hay, hlow)
    if not pos then return nil end
    local score = runScore(hay, pos, n)
    if atStart then return LEVEL.start, score end
    if score < floor then return nil end
    return LEVEL.inside, score
  end
  local score = align(word, hay, hlow)
  local pos, atStart = wholeAt(word, hay, hlow)
  if atStart then return LEVEL.start, score end
  if isInitials(word, hay, hlow) then return LEVEL.initials, score end
  if score < floor then return nil end
  if pos then return LEVEL.inside, score end
  return LEVEL.scattered, score
end

--- M.fuzzy(query, hay) -> score, level, within, atStart, or nil
--- The one search, docs/PLAN-UNIFIED-SEARCH.md phase one. Three rules sit on top of the
--- subsequence scorer above.
---
--- Each word separately. The query splits on whitespace, every word must match, and their
--- scores are summed, so "hello there" finds "there, hello" and a word is never assembled
--- from letters belonging to the other one. Every word is required, so google chrome finds
--- nothing in a row titled Chrome.
---
--- Four levels per word, strongest first, decided by Milos on 2026-10-17. A word found whole
--- at a word start, se in Settings. A word spelled by the first letters of consecutive words,
--- os in OLM settings, dd in Docker Desktop, ps in Printers & Scanners. A word found whole
--- inside a word, se in Base. And a scattered alignment with gaps or typos, the old fuzzy
--- match. A row's level is the sum over its words, and every step up outranks any difference
--- between scores at the same level, so typing se ranks Settings, then Some example, then
--- Base, and inside a level the ordinary scoring orders the rows as before. The first two
--- levels skip the floor, the last two must clear it.
---
--- The step is derived per query from the weights rather than chosen. A word of n characters
--- scores at most n times TOP. The least a matching word can score is above minus a full LONG
--- of inner gap, since every alignment the levels accept pays at most its haystack length in
--- gaps, the inner gap costs most, and a short haystack is at most LONG bytes while a long one
--- is scored only by runScore, whose gap is capped. So the scores at one level sum can never
--- spread wider than the sum over the words of n times TOP plus LONG times the inner gap, the
--- step is that sum, and a row with a higher level sum always scores higher. The score stays
--- the single number lib/chooser/rank.lua sorts on.
---
--- Long bodies. Past LONG bytes a word matches only where it sits whole, at a word start or
--- inside a word, the best occurrence chosen, found with a plain byte scan over a lowered copy
--- kept from one keystroke to the next, see lowered. That keeps the words strategy's speed
--- over a long body, so the words strategy can retire.
---
--- The later answers are for a consumer that compares rows by more than order, the
--- launcher's nearness rule. level is the row's level sum, within its score inside the level,
--- and atStart whether every word matched at a word start. Returns nil when a word is absent,
--- or when a word matched only inside a word or scattered scores below the floor.
function M.fuzzy(query, hay)
  local words = {}
  for word in query:lower():gmatch("%S+") do words[#words + 1] = word end
  if #words == 0 then return 0, 0, 0, true end
  local m = #hay
  if m == 0 then return nil end

  local long = m > LONG
  -- A short haystack is lowered here, once for every word, since it is short by definition
  -- and the dynamic program reads it byte by byte anyway. A long one comes from the memo.
  local hlow = long and lowered(hay) or hay:lower()

  local within, level, step, atStart = 0, 0, 0, true
  for _, word in ipairs(words) do
    local wordLevel, score = matchWord(word, hay, hlow, long)
    if not wordLevel then return nil end
    level = level + wordLevel
    within = within + score
    if wordLevel ~= LEVEL.start then atStart = false end
    step = step + #word * TOP - LONG * GAP_INNER
  end
  return level * step + within, level, within, atStart
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
