-- One plugin's shared shape for a Hyper context, factored out once the twelve hand written
-- blocks in config/keys.lua were read side by side. Every one of them opens with a primary
-- verb on i, closes on x, and settles ties at the same priority, and ten of the twelve also
-- move the highlight on j and k, so a plugin should only ever have to say what its primary
-- verb does and what else it needs, never retype the keys every list already agrees on.
--
-- Two of the twelve broke the shared pattern once it was checked rather than assumed. The
-- keep awake field is a single morphing row with nothing to move between, so it drops the
-- shared move keys entirely, and the launcher closes on space rather than x because space is
-- also its own open key. Both are expressed here as fields on the declaration rather than as
-- a plugin name this module recognises, since a name check here would be exactly the special
-- casing the twelve were read side by side to avoid.

local obj = {}

-- hs.logger is the one hs call this module makes, and only to name a bad declaration in the
-- console, so a plain Lua load with no Hammerspoon running still works for a unit test. A
-- silent stub in that case keeps the module loadable rather than failing on the first line.
local log
if hs and hs.logger then
  log = hs.logger.new("Surface", "info")
else
  log = { e = function() end, w = function() end, i = function() end }
end

-- The two bindings every list with anything to move between agrees on, named once so a
-- wording change is one edit here rather than a hunt through twelve blocks that used to
-- repeat it by hand.
local MOVE_NEXT = { key = "j", action = "selectNext", description = "Move down" }
local MOVE_PREV = { key = "k", action = "selectPrev", description = "Move up" }

-- The action panel's own chord, named here as plain data with no reference to what the
-- action panel is or does, the same way every other binding this module builds names only a
-- key and an action. Every real context carries this chord today, added by a loop at the
-- bottom of config/keys.lua, and this module now carries it too, so a context built here is
-- honest about the whole set of keys live while it is open and the chord no longer depends on
-- a loop somewhere else remembering to add it, or on the action panel plugin declaring a
-- surface of its own to earn a place in every list.
local ACTION_PANEL_BINDING = { key = ".", action = "openActionPanel", description = "Actions" }

-- The close binding a context gets unless it says otherwise. A plugin overrides only the
-- field that differs for it, the launcher's key of space standing in for x, rather than
-- restating the action and the description every other context already shares.
local function closeBinding(decl)
  local close = decl.close
  if close == false then return nil end
  close = close or {}
  return {
    key = close.key or "x",
    action = close.action or "closeChooser",
    description = close.description or "Close",
    -- Carried through rather than left behind, the same as the primary binding does below,
    -- so a plugin that ever needs its close key gated behaves no differently than any other
    -- binding this module builds.
    chord = close.chord,
    needs = close.needs,
    repeats = close.repeats,
  }
end

-- Whether a binding belongs in the built block. A binding naming no requirement always
-- belongs. One naming a requirement belongs only when the caller's available table says the
-- name is present, and passing no available table at all is read as not filtering anything,
-- which is what lets a context round trip against real data that carries a needs gated
-- binding with nothing here ever having dropped it. The caller answers what a name means,
-- this module only asks whether the one it was given is there.
local function keep(binding, available)
  if binding.needs == nil then return true end
  if available == nil then return true end
  return available[binding.needs] == true
end

-- The loose shape a row in `extra` is trusted to have, a key and an action naming what it
-- does, the same two fields every binding in config/keys.lua carries whether or not it also
-- carries mods, a glyph, a when, or chord = false.
local function looksLikeBinding(value)
  return type(value) == "table" and type(value.key) == "string" and type(value.action) == "string"
end

-- Checks the three gates a binding may carry beyond its key and action, so a shape nothing
-- downstream could honour is named here rather than surfacing later as a binding that quietly
-- keeps a field no caller can make sense of. chord is only ever meaningful set to false, the
-- sentinel that lists a key in the hint panel without binding it, so anything else in that
-- field cannot be honoured. needs only ever names a requirement as a string, the name a
-- caller's available table is asked about. repeats only ever answers whether the key auto
-- repeats, plainly true or false.
local function validateGates(label, row)
  if row.chord ~= nil and row.chord ~= false then
    return false, label .. ".chord is set to something other than false, and false is its only honoured value"
  end
  if row.needs ~= nil and type(row.needs) ~= "string" then
    return false, label .. ".needs is a " .. type(row.needs) .. " rather than a string naming what it depends on"
  end
  if row.repeats ~= nil and type(row.repeats) ~= "boolean" then
    return false, label .. ".repeats is a " .. type(row.repeats) .. " rather than a boolean"
  end
  return true
end

-- Checks a declaration is usable before context() trusts it, so a plugin with no primary
-- verb or a malformed extra row is named in the console rather than silently producing a
-- context that binds nothing on i, or failing deep inside whatever later walks the bindings
-- list expecting every row to look like one.
function obj.validate(name, decl)
  if type(name) ~= "string" or name == "" then
    return false, "needs a context name to key the hyperContexts block on"
  end
  if type(decl) ~= "table" then
    return false, "surface declaration is a " .. type(decl) .. " rather than a table"
  end
  if type(decl.primary) ~= "table" then
    return false, "primary is a " .. type(decl.primary) .. " rather than a table naming an action"
  end
  if type(decl.primary.action) ~= "string" or decl.primary.action == "" then
    return false, "primary names no action for the i key to run"
  end
  if decl.primary.description ~= nil and type(decl.primary.description) ~= "string" then
    return false, "primary.description is a " .. type(decl.primary.description) .. " rather than a string"
  end
  local pok, perr = validateGates("primary", decl.primary)
  if not pok then return false, perr end
  if decl.nav ~= nil and type(decl.nav) ~= "boolean" then
    return false, "nav is a " .. type(decl.nav) .. " rather than a boolean"
  end
  if decl.close ~= nil and decl.close ~= false and type(decl.close) ~= "table" then
    return false, "close is a " .. type(decl.close) .. " rather than a table or false"
  end
  if type(decl.close) == "table" then
    local cok, cerr = validateGates("close", decl.close)
    if not cok then return false, cerr end
  end
  if decl.extra ~= nil then
    if type(decl.extra) ~= "table" then
      return false, "extra is a " .. type(decl.extra) .. " rather than a list of bindings"
    end
    for i, row in ipairs(decl.extra) do
      if not looksLikeBinding(row) then
        return false, "extra[" .. i .. "] is not a binding, it needs a key and an action"
      end
      local rok, rerr = validateGates("extra[" .. i .. "]", row)
      if not rok then return false, rerr end
    end
  end
  if decl.when ~= nil and type(decl.when) ~= "string" then
    return false, "when is a " .. type(decl.when) .. " rather than a string"
  end
  if decl.priority ~= nil and type(decl.priority) ~= "number" then
    return false, "priority is a " .. type(decl.priority) .. " rather than a number"
  end
  return true
end

-- The predicate name a context is gated on, named as its own function rather than left inline
-- inside context() below. A caller has to install this exact name into a predicate table
-- before any context is bound, at an earlier stage than the one that calls obj.context, so it
-- must be answerable on its own rather than only as a side effect of building a whole block,
-- which is what left a caller guessing it before this existed. Defaults to the context name
-- with Open appended, so browserTabs gives browserTabsOpen, and a plugin that ever needs to
-- differ still says so through decl.when rather than this module growing a name based
-- exception for it.
function obj.whenFor(name, decl)
  decl = decl or {}
  return decl.when or (name .. "Open")
end

-- Builds one hyperContexts block from a plugin's surface declaration. when comes from
-- obj.whenFor above, and priority is derived in the same spirit, since every context checked
-- against this module settles ties at the same 100, and a plugin that ever needs to differ
-- says so by passing priority through decl rather than this module growing a name based
-- exception for it.
--
-- The action panel's own binding, Hyper and period, is appended to every block this module
-- builds. Every real context carries that chord today, added by a loop at the bottom of
-- config/keys.lua, and stating it here once, as plain data naming no plugin, keeps a context
-- built here honest about the whole set of keys live while it is open with no dependence on a
-- loop elsewhere remembering it or on the action panel plugin declaring a surface to earn it.
--
-- available is optional, and it is how a binding's needs is honoured without this module ever
-- learning what any name means. Passing nothing here leaves every needs gated binding in
-- place undropped, which is what a context built from a plugin whose real data already
-- carries such a binding needs in order to round trip. A caller that has resolved which names
-- are present passes them here, and a binding naming one that is absent is dropped from the
-- built block entirely rather than landing as a key that does nothing.
function obj.context(name, decl, available)
  local ok, err = obj.validate(name, decl)
  if not ok then
    log.e("plugin '" .. tostring(name) .. "' surface declaration is unusable, " .. err)
    return nil, err
  end

  local bindings = {}

  -- chord, needs and repeats are carried through from decl.primary rather than left behind
  -- the way only action and description used to be, so a primary binding is subject to the
  -- same gates as any other one this module builds.
  local primary = {
    key = "i",
    action = decl.primary.action,
    description = decl.primary.description,
    chord = decl.primary.chord,
    needs = decl.primary.needs,
    repeats = decl.primary.repeats,
  }
  if keep(primary, available) then
    bindings[#bindings + 1] = primary
  end

  -- Moving the highlight is the default because all but one of the contexts checked against
  -- this module are a list you scroll through. The one exception, a single morphing row with
  -- nothing to move between, sets nav to false rather than this module trying to infer it
  -- from whether decl.extra looks a certain way.
  if decl.nav ~= false then
    if keep(MOVE_NEXT, available) then bindings[#bindings + 1] = MOVE_NEXT end
    if keep(MOVE_PREV, available) then bindings[#bindings + 1] = MOVE_PREV end
  end

  -- Extra bindings sit between the move keys and close because that is where every context
  -- that has any puts them, scrolling a preview, appending to a batch, walking a folder,
  -- never after the key that closes the list.
  for _, row in ipairs(decl.extra or {}) do
    if keep(row, available) then
      bindings[#bindings + 1] = row
    end
  end

  local close = closeBinding(decl)
  if close and keep(close, available) then
    bindings[#bindings + 1] = close
  end

  bindings[#bindings + 1] = ACTION_PANEL_BINDING

  return {
    name = name,
    when = obj.whenFor(name, decl),
    priority = decl.priority or 100,
    bindings = bindings,
  }
end

return obj
