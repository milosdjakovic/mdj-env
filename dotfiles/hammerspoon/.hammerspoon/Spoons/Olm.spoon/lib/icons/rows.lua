-- Turns a row's icon into the image the chooser shows, in the one place both callers share.
-- The stage runs it on the rows of a presentation and the query scope runs it on the rows of a
-- launcher scope, and both hand it the owning plugin's identity, so a key means the same thing
-- wherever the row ends up.
--
-- A row carries icon as data, a key into the owning plugin's manifest icons or a table spec for
-- a glyph only known at runtime, a VPN country flag. A row that already carries an image keeps
-- it, since a real picture, an app icon or a file icon, is not an icon key. The row is copied
-- before the image is set, because a plugin may hold the row table it built, and an image
-- drawn for one colour must not stay on a row that outlives a theme switch.
--
-- An unknown key logs one warning per owner and key and the row shows no icon. A row with no
-- icon field passes through untouched and uncopied. instance.image is the same resolution for
-- anything that is not a row, a plugin's own identity icon, so there is one copy of the rule.

local M = {}

--- M.new(opts) -> instance
--- opts.engine    a lib/icons instance, image(spec, points).
--- opts.declared  function of an owner identity answering that plugin's icons table or nil.
--- opts.points    the side the image is drawn at, what a chooser row scales down from.
--- opts.log       optional table with w, the warning sink.
function M.new(opts)
  local engine = assert(opts.engine, "icons.rows, new needs an engine")
  local declared = assert(opts.declared, "icons.rows, new needs a declared function")
  local points = opts.points
  local log = opts.log
  local warned = {}
  local instance = {}

  --- instance.image(spec, owner) -> hs.image or nil
  --- The one function turning an owner and an icon into an image, which every reader of an icon
  --- goes through, a row, a launcher row, an action panel verb, a scope's own identity. spec is
  --- a table of source name to value, drawn as it stands, or a string. A string that is a key the
  --- owner declared in its manifest icons draws that entry. A string that is not an identifier,
  --- an emoji a person wrote over a plugin's default icon in their config, is the documented
  --- shorthand and means { emoji = string }. An identifier no manifest declared is a typo and
  --- logs one warning per owner and key, and nothing is drawn.
  function instance.image(spec, owner)
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
    return engine.image(spec, points)
  end

  --- instance.resolve(row, owner) -> row
  --- The row itself when it needs nothing, a shallow copy with image set when it does.
  function instance.resolve(row, owner)
    if type(row) ~= "table" or row.icon == nil or row.image ~= nil then return row end
    local copy = {}
    for k, v in pairs(row) do copy[k] = v end
    copy.image = instance.image(row.icon, owner)
    return copy
  end

  --- instance.resolveAll(rows, owner) -> rows, every one resolved. The list itself comes back
  --- when no row needed anything, so a long list of rows that carry images, the emoji picker's,
  --- is walked once and never copied.
  function instance.resolveAll(rows, owner)
    local out
    for i, row in ipairs(rows or {}) do
      local resolved = instance.resolve(row, owner)
      if resolved ~= row then
        if not out then
          out = {}
          for j = 1, #rows do out[j] = rows[j] end
        end
        out[i] = resolved
      end
    end
    return out or rows
  end

  return instance
end

return M
