-- Turns a row's icon into the picture the chooser shows, and does it when the chooser paints.
-- A row names its icon as data, icon, a key into the owning plugin's manifest icons or a table
-- spec for a glyph only known at runtime, a VPN country flag, plus iconOwner, the identity that
-- key is read against. Whoever knows the owner stamps it onto the row, the stage with the
-- presenting plugin, the query scope with the scope, the launcher with the row's own owner. The
-- chooser then asks instance.image(icon, iconOwner) for the picture each time it draws a row.
--
-- A row never holds a picture of an icon, and that is the point. A picture baked into a row when
-- the row was built is drawn in the colour of whichever half the system was in at that moment,
-- and the launcher keeps its rows across shows, so the icon kept its colour after a light and
-- dark switch. Resolving at paint reads the colour on every call, and the engine caches by
-- source, value, size and colour, so a frame costs a table lookup and a switch redraws each
-- symbol once, with no watcher and no cache that has to be told to flush.
--
-- A row that carries a real picture in image, an app icon, a file icon, a thumbnail, is not an
-- icon key and image wins over icon. Stamping copies a row before it sets the owner, because a
-- plugin may hold the row table it built. A row with no icon, or one that carries an image or
-- already names its owner, passes through untouched and uncopied.
--
-- An unknown key logs one warning per owner and key and the row shows no icon. instance.image
-- is the one place a key or spec becomes a picture, for a row at paint time and for anything
-- else, a plugin's own identity icon, so there is one copy of the rule.

local M = {}

--- M.new(opts) -> instance
--- opts.engine    a lib/icons instance, image(spec, points) and elements(spec, frame, points).
--- opts.declared  function of an owner identity answering that plugin's icons table or nil.
--- opts.points    the side the image is drawn at, what a chooser row scales down from.
--- opts.log       optional table with w, the warning sink.
--- opts.marks     optional { owner, chosen, notChosen }, Olm's own radio pair, the two keys and
---                the identity whose manifest declares them, a function when the identity is
---                only known after the resolver is built. A row saying chosen is drawn with it.
function M.new(opts)
  local engine = assert(opts.engine, "icons.rows, new needs an engine")
  local declared = assert(opts.declared, "icons.rows, new needs a declared function")
  local points = opts.points
  local log = opts.log
  local marks = opts.marks
  local warned = {}
  local instance = {}

  -- A key or a spec turned into a table spec, or nil, by the rules instance.image states.
  local function resolve(spec, owner)
    if spec == nil then return nil end
    if type(spec) == "string" then
      local icons = declared(owner)
      local entry = icons and icons[spec]
      if entry ~= nil then
        spec = entry
      elseif spec:match("^[%a_][%w_]*$") then
        local mark = tostring(owner) .. "\0" .. spec
        if log and not warned[mark] then
          warned[mark] = true
          log.w(string.format("icon '%s' is not declared by '%s', its row shows no icon", spec, tostring(owner)))
        end
        return nil
      else
        spec = { emoji = spec }
      end
    end
    if type(spec) ~= "table" then return nil end
    return spec
  end

  --- instance.image(spec, owner) -> hs.image or nil
  --- The one function turning an owner and an icon into an image, which every reader of an icon
  --- goes through, a row, a launcher row, an actions pane verb, a scope's own identity. spec is
  --- a table of source name to value, drawn as it stands, or a string. A string that is a key the
  --- owner declared in its manifest icons draws that entry. A string that is not an identifier,
  --- an emoji a person wrote over a plugin's default icon in their config, is the documented
  --- shorthand and means { emoji = string }. An identifier no manifest declared is a typo and
  --- logs one warning per owner and key, and nothing is drawn.
  function instance.image(spec, owner)
    spec = resolve(spec, owner)
    return spec and engine.image(spec, points) or nil
  end

  --- instance.elements(spec, owner, frame) -> array of canvas elements or nil
  --- The same resolution as image, answered as elements drawn into frame, for a canvas that
  --- paints the icon itself. A glyph is then text in the frame rather than a picture kept for
  --- the life of the config, see lib/icons/sources/emoji.lua.
  function instance.elements(spec, owner, frame)
    spec = resolve(spec, owner)
    return spec and engine.elements(spec, frame, points) or nil
  end

  --- instance.stamp(row, owner) -> row
  --- The row itself when it needs nothing, a shallow copy with iconOwner set when it names an
  --- icon, carries no picture and names no owner yet. It never draws anything.
  ---
  --- A row in a pick one list says chosen, true on the choice in force and false on the others,
  --- and never names the marker. Olm owns it, the radio pair every list shares, so the copy takes
  --- Olm's own key and owner over whatever icon the row named. A row of such a list that keeps a
  --- picture of its own on the rows not chosen, a flag or a device kind, leaves chosen unset there.
  function instance.stamp(row, owner)
    if type(row) == "table" and row.chosen ~= nil and marks then
      local markOwner = marks.owner
      if type(markOwner) == "function" then markOwner = markOwner() end
      local key = row.chosen and marks.chosen or marks.notChosen
      if row.icon == key and row.iconOwner == markOwner then return row end
      local copy = {}
      for k, v in pairs(row) do copy[k] = v end
      copy.icon, copy.iconOwner = key, markOwner
      return copy
    end
    if type(row) ~= "table" or row.icon == nil or row.image ~= nil or row.iconOwner ~= nil then
      return row
    end
    local copy = {}
    for k, v in pairs(row) do copy[k] = v end
    copy.iconOwner = owner
    return copy
  end

  --- instance.stampAll(rows, owner) -> rows, every one stamped. The list itself comes back
  --- when no row needed anything, so a long list of rows that carry images, the emoji picker's,
  --- is walked once and never copied.
  function instance.stampAll(rows, owner)
    local out
    for i, row in ipairs(rows or {}) do
      local stamped = instance.stamp(row, owner)
      if stamped ~= row then
        if not out then
          out = {}
          for j = 1, #rows do out[j] = rows[j] end
        end
        out[i] = stamped
      end
    end
    return out or rows
  end

  return instance
end

return M
