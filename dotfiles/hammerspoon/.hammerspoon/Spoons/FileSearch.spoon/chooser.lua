--- File search list surface.
---
--- Pure policy over the engine's api. It turns rows into what the picker draws and turns a
--- selection into an action, and it knows nothing about where a row came from, which source
--- answered, or that sources exist at all.
---
--- It opts OUT of the shared matcher, passing matcher false, and that is deliberate rather
--- than a shortcut. A query here is structured, it carries sigils, a type token and a scope,
--- so it is not a plain filter over a list and the atom re ranking what came back would fight
--- the engine's own ordering and hide the status row. This is the same opt out the clipboard,
--- the emoji picker and three others make for the same reason. The matcher still reaches the
--- engine, injected by the root, where it does the local narrow between round trips, so the
--- policy is not lost, it just applies one layer down.
---
--- It names no key anywhere. The actions are exposed as plain methods, a Hyper context in
--- config/keys.lua decides which key reaches which one, and the deferred helper panel spells
--- them out, so rebinding is a config edit and no wording here can disagree with a binding.
--- The one wording it does carry is the grammar itself, which is the spoon's own syntax rather
--- than anything about keys, and it is shown on a help screen reached by typing a question mark.

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(spoonPath .. "util.lua")()

local M = {}

local cfg = {
  chooser = nil,      -- the Chooser factory
  theme = nil,
  placeholder = "",
  api = nil,          -- the engine verbs, the only way this file reaches the engine
  iconFor = nil,      -- shared icon memo from the root, optional
  copy = nil,         -- injected clipboard write, so this file never names a clipboard
  onPositioned = nil,
  onActivity = nil,
  onClose = nil,
}

local picker = nil

-- The home prefix, collapsed in a subtitle so a row reads as ~/Development rather than
-- repeating the same twenty characters on every line.
local HOME = os.getenv("HOME") or ""
local function shortDir(dir)
  if not dir or dir == "" then return "" end
  if HOME ~= "" and dir:sub(1, #HOME) == HOME then
    return "~" .. dir:sub(#HOME + 1)
  end
  return dir
end

local function humanBytes(n)
  n = tonumber(n) or 0
  if n < 1024 then return string.format("%d B", n) end
  if n < 1024 * 1024 then return string.format("%d KB", math.floor(n / 1024 + 0.5)) end
  if n < 1024 * 1024 * 1024 then return string.format("%.1f MB", n / 1024 / 1024) end
  return string.format("%.1f GB", n / 1024 / 1024 / 1024)
end

local function humanAge(epoch)
  local secs = os.time() - (tonumber(epoch) or 0)
  if secs < 60 then return "just now" end
  if secs < 3600 then return math.floor(secs / 60) .. "m ago" end
  if secs < 86400 then return math.floor(secs / 3600) .. "h ago" end
  return math.floor(secs / 86400) .. "d ago"
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

-- Render an emoji to a small image so a row that has no file behind it can still carry an icon.
-- An offscreen canvas drawn once and cached by the string, since the supplier runs on every
-- keystroke, and a false marks a string that will not render so it is attempted only once. This
-- Hammerspoon has no SF Symbol api, so it is how the launcher, the clipboard, Processes and three
-- others do the same thing. Cached permanently rather than through the injected memo, because a
-- glyph cannot go stale the way a file type icon can when its default application changes.
local glyphCache = {}
local function glyph(str)
  local hit = glyphCache[str]
  if hit ~= nil then return hit or nil end
  local size = 28
  local cv = hs.canvas.new({ x = 0, y = 0, w = size, h = size })
  cv[1] = {
    type = "text",
    text = str,
    textSize = 21,
    textAlignment = "center",
    frame = { x = 0, y = 0, w = size, h = size },
  }
  local img = cv:imageFromCanvas()
  cv:delete()
  glyphCache[str] = img or false
  return img
end

-- The icon for a row. Types are keyed by extension rather than by path, which is what makes
-- the memo effective, since a hundred rows of one kind ask once. Folders share one key.
-- Without an injected memo this still works and simply asks every time, measured at 6.6ms for
-- two hundred rows against 0.2ms memoized, so the fallback is slower and perfectly usable.
local function iconFor(row)
  local memo = cfg.iconFor
  if row.isDir then
    if memo then return memo("dir", function() return hs.image.iconForFileType("public.folder") end) end
    return hs.image.iconForFileType("public.folder")
  end
  local ext = row.ext or ""
  if ext ~= "" then
    if memo then return memo("ext:" .. ext, function() return hs.image.iconForFileType(ext) end) end
    return hs.image.iconForFileType(ext)
  end
  if memo then return memo("data", function() return hs.image.iconForFileType("public.data") end) end
  return hs.image.iconForFileType("public.data")
end

local function subtitleFor(row)
  local parts = { shortDir(row.dir) }
  if row.modified then parts[#parts + 1] = humanAge(row.modified) end
  if row.size then parts[#parts + 1] = humanBytes(row.size) end
  return table.concat(parts, "  ")
end

local function fileRows(rows)
  local out = {}
  for i = 1, #rows do
    local r = rows[i]
    out[#out + 1] = {
      title = r.name or r.path,
      subTitle = subtitleFor(r),
      image = iconFor(r),
      item = r,
    }
  end
  return out
end

-- The back row, first in the list while browsing a directory, so going up is something you can
-- see rather than only a key you have to remember.
--
-- It is an ORDINARY DIRECTORY ROW for the parent, not a special kind of entry, which is what
-- keeps it from needing special cases. Reveal, copy path and open folder all mean the obvious
-- thing on it because it really is that directory, and browsing into it really does go back.
-- The one flag it carries is read by insertSelected, so the primary key goes up rather than
-- opening the parent in Finder, which is what a row named two dots should do.
local function upRow()
  if not cfg.api.upQuery then return nil end
  local q = cfg.api.upQuery()
  if not q then return nil end
  local path = q:gsub("/+$", "")
  if path == "" then path = "/" end
  local row = {
    path = path,
    lower = path:lower(),
    name = "..",
    dir = util.dirname(path),
    isDir = true,
    ext = "",
    up = true,
  }
  return { title = "..", subTitle = "up to " .. shortDir(path), image = iconFor(row), item = row }
end

-- How each empty state looks. A row that is not a file still gets an icon, a headline naming what
-- the state IS, and a detail saying what to do about it, so an empty list never reads as a broken
-- picker and never puts a bare fragment of internal wording on screen.
--
-- Keyed on the status text the engine and the sources produce, which is a seam worth being honest
-- about. Those strings are free text rather than identifiers, so a producer rewording one drops it
-- out of this table. That is why the fallback carries the raw status as its detail. An unmapped
-- state loses its tailored headline and stays perfectly readable, which is a fair price for not
-- making every source declare a presentation key it has no interest in.
local STATUS = {
  ["searching"]           = { icon = "🔍", title = "Searching",       detail = "asking the index" },
  ["loading"]             = { icon = "⏳", title = "Recent files",    detail = "gathering what you touched lately" },
  ["keep typing"]         = { icon = "⌨️",  title = "Keep typing",     detail = "three characters, or name a folder to search inside" },
  ["nothing to search for"] = { icon = "⌨️", title = "Keep typing",   detail = "add something to search for" },
  ["nothing found"]       = { icon = "🤷", title = "No matches",      detail = "try fewer words, or a bang to include pruned folders" },
  ["empty folder"]        = { icon = "📭", title = "Empty folder",    detail = "there is nothing in this one" },
  ["no such directory"]   = { icon = "📁", title = "No such folder",  detail = "check the path, or give a full one like ~/Documents" },
  ["no directory"]        = { icon = "📁", title = "No such folder",  detail = "check the path, or give a full one like ~/Documents" },
  ["no source available"] = { icon = "🚫", title = "Nothing can answer that", detail = "a tool it needs is missing, the console names which" },
  ["type something to search hidden files"] = { icon = "👻", title = "Search hidden files", detail = "type something to search hidden files" },
  ["timed out"]           = { icon = "⌛", title = "Timed out",       detail = "that took too long, try narrowing it" },
  ["listing failed"]      = { icon = "⚠️",  title = "Could not list that folder", detail = "check its permissions" },
  ["walk failed"]         = { icon = "⚠️",  title = "Search failed",   detail = "the walker returned an error" },
}
local STATUS_FALLBACK = { icon = "⚠️", title = "Nothing to show" }

-- A single inert row explaining why the list is empty, so the picker never looks broken.
local function statusRow(status)
  local look = STATUS[status] or STATUS_FALLBACK
  return { {
    title = look.title,
    subTitle = look.detail or status,
    image = glyph(look.icon),
    enabled = false,
    item = { status = true },
  } }
end

-- The grammar, on a screen of its own, an icon for what each line demonstrates, the syntax as the
-- headline and what it does underneath. Every row is inert, so there is nothing to select by
-- mistake and Escape or clearing the field returns to searching.
local HELP = {
  { "🔍", "hammerspoon",        "plain text searches names everywhere" },
  { "🏷️",  ".js hello",          "a dot attached to a token is a type" },
  { "👻", ". js",               "a dot alone includes hidden files" },
  { "👻", ".zshrc",             "a dotted name is hidden too, with no sigil" },
  { "📂", "downloads/",         "a trailing slash browses that folder, newest first" },
  { "🔎", "downloads/hs",       "with text it searches inside it" },
  { "🧩", ".js src/api",        "a type, a scope and text combine in that order" },
  { "❗", "! ts node_modules/", "a bang includes what is normally pruned" },
  { "🏠", "~/Development/mdj",  "an absolute or tilde path scopes directly" },
}

local function helpRows()
  local out = {}
  for _, h in ipairs(HELP) do
    out[#out + 1] = {
      title = h[2],
      subTitle = h[3],
      image = glyph(h[1]),
      enabled = false,
      item = { help = true },
    }
  end
  return out
end

--- The row supplier. The engine is asked what to draw for this query and may schedule work as
--- a side effect, which is why nothing here decides whether to search.
local function supplier(q)
  q = q or ""
  if q == "?" then return helpRows() end
  local rows, status = cfg.api.rowsFor(q)
  local out
  if (not rows or #rows == 0) and status then
    out = statusRow(status)
  else
    out = fileRows(rows or {})
  end
  -- Only while browsing, which is a scope with nothing typed. Once text is typed the list is
  -- search results and a back row sitting above them would be competing with the answer. The key
  -- still works there, it is only the row that is browse specific.
  local parsed = cfg.api.parsed and cfg.api.parsed()
  if parsed and parsed.kind == "browse" then
    local up = upRow()
    if up then table.insert(out, 1, up) end
  end
  return out
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

-- Always through hs.task, never hs.execute, for the same reason every shellout here goes that
-- way. Opening a large document can take the launcher services a moment and a blocking call
-- would hold the main thread through it.
local function openPath(path, reveal)
  if not path then return end
  local args = reveal and { "-R", path } or { path }
  local t = hs.task.new("/usr/bin/open", nil, args)
  if t then t:start() end
end

local function selectedRow()
  if not picker then return nil end
  local item = picker:selectedItem()
  if not item or item.status or item.help then return nil end
  return item
end

--- Open the highlighted row with whatever the system considers its default. A directory opens
--- in Finder, which is the same verb, so no special case is needed.
local function onSelect(item)
  if not item or item.status or item.help then return end
  openPath(item.path, false)
end

--------------------------------------------------------------------------------
-- Public surface
--------------------------------------------------------------------------------

--- chooser.configure(opts) - see the fields on cfg above. Called by the composition root,
--- which is the only place that knows the concrete collaborators.
function M.configure(opts)
  for k, v in pairs(opts or {}) do cfg[k] = v end
  return M
end

--- chooser.start() - build the picker instance once and reuse it across shows.
function M.start()
  if picker or not cfg.chooser then return M end
  picker = cfg.chooser.new({
    theme = cfg.theme,
    rows = supplier,
    -- The engine owns filtering and ordering, see the header.
    matcher = false,
    placeholder = cfg.placeholder,
    onSelect = onSelect,
    onPositioned = cfg.onPositioned,
    onActivity = cfg.onActivity,
    onClose = function()
      -- Abandon anything in flight, so a search for a picker nobody is looking at is not
      -- still running, and the root's overlay teardown runs through the injected handler.
      if cfg.api then cfg.api.cancel() end
      if cfg.onClose then cfg.onClose() end
    end,
  })
  return M
end

--- chooser.show() - open on a fresh session.
function M.show()
  M.start()
  if not picker then return end
  cfg.api.reset()
  picker:show()
end

--- chooser.refresh() - redraw from what the engine now holds, without re dispatching. Wired as
--- the engine's onResults, so an answer arriving after the keystroke that asked for it paints
--- itself. The highlight is preserved, since a list filling in under the cursor should not move
--- what the user was about to choose.
function M.refresh()
  if picker and picker:isShowing() then
    picker:refresh(false)
  end
end

function M.isShowing()
  return picker ~= nil and picker:isShowing()
end

function M.hide()
  if picker then picker:hide() end
end

function M.selectNext()
  if picker then picker:selectNext() end
end

function M.selectPrev()
  if picker then picker:selectPrev() end
end

--- chooser.insertSelected() - the primary key, choosing the highlighted row.
---
--- The back row is intercepted BEFORE delegating, and it has to be. Choosing a row goes through
--- the atom's completion, which tears the picker down straight after, and there is no way to veto
--- that from a consumer. So going up through the completion path would close the picker on the
--- way. Checked here instead, the primary key on the back row simply moves up a level and the
--- picker stays where it is.
function M.insertSelected()
  if not picker then return end
  local item = picker:selectedItem()
  if item and item.up then
    M.browseUp()
    return
  end
  picker:insertSelected()
end

-- Put a query in the field and rebuild. Setting the field may or may not fire the change
-- callback depending on the widget, so the rebuild is asked for explicitly, and asking twice is
-- harmless because the engine answers an unchanged query from what it already holds.
local function goTo(q)
  if not q or not picker then return end
  picker:setQuery(q)
  picker:refresh(true)
end

--- chooser.browseInto() - walk into the highlighted directory rather than opening it.
--- The query becomes that directory as an absolute scope, so this introduces no new concept,
--- it types what the user could have typed. A row that is not a directory is left alone.
function M.browseInto()
  local row = selectedRow()
  if not row then return end
  goTo(cfg.api.browseQueryFor(row))
end

--- chooser.browseUp() - leave the directory being browsed for the one above it.
--- The mirror of browseInto and expressed the same way, as a scope rather than as a move, so
--- there is no history to keep and nothing to get out of step with the field. It does nothing
--- when the query carries no scope, since there is nowhere above a search of everywhere.
function M.browseUp()
  if not picker or not cfg.api.upQuery then return end
  goTo(cfg.api.upQuery())
end

--- chooser.reveal() - show the highlighted row in Finder instead of opening it.
function M.reveal()
  local row = selectedRow()
  if not row then return end
  openPath(row.path, true)
  M.hide()
end

--- chooser.openFolder() - open the folder holding the highlighted row.
function M.openFolder()
  local row = selectedRow()
  if not row then return end
  openPath(row.isDir and row.path or row.dir, false)
  M.hide()
end

--- chooser.copyPath() - put the highlighted path on the clipboard through the injected writer,
--- so this file never learns what a clipboard is. Without one injected it does nothing rather
--- than reaching for the pasteboard directly.
function M.copyPath()
  local row = selectedRow()
  if not row then return end
  if cfg.copy then cfg.copy(row.path) end
  M.hide()
end

return M
