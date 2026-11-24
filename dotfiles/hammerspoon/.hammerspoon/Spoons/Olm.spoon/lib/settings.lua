-- Olm Settings, every setting the Olm Settings window shows, and the one store on this Mac that
-- holds what was set there, docs/DESIGN-APP-SETTINGS.md.
--
-- A setting is declared once here, its id, its section, its title and the words a search finds it
-- by, its kind, its choices or its range, whether it applies at once or on a reload, and where its
-- default comes from. Live is only what the root can apply without a reload, the placement, the
-- theme and the highlight, since every other value is copied into the look, the leaders or the
-- lists as Olm loads. The rest apply in one reload when the window closes, S.3. The default is always the config file's own value, so a new machine starts
-- from the files, and a value saved in the store wins over it on this one.
--
-- The store is one JSON file, ~/.olm/state/settings.json, { version = 1, values = { id = value } }.
-- Nothing else on this Mac answers a setting the store holds. The five keys Hammerspoon's own
-- settings held before it, the chooser, the canvas theme, the glass highlight, the placement and
-- the plugins switched off, are moved into it once by migrate and removed there.
--
-- Everything here is plain Lua. The file read and write, the JSON codec and the old store are
-- handed in, so test/settings.lua drives it with no Hammerspoon at all.

local M = {}

M.VERSION = 1

--- M.SECTIONS, the sidebar of the window, in its order. symbol is the SF Symbol beside the title.
M.SECTIONS = {
  { id = "general", title = "General", symbol = "gearshape" },
  { id = "appearance", title = "Appearance", symbol = "paintbrush" },
  { id = "motion", title = "Motion", symbol = "wind" },
  { id = "behaviour", title = "Behaviour", symbol = "hand.tap" },
  { id = "leaders", title = "Leaders", symbol = "command" },
  { id = "applications", title = "Applications", symbol = "square.grid.2x2" },
  { id = "windows", title = "Window Management", symbol = "macwindow" },
  { id = "plugins", title = "Plugins", symbol = "puzzlepiece.extension" },
}

--- M.LEGACY, each old hs.settings key and the id its value moves to. A function turns the old
--- shape into the new one, the placement's table into its mode.
M.LEGACY = {
  olmChooser = { id = "chooser" },
  olmTheme = { id = "theme" },
  olmGlassHighlight = { id = "highlight" },
  overlayDisplayPolicy = { id = "placement", from = function(old)
    return type(old) == "table" and old.mode or nil
  end },
  ["Olm.disabledPlugins"] = { id = "plugins.off" },
}

-- The fixed declarations. target is where the value lives once loaded, the root's table first, so
-- overlay(name, root) reads the default there and lays a saved value over it. shipped is the
-- default when the file leaves the key out, the value the reader itself would use then.
local function n(id, section, title, target, min, max, step, unit, shipped, keywords)
  return { id = id, section = section, title = title, kind = "number", target = target, min = min,
    max = max, step = step, unit = unit, shipped = shipped, keywords = keywords or {}, applies = "reload" }
end

--- M.LEADER_KEYS, the physical keys a leader may sit on, lib/keyremap.lua's allow list in the order
--- the menu lists them, left and right apart, and none for a leader of real modifiers alone.
M.LEADER_KEYS = {
  { value = "capsLock", title = "Caps Lock" },
  { value = "leftShift", title = "Left Shift" }, { value = "rightShift", title = "Right Shift" },
  { value = "leftControl", title = "Left Control" }, { value = "rightControl", title = "Right Control" },
  { value = "leftOption", title = "Left Option" }, { value = "rightOption", title = "Right Option" },
  { value = "leftCommand", title = "Left Command" }, { value = "rightCommand", title = "Right Command" },
  { value = "f13", title = "F13" }, { value = "f14", title = "F14" }, { value = "f15", title = "F15" },
  { value = "f16", title = "F16" }, { value = "f17", title = "F17" }, { value = "f18", title = "F18" },
  { value = "f19", title = "F19" }, { value = "f20", title = "F20" },
  { value = "none", title = "None, Real Modifiers Only" },
}

--- M.LEADER_SENDS, how the key reaches Olm, a function key through hidutil, the leader's real
--- modifiers through kanata, or both, which is how Hyper and META ship.
M.LEADER_SENDS = {
  { value = "both", title = "Real Modifiers and a Function Key" },
  { value = "mods", title = "Real Modifiers" },
  { value = "fkey", title = "A Function Key" },
}

M.LEADER_SENDS_DETAIL = "A function key needs nothing extra, but stops working while any app has a "
  .. "password field open, and Olm tells you which app. Real modifiers need kanata and keep working "
  .. "in password fields, but other apps lose the shortcuts they use. Both picks whichever arrives."

M.LEADER_KEY_DETAIL = "A left Shift, Control, Option or Command made a leader stops working as "
  .. "itself, so use the right one for that."

M.DECLARED = {
  { id = "chooser", section = "general", title = "Chooser", kind = "choice", applies = "reload",
    keywords = { "glass", "canvas", "provider", "picker", "swift" } },
  { id = "placement", section = "general", title = "Placement", kind = "choice", applies = "live",
    keywords = { "display", "screen", "cursor", "monitor", "active window" },
    choices = { { value = "cursor", title = "Under the cursor" },
                { value = "activeWindow", title = "With the active window" } } },
  n("rowLimit", "general", "Rows per list", { "policy", "chooserRowLimit" }, 10, 500, 10, "rows", 50,
    { "limit", "more", "page" }),

  { id = "theme", section = "appearance", title = "Theme", kind = "choice", applies = "live",
    keywords = { "colour", "color", "palette", "dark", "light" } },
  { id = "highlight", section = "appearance", title = "Highlight", kind = "choice", applies = "live",
    keywords = { "theme", "accent", "colour", "color", "glass", "selection" } },
  { id = "font.ui", section = "appearance", title = "Interface font", kind = "font", applies = "reload",
    target = { "typography", "fonts", "ui" }, keywords = { "typeface", "text" } },
  { id = "font.mono", section = "appearance", title = "Code font", kind = "font", applies = "reload",
    target = { "typography", "fonts", "mono" }, keywords = { "typeface", "monospaced", "fixed" } },
  n("size.title", "appearance", "Title size", { "typography", "sizes", "title" }, 10, 32, 1, "points", nil,
    { "text", "font" }),
  n("size.body", "appearance", "Body size", { "typography", "sizes", "body" }, 10, 32, 1, "points", nil,
    { "text", "font", "row" }),
  n("size.caption", "appearance", "Caption size", { "typography", "sizes", "caption" }, 10, 32, 1, "points", nil,
    { "text", "font", "subtitle" }),
  n("size.section", "appearance", "Section size", { "typography", "sizes", "section" }, 10, 32, 1, "points", nil,
    { "text", "font", "heading" }),
  n("size.code", "appearance", "Code size", { "typography", "sizes", "code" }, 10, 32, 1, "points", nil,
    { "text", "font", "monospaced" }),
  -- The icon sets' choices are the sources the root builds, declared there, and the file's
  -- reader fills a key it leaves out, so neither carries a value here.
  { id = "icons.set", section = "appearance", title = "Icon set", kind = "choice", applies = "reload",
    target = { "icons", "set" }, keywords = { "symbols", "glyphs", "pictures" } },
  { id = "icons.fallback", section = "appearance", title = "Icon fallback", kind = "choice", applies = "reload",
    target = { "icons", "fallback" }, keywords = { "symbols", "glyphs", "pictures" } },
  n("cornerRadius", "appearance", "Corner radius", { "policy", "surface", "cornerRadius" }, 0, 24, 1, "points", 17,
    { "rounded", "corners", "radius" }),
  n("borderWidth", "appearance", "Border width", { "policy", "surface", "borderWidth" }, 0, 3, 0.5, "points", 1,
    { "outline", "stroke", "edge" }),
  n("spacing.outer", "appearance", "Outer padding", { "policy", "spacing", "outer" }, 0, 24, 1, "points", 9,
    { "margin", "space", "gap" }),
  n("spacing.inner", "appearance", "Inner padding", { "policy", "spacing", "inner" }, 0, 24, 1, "points", 14,
    { "margin", "space", "row" }),
  n("spacing.bar", "appearance", "Bar padding", { "policy", "spacing", "bar" }, 0, 16, 1, "points", 6,
    { "margin", "space", "bottom bar" }),

  n("motion.show", "motion", "Show and hide", { "policy", "motion", "show" }, 0, 0.5, 0.01, "seconds", 0.15,
    { "animation", "speed", "open", "close", "fade" }),
  n("motion.reshape", "motion", "Reshape", { "policy", "motion", "reshape" }, 0, 0.5, 0.01, "seconds", 0.18,
    { "animation", "speed", "resize", "preview" }),
  n("motion.rise", "motion", "Rise", { "policy", "motion", "rise" }, 0, 20, 1, "points", 4,
    { "animation", "offset", "slide" }),
  n("motion.scale", "motion", "Scale", { "policy", "motion", "scale" }, 0.8, 1, 0.01, "times", 0.98,
    { "animation", "zoom", "grow" }),

  n("cycleIdle", "behaviour", "The fn cycle's wait", { "stage", "CYCLE_IDLE" }, 0.3, 2, 0.05, "seconds", 0.8,
    { "input source", "keyboard", "language", "globe", "fn" }),
  n("cheatSheetDelay", "behaviour", "Cheat sheet delay", { "policy", "chord", "holdDelay" }, 0.1, 2, 0.05,
    "seconds", 0.6, { "hold", "reveal", "leader", "hyper", "meta" }),
  -- macOS's own input source picker on a tap of fn is no setting. Input Sources owns the Globe key
  -- while it is on, claimed exclusively so macOS shows nothing, and with it off macOS answers the tap.

  -- Window Management's steps and sizes are the window manager's, declared in its manifest and
  -- read by M.fromManifest, since only a plugin may name itself.

  -- The three leaders, each its physical key, how that key reaches Olm and whether a hold shows its
  -- cheat sheet, docs/DESIGN-APP-LEADERS.md. The root lays them over SHIPPED_LEADERS as the leaders
  -- section of config/keymap.lua is laid, gives each its default from there, and locks a leader that
  -- section names. They apply on a reload, since Hammerspoon still builds the leaders.
  { id = "leader.hyper.key", section = "leaders", title = "Hyper Key", kind = "choice", applies = "reload",
    choices = M.LEADER_KEYS, detail = M.LEADER_KEY_DETAIL, keywords = { "hyper", "leader", "modifier", "remap", "caps lock", "left", "right" } },
  { id = "leader.hyper.sends", section = "leaders", title = "Hyper Sends", kind = "choice", applies = "reload",
    choices = M.LEADER_SENDS, detail = M.LEADER_SENDS_DETAIL,
    keywords = { "hyper", "leader", "kanata", "karabiner", "function key", "password", "secure input", "modifiers" } },
  { id = "leader.hyper.sheet", section = "leaders", title = "Hyper Cheat Sheet on Hold", kind = "switch",
    applies = "reload", keywords = { "hyper", "leader", "cheat sheet", "shortcuts", "hold" } },
  { id = "leader.meta.key", section = "leaders", title = "META Key", kind = "choice", applies = "reload",
    choices = M.LEADER_KEYS, detail = M.LEADER_KEY_DETAIL, keywords = { "meta", "leader", "modifier", "remap", "caps lock", "left", "right" } },
  { id = "leader.meta.sends", section = "leaders", title = "META Sends", kind = "choice", applies = "reload",
    choices = M.LEADER_SENDS, detail = M.LEADER_SENDS_DETAIL,
    keywords = { "meta", "leader", "kanata", "karabiner", "function key", "password", "secure input", "modifiers" } },
  { id = "leader.meta.sheet", section = "leaders", title = "META Cheat Sheet on Hold", kind = "switch",
    applies = "reload", keywords = { "meta", "leader", "cheat sheet", "shortcuts", "hold" } },
  { id = "leader.super.key", section = "leaders", title = "SUPER Key", kind = "choice", applies = "reload",
    choices = M.LEADER_KEYS, detail = M.LEADER_KEY_DETAIL, keywords = { "super", "leader", "modifier", "remap", "caps lock", "left", "right" } },
  { id = "leader.super.sends", section = "leaders", title = "SUPER Sends", kind = "choice", applies = "reload",
    choices = M.LEADER_SENDS, detail = M.LEADER_SENDS_DETAIL,
    keywords = { "super", "leader", "kanata", "karabiner", "function key", "password", "secure input", "modifiers" } },
  { id = "leader.super.sheet", section = "leaders", title = "SUPER Cheat Sheet on Hold", kind = "switch",
    applies = "reload", keywords = { "super", "leader", "cheat sheet", "shortcuts", "hold" } },

  -- Every key set in Olm Settings, an action id to its chord, hyper+C, or false for none, laid over
  -- config/keymap.lua and this machine's app keys by the root before the keymap is read, so a key
  -- set on the Applications page travels with Olm's config when it is exported.
  { id = "keys", section = "applications", title = "Shortcuts", kind = "keys", applies = "reload", shipped = {},
    keywords = { "key", "shortcut", "hotkey", "chord", "hyper" } },

  { id = "plugins.off", section = "plugins", title = "Plugins switched off", kind = "list", applies = "reload",
    hidden = true, shipped = {} },
}

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

local function equal(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- A named size's anchors and displays, plugins/windowmanager/plan.lua's.
local SIZE_ANCHORS = { topLeft = true, top = true, topRight = true, left = true, center = true, right = true,
  bottomLeft = true, bottom = true, bottomRight = true }
local SIZE_DISPLAYS = { current = true, builtin = true, external = true, pointer = true }

local PLACE_DISPLAYS = { was = true, active = true, pointer = true }
local function positive(v) return v == nil or (type(v) == "number" and v == v and v > 0) end

--- M.checkPlace(place) -> ok, why
--- Whether an application's own place from the Applications page is one the app can run: a display
--- of the three, center on or off, a size in points or a percent with a least and a most, and a
--- padding of x and y.
function M.checkPlace(p)
  if type(p) ~= "table" then return false, "is not a table" end
  if p.display ~= nil and not PLACE_DISPLAYS[p.display] then return false, "names a display that is not one of three" end
  if p.center ~= nil and type(p.center) ~= "boolean" then return false, "says center as neither on nor off" end
  if p.size ~= nil then
    local s = p.size
    if type(s) ~= "table" then return false, "has a size that is not a table" end
    if s.unit ~= "points" and s.unit ~= "percent" then return false, "measures its size in neither points nor percent" end
    for _, k in ipairs({ "width", "height", "minWidth", "minHeight", "maxWidth", "maxHeight" }) do
      if not positive(s[k]) then return false, "has a " .. k .. " that is not a size" end
    end
    if s.width == nil or s.height == nil then return false, "has a size with no width or no height" end
    if s.unit == "percent" and (s.width > 100 or s.height > 100) then return false, "asks for more than all of the display" end
  end
  if p.padding ~= nil then
    if type(p.padding) ~= "table" then return false, "has a padding that is not a table" end
    for _, k in ipairs({ "x", "y" }) do
      local v = p.padding[k]
      if v ~= nil and (type(v) ~= "number" or v ~= v or v < 0) then return false, "has a padding that is not a distance" end
    end
  end
  return true
end

--- M.check(decl, value) -> ok, why
--- Whether value is one decl allows, and the reason in words when it is not.
function M.check(decl, value)
  local kind = decl.kind
  if kind == "choice" then
    if type(value) ~= "string" then return false, "is not one of its choices" end
    if decl.choices == nil then return true end
    for _, choice in ipairs(decl.choices) do
      if choice.value == value then return true end
    end
    return false, "is " .. value .. ", which is not one of its choices"
  elseif kind == "number" then
    if type(value) ~= "number" or value ~= value then return false, "is not a number" end
    if decl.min and value < decl.min then return false, "is below " .. decl.min end
    if decl.max and value > decl.max then return false, "is above " .. decl.max end
    return true
  elseif kind == "font" then
    if type(value) ~= "string" or value == "" then return false, "is not a font name" end
    return true
  elseif kind == "switch" or kind == "checkbox" then
    if type(value) ~= "boolean" then return false, "is not on or off" end
    return true
  elseif kind == "handler" then
    return false, "is the app macOS opens it with, which Olm.app asks macOS to change"
  elseif kind == "text" then
    if type(value) ~= "string" then return false, "is not words" end
    if decl.maxLength and #value > decl.maxLength then return false, "is longer than " .. decl.maxLength end
    if not decl.lines and value:find("[\r\n]") then return false, "is more than one line" end
    return true
  elseif kind == "keys" then
    if type(value) ~= "table" then return false, "is not a table of actions and their keys" end
    for action, chord in pairs(value) do
      if type(action) ~= "string" or not action:find(".", 1, true) then
        return false, "holds an entry that is not an action by its id"
      end
      if chord ~= false and (type(chord) ~= "string" or not chord:find("+", 1, true)) then
        return false, "gives " .. action .. " a key that is neither a chord nor none"
      end
    end
    return true
  elseif kind == "apps" then
    -- Each application by its bundle id, with the mode its key takes, and the name and path of one
    -- added from outside the catalog.
    if type(value) ~= "table" then return false, "is not a table of applications" end
    for bundle, o in pairs(value) do
      if type(bundle) ~= "string" or type(o) ~= "table" then
        return false, "holds an entry that is not an application by its bundle id"
      end
      if o.mode ~= nil and o.mode ~= "cycle" and o.mode ~= "hides" then
        return false, "gives " .. bundle .. " a mode that is neither cycle nor hides"
      end
      if (o.name ~= nil and type(o.name) ~= "string") or (o.path ~= nil and type(o.path) ~= "string") then
        return false, "gives " .. bundle .. " a name or a path that is not words"
      end
      if o.place ~= nil then
        local ok, why = M.checkPlace(o.place)
        if not ok then return false, "gives " .. bundle .. " a place that " .. why end
      end
      -- Its key, once the app keeps the catalog, step 6.2b, a leader by name or none, the key's
      -- name, its key code and the modifiers beyond the leader.
      if o.key ~= nil then
        local k = o.key
        local fine = type(k) == "table" and type(k.key) == "string" and k.key ~= ""
          and type(k.code) == "number" and k.code == math.floor(k.code) and k.code >= 0 and (k.leader == nil or type(k.leader) == "string")
          and (k.mods == nil or type(k.mods) == "table")
        if fine then
          for _, m in ipairs(k.mods or {}) do
            if m ~= "shift" and m ~= "ctrl" and m ~= "alt" and m ~= "cmd" then fine = false end
          end
        end
        if not fine then return false, "gives " .. bundle .. " a key that is not a key" end
      end
    end
    return true
  elseif kind == "sizes" then
    -- The window manager's named sizes, each an id of letters and digits its action is named by,
    -- a name, a width and a height in points or a percent of the screen, an anchor and a display.
    if type(value) ~= "table" then return false, "is not a list of sizes" end
    local seen = {}
    for i, z in ipairs(value) do
      if type(z) ~= "table" or type(z.id) ~= "string" or not z.id:match("^%l[%w]*$") then
        return false, "holds size " .. i .. " with no id of letters and digits"
      end
      if seen[z.id] then return false, "holds the size " .. z.id .. " twice" end
      seen[z.id] = true
      if type(z.name) ~= "string" or z.name == "" then return false, "gives the size " .. z.id .. " no name" end
      if type(z.width) ~= "number" or type(z.height) ~= "number" or z.width <= 0 or z.height <= 0 then
        return false, "gives " .. z.name .. " a width or a height that is not a size"
      end
      if z.unit ~= "points" and z.unit ~= "percent" then return false, "gives " .. z.name .. " a unit that is neither points nor percent" end
      if z.unit == "percent" and (z.width > 100 or z.height > 100) then
        return false, "gives " .. z.name .. " more than all of the screen"
      end
      if not SIZE_ANCHORS[z.anchor] then return false, "gives " .. z.name .. " no anchor of the nine" end
      if not SIZE_DISPLAYS[z.display] then return false, "gives " .. z.name .. " a display that is not one of four" end
    end
    return true
  elseif kind == "list" or kind == "picks" then
    if type(value) ~= "table" then return false, "is not a list of names" end
    for i, item in ipairs(value) do
      if type(item) ~= "string" then return false, "item " .. i .. " is not a name" end
    end
    return true
  end
  return false, "has a kind nothing checks, " .. tostring(kind)
end

--------------------------------------------------------------------------------
-- A plugin's own settings, its manifest's settings list
--------------------------------------------------------------------------------

local KINDS = { number = true, switch = true, checkbox = true, text = true, choice = true, apps = true, sizes = true,
  handler = true, picks = true }

-- Whether a choice spec lists its choices, each a value and a title, and ships one of them.
local function readChoices(spec)
  if type(spec.choices) ~= "table" or #spec.choices < 2 then return nil end
  local out, shipped = {}, false
  for _, c in ipairs(spec.choices) do
    if type(c) ~= "table" or type(c.value) ~= "string" or type(c.title) ~= "string" then return nil end
    if c.value == spec.shipped then shipped = true end
    out[#out + 1] = { value = c.value, title = c.title }
  end
  return shipped and out or nil
end

--- M.fromManifest(identity, specs) -> declarations, problems
--- A plugin's settings list read into declarations, docs/DESIGN-APP-SETTINGS.md S.4. Each spec is
--- { key, at, title, section, kind, keywords, detail, and for a number min, max, step, unit, shipped }, detail a line shown under the title.
--- kind is number, switch, checkbox, text, choice, apps or sizes, a text taking an optional
--- placeholder, maxLength and lines, the rows its box is tall, a list of one entry per line. A handler
--- names a scheme, https, and is the app macOS opens it with, read and changed by Olm.app, no at and
--- nothing stored. picks is a list of names checked off a list Olm.app finds, source, browsers, with
--- fixed names after them, such as Copy Link. section is optional, and a setting naming none is drawn on the
--- plugin's own page, which its switch in Plugins opens. at
--- is the path into the plugin's own data, its first word a need the manifest declares with source
--- user, so the saved value is laid over what the plugin is handed and the plugin reads it with no
--- word of its own. The id is the identity, a dot and the key, so no plugin can take another's or
--- one of Olm's own, and every such setting applies on reload, since the data is handed over once a
--- load, unless liveWhen names a switch of the bridge that is on, its owner then the app. A spec that cannot be read is left out and named in problems, the rest still declared.
function M.fromManifest(identity, specs)
  local out, problems = {}, {}
  if specs == nil then return out, problems end
  if type(specs) ~= "table" then
    return out, { "settings is a " .. type(specs) .. " rather than a list" }
  end
  local sections = {}
  for _, section in ipairs(M.SECTIONS) do sections[section.id] = true end
  local seen = {}
  for i, spec in ipairs(specs) do
    local where = "settings[" .. i .. "]"
    local why
    if type(spec) ~= "table" then why = "is not a table"
    elseif type(spec.key) ~= "string" or not spec.key:match("^[%w_]+$") then why = "names no key of letters and digits"
    elseif seen[spec.key] then why = "repeats the key " .. spec.key
    elseif spec.kind ~= "handler" and (type(spec.at) ~= "table" or #spec.at == 0) then
      why = "names no path into the plugin's data in at"
    elseif spec.kind == "picks" and not (type(spec.source) == "string" and spec.source ~= "") then
      why = "is a picks setting with no source, the list Olm.app finds its choices in, such as browsers"
    elseif spec.kind == "picks" and spec.fixed ~= nil and type(spec.fixed) ~= "table" then
      why = "is a picks setting whose fixed choices are not a list of names"
    elseif spec.kind == "handler" and not (type(spec.scheme) == "string" and spec.scheme:match("^%a[%w+.-]*$")) then
      why = "is a handler with no scheme, such as https"
    elseif type(spec.title) ~= "string" or spec.title == "" then why = "has no title"
    elseif spec.section ~= nil and not sections[spec.section] then why = "names no section of the window, " .. tostring(spec.section)
    elseif not KINDS[spec.kind] then
      why = "has the kind " .. tostring(spec.kind) .. ", where a number, a switch, a checkbox, a text, a choice, a handler or picks is read"
    elseif spec.section == nil and (spec.kind == "apps" or spec.kind == "sizes") then
      why = "is a " .. spec.kind .. " setting with no section, and only its own section draws one"
    elseif spec.kind == "text" and spec.maxLength ~= nil and not (type(spec.maxLength) == "number" and spec.maxLength > 0) then
      why = "is a text with a maxLength that is not a length"
    elseif spec.lines ~= nil and not (spec.kind == "text" and math.type(spec.lines) == "integer"
      and spec.lines >= 2 and spec.lines <= 20) then
      why = "has lines that are not a text's rows, a whole number from 2 to 20"
    elseif spec.placeholder ~= nil and type(spec.placeholder) ~= "string" then
      why = "has a placeholder that is not words"
    elseif spec.kind == "choice" and not readChoices(spec) then
      why = "is a choice with no list of two or more, each a value and a title, shipping one of them"
    elseif spec.kind == "number" and not (type(spec.min) == "number" and type(spec.max) == "number"
      and spec.min < spec.max and type(spec.step) == "number" and spec.step > 0) then
      why = "is a number with no range, min below max and a step above nothing"
    end
    if not why then
      for _, word in ipairs(spec.kind == "handler" and {} or spec.at) do
        if type(word) ~= "string" or word == "" then why = "has a path in at that is not words" end
      end
    end
    if why then
      problems[#problems + 1] = where .. " " .. why .. ", so it is left out"
    else
      seen[spec.key] = true
      -- A handler is a fact about the Mac that Olm.app reads and changes, so nothing is stored.
      local target
      if spec.kind ~= "handler" then
        target = { identity }
        for _, word in ipairs(spec.at) do target[#target + 1] = word end
      end
      -- A setting naming no section lives on the plugin's own page, reached from its switch in
      -- Plugins, asked by Milos on 2026-11-24.
      out[#out + 1] = { id = identity .. "." .. spec.key, section = spec.section or "plugins",
        page = spec.section == nil and identity or nil, title = spec.title,
        placeholder = spec.placeholder, maxLength = spec.maxLength, lines = spec.lines,
        detail = type(spec.detail) == "string" and spec.detail or nil, kind = spec.kind, target = target, min = spec.min, max = spec.max, step = spec.step,
        unit = spec.unit, shipped = copy(spec.shipped), keywords = copy(spec.keywords or {}),
        choices = spec.kind == "choice" and readChoices(spec) or nil,
        extra = type(spec.extra) == "string" and spec.extra or nil,
        liveWhen = type(spec.liveWhen) == "string" and spec.liveWhen or nil,
        scheme = spec.kind == "handler" and spec.scheme or nil,
        source = spec.kind == "picks" and spec.source or nil,
        fixed = spec.kind == "picks" and copy(spec.fixed or {}) or nil,
        applies = spec.kind == "handler" and "live" or "reload", owner = identity }
    end
  end
  return out, problems
end

--------------------------------------------------------------------------------
-- The store
--------------------------------------------------------------------------------

--- M.store(opts) -> store
--- opts.path     the file, ~/.olm/state/settings.json
--- opts.read     function(path) -> text or nil
--- opts.write    function(path, text) -> true when written, through a temporary file and a rename
--- opts.decode   function(text) -> table, may raise
--- opts.encode   function(table) -> text
--- opts.log      a table with w
--- A file that cannot be read as a store is said once and kept beside as settings.json.broken
--- before the first write, so nothing a person set is lost to a bad edit.
function M.store(opts)
  local self = {}
  local log = opts.log or { w = function() end }
  local values, broken = {}, nil
  do
    local text = opts.read(opts.path)
    if text ~= nil and text ~= "" then
      local ok, parsed = pcall(opts.decode, text)
      if ok and type(parsed) == "table" and type(parsed.values) == "table" then
        values = parsed.values
      else
        broken = text
        log.w("Olm settings, " .. opts.path .. " is not a settings store, so every setting is on its file "
          .. "and the file is kept as settings.json.broken at the next change")
      end
    end
  end

  local function flush()
    if broken ~= nil then
      opts.write(opts.path .. ".broken", broken)
      broken = nil
    end
    local ok = opts.write(opts.path, opts.encode({ version = M.VERSION, values = values }))
    if not ok then log.w("Olm settings, " .. opts.path .. " could not be written") end
    return ok
  end

  --- store.get(id) -> the saved value or nil, a copy, so a reader cannot change the store.
  function self.get(id) return copy(values[id]) end

  --- store.set(id, value) -> true when written. nil removes the saved value, so the file's
  --- stands again. Setting the value already saved writes nothing.
  function self.set(id, value)
    if equal(values[id], value) then return true end
    values[id] = copy(value)
    return flush()
  end

  --- store.values() -> a copy of every saved value by id.
  function self.values() return copy(values) end

  --- store.migrate(legacy) -> the ids moved, sorted
  --- legacy.get(key) and legacy.clear(key) over Hammerspoon's own settings. Each M.LEGACY key that
  --- holds a value is moved here unless the store already holds that id, and is removed there
  --- either way, so there is only ever one answer. Written once, whatever moved.
  function self.migrate(legacy)
    local moved, changed = {}, false
    local keys = {}
    for key in pairs(M.LEGACY) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
      local old = legacy.get(key)
      if old ~= nil then
        local rule = M.LEGACY[key]
        local value = old
        if rule.from then value = rule.from(old) end
        if value ~= nil and values[rule.id] == nil then
          values[rule.id] = copy(value)
          moved[#moved + 1] = rule.id
          changed = true
        end
        legacy.clear(key)
      end
    end
    if changed then flush() end
    table.sort(moved)
    return moved
  end

  return self
end

--------------------------------------------------------------------------------
-- The declarations over a store
--------------------------------------------------------------------------------

local function walk(root, target)
  local node = root
  for i = 2, #target - 1 do
    if type(node) ~= "table" then return nil end
    node = node[target[i]]
  end
  if type(node) ~= "table" then return nil end
  return node, target[#target]
end

--- M.new(opts) -> settings
--- opts.store   a store, M.store
--- opts.log     a table with w
--- opts.declared the declarations, M.DECLARED when not given
--- The one instance the root holds. It knows every declaration, the default each one was found
--- with, and answers the share the window draws.
function M.new(opts)
  local self = {}
  local store = opts.store
  local log = opts.log or { w = function() end }
  local order, byId, defaults = {}, {}, {}
  for _, decl in ipairs(opts.declared or M.DECLARED) do
    local own = copy(decl)
    order[#order + 1] = own
    byId[own.id] = own
    if own.target == nil and own.shipped ~= nil then defaults[own.id] = copy(own.shipped) end
  end
  local said = {}

  local function sayOnce(id, why)
    if said[id] then return end
    said[id] = true
    log.w("Olm settings, the saved " .. id .. " " .. why .. ", so its file's value is used")
  end

  --- settings.store, the store, for the readers that write through it.
  self.store = store

  --- settings.declaration(id) -> the declaration, or nil.
  function self.declaration(id) return byId[id] end

  --- settings.import(values, change) -> refused
  --- An exported config taken whole, docs/DESIGN-APP-SETTINGS.md Export and import. Each value is
  --- handed to change, the service's, so it is checked and applied as one set in the window is, and
  --- every saved value the file leaves out is reset, so the config is the file's. Answers each refused
  --- id with why, the rest taken.
  function self.import(values, change)
    local refused = {}
    if type(values) ~= "table" then return { { id = "values", why = "is not a table" } } end
    for _, decl in ipairs(order) do
      local value = values[decl.id]
      if value == nil and self.saved(decl.id) ~= nil then
        change(decl.id, nil)
      elseif value ~= nil then
        local ok, why = change(decl.id, value)
        if not ok then refused[#refused + 1] = { id = decl.id, why = why } end
      end
    end
    return refused
  end

  --- settings.declare(id, fields) lays fields over a declaration, or adds one, the choices of the
  --- chooser and theme known only once their stores are built, a default, a plugin's switch.
  --- default in fields is the file's value for a setting with no target.
  -- What answers a declaration's liveWhen, a switch's name to whether it is on, set by the root.
  local switchOn = function() return false end

  --- settings.liveWhen(fn)
  --- fn answers whether a switch is on, by name. A plugin setting naming one in liveWhen applies
  --- live while it is on, since then its owner is the app and reads the change at once.
  function self.liveWhen(fn)
    if type(fn) == "function" then switchOn = fn end
  end

  --- settings.applies(id) -> "live" or "reload", what a declaration applies on now.
  function self.applies(id)
    local decl = byId[id]
    if decl == nil then return nil end
    if decl.liveWhen and switchOn(decl.liveWhen) == true then return "live" end
    return decl.applies
  end

  function self.declare(id, fields)
    local decl = byId[id]
    if decl == nil then
      decl = { id = id, keywords = {} }
      order[#order + 1] = decl
      byId[id] = decl
    end
    for k, v in pairs(fields) do
      if k == "default" then defaults[id] = copy(v) else decl[k] = copy(v) end
    end
    return decl
  end

  --- settings.plugin(identity, specs, data) -> problems
  --- A plugin's manifest settings declared and laid over data, the plugin's own data before it is
  --- handed over, a group data leaves out made so a saved value still reaches it. Answers the
  --- problems M.fromManifest found, for the root to say.
  --- resolve, optional, answers a function for a member name a spec's extra names, called as the
  --- share is written, so a setting's page draws with what the plugin knows then, the app toggler's
  --- catalog for the Applications page. The plugin never learns the window exists.
  function self.plugin(identity, specs, data, resolve)
    local decls, problems = M.fromManifest(identity, specs)
    if #decls == 0 or type(data) ~= "table" then return problems end
    for _, decl in ipairs(decls) do
      local node = data
      for i = 2, decl.target and #decl.target - 1 or 0 do
        local word = decl.target[i]
        if type(node[word]) ~= "table" then node[word] = {} end
        node = node[word]
      end
      if decl.extra and type(resolve) == "function" then decl.extraFrom = resolve(decl.extra) end
      self.declare(decl.id, decl)
    end
    self.overlay(identity, data, nil, true)
    return problems
  end

  --- settings.value(id) -> the saved value when it is one the declaration allows, else the default.
  function self.value(id)
    local decl = byId[id]
    local saved = store.get(id)
    if decl and saved ~= nil then
      local ok, why = M.check(decl, saved)
      if ok then return saved end
      sayOnce(id, why)
    end
    return copy(defaults[id])
  end

  --- settings.saved(id) -> the saved value when it is one the declaration allows, else nil.
  function self.saved(id)
    local decl = byId[id]
    local saved = store.get(id)
    if saved == nil or decl == nil then return nil end
    local ok, why = M.check(decl, saved)
    if ok then return saved end
    sayOnce(id, why)
    return nil
  end

  --- settings.default(id) -> the file's value, or the shipped one when the file leaves it out.
  function self.default(id) return copy(defaults[id]) end

  --- settings.overlay(name, root, shipped)
  --- For every declaration whose target starts with name, reads its default out of root, the
  --- file's value, else the same key of shipped, a table shaped as root, else the declaration's
  --- shipped one, and lays the saved value over it in place. Called by the root once per table as
  --- each is loaded, the policy, the typography, the icons, the stage. A group root leaves out is
  --- not made, so a setting with nowhere to go is shown and not applied. fill, which a plugin's
  --- settings pass, also writes the declaration's shipped value where the file leaves the key out,
  --- so the manifest is the one statement of a default and a value can leave the person's config
  --- for Olm's, as the window sizes did on 2026-11-23.
  function self.overlay(name, root, shipped, fill)
    if type(root) ~= "table" then return end
    for _, decl in ipairs(order) do
      local target = decl.target
      if target and target[1] == name then
        local parent, key = walk(root, target)
        local found = parent and parent[key]
        if found == nil and type(shipped) == "table" then
          local fromShipped, shippedKey = walk(shipped, target)
          found = fromShipped and fromShipped[shippedKey]
        end
        if found == nil then found = decl.shipped end
        defaults[decl.id] = copy(found)
        local saved = self.saved(decl.id)
        if saved ~= nil and parent ~= nil then
          parent[key] = saved
        elseif fill and parent ~= nil and parent[key] == nil and found ~= nil then
          parent[key] = copy(found)
        end
      end
    end
  end

  --- settings.change(id, value) -> ok, why
  --- The window's change of one setting, checked against its declaration and saved, or with value
  --- nil reset, its saved value removed so the file's stands again. A value equal to the default
  --- is not saved. A plugin's switch is kept in its list, the plugins switched off. A hidden,
  --- absent or locked setting is refused, why says so in words.
  function self.change(id, value)
    local decl = byId[id]
    if decl == nil or decl.hidden or decl.absent then return false, "is not a setting the window shows" end
    if decl.locked then return false, "is locked, " .. tostring(decl.locked) end
    if decl.member then
      local on = value
      if on == nil then on = true end
      if type(on) ~= "boolean" then return false, "is not on or off" end
      local off = {}
      for _, name in ipairs(self.value(decl.member.list) or {}) do
        if name ~= decl.member.name then off[#off + 1] = name end
      end
      if not on then off[#off + 1] = decl.member.name end
      table.sort(off)
      store.set(decl.member.list, #off > 0 and off or nil)
      return true
    end
    if value == nil then
      store.set(id, nil)
      return true
    end
    local ok, why = M.check(decl, value)
    if not ok then return false, why end
    if equal(value, defaults[id]) then store.set(id, nil) else store.set(id, value) end
    return true
  end

  --- settings.share() -> the table ~/.olm/run/settings.json holds, every section in order with
  --- each setting's declaration, default and current value. A hidden declaration, the list the
  --- plugin switches are kept in, is not drawn and is not shared.
  function self.share()
    local sections = {}
    local bySection = {}
    for _, section in ipairs(M.SECTIONS) do
      local entry = { id = section.id, title = section.title, symbol = section.symbol, settings = {} }
      sections[#sections + 1] = entry
      bySection[section.id] = entry
    end
    for _, decl in ipairs(order) do
      local section = bySection[decl.section]
      if section and not decl.hidden and not decl.absent then
        local row = {
          id = decl.id, title = decl.title, detail = decl.detail, kind = decl.kind,
          keywords = copy(decl.keywords or {}), applies = self.applies(decl.id),
          choices = copy(decl.choices), min = decl.min, max = decl.max, step = decl.step, unit = decl.unit,
          locked = decl.locked,
          page = decl.page, plugin = decl.member and decl.member.name or nil,
          placeholder = decl.placeholder, maxLength = decl.maxLength, lines = decl.lines, scheme = decl.scheme,
          source = decl.source, fixed = copy(decl.fixed),
          default = copy(defaults[decl.id]),
        }
        if type(decl.extraFrom) == "function" then
          local ok, extra = pcall(decl.extraFrom)
          if ok and type(extra) == "table" then row.extra = extra end
        end
        if decl.member then
          local off = self.value(decl.member.list) or {}
          local isOff = false
          for _, name in ipairs(off) do if name == decl.member.name then isOff = true end end
          row.value = not isOff
          row.default = true
        else
          row.value = self.value(decl.id)
        end
        section.settings[#section.settings + 1] = row
      end
    end
    local out = {}
    for _, section in ipairs(sections) do
      if #section.settings > 0 then out[#out + 1] = section end
    end
    return { version = M.VERSION, sections = out }
  end

  return self
end

return M
