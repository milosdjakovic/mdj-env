--- === TextCase ===
---
--- Convert the current selection to another case, in place. It reads whatever text is
--- selected, lists every case as a row whose title demonstrates the case and whose
--- subtitle previews the selection rendered that way, and on select pastes the chosen
--- result over the selection.
---
--- The engine is a Context over a Strategy family. The transforms are an interchangeable
--- set of pure string to string algorithms it iterates generically, never naming a
--- concrete one, so adding a case never touches this file. It also names no clipboard: it
--- reads through an injected `read(cb)` and writes through an injected `apply(text)`, both
--- supplied by the composition root, so the mechanism that captures and replaces the
--- selection lives outside this spoon and this spoon depends only on the two small
--- contracts. This is dependency inversion, the engine and the clipboard both point at
--- contracts rather than at each other.
---
--- The transforms are the spoon's own policy, so it loads transforms.lua itself rather
--- than having the root inject a catalog that has one implementation and one consumer,
--- the same way Emoji loads its own dataset. Only the genuine cross-spoon seams, read and
--- apply, are injected.
---
--- Rows are data, never functions. Each row carries only a serializable { text = result }
--- descriptor, the transform having run once at show time over the captured selection, so
--- on select the engine just pastes that text and no selection state is held across the
--- chooser lifecycle. This is the same Command as data rule every list tool here follows.
---
--- This is the olm side copy of TextCase, phase six of the olm build plan, and the
--- original this was copied from lived at Spoons/TextCase.spoon.

local obj = {}
obj.__index = obj
obj.name = "TextCase"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Load the transforms by absolute path, the loadfile pattern the spoons use since a
-- spoon directory is not on package.path.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function loadSibling(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("TextCase: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

-- Injected via configure
obj._chooser = nil        -- the Chooser factory (has .new)
obj._theme = nil
obj._placeholder = nil
obj._read = nil           -- function(cb) -> yields the selection text, or nil
obj._apply = nil          -- function(text) -> writes text in place
obj._shortcutPanel = nil  -- { onPositioned, onActivity, onClose }

-- Owned state
obj._transforms = nil     -- the ordered catalog loaded from transforms.lua
obj._picker = nil         -- the built Chooser instance
obj._surface = nil        -- dot-called navigation adapter over the instance
obj._rows = nil           -- rows prebuilt for the current open, read by the supplier
obj._iconCache = nil

-- How long a preview subtitle may be before it is elided, and the row glyphs. The
-- preview is display only; the pasted result is always the full untruncated transform.
local PREVIEW_MAX = 80
local ICON = {
  upper = "🔠", lower = "🔡", title = "🔤", sentence = "✍️",
  capitalize = "🔤", toggle = "🔁", camel = "🐫", pascal = "🔺",
  snake = "🐍", constant = "📢", kebab = "🍢", dot = "🔵",
}
local ICON_FALLBACK = "🔤"
local EMPTY_ICON = "🚫" -- the no-selection guidance row

-- Collapse whitespace to single spaces and elide, so a multi-line or long selection
-- still reads as one tidy row. Bytes, not codepoints, so an elided multibyte tail is
-- possible on non-ASCII text; the preview is cosmetic and the pasted text is unaffected.
local function preview(s)
  s = s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  if s == "" then return "(empty)" end
  if #s > PREVIEW_MAX then s = s:sub(1, PREVIEW_MAX - 1) .. "…" end
  return s
end

--- TextCase:init()
--- Method
--- Load the transforms and prepare the icon cache. No collaborator is wired yet, that
--- waits for configure.
function obj:init()
  self._transforms = loadSibling("transforms.lua")
  self._iconCache = {}
  self._rows = {}
  return self
end

-- The row glyph as an image, rendered once through one canvas and cached, sized to line
-- up with the app icons, the same technique the launcher and the overlay picker use since
-- this Hammerspoon has no SF Symbol API.
function obj:_glyphIcon(glyph)
  local cache = self._iconCache
  if cache[glyph] == nil then
    local size = 72
    local c = hs.canvas.new({ x = 0, y = 0, w = size, h = size })
    c[1] = { type = "text", text = glyph, textSize = 52, textAlignment = "center",
             frame = { x = "0%", y = "8%", w = "100%", h = "100%" } }
    cache[glyph] = c:imageFromCanvas() or false
    c:delete()
  end
  return cache[glyph] or nil
end

function obj:_icon(id)
  return self:_glyphIcon(ICON[id] or ICON_FALLBACK)
end

-- Build the rows for one open. With no selection captured it is a single non-actionable
-- row guiding the user, the same shape Vpn's unavailable row uses (plain data, no key
-- names). Otherwise one row per transform, the title demonstrating the case and the
-- subtitle previewing the selection through that transform, the result carried on the row
-- so a pick pastes it with no re-read.
function obj:_buildRows(text)
  if not text or text:match("^%s*$") then
    return { { title = "No text selected", subTitle = "Select some text, then open Text Case",
              image = self:_glyphIcon(EMPTY_ICON), enabled = false } }
  end
  local rows = {}
  for _, t in ipairs(self._transforms) do
    local result = t.fn(text)
    rows[#rows + 1] = {
      title = t.name,
      subTitle = preview(result),
      image = self:_icon(t.id),
      item = { text = result },
    }
  end
  return rows
end

--- TextCase:configure(opts)
--- Method
--- Wire the collaborators and build the picker. opts.chooser is the Chooser factory,
--- opts.read captures the selection, opts.apply writes text in place, and
--- opts.shortcutPanel is the docked hint panel's three callbacks.
function obj:configure(opts)
  opts = opts or {}
  self._chooser = opts.chooser
  self._theme = opts.theme
  self._placeholder = opts.placeholder or "Convert selected text"
  self._read = opts.read
  self._apply = opts.apply
  self._shortcutPanel = opts.shortcutPanel or {}

  local this = self
  self._picker = self._chooser.new({
    theme = self._theme,
    placeholder = self._placeholder,
    -- The rows are a static set per open, prebuilt from the captured selection, so the
    -- supplier ignores the query and the shared fuzzy matcher filters over title and
    -- subtitle. No matcher opt-out needed.
    rows = function() return this._rows end,
    onSelect = function(item)
      -- Runs after the chooser tears down and focus returns to the source app; apply's
      -- own internal delay covers the focus handoff, and the selection is still there for
      -- the paste to replace. The guidance row carries no text, so it is a no-op.
      if item and item.text and this._apply then
        this._apply(item.text)
      end
    end,
    onPositioned = self._shortcutPanel.onPositioned,
    onActivity = self._shortcutPanel.onActivity,
    onClose = self._shortcutPanel.onClose,
  })

  -- Dot-called navigation adapter over the colon-called instance, for the shared
  -- activeChooser / routeNav registry, the same shape every other picker exposes.
  self._surface = {
    isShowing = function() return this._picker:isShowing() end,
    selectNext = function() this._picker:selectNext() end,
    selectPrev = function() this._picker:selectPrev() end,
    insertSelected = function() this._picker:insertSelected() end,
    hide = function() this._picker:hide() end,
  }
  return self
end

--- TextCase:show()
--- Method
--- Read the selection, then open the picker on the built rows. The read is asynchronous
--- (a clipboard round trip), so the picker is shown only once the selection is in hand.
--- Without a reader wired it opens straight to the guidance row.
function obj:show()
  if not self._read then
    self._rows = self:_buildRows(nil)
    self._picker:show()
    return
  end
  local this = self
  self._read(function(text)
    this._rows = this:_buildRows(text)
    this._picker:show()
  end)
end

--- TextCase:isShowing()
--- Method
--- Whether the picker is open. Read by the textCaseOpen predicate.
function obj:isShowing()
  return self._picker ~= nil and self._picker:isShowing()
end

--- TextCase:surface()
--- Method
--- The navigation adapter for the shared choosers registry.
function obj:surface()
  return self._surface
end

return obj
