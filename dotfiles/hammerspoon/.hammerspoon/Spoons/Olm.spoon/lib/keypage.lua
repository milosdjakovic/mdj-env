--- === keypage ===
---
--- The OLM keys page, every chord Olm binds listed read only, so a person can see their keys. It is
--- Olm's own list rather than a plugin's, reached by the launcher's own OLM keys row, which the
--- root answers in the launcher's row intercept by pushing this presentation onto the stage over
--- the open launcher, so the launcher's list becomes this one in place. Back, or Backspace on an
--- empty field, pops it and the launcher's list comes back.
---
--- Pure, no state and no hs. The contract is the deps table presentation takes.
---
---   name      the presentation's name, the launcher's identity, since a level pushed over a list
---             is named for that list, the stage's own rule for a child, so its icon keys are read
---             against the launcher's manifest.
---   catalog   a function answering the entries, lib/hints.lua's keyEntries, { chord, description,
---             owner, list }, which the root builds once per load and keeps.
---   pop       the stage's pop, what the Back row asks.
---
--- The page is read only. A key is changed in config/keymap.lua, so a row only says what is bound,
--- and choosing one answers stay and does nothing, so the page never pops or closes under a person
--- reading it.

local M = {}

-- The icon keys, declared with their glyphs in the launcher's manifest.
M.ICON_KEY = "keys"
M.ICON_BACK = "back"

--- M.subtitle(entry) -> string
--- The chord and whose it is. A list key reads as the chord in that list, the words the action
--- panel uses for a verb of a hosted list, and a global key as the chord and its owner, joined by
--- the middot a launcher row joins its category and chord with. An owner the title already says,
--- a tool's own open key, is not said twice.
function M.subtitle(entry)
  local chord = tostring(entry.chord)
  if entry.list then return chord .. " in " .. tostring(entry.list) end
  if entry.owner == nil or entry.owner == entry.description then return chord end
  return chord .. " · " .. tostring(entry.owner)
end

--- M.rows(catalog) -> rows
--- Back, pinned so the shared search never drops it, then one row per entry in the catalog's
--- order, every global key a leader at a time and then every list's keys a list at a time. The
--- subtitle stays searchable, since on this page the chord is what a person looks a key up by,
--- Hyper K or Meta, and the owner joins as a keyword so a plugin's name finds every key it has.
function M.rows(catalog)
  local rows = { { title = "Back", icon = M.ICON_BACK, item = { back = true }, pinned = true } }
  for _, entry in ipairs(catalog or {}) do
    rows[#rows + 1] = {
      title = tostring(entry.description),
      subTitle = M.subtitle(entry),
      icon = M.ICON_KEY,
      item = { boundKey = true },
      keywords = entry.owner ~= entry.description and entry.owner or nil,
    }
  end
  return rows
end

--- M.presentation(deps) -> presentation
--- A fresh presentation per push. The keymap is fixed for the load and nothing on this page
--- changes it, so the rows are built once, on the first rebuild of this show, and every rebuild a
--- keystroke causes hands back the same list.
function M.presentation(deps)
  local shown = nil
  return {
    name = deps.name,
    placeholder = "OLM keys",
    rows = function()
      shown = shown or M.rows(deps.catalog())
      return shown
    end,
    -- Every reachable row is caught by intercept below, but the field is required on every
    -- presentation.
    onSelect = function() end,
    intercept = function(item)
      if type(item) ~= "table" then return false end
      if item.back then
        if deps.pop then deps.pop() end
        return true
      end
      if item.boundKey then return "stay" end
      return false
    end,
  }
end

return M
