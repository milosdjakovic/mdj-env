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

-- Scoring weights. A boundary must outrank a bare letter, so gh lands on GitHub's G
-- and H rather than the g in login. Word starts, camel humps, and consecutive
-- matches win, while gaps and length lose a little, all small enough that a boundary
-- always beats them.
local MATCH  = 1    -- every matched character is worth at least this
local START  = 10   -- the match is the first character of the haystack
local BOUND  = 8    -- the match sits just after a separator, a word start
local CAMEL  = 7    -- the match is an uppercase letter after a lowercase, a camel hump
local CONSEC = 6    -- the match directly follows the previous match
local LEAD   = 0.4  -- penalty per character skipped before the first match
local LENGTH = 0.04 -- penalty per haystack character, a mild bias toward tighter rows

--- M.fuzzy(query, hay) -> score or nil
--- A greedy subsequence scorer in the spirit of fzy, linear in the haystack length
--- with no matrix and no per-call allocation, so it stays cheap to run over a few
--- hundred rows on every keystroke. It matches each query character against the next
--- occurrence in the haystack, case insensitively, and awards boundary, camel, and
--- consecutive bonuses read from the original haystack so casing still informs the
--- rank. Greedy leftmost matching can miss the single best alignment on an adversarial
--- string, which never turns a real match into a miss, it only shifts a rank slightly,
--- a fair trade for the short labels these choosers hold. Returns nil when the query
--- is not a subsequence of the haystack.
function M.fuzzy(query, hay)
  local q = query:lower()
  local ql = #q
  if ql == 0 then return 0 end
  local hl = #hay
  if ql > hl then return nil end
  local hlow = hay:lower()

  local score = 0
  local qi = 1
  local qb = q:byte(1)
  local prev = 0    -- haystack index of the previous match, 0 for none yet
  local first = nil -- haystack index of the first match
  for hi = 1, hl do
    if hlow:byte(hi) == qb then
      if not first then first = hi end
      local bonus = 0
      if hi == 1 then
        bonus = START
      else
        local pb = hay:byte(hi - 1)
        if SEP[pb] then
          bonus = BOUND
        elseif isLower(pb) and isUpper(hay:byte(hi)) then
          bonus = CAMEL
        end
      end
      if prev > 0 and hi == prev + 1 then
        bonus = bonus + CONSEC
      end
      score = score + MATCH + bonus
      prev = hi
      qi = qi + 1
      if qi > ql then
        return score - (first - 1) * LEAD - hl * LENGTH
      end
      qb = q:byte(qi)
    end
  end
  return nil
end

--- M.substring(query, hay) -> score or nil
--- The pre-fuzzy behaviour, kept as the second strategy behind the same seam. A plain
--- case insensitive substring test. Every match scores zero, so the atom leaves
--- matches in their natural order, exactly what the choosers did before, so injecting
--- this at the root reproduces the old lists.
function M.substring(query, hay)
  local q = query:lower()
  if q == "" then return 0 end
  return (hay:lower():find(q, 1, true) and 0) or nil
end

return M
