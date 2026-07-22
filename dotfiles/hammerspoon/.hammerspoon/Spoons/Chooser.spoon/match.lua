--- === Chooser.match ===
---
--- Shared matching strategies for the Chooser atom. Each is a pure function
--- match(query, hay) -> score or nil. A nil means the row does not match and is
--- dropped. A number is a rank, higher is better, and the atom sorts survivors by it
--- with the original order breaking ties, so a stable secondary order like the
--- launcher's recency still shows through. This is the concrete policy the design
--- principles separate from the mechanism, injected once from the composition root so
--- every chooser shares one matcher and swapping them all is a single edit.

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
-- a camel hump (CAMEL), so a near-contiguous match like dspl over "Displays" outranks the
-- same letters scattered across the separate words of a keyword bag, which was the bug
-- that surfaced Device Management above Displays. START rewards the very first character.
-- Gaps come in three kinds, following fzy. A leading gap before the first match and a
-- trailing gap after the last are nearly free, so a term sitting deep in a long clipboard
-- body is not crushed by the text around it. An inner gap between two matched characters
-- costs real points, so spreading a query across a wide span loses, which is what pulls
-- the scattered keyword-bag matches down and, past a point, under the floor. A skipped
-- query character is a typo and costs TYPO, see below.
local MATCH   = 1
local START   = 10
local BOUND   = 7
local CAMEL   = 6
local CONSEC  = 10
local GAP_LEAD  = -0.02
local GAP_INNER = -0.4
local GAP_TRAIL = -0.02
local NEG       = -1e9

-- Typo tolerance. The matcher may skip a query character it cannot place, so a missed,
-- misspelled, or swapped letter still hits, each skip costing TYPO. There is no hard
-- budget: enough skips simply sink the score beneath the floor, which is what keeps a
-- query full of wrong letters from matching everything.
local TYPO = 6

-- The relevance floor. A subsequence match over a long searchable text, an app label
-- plus its hidden keyword bag, can line up by scattering letters across unrelated words
-- (typing dspl finds Trackpad through "...pa[d] [S]ystem ... track[p]ad ... c[l]ick").
-- Such a match earns few bonuses, so it scores low, and a minimum score scaled to the
-- query length, since a longer query naturally scores higher, drops the scattered tail
-- while every real match clears it easily. Raise FLOOR_STEP to cut more, lower it to
-- keep more.
local FLOOR_BASE = 2
local FLOOR_STEP = 3.5
local function minScore(n) return FLOOR_BASE + (n - 1) * FLOOR_STEP end

-- The bonus for matching a query character at haystack position j (1-based), read from
-- the original haystack so casing still informs the rank.
local function bonusAt(hay, j)
  if j == 1 then return START end
  local pb = hay:byte(j - 1)
  if SEP[pb] then return BOUND end
  if isLower(pb) and isUpper(hay:byte(j)) then return CAMEL end
  return 0
end

--- M.fuzzy(query, hay) -> score or nil
--- A dynamic-programming subsequence scorer in the spirit of fzy, with bounded typo
--- tolerance. Two rolling rows carry D, the best score of an alignment whose last query
--- character is matched at this haystack position, and Mrow, the best score of matching
--- the query prefix within this haystack prefix. A match opens a run with a boundary or
--- camel bonus or extends one with the consecutive bonus; Mrow then takes the best of
--- matching here, skipping this haystack character for a gap, or skipping this query
--- character as a typo. The gap is leading before the first match, trailing on the last
--- query character, or inner between matches, and only the inner gap costs much, so span
--- is penalized while position within a long body is not. Because it explores every
--- alignment rather than greedily taking the leftmost letter, it finds a term late in a
--- long body and tolerates a swapped or wrong letter, where a greedy scan would lock onto
--- the wrong occurrence and starve the rest. It runs in the query length times the
--- haystack length per row, cheap over a few hundred rows at typing speed. Returns nil
--- when the best alignment scores below the relevance floor, which is where absent
--- letters, too many typos, and the scattered tail all land.
function M.fuzzy(query, hay)
  local q = query:lower()
  local n = #q
  if n == 0 then return 0 end
  local m = #hay
  if m == 0 then return nil end
  local hlow = hay:lower()

  -- Row 0, no query characters consumed yet. Mrow is zero everywhere so a match may open
  -- at any position, and D is impossible.
  local Mprev, Dprev = {}, {}
  for j = 0, m do Mprev[j] = 0; Dprev[j] = NEG end

  for i = 1, n do
    local qb = q:byte(i)
    -- The gap that trails the final query character is nearly free, so a match near the
    -- front of a long body is not punished for the text after it; inner gaps between
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
          -- The first character pays only a near-free leading gap for how far in it sits.
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

  local score = Mprev[m]
  if score < minScore(n) then return nil end
  return score
end

--- M.substring(query, hay) -> score or nil
--- The pre-fuzzy behaviour, kept as the second strategy behind the same seam. A plain
--- case insensitive substring test, no typo tolerance and no floor. Every match scores
--- zero, so the atom leaves matches in their natural order, exactly what the choosers
--- did before, so injecting this at the root reproduces the old lists.
function M.substring(query, hay)
  local q = query:lower()
  if q == "" then return 0 end
  return (hay:lower():find(q, 1, true) and 0) or nil
end

return M
