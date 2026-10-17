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
--- answer two more values after the score, the tier and the score inside that tier, which
--- lib/chooser/rank.lua carries along for a consumer that has to tell a better kind of
--- match from a better scored one of the same kind. A caller reading only the first value
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
-- tier below is derived from.
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
-- keep more. It applies to a word matched with gaps or typos only. A word found whole
-- is a match however little its position earns, see the tier below.
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
-- keyed by the body itself. Lua interns a string and caches a long string's hash in it, so
-- finding the copy again is a table lookup on the very string the row already holds. The
-- memo is bounded by FOLD_BUDGET bytes and starts over when it fills, so a body that left
-- the list is forgotten within a budget's worth of new ones, and a list larger than the
-- budget degrades to lowering per call, which is still correct.
--
-- A Lua pattern with a class of both cases per letter would avoid the copy altogether, and
-- was measured and rejected on 2026-10-17, decisions/olm-unified-search.md. The pattern
-- matcher steps through the body a byte at a time in Lua's own matcher, where a plain find
-- is a C level scan, and it came out four times slower than lowering on every call.
local FOLD_BUDGET = 4 * 1024 * 1024
local folded, foldedBytes = {}, 0
local function lowered(hay)
  local low = folded[hay]
  if low then return low end
  low = hay:lower()
  foldedBytes = foldedBytes + #low
  if foldedBytes > FOLD_BUDGET then
    folded, foldedBytes = {}, #low
  end
  folded[hay] = low
  return low
end

-- What a word found whole at position pos scores in a long body, the score the dynamic
-- program gives the same contiguous run, a first character with its boundary bonus and
-- every later one extending the run. The leading gap is counted only up to LONG, so a word
-- deep in a long body costs no more than one at the end of a short one, which keeps every
-- score inside the range the tier below is derived for.
local function runScore(hay, pos, n)
  local lead = pos - 1
  if lead > LONG then lead = LONG end
  return lead * GAP_LEAD + bonusAt(hay, pos) + MATCH + (n - 1) * (CONSEC + MATCH)
end

--- M.fuzzy(query, hay) -> score, tier, within, or nil
--- The one search, docs/PLAN-UNIFIED-SEARCH.md phase one. Three rules sit on top of the
--- subsequence scorer above.
---
--- Each word separately. The query splits on whitespace, every word must match, and their
--- scores are summed, so "hello there" finds "there, hello" and a word is never assembled
--- from letters belonging to the other one. A single word query is the old behaviour.
---
--- Contiguous first. A word found whole in the haystack, ignoring case, is a better kind of
--- match than any alignment with gaps or typos, so the score carries a tier, the count of
--- words found whole, and every tier sits above the one below it whatever the scores inside
--- them. Typing se ranks Settings, Sending and even Base above Some example, and inside a
--- tier the ordinary scoring orders the rows, so a word found at a word start still beats
--- one found mid word. The tier counts per word rather than once for the whole query
--- because a query of two words is a request for both, and a row holding both whole is a
--- better answer than one holding one of them whole and the other scattered. A word found
--- whole skips the floor, since the floor exists to cut scattered alignments and a whole
--- word deep in a long row is not one.
---
--- The tier is a step of span points, derived per query from the weights rather than
--- chosen. A word of n characters scores at most n times TOP, and a word found whole scores
--- at least its run minus a full LONG of near free gap, so the scores inside a tier can
--- never spread wider than the sum over the words of n times TOP plus that gap. span is
--- that sum, so one more word found whole outranks any difference inside a tier, and the
--- score stays the single number lib/chooser/rank.lua sorts on.
---
--- Long bodies. Past LONG bytes a word matches only where it sits whole, found with a plain
--- byte scan over a lowered copy kept from one keystroke to the next, see lowered. That
--- keeps the words strategy's speed over a long body, so the words strategy can retire.
---
--- The second and third answers are the tier and the score inside it, for a consumer that
--- compares rows by proportion, the launcher's nearness rule, where a step of span would
--- read as closeness it is not. Returns nil when a word is absent, or when a word matched
--- only with gaps scores below the floor.
function M.fuzzy(query, hay)
  local words = {}
  for word in query:lower():gmatch("%S+") do words[#words + 1] = word end
  if #words == 0 then return 0, 0, 0 end
  local m = #hay
  if m == 0 then return nil end

  local long = m > LONG
  -- A short haystack is lowered here, once for every word, since it is short by definition
  -- and the dynamic program reads it byte by byte anyway. A long one comes from the memo.
  local hlow = long and lowered(hay) or hay:lower()

  local within, tier, span = 0, 0, 0
  for _, word in ipairs(words) do
    local n = #word
    span = span + n * TOP
    local score
    if long then
      local pos = hlow:find(word, 1, true)
      if not pos then return nil end
      score = runScore(hay, pos, n)
      tier = tier + 1
    else
      score = align(word, hay, hlow)
      if hlow:find(word, 1, true) then
        tier = tier + 1
      elseif score < minScore(n) then
        return nil
      end
    end
    within = within + score
  end
  -- The near free gap a word found whole can still pay, at most LONG bytes of it per word.
  span = span + #words * LONG * math.max(-GAP_LEAD, -GAP_TRAIL)
  return tier * span + within, tier, within
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
