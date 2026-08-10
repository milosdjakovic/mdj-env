--- File search list surface.
---
--- Pure policy over the engine's api. It turns rows into what the picker draws and turns a
--- selection into an action, and it knows nothing about where a row came from, which source
--- answered, or that sources exist at all.
---
--- It also owns the pane beside the list, since it is the only piece that knows when the
--- highlight moved and when the window went away. The pane and the thumbnail chain behind it
--- are loaded here for that reason, and both are handed their policy rather than reading any.
--- Whether there is a pane at all is decided by the main root injecting the shared canvas
--- surface, and with nothing injected this file behaves exactly as it did before one existed.
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
-- The pictures a viewer may want. Loaded here rather than by the spoon root because it is
-- driven from this surface and from nothing else. The VIEWER itself is not loaded here, it is
-- injected, since which one is in use is a choice and this file must not know the answer.
local thumbs = loadfile(spoonPath .. "thumbs.lua")()

local M = {}

local cfg = {
  chooser = nil,      -- the Chooser factory
  theme = nil,
  placeholder = "",
  api = nil,          -- the engine verbs, the only way this file reaches the engine
  iconFor = nil,      -- shared icon memo from the root, optional
  copy = nil,         -- injected clipboard write, so this file never names a clipboard
  onUse = nil,        -- injected, told which path an action was performed on. This file does not
                      -- learn what is done with that, the same seam as copy above
  usedAt = nil,       -- injected, asks when a path was last used. The read side of onUse, on the
                      -- same seam, so what records a use and what reports one stay together
  surface = nil,      -- the shared canvas surface, injected by the main root. Absent means no
                      -- pane at all and the picker opens exactly as it did before there was one
  preview = nil,      -- the preview block from config, split below between the viewer and thumbs
  -- The preview providers, in priority order, injected by the spoon root, which is the only
  -- place that names a concrete one. The first that reports itself available wins, the same
  -- shape the emoji backends use, so an unavailable first choice degrades to the next rather
  -- than to no preview. This file calls the contract and never asks which it got, except for
  -- the one question the contract exists to answer, whether it follows the highlight.
  viewers = nil,
  -- The provider asked for rather than followed, injected by the spoon root on its own field
  -- since it answers a different question than the docked chain above. The docked chain picks
  -- what sits beside the list, and this picks what the q key opens on top of it, so the two are
  -- resolved separately and the one that follows the highlight never has to also be the one a
  -- key can ask for. Nil means there is nothing to ask for, the same as an empty docked chain.
  peekProvider = nil,
  onPositioned = nil,
  onActivity = nil,
  onClose = nil,
}

local picker = nil

-- The provider in use for this picker, resolved once in start, see resolveViewer.
--
-- A Null Object rather than nil, so every call site is one line instead of a guard, and so a
-- root that wires no provider at all gets a picker that behaves exactly as it did before there
-- was any preview rather than one that errors on the first highlight.
local NO_VIEWER = {
  name = "none",
  followsHighlight = false,
  available = function() return false, "no provider was wired" end,
  companionWidth = function() return 0 end,
  configure = function() end,
  dock = function() end,
  show = function() end,
  scrollBy = function() end,
  clear = function() end,
  close = function() end,
}
local viewer = NO_VIEWER

-- The provider the q key opens, resolved once in start alongside the docked one above and kept
-- as its own variable rather than a second slot in the same one, since the two answer to
-- different callers and a viewer that follows the highlight must never also be reached by a
-- key. Defaults to the same Null Object, so a root wiring none of it gets a q key that is asked
-- to drop from the binding rather than one that opens nothing when pressed.
local peekViewer = NO_VIEWER

-- The latest chooser frame the atom reported, kept so a later peek can hand it to a provider
-- that needs to know which screen the picker is actually on. Set every time onPositioned fires
-- and read only by the peek path, since the docked viewer already gets its own placement
-- straight from the companion rect and never asks for this.
local lastChooserFrame = nil

-- How a fact is worded lives in util, because the pane beside this list states the same
-- ones and a size or an age must not come out phrased two ways. Only the path is worded here
-- now, since the row gave its ages back to the path and the pane is where they are read.
local shortDir = util.shortDir

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

-- Elided directories for this open, keyed by the path and the room it had. A page of search
-- results is many files across few folders, so the same directory is asked about over and over.
-- Cleared when the picker closes, since the next open may land on a display of another width.
local dirFits = {}

-- The directory, shortened to the room the row actually has.
--
-- With no picker yet, or a picker too old to answer, the full directory comes back and the
-- widget cuts it as it always did. Nothing here depends on the measurement being available.
--
-- ONE COUPLING WORTH KNOWING. These rows are also handed to the launcher's alias, and they
-- are fitted here against THIS picker's room rather than the one that will draw them, since
-- a query scope is deliberately never told which surface is asking. It is right today
-- because both come from the atom's one uniform width, so both answer 354, and it is a
-- coincidence held in place by that default rather than by anything here. A picker that
-- pinned its own width and then scoped to this tool would shorten against the wrong number.
-- The fix at that point is for a surface to state its room, which means a parameter on the
-- scope contract, and that is not worth adding for a case nothing has yet.
local function fitDir(dir, reserved)
  if dir == "" then return dir end
  if not (picker and picker.textBudget) then return dir end
  -- `reserved` is the rest of the line verbatim, its own separator included, so a caller
  -- states what shares the row rather than this having to know where each caller puts it.
  local budget = picker:textBudget() - picker:textWidth(reserved, "sub")
  local key = dir .. "\0" .. math.floor(budget)
  local hit = dirFits[key]
  if hit then return hit end
  local fitted = util.elideDir(dir, budget, function(s) return picker:textWidth(s, "sub") end)
  dirFits[key] = fitted
  return fitted
end

-- What a row says about itself, which is the directory and nothing else.
--
-- It once also carried two labelled ages, when you last reached for the file and when the file
-- last changed, and they were dropped after measuring what they cost. THE TWO OF THEM TOOK 57
-- PERCENT OF THE LINE, and the line's whole job is telling four files called init.lua apart,
-- which is a thing only the path does. Every point they held was a point the path did not have,
-- and the paths that lost most were the deep ones, exactly the rows where knowing the folder
-- matters. So `~/…/impeccable/public` is now `~/.claude/plugins/marketplaces/impeccable/public`.
--
-- Neither age was carrying its weight for the price. When a file last changed almost never
-- decides which one you open, and when you last used it was only ever an explanation for the
-- ordering of the list you land on, which is a thing the ordering itself already shows. Both are
-- still one keystroke away in the pane, on the row you are actually asking about, which is the
-- same argument this file already makes for keeping a size off the row.
--
-- Worth knowing that a searched row never carried an age anyway. Only the recent list reads a
-- date, and frecency rarely holds a record for a path you just searched for, so on the list you
-- spend most of your time in this changed nothing at all.
local function subtitleFor(row)
  return fitDir(shortDir(row.dir), "")
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
  -- Expanded, because that query is written for the FIELD and home is collapsed to a tilde
  -- there so climbing a few levels does not fill the box with the same twenty characters. A row
  -- is not a field. Its path is handed to Finder, to open, and to whatever the preview provider
  -- shells out to, and none of those expand a tilde.
  --
  -- The trap that hid this is that hs.fs.attributes DOES expand one, so every guard of the shape
  -- does this path exist passed happily and only the external process failed. It showed up as a
  -- Quick Look panel stuck on a file called ~, launched and never able to render.
  local path = util.expandHome(q):gsub("/+$", "")
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
  local lead = "up to "
  return {
    title = "..",
    subTitle = lead .. fitDir(shortDir(path), lead),
    image = iconFor(row),
    item = row,
  }
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

-- Every action says which row it acted on, and they all say it the same way. Doing anything at
-- all to a row is the signal, since a distinction between opening one and copying its path would
-- be a claim about intent that cannot be backed, and copying a path is often the strongest signal
-- there is. The back row is excluded, because it is the parent directory rather than something
-- chosen, and counting it would float whatever you happen to be browsing through.
local function noteUse(row)
  if not row or row.up then return end
  if cfg.onUse and row.path then cfg.onUse(row.path) end
end

--- Open the highlighted row with whatever the system considers its default. A directory opens
--- in Finder, which is the same verb, so no special case is needed.
local function onSelect(item)
  if not item or item.status or item.help then return end
  noteUse(item)
  openPath(item.path, false)
end

--------------------------------------------------------------------------------
-- The pane, following the highlight
--------------------------------------------------------------------------------

-- The atom's onHighlight target, fired from a poll. A row with nothing to describe, a status
-- row or a help row, clears the pane rather than leaving a stale one beside the list.
local function onHighlight(item)
  if item and item.path and not (item.status or item.help) then
    viewer.show(item)
  else
    viewer.clear()
  end
end

-- Compose with the root's own onPositioned rather than replacing it. The atom reports both
-- frames, the pane docks into the companion rect it reserved, and the root's shortcut panel
-- still gets its anchor, so neither knows about the other.
--
-- The anchor handed on spans the pair rather than the list alone, the same as the clipboard
-- and Processes, so the hints sit full width beneath both panes instead of stopping short
-- under the list. With no pane there is no companion rect and the anchor is the plain chooser
-- frame, exactly as it was before the pane existed.
local function onPositioned(chooserFrame, companionFrame)
  -- Kept for the peek path below, which fires later on a key press rather than on this call, so
  -- it needs its own record of where the picker actually landed rather than the seed it opened
  -- with.
  lastChooserFrame = chooserFrame
  if companionFrame then
    viewer.dock(companionFrame)
    -- The atom seeds the highlight before it positions anything, so the first onHighlight lands
    -- with nowhere to draw. This is what fills the pane on open.
    --
    -- Gated on the same question the poll is, and it has to be. This call is a direct one rather
    -- than one the atom makes, so without the gate it reached a provider that is supposed to be
    -- asked rather than followed. Under Quick Look that meant merely opening the picker threw a
    -- panel onto the screen for whatever row happened to be first, which is the back row.
    if picker and viewer.followsHighlight then onHighlight(picker:selectedItem()) end
  end
  if not cfg.onPositioned then return end
  local anchor = chooserFrame
  if companionFrame then
    anchor = {
      x = chooserFrame.x, y = chooserFrame.y, h = chooserFrame.h,
      w = (companionFrame.x + companionFrame.w) - chooserFrame.x,
    }
  end
  cfg.onPositioned(anchor)
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
---
--- The provider is resolved and configured FIRST, because how much room it wants decides the
--- shape of the picker and that is fixed when the instance is built. A provider that reports
--- itself unavailable is passed over with one console line naming why, which is the same
--- degradation every optional tool here gets, and with none left the picker comes up exactly as
--- it did before there was any preview rather than half wired.
function M.start()
  if picker or not cfg.chooser then return M end

  local policy = cfg.preview or {}
  thumbs.configure({
    -- Written with a tilde in config, since nothing there names an absolute location.
    cacheDir = policy.cacheDir and util.expandHome(policy.cacheDir) or nil,
    cacheFiles = policy.cacheFiles,
    nativeMaxBytes = policy.nativeMaxBytes,
  })

  -- Everything a provider might want, offered to whichever one is in use. Each takes what it
  -- knows about and ignores the rest, which is what lets one call configure both of them.
  local deps = {
    surface = cfg.surface,
    -- Read through the instance rather than captured, so a provider picks up the palette the
    -- atom selected for THIS open and follows the light and dark switch with it.
    palette = function() return picker and picker:activeTheme().preview end,
    limits = policy,
    -- The same seam the row subtitle reads, so a preview and the row cannot disagree about when
    -- a path was last acted on.
    usedAt = cfg.usedAt,
    thumbs = thumbs,
    log = util.log,
  }
  viewer = NO_VIEWER
  for _, candidate in ipairs(cfg.viewers or {}) do
    candidate.configure(deps)
    local ok, why = candidate.available()
    if ok then
      viewer = candidate
      break
    end
    util.log.i("preview provider " .. tostring(candidate.name) .. " stepped aside, " .. tostring(why))
  end

  -- The provider a key can ask for, resolved the same way as the docked one just above but on
  -- its own field and with no chain behind it, since there is exactly one candidate rather than
  -- an ordered list to fall through. Stepping aside here means the q key drops from the binding
  -- rather than opening nothing, the same degradation every optional provider in this file gets.
  peekViewer = NO_VIEWER
  if cfg.peekProvider then
    cfg.peekProvider.configure(deps)
    local ok, why = cfg.peekProvider.available()
    if ok then
      peekViewer = cfg.peekProvider
    else
      util.log.i("peek preview provider " .. tostring(cfg.peekProvider.name) .. " stepped aside, " .. tostring(why))
    end
  end

  picker = cfg.chooser.new({
    theme = cfg.theme,
    rows = supplier,
    -- The engine owns filtering and ordering, see the header.
    matcher = false,
    placeholder = cfg.placeholder,
    onSelect = onSelect,
    -- The parent row is a step rather than a destination, so it puts the query for the level above
    -- in the field and the picker stays where it is. Asked before a row may complete, which is
    -- what makes Return, the insert key and a click all go up, where before only the insert key
    -- did and the other two opened the parent folder instead. Every other row answers false and
    -- is opened exactly as it always was.
    --
    -- The field is set here rather than answered with, because the atom's hook says only whether
    -- the row was a completion and leaves what it meant to whoever knows. So the query goes in
    -- through the picker itself, which is also what a level change already does elsewhere here.
    intercept = function(item)
      if not (item and item.up and cfg.api and cfg.api.upQuery) then return false end
      local query = cfg.api.upQuery()
      if type(query) ~= "string" or query == "" then return false end
      picker:setQuery(query)
      return true
    end,
    -- Setting this is what starts the atom's highlight poll, so a provider that is asked for
    -- rather than followed costs no timer at all.
    onHighlight = viewer.followsHighlight and onHighlight or nil,
    onPositioned = onPositioned,
    onActivity = cfg.onActivity,
    -- A trackpad or a wheel over the companion rect, which a canvas cannot report for itself.
    -- The same verb the two keys go through, so there is one notion of where a pane is scrolled
    -- to, and nothing to wire when the provider reserved no rect.
    onScroll = viewer.followsHighlight and viewer.scrollBy or nil,
    onClose = function()
      -- Abandon anything in flight, so a search for a picker nobody is looking at is not
      -- still running, and the root's overlay teardown runs through the injected handler.
      if cfg.api then cfg.api.cancel() end
      -- Closed on the atom's one idempotent teardown path, so no dismissal leaves a canvas or
      -- a Quick Look window behind, and a reopen builds a fresh one. Both viewers are told,
      -- since either one, the docked or the one a key asks for, may have something open.
      viewer.close()
      peekViewer.close()
      -- The next open may land on a display of another width, so what fitted here is not
      -- what fits there. Dropped on the same one path everything else is, and the last frame
      -- goes with it since it describes a picker that is now gone.
      dirFits = {}
      lastChooserFrame = nil
      if cfg.onClose then cfg.onClose() end
    end,
    layout = {
      -- The provider says how much room it needs, so the one that draws beside the list gets it
      -- and the one that opens its own window leaves the picker as a plain list.
      companionWidth = viewer.companionWidth(policy),
      -- Every title here is a filename, and the last few characters of a filename are its
      -- extension. A tail cut spends them first, so a long name arrives as
      -- `mahamba_gastric-pain-evaluation-protocol_5b…` with the one field that says what KIND
      -- of thing it is gone. Cutting the middle keeps both ends and costs nothing, since
      -- AppKit does it from the paragraph style with no measuring involved.
      titleLineBreak = "truncateMiddle",
    },
  })
  return M
end

--- chooser.beginSession() - start a fresh session without showing anything.
---
--- Split out of show because a second surface needs the same beginning. It clears what the last
--- session held, asks for the recent list, and warms whatever the root warms, and every one of
--- those is what makes an empty query answer with something. Calling it repeatedly is harmless,
--- since the recent fetch holds its own handle and refuses to start twice.
function M.beginSession()
  if cfg.api then cfg.api.reset() end
  return M
end

--- chooser.ensureSession() - join a session, starting one only if there is none.
---
--- What a surface with no open of its own calls instead of beginSession. The launcher's scope is
--- asked for rows on every keystroke and again every time it is told the rows changed, and it has
--- no moment it could call a fresh start, so beginning a session there restarts one perpetually.
--- The engine's note on ensureSession has why that is a loop rather than only waste.
function M.ensureSession()
  if cfg.api and cfg.api.ensureSession then cfg.api.ensureSession() end
  return M
end

--- chooser.show() - open on a fresh session.
function M.show()
  M.start()
  if not picker then return end
  M.beginSession()
  picker:show()
end

--- chooser.rowsForQuery(q) -> the rows a query draws, for a surface other than this picker.
---
--- The row supplier itself, exposed rather than reimplemented, so a second surface shows the
--- same titles, the same subtitles, the same icons, the same status rows and the same help
--- screen. Anything else would be a second presentation of one list, free to disagree with this
--- one about what a row says.
---
--- The engine behind it is one instance, so two surfaces reading it at once would each be
--- changing the query the other is asking about. In practice only one list is on screen at a
--- time, and the failure would be a confused list rather than a broken one, so this is a note
--- and not a mechanism.
function M.rowsForQuery(q)
  return supplier(q)
end

--- chooser.choose(row) - do to a row what the primary key does, for a surface with no picker.
--- The same function this picker's own selection runs through, so choosing is defined once and
--- records the use once. A status row or a help row is ignored here exactly as it is there.
function M.choose(row)
  onSelect(row)
end

--- chooser.refresh() - redraw from what the engine now holds, without re dispatching. Wired as
--- the engine's onResults, so an answer arriving after the keystroke that asked for it paints
--- itself. The highlight is preserved, since a list filling in under the cursor should not move
--- what the user was about to choose.
---
--- The pane is re rendered explicitly, and it has to be. The atom's poll compares the highlighted
--- ROW NUMBER, so a result set landing under a stationary highlight is the same number and fires
--- nothing, which would leave the pane describing whatever used to be in that position.
--- Gated for the same reason the seed in onPositioned is. Rows landing under the cursor must not
--- throw a window onto the screen for a provider nobody asked yet.
function M.refresh()
  if picker and picker:isShowing() then
    picker:refresh(false)
    if viewer.followsHighlight then onHighlight(picker:selectedItem()) end
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

-- How far one key press moves the pane, roughly a wheel notch, the same distance the clipboard
-- moves per press so the gesture means the same amount in both.
local PANE_SCROLL_STEP = 120

--- chooser.scrollPreviewDown() / chooser.scrollPreviewUp() - move the pane's body, for the
--- shared Hyper+Cmd+j and Hyper+Cmd+k actions, so a long file head or a big folder can be read
--- without reaching for the trackpad. Both go through the pane's one scroll verb, which is also
--- what the atom's trackpad callback goes through.
function M.scrollPreviewDown()
  viewer.scrollBy(PANE_SCROLL_STEP)
end

function M.scrollPreviewUp()
  viewer.scrollBy(-PANE_SCROLL_STEP)
end

--- chooser.peekPreview(), show the highlighted row in the peek viewer, the provider that is
--- asked for rather than followed.
---
--- Inert with no peek viewer resolved, because then there is nothing to ask for. The binding is
--- gated on the same question through a predicate, so the key drops out of the shortcut panel
--- too rather than being listed and doing nothing.
function M.peekPreview()
  if peekViewer == NO_VIEWER then return end
  -- Refused once the list is gone, and this one is about LIFETIME rather than about the row. Every
  -- other verb here is a one shot, so acting on a stale highlight would at worst reveal the wrong
  -- file. This one opens a window whose only teardown is the picker closing, so a peek that lands
  -- after that teardown has already run leaves a panel on screen that nothing owns and nothing
  -- will ever take down. Cheap to ask, and the alternative is unrecoverable without a kill.
  if not M.isShowing() then return end
  local row = selectedRow()
  if not row then return end
  M.peekRow(row)
end

--- chooser.peekRow(row), show a row this picker was HANDED rather than one it highlighted, for
--- another surface listing the same rows.
---
--- Split out of peekPreview rather than reached by pretending to be it, because the two differ in
--- exactly one thing, who owns the row, and that decides the lifetime guard. peekPreview refuses
--- once this picker has gone, since the panel it opens is torn down when this picker closes. A
--- caller holding its own list is a different owner with a different close, so it must not be
--- held to this picker's, and it takes on the same duty instead, which is to call closePreview
--- when its own list goes.
---
--- The latest chooser frame goes with the row, so the peek viewer can pick the same screen the
--- picker is actually on. A viewer that does not read a second argument simply never asks for it.
function M.peekRow(row)
  if peekViewer == NO_VIEWER then return end
  if not (row and row.path) or row.status or row.help then return end
  noteUse(row)
  peekViewer.show(row, lastChooserFrame)
end

--- chooser.closePreview(), put away whatever the peek viewer has open. The other half of peekRow,
--- for the surface that asked, since a preview outliving the list it describes is the one failure
--- this provider can leave on screen.
function M.closePreview()
  peekViewer.close()
end

--- chooser.insertSelected() - the primary key, choosing the highlighted row.
---
--- It used to intercept the back row here and browse up instead of delegating, because choosing a
--- row goes through the atom's completion which tears the picker down straight after. That is the
--- injected `intercept` above now, asked by the atom before a row may complete, so the interception
--- covers Return and a mouse click as well rather than this one key. Nothing is left to check here.
function M.insertSelected()
  if not picker then return end
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
  noteUse(row)
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
  noteUse(row)
  openPath(row.path, true)
  M.hide()
end

--- chooser.copyPath() - put the highlighted path on the clipboard through the injected writer,
--- so this file never learns what a clipboard is. Without one injected it does nothing rather
--- than reaching for the pasteboard directly.
function M.copyPath()
  local row = selectedRow()
  if not row then return end
  noteUse(row)
  if cfg.copy then cfg.copy(row.path) end
  M.hide()
end

return M
