--- === labels ===
---
--- The one spelling of a chord and of a set of aliases, wherever a person reads one. Two surfaces
--- state a chord, every launcher row and the action bar, and two state a set of aliases, a
--- launcher row and the alias directory's own rows. Spelling either in each surface is how one key
--- came to read two ways depending on where you met it, one writing a plus where the other wrote a
--- space, and how one set of aliases differed by a leading space.
---
--- It moved here from the composition root, which still hands both functions to every surface
--- that spells one, so no surface spells its own. Pure, no state and no hs. The glyph helper a
--- chord is spelled with is the shared cheat sheet renderer's, handed in by the root rather than
--- loaded, since that renderer is an atom the spoon publishes once.

local obj = {}

--- labels.chordLabel(glyphFor) -> function(leader, key, mods) -> string
--- The speller every surface is handed, a leader's name then a space then the key glyph, the glyph
--- from glyphFor(key, mods). A leader spelled as a symbol, one with no letter in it, takes a thin
--- space rather than a full one, so it sits close to the glyph without touching it.
function obj.chordLabel(glyphFor)
  return function(leader, key, mods)
    local space = leader:find("%a") and " " or "\u{2009}"
    return leader .. space .. glyphFor(key, mods)
  end
end

--- labels.aliasLabel(aliases) -> string
--- The words alone, in brackets, or the empty string for none. A joining space is the caller's,
--- since it belongs to whichever surface is joining and not to the wording.
function obj.aliasLabel(aliases)
  if not aliases or #aliases == 0 then return "" end
  return "(" .. table.concat(aliases, ", ") .. ")"
end

return obj
