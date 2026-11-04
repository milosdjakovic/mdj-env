--- === labels ===
---
--- The one spelling of a chord and of a set of aliases, wherever a person reads one. Two surfaces
--- state a chord, every launcher row and the bottom bar, and two state a set of aliases, a
--- launcher row and the alias directory's own rows. Spelling either in each surface is how one key
--- came to read two ways depending on where you met it, one writing a plus where the other wrote a
--- space, and how one set of aliases differed by a leading space.
---
--- It moved here from the composition root, which still hands both functions to every surface
--- that spells one, so no surface spells its own. Pure, no state and no hs. A chord is a kbd chord,
--- lib/kbd.lua, the one vocabulary of keys.

local obj = {}

local kbd = assert(loadfile(debug.getinfo(1, "S").source:sub(2):match("(.*/)") .. "kbd.lua"))()

--- labels.chordLabel() -> function(leader, key, mods) -> chord
--- The speller every surface is handed, a leader key, a key name and its modifier names as one
--- kbd chord, the leader first. One entry per key and never a string, so how a chord is spaced is
--- decided where it is drawn, see lib/kbd.lua. A nil leader spells a plain combination.
function obj.chordLabel()
  return function(leader, key, mods)
    return kbd.binding(key, mods, leader)
  end
end

--- labels.leaderLegend(symbols, leaderSpecs) -> lines
--- The info pane's legend, one line per shipped leader in the order symbols lists them, each
--- { catalogName, key }, for every leader of this load's leaderSpecs that is one of them. A line is
--- { lead, label, badges }, the leader's symbol drawn before its word, and its physical key as the
--- chord, read from the load so a leader moved to another key says so. A held key is kbd.physical's,
--- a leader of modifiers alone is those modifiers, and a leader with neither has no chord.
function obj.leaderLegend(symbols, leaderSpecs)
  local lines = {}
  for _, entry in ipairs(symbols) do
    local word = entry.catalogName:sub(1, 1) .. entry.catalogName:sub(2):lower()
    for _, spec in ipairs(leaderSpecs) do
      if spec.catalogName == entry.catalogName then
        local where
        if spec.key then
          where = kbd.physical(tostring(spec.key))
        elseif type(spec.mods) == "table" and #spec.mods > 0 then
          where = kbd.modifiers(spec.mods)
        end
        lines[#lines + 1] = { lead = kbd.of(entry.key), label = word, badges = where and { where } or nil }
      end
    end
  end
  return lines
end

--- labels.aliasLabel(aliases) -> string
--- The words alone, in brackets, or the empty string for none. A joining space is the caller's,
--- since it belongs to whichever surface is joining and not to the wording.
function obj.aliasLabel(aliases)
  if not aliases or #aliases == 0 then return "" end
  return "(" .. table.concat(aliases, ", ") .. ")"
end

return obj
