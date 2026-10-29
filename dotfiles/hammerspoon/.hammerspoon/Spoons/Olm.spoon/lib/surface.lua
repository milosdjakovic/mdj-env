-- One plugin's shared shape for a Hyper context, factored out once the twelve hand written
-- blocks in the old config/keys.lua were read side by side. Every one of them opens with a primary
-- verb, closes, and settles ties at the same priority, and ten of the twelve also move the
-- highlight, so a plugin should only ever have to say what its primary verb does and what else
-- it needs, never retype the verbs every list already agrees on. The keys those shared verbs sit
-- on are Olm's own all layer since phase 7 of the keymap plan, handed in, and this file names none.
--
-- Two of the twelve broke the shared pattern once it was checked rather than assumed. The
-- keep awake field is a single morphing row with nothing to move between, so it drops the
-- shared move keys entirely, and the launcher closes on a key of its own because that key is
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

-- The shared verbs every list agrees on, named once by what they do and never by the key they
-- sit on. Which key each one sits on is not this module's business. It is Olm's own all layer,
-- lib/keymap.lua's listDefaults, which the caller hands to context() as keys, and a person moves
-- one in the lists section of config/keymap.lua, so this file holds no key at all and the dry
-- gate refuses one written here. Each binding a shared verb builds carries the verb as shared,
-- which is how the keymap's lists layer finds the primary and the close of a list whose action
-- names differ from another's.
--
-- The action panel's own verb is one of them, named here as plain data with no reference to
-- what the action panel is or does. Every real context carried its chord once a loop at the
-- bottom of the old config/keys.lua added it, and this module carries it now, so a context built
-- here is honest about the whole set of keys live while it is open and no plugin has to declare
-- a surface of its own to earn a place in every list.
local MOVE_NEXT = { shared = "selectNext", action = "selectNext", description = "Move down" }
local MOVE_PREV = { shared = "selectPrev", action = "selectPrev", description = "Move up" }
local ACTION_PANEL = { shared = "openActionPanel", action = "openActionPanel", description = "Actions" }
-- The key panel's own verb, toggling the list of every key the open list answers above its
-- footer. Like the action panel's it names no plugin and sits in every block this module builds.
local SHOW_KEYS = { shared = "showKeys", action = "showKeys", description = "Keys" }

-- Where the all layer puts one shared verb, a list of places each holding a key, its modifiers
-- and its leader. An entry is a bare key name on the list role, a table of key, mods and leader
-- false for a key the open list's own field answers, or a list of such tables for a verb on more
-- than one key, see lib/keymap.lua's listDefaults. The leader is nil for a bare key, which is what
-- lets the keymap's lists layer place it on the list role later.
local function layerPlaces(entry)
  if entry == nil then return {} end
  if type(entry) ~= "table" then return { { key = entry } } end
  if entry.key ~= nil then return { entry } end
  return entry
end

-- A fresh copy of a list of modifiers, so two blocks never share one table a later pass edits.
local function copyMods(mods)
  if mods == nil then return nil end
  local out = {}
  for i, m in ipairs(mods) do out[i] = m end
  return out
end

-- One shared verb as bindings of its own, a fresh table for every context and every key the all
-- layer gives it, or none where the layer gives it no key, since a verb with no key is not bound.
local function sharedBindings(verb, keys)
  local out = {}
  for _, place in ipairs(layerPlaces((keys or {})[verb.shared])) do
    if place.key ~= nil then
      out[#out + 1] = { shared = verb.shared, key = place.key, mods = copyMods(place.mods), leader = place.leader,
        layerKey = true, action = verb.action, description = verb.description }
    end
  end
  return out
end

-- The close binding a context gets unless it says otherwise. A plugin overrides only the
-- field that differs for it, the launcher's own key standing in for the shared one, rather than
-- restating the action and the description every other context already shares. A key the
-- manifest states is that list's default, laid over the all layer's, and a close with no key
-- from either is not bound.
local function closeBinding(decl, keys)
  local close = decl.close
  if close == false then return nil end
  close = close or {}
  local key, layerKey = close.key, nil
  if key == nil then key, layerKey = (keys or {}).close, true end
  if key == nil then return nil end
  return {
    shared = "close",
    key = key,
    layerKey = layerKey,
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
-- does, the same two fields every binding a manifest declares carries whether or not it also
-- carries mods, a glyph, a when, or chord = false.
local function looksLikeBinding(value)
  return type(value) == "table" and type(value.key) == "string" and type(value.action) == "string"
end

-- A row of extra with no key, an action of the action panel alone, never bound and listed in no
-- key panel, so it needs a description for the panel to show. docs/PLAN-ACTION-PANEL.md.
local function looksLikePanelVerb(value)
  return type(value) == "table" and value.key == nil and type(value.action) == "string"
    and value.action ~= "" and type(value.description) == "string"
end

-- Checks the four fields a verb may carry for the action panel, section, applies, choices and
-- confirm, docs/PLAN-ACTION-PANEL.md. applies and choices name a method of the plugin's surface,
-- so each is a name rather than a function, and confirm is true or the confirm row's own title.
local function validatePanelFields(label, row)
  for _, field in ipairs({ "section", "applies", "choices" }) do
    local value = row[field]
    if value ~= nil and (type(value) ~= "string" or value == "") then
      return false, label .. "." .. field .. " is a " .. type(value) .. " rather than a name"
    end
  end
  if row.confirm ~= nil and row.confirm ~= true and (type(row.confirm) ~= "string" or row.confirm == "") then
    return false, label .. ".confirm is neither true nor the confirm row's title"
  end
  if row.choices ~= nil and row.confirm ~= nil then
    return false, label .. " sets both choices and confirm, and a verb opens one level or the other"
  end
  return true
end

-- Checks the three gates a binding may carry beyond its key and action, so a shape nothing
-- downstream could honour is named here rather than surfacing later as a binding that quietly
-- keeps a field no caller can make sense of. chord is only ever meaningful set to false, the
-- sentinel that lists a key in the key panel without binding it, so anything else in that
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

-- An icon on the primary or the secondary is a key of the manifest's own icons, a string, the
-- shape an extra row's icon takes. Whether the key is declared is the dry gate's literal scan, the
-- same check an extra row's icon gets, so this only refuses a value that is no key at all.
local function validateIcon(label, row)
  if row.icon ~= nil and (type(row.icon) ~= "string" or row.icon == "") then
    return false, label .. ".icon is a " .. type(row.icon) .. " rather than the name of one of the manifest's icons"
  end
  return true
end

-- The fields a secondary may carry, the same shape as primary. It names no key, since Command
-- and Return is Olm's own all layer, so a key, mods or leader written here is refused rather
-- than read as a second place a list key is set. chord is refused too, since chord false would
-- leave the action bar naming a Command and Return that nothing binds. icon names a key of the
-- manifest's own icons, the way an extra row's does, for its row in the action panel.
local SECONDARY_FIELDS = { action = true, description = true, needs = true, repeats = true, icon = true }

-- Checks the optional second action a list answers on Command and Return, the same way primary
-- is checked, and refuses any field the shape does not name.
local function validateSecondary(secondary)
  if type(secondary) ~= "table" then
    return false, "secondary is a " .. type(secondary) .. " rather than a table naming an action"
  end
  if type(secondary.action) ~= "string" or secondary.action == "" then
    return false, "secondary names no action for Command and Return to run"
  end
  if secondary.description ~= nil and type(secondary.description) ~= "string" then
    return false, "secondary.description is a " .. type(secondary.description) .. " rather than a string"
  end
  for field in pairs(secondary) do
    if not SECONDARY_FIELDS[field] then
      return false, "secondary." .. tostring(field) .. " is not a field a secondary takes, only action, description, needs, repeats and icon"
    end
  end
  local iok, ierr = validateIcon("secondary", secondary)
  if not iok then return false, ierr end
  return validateGates("secondary", secondary)
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
    return false, "primary names no action for the primary key to run"
  end
  if decl.primary.description ~= nil and type(decl.primary.description) ~= "string" then
    return false, "primary.description is a " .. type(decl.primary.description) .. " rather than a string"
  end
  local pok, perr = validateGates("primary", decl.primary)
  if not pok then return false, perr end
  local piok, pierr = validateIcon("primary", decl.primary)
  if not piok then return false, pierr end
  if decl.secondary ~= nil then
    local sok, serr = validateSecondary(decl.secondary)
    if not sok then return false, serr end
  end
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
      if not looksLikeBinding(row) and not looksLikePanelVerb(row) then
        return false, "extra[" .. i .. "] is not a binding, it needs a key and an action, or an"
          .. " action and a description with no key for a verb of the action panel alone"
      end
      local rok, rerr = validateGates("extra[" .. i .. "]", row)
      if not rok then return false, rerr end
      local fok, ferr = validatePanelFields("extra[" .. i .. "]", row)
      if not fok then return false, ferr end
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
-- The action panel's own binding and the key panel's are appended to every block this module
-- builds, as plain data naming no plugin, see ACTION_PANEL and SHOW_KEYS above.
--
-- keys is Olm's own all layer, a shared verb to the key it sits on, primary, secondary, selectNext,
-- selectPrev, close, openActionPanel and showKeys, lib/keymap.lua's listDefaults in a real load,
-- an entry being a bare key or a key the field answers with modifiers alone. A verb the
-- layer gives no key is left out of the block, and a close key the manifest states wins over the
-- layer's, since it is that list's own default. The person's lists section is laid over the built
-- block afterwards by lib/keymap.lua's applyLists, never here. A binding whose key came from the
-- all layer says so in layerKey, since a person's all moves only those, and a manifest that states
-- its own key for a shared verb, the launcher's close, keeps it unless the person names that list.
-- A binding dropped for a need this machine lacks is remembered in the block's unmet, its action to
-- the need, so an entry naming it is answered as a routine note rather than a typo.
--
-- available is optional, and it is how a binding's needs is honoured without this module ever
-- learning what any name means. Passing nothing here leaves every needs gated binding in
-- place undropped, which is what a context built from a plugin whose real data already
-- carries such a binding needs in order to round trip. A caller that has resolved which names
-- are present passes them here, and a binding naming one that is absent is dropped from the
-- built block entirely rather than landing as a key that does nothing.
function obj.context(name, decl, available, keys)
  local ok, err = obj.validate(name, decl)
  if not ok then
    log.e("plugin '" .. tostring(name) .. "' surface declaration is unusable, " .. err)
    return nil, err
  end

  local bindings = {}
  -- A binding dropped for an unmet need, by action, to the need it named.
  local unmet = {}
  local function take(binding)
    if keep(binding, available) then return true end
    unmet[binding.action] = binding.needs
    return false
  end

  -- chord, needs, repeats and icon are carried through from decl.primary rather than left behind
  -- the way only action and description used to be, so a primary binding is subject to the
  -- same gates as any other one this module builds.
  local primary = {
    shared = "primary",
    key = (keys or {}).primary,
    layerKey = true,
    action = decl.primary.action,
    description = decl.primary.description,
    chord = decl.primary.chord,
    needs = decl.primary.needs,
    repeats = decl.primary.repeats,
    icon = decl.primary.icon,
  }
  if primary.key ~= nil and take(primary) then
    bindings[#bindings + 1] = primary
  end

  -- The optional second action, right after the primary so the action panel lists the two
  -- together. It is built only when the list declares one, so a list with none binds nothing on
  -- its key and Command and Return keeps choosing the row there. The plugin's surface adapter
  -- answers its action the way it answers any extra row's.
  if decl.secondary then
    for _, secondary in ipairs(sharedBindings({ shared = "secondary", action = decl.secondary.action,
      description = decl.secondary.description }, keys)) do
      secondary.needs = decl.secondary.needs
      secondary.repeats = decl.secondary.repeats
      secondary.icon = decl.secondary.icon
      if take(secondary) then bindings[#bindings + 1] = secondary end
    end
  end

  -- Moving the highlight is the default because all but one of the contexts checked against
  -- this module are a list you scroll through. The one exception, a single morphing row with
  -- nothing to move between, sets nav to false rather than this module trying to infer it
  -- from whether decl.extra looks a certain way.
  if decl.nav ~= false then
    for _, verb in ipairs({ MOVE_NEXT, MOVE_PREV }) do
      for _, b in ipairs(sharedBindings(verb, keys)) do
        if take(b) then bindings[#bindings + 1] = b end
      end
    end
  end

  -- Extra bindings sit between the move keys and close because that is where every context
  -- that has any puts them, scrolling a preview, appending to a batch, walking a folder,
  -- never after the key that closes the list.
  -- A row with no key is a verb of the action panel alone, kept out of the bindings, since every
  -- reader of a binding reads its key, and listed in panel for the action panel and the dispatch.
  local panel = {}
  for _, row in ipairs(decl.extra or {}) do
    if take(row) then
      if row.key == nil then panel[#panel + 1] = row else bindings[#bindings + 1] = row end
    end
  end

  local close = closeBinding(decl, keys)
  if close and take(close) then
    bindings[#bindings + 1] = close
  end

  for _, verb in ipairs({ ACTION_PANEL, SHOW_KEYS }) do
    for _, b in ipairs(sharedBindings(verb, keys)) do bindings[#bindings + 1] = b end
  end

  return {
    name = name,
    when = obj.whenFor(name, decl),
    priority = decl.priority or 100,
    bindings = bindings,
    panel = panel[1] and panel or nil,
    unmet = next(unmet) and unmet or nil,
  }
end

return obj
