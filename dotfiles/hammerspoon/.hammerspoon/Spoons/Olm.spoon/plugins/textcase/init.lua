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
--- Migrated onto host/stage, the trickle migration. This plugin owns no chooser instance
--- and builds no window any more. Its row builder, its selection dispatch, and its
--- deferred first show are exactly what they always were, now named on the manifest's own
--- presentation block instead of handed to a Chooser.new call this file no longer makes.
---
--- The deferred read used to be this file's own private shape, obj:show reading first and
--- calling obj._picker:show() only once the text was in hand, so the picker never flashed
--- the guidance row and then the real one. That is exactly what the presentation contract's
--- own enter exists for, a member handed one function, proceed, in place of the stage
--- showing this presentation immediately, so the read keeps deciding when the first row
--- means anything and the stage never learns why. Unlike VPN and menu search, which show at
--- once and correct afterward, this plugin already refused that shape before it had a name
--- for refusing it, so enter carries the same behaviour forward rather than introducing it.
--- A timeout is arranged around the read regardless, contract v2's own requirement that a
--- deferring presentation cannot strand a person on a launcher row waiting on an answer that
--- never comes, which the original synchronous-looking call never needed to state because
--- nothing was deferring around it.
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
obj._read = nil            -- function(cb) -> yields the selection text, or nil
obj._apply = nil           -- function(text) -> writes text in place
obj._stagePresent = nil    -- root published, the hotkey door onto the shared stage

-- Owned state
obj._transforms = nil      -- the ordered catalog loaded from transforms.lua
obj._rows = nil            -- rows prebuilt for the current open, read by the supplier
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

-- The longest the selection read is ever allowed to run before this presentation shows
-- itself regardless, contract v2's own requirement that a member declaring enter arranges
-- its own timeout, the identical discipline VPN's own FETCH_TIMEOUT and Processes' own
-- ENTER_TIMEOUT already keep, so a paste engine that never calls back cannot strand a
-- person on a launcher row that silently does nothing. Chosen well past what a clipboard
-- round trip ever takes, since the read this guards is a single pasteboard snapshot rather
-- than a shelled out process.
local ENTER_TIMEOUT = 3

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
--- Wire the collaborators. opts.read captures the selection, opts.apply writes text in
--- place, and opts.stagePresent is the root published hotkey door onto the shared stage.
--- The chooser factory, the theme, and the docked panel triple no longer arrive here, this
--- plugin owning no instance of its own to hand any of them to any more.
function obj:configure(opts)
  opts = opts or {}
  self._read = opts.read
  self._apply = opts.apply
  self._stagePresent = opts.stagePresent
  return self
end

--- TextCase:rows(query) -> list
--- Method
--- The presentation contract's own rows, named on the manifest's own presentation block.
--- A static set per open, prebuilt from the captured selection by enter below, so the
--- query is ignored here exactly as it always was and the shared fuzzy matcher, this
--- plugin declaring none of its own, filters over title and subtitle.
function obj:rows(query)
  return self._rows
end

--- TextCase:select(item)
--- Method
--- Apply one of those rows, named on the manifest's own presentation block as the
--- contract's onSelect. Runs after the chooser tears down and focus returns to the source
--- app, lib/paste's own internal delay covering the focus handoff exactly as before, and
--- the selection is still there for the paste to replace. The guidance row carries no
--- text, so it is a no-op.
function obj:select(item)
  if item and item.text and self._apply then
    self._apply(item.text)
  end
end

--- TextCase:enter(proceed)
--- Method
--- Contract v2's own deferred entry, named on the manifest's own presentation block. Reads
--- the selection first and proceeds once the rows built from it are ready, so the picker
--- never appears before its first row means anything, the identical rule this file always
--- kept before the stage existed to ask for it explicitly. Without a reader wired it
--- proceeds at once onto the guidance row, the same as opening with nothing selected.
---
--- Races its own ENTER_TIMEOUT, so a read that never calls back proceeds anyway on the
--- guidance row rather than stranding a person on a launcher row that silently does
--- nothing, contract v2's own requirement for any presentation declaring enter.
function obj:enter(proceed)
  if not self._read then
    self._rows = self:_buildRows(nil)
    proceed()
    return
  end
  local this = self
  local fired = false
  local timeoutTimer = hs.timer.doAfter(ENTER_TIMEOUT, function()
    if fired then return end
    fired = true
    this._rows = this:_buildRows(nil)
    proceed()
  end)
  self._read(function(text)
    if fired then return end
    fired = true
    timeoutTimer:stop()
    this._rows = this:_buildRows(text)
    proceed()
  end)
end

--- TextCase:show()
--- Method
--- registry.open's own hotkey door. This tool proposes no key of its own, opened only from
--- the launcher, so this is reached through the registered special row dispatch rather
--- than a chord of its own. cfg.stagePresent asks the registry for this plugin's own
--- presentation and hands it to Stage:present, which is what runs enter's own read before
--- showing anything, exactly what this function used to do inline before this plugin had a
--- presentation to defer through instead.
function obj:show()
  if self._stagePresent then self._stagePresent("textCase") end
end

return obj
