--- Hammerspoon clipboard manager, the mechanism. Composition root.
---
--- A self-contained clipboard history that lives entirely in Lua, no companion
--- app. It polls the pasteboard, records text, urls, images, and files, shows a
--- searchable hs.chooser with a live preview pane docked beside it, and pastes
--- the chosen item back into the frontmost app.
---
--- This is the mechanism only. It knows nothing about being a provider; it just
--- exposes an API, configure, start, show, isShowing, clear, and the actions that need no
--- picker at all, appendCopy and pasteNext. The contract
--- face that plugs it into the ClipboardHistory chain lives outside it, in
--- providers/hammerspoon.lua, which delegates to this API. This file is the only
--- one that names the concrete internal pieces. It loads the siblings by absolute
--- path (a spoon dir is not on package.path), holds the config defaults, and
--- wires store, readers, monitor, and ui together.
---
--- Responsibilities split across the folder:
---   util.lua      pure string and pasteboard helpers
---   preview.lua   async preview-image generation, a Chain of Responsibility
---   store.lua     the store core, the ordered deduped persisted list plus the accept
---                 gate, decides nothing about media or eviction on its own
---   media.lua     the image and file lifecycle, an optional layer of the store, and the
---                 staging that keeps a same folder file paste out of Finder's way
---   finder-target.lua the one file that knows Finder or AppleScript, answering only
---                 where a paste would land right now
---   retention.lua the eviction policies (count, age, bytes), combined as an or
---   readers.lua   per-type capture readers, a Chain of Responsibility
---   monitor.lua   the poll engine and paste-back, owns the self-capture guard
---   session.lua   the transient session state, the append accumulator and the paste walk
---   ui.lua        the chooser and the live preview pane

-- Load siblings by absolute path, the loadfile pattern the spoons use.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("clipboard native: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

local util = load("util.lua")
local preview = load("preview.lua")
local store = load("store.lua")
local media = load("media.lua")
local finderTargetAdapter = load("finder-target.lua")
local retention = load("retention.lua")
local readers = load("readers.lua")
local monitor = load("monitor.lua")
local session = load("session.lua")
local ui = load("ui.lua")

local HOME = os.getenv("HOME")
local DATA_DIR = HOME .. "/.cache/hs-clipboard"

-- hs.chooser sizes by whole row count, not pixels, so rows(N) is only a request
-- and the window height cannot be set directly. Once the chooser has been
-- reshown, its steady-state height settles near 94 plus 42 times the row count,
-- 10 rows landing around 514pt. The ui reads the chooser's real rendered frame
-- after it shows and sizes the preview to match, so both panes are always the
-- same height. The line below (42pt per row over a 94pt search-field and chrome
-- base, measured on the real Chooser window) seeds the preview's first frame
-- before that correction. Fractional counts are rejected by hs.chooser, so this
-- must stay a whole number.
local CHOOSER_ROWS = 10 -- 94 + 10*42 = 514pt steady-state height
local CHOOSER_ROW_H = 42 -- measured points per visible row
local CHOOSER_BASE_H = 94 -- measured search-field and chrome overhead, points

-- Defaults. The outer composition root may override any of these via configure()
-- before start(). Stored outside the git-tracked config dir.
local config = {
  cacheParent = HOME .. "/.cache",
  dataDir = DATA_DIR,
  thumbDir = DATA_DIR .. "/thumbs",
  filesDir = DATA_DIR .. "/files",
  stageDir = DATA_DIR .. "/stage", -- files staged under a free name for a paste into a folder that already holds that name
  storePath = DATA_DIR .. "/history.json",

  -- The one adapter that knows Finder or AppleScript, answering only where a paste
  -- would land. A paste presents the right name regardless of this setting, that part is
  -- app agnostic and always runs. Set to false or nil to turn off only Finder's own
  -- collision numbering, or to a different table answering the same folder() contract to
  -- swap it for another target.
  finderTarget = finderTargetAdapter,

  maxEntries = 1000, -- history cap, trimmed on insert
  maxFileSnapshot = 10 * 1024 * 1024, -- freeze a real copy only up to this size; bigger files are linked
  maxSnapshotBytes = 2 * 1024 * 1024 * 1024, -- total frozen bytes on disk; over this the oldest are dropped (files demote to links, images are removed)
  thumbEdge = 64, -- row thumbnail, max pixels on the larger edge
  previewEdge = 500, -- downscaled preview image, max pixels on the larger edge (video width for ffmpeg)
  fileReadCap = 256 * 1024, -- how much of a text file to preview

  pollInterval = 0.5, -- changeCount poll
  pasteDelay = 0.1, -- focus settle before Cmd+V
  previewPoll = 0.08, -- follow-selection poll

  -- What an appended piece is joined onto the entry with. A newline, matching what a
  -- collected batch pastes with, so gathering on the copy side and gathering on the paste
  -- side produce the same shape.
  appendSeparator = "\n",
  -- How long a gap between presses still counts as the same walk through history. A walk is
  -- a burst while filling one form, so a longer pause means the next press is a fresh intent
  -- and should start from the newest entry again. A plain Cmd+V ends a walk at once and does
  -- not wait out this gap at all, since the monitor's paste watcher reports it the instant it
  -- happens rather than at the next press.
  sequenceIdleReset = 10,
  -- How long the pasteboard is left alone after each step of a walk, which is all the time the
  -- receiving app has to read what was pasted before the next step overwrites it or the clipboard
  -- is put back. Tapping the key faster than this does not paste faster, it only queues, because
  -- the limit is the app's own paste handling rather than the key. Too short and a burst pastes
  -- only some of what was asked for, in an app that services a paste slowly.
  sequenceDrainDelay = 0.25,

  chooserWidthPct = 32, -- list width, percent of screen, capped by paneMaxW below
  paneMaxW = 480, -- cap for each pane's width, in points
  chooserRows = CHOOSER_ROWS, -- desired row count, trimmed on short screens to keep the padding
  chooserRowH = CHOOSER_ROW_H, -- points per row, used to fit rows to the screen
  chooserBaseH = CHOOSER_BASE_H, -- search-field and chrome overhead, points
  previewW = 480,
  previewH = CHOOSER_BASE_H + CHOOSER_ROWS * CHOOSER_ROW_H, -- seed height, matchPreviewToChooser corrects it to the chooser's real height
  uiGap = 12,
  uiTopFrac = 0.06, -- bias the pair toward the top of the screen
  minVPad = 60, -- mandatory space above and below the pair, honored on short screens

  -- NSPasteboard hints that a copy must not be recorded; the concealed one is
  -- what password managers stamp.
  skipTypes = {
    "org.nspasteboard.ConcealedType",
    "org.nspasteboard.TransientType",
    "org.nspasteboard.AutoGeneratedType",
  },
}

local function merged(extra)
  local t = {}
  for k, v in pairs(config) do t[k] = v end
  for k, v in pairs(extra) do t[k] = v end
  return t
end

local M = {}

--- M.show() - reveal the clipboard chooser with its live preview pane.
function M.show()
  ui.show()
end

--- M.isShowing() - is the chooser currently visible.
function M.isShowing()
  return ui.isShowing()
end

--- M.hide() - dismiss the chooser and its preview pane.
function M.hide()
  ui.hide()
end

--- M.selectNext() / M.selectPrev() - move the chooser highlight, for the Hyper j
--- and k navigation bindings wired in the composition root.
function M.selectNext()
  ui.selectNext()
end

function M.selectPrev()
  ui.selectPrev()
end

--- M.insertSelected() - paste the highlighted entry, same as Return.
function M.insertSelected()
  ui.insertSelected()
end

--- M.appendSelected() - toggle the highlighted entry in the append batch, for the
--- Hyper a binding. The chooser stays open so several items can be gathered.
function M.appendSelected()
  ui.appendSelected()
end

--- M.scrollPreviewDown() / M.scrollPreviewUp() - scroll the preview pane, for the
--- Hyper+Cmd+j and Hyper+Cmd+k bindings wired in the composition root, so a long
--- entry can be read without reaching for the mouse.
function M.scrollPreviewDown()
  ui.scrollPreviewDown()
end

function M.scrollPreviewUp()
  ui.scrollPreviewUp()
end

--- M.deleteSelected() - delete the highlighted entry, or the whole marked batch when
--- one is gathered, for the Hyper d binding wired in the composition root.
function M.deleteSelected()
  ui.deleteSelected()
end

--- M.appendCopy() - copy the selection and glue it onto the newest entry instead of pushing a
--- new one, so several selections gather into one clipboard item that a plain paste delivers
--- whole. The first press behaves like a plain copy, see session.lua for when.
function M.appendCopy()
  session.appendCopy()
end

--- M.pasteNext() - paste the next entry in a walk through history, starting at the newest.
--- The walk leaves both the order of history and the clipboard as it found them.
function M.pasteNext()
  session.pasteNext()
end

--- M.resetSequence() - end a walk, so the next M.pasteNext starts from the newest entry.
--- Walks already end on their own, so this is for a caller that wants to force it.
function M.resetSequence()
  session.resetSequence()
end

--- M.pasteText(text) - insert arbitrary text into the frontmost app by pasting it,
--- the reliable way to land an emoji or other astral glyph that a synthesized keystroke
--- mangles in terminals and some native apps. The pasteboard is snapshotted and put back
--- after, and the write is hidden from the poll, so the clipboard is left untouched and
--- history is not polluted. A consumer with no relation to clipboard history can borrow
--- this, which is why the emoji picker's onInsert is wired to it in the composition root.
function M.pasteText(text)
  monitor.pasteText(text)
end

--- M.copySelection(cb) - read the current selection without disturbing the clipboard,
--- the read-side mirror of pasteText. It copies the selection, reads the text, and
--- restores the clipboard, hidden from the poll so history is not polluted, then calls
--- cb(text), or cb(nil) when nothing was selected. A consumer with no relation to
--- clipboard history can borrow this, which is why the text case picker's read is wired
--- to it in the composition root.
function M.copySelection(cb)
  monitor.copySelection(cb)
end

--- M.setLogLevel(level) - raise or lower the log level of every module in the mechanism at once,
--- taking any level hs.logger accepts. The append and the walk both work by writing the
--- pasteboard, sending a keystroke and waiting, so when one misbehaves the only evidence is a
--- timeline across both modules, and at "debug" they print one. Handy from the console:
--- hs -c 'spoon.ClipboardHistory.manager.setLogLevel("debug")'
function M.setLogLevel(level)
  monitor.log.setLogLevel(level)
  session.log.setLogLevel(level)
end

--- M.clear() - wipe history and media. Handy from the console:
--- hs -c "spoon.ClipboardHistory.providers.hammerspoon.clear()"
function M.clear()
  store.clear()
  ui.refresh()
end

--- M.configure(opts) - override any config default before start.
function M.configure(opts)
  if opts then
    for k, v in pairs(opts) do
      config[k] = v
    end
  end
  return M
end

--- M.start() - wire the pieces and begin monitoring. Called once by the outer
--- composition root. Safe across hs.reload(): reload tears down the whole Lua
--- state and history is read back from disk here.
function M.start()
  math.randomseed(os.time())
  config.util = util

  -- Hand the preview chain its tool paths. Both are resolved outside this spoon by the
  -- shared dependency door and injected through configure, so nothing here probes and a
  -- missing one just leaves the video generator unable to handle anything.
  preview.configure({ util = util, ffmpeg = config.ffmpeg, ffprobe = config.ffprobe })

  -- The media layer, images and files, injected into the store. It gets the dirs and
  -- sizes, the preview module, the store's save so a late async render can re-persist,
  -- and a repaint hook so a preview that lands after the entry saved repaints the open
  -- chooser without the user moving the selection.
  media.configure({
    cacheParent = config.cacheParent,
    dataDir = config.dataDir,
    thumbDir = config.thumbDir,
    filesDir = config.filesDir,
    stageDir = config.stageDir,
    maxFileSnapshot = config.maxFileSnapshot,
    thumbEdge = config.thumbEdge,
    previewEdge = config.previewEdge,
    util = util,
    preview = preview,
    save = store.save,
    onMediaReady = function()
      ui.mediaReady()
    end,
  })

  -- The store core. It accepts every kind, so text, url, image, and file all combine
  -- into one rolling history. That wide accept set is the combine, one store taking many
  -- kinds. Retention is count then bytes with no age, exactly the previous behavior, and
  -- the media layer handles the images and files. A future snippet store reuses this same
  -- core with a text only accept set and no media layer.
  store.configure(merged({
    accepts = { text = true, url = true, image = true, file = true },
    retention = {
      retention.count(config.maxEntries),
      retention.bytes(config.maxSnapshotBytes),
    },
    media = media,
    util = util,
  }))

  -- The transient session layer, the append accumulator and the paste walk. It is policy over
  -- the store and the monitor and holds no persistent state of its own, so it is configured
  -- here and never started. It gets the readers module rather than a built chain, since what it
  -- needs is textEntry, the one place a text entry's label is decided.
  session.configure({
    store = store,
    monitor = monitor,
    readers = readers,
    util = util,
    media = media,
    appendSeparator = config.appendSeparator,
    sequenceIdleReset = config.sequenceIdleReset,
    sequenceDrainDelay = config.sequenceDrainDelay,
    onEntryChanged = function(entry)
      ui.entryChanged(entry)
    end,
    -- Passed straight through, so the surface the message is drawn on stays the root's choice
    -- and neither this module nor the session layer names one.
    onMessage = config.onMessage,
  })

  -- onCapture is what tells the session layer a pasteboard change was a real copy rather than
  -- one of our own pastes. Only the monitor still knows, which is why it is published from
  -- there rather than inferred from the store. onUserPaste is the same shape for a plain
  -- Cmd+V, which changes nothing on the pasteboard and so needs an event tap rather than the
  -- poll to see at all, and it is wired straight to resetSequence since a user paste ends a
  -- walk exactly the way a genuine copy already does.
  monitor.configure({
    readers = readers.build(util),
    store = store,
    util = util,
    skipTypes = config.skipTypes,
    pollInterval = config.pollInterval,
    pasteDelay = config.pasteDelay,
    onCapture = session.noteCapture,
    onUserPaste = session.resetSequence,
    -- The one place this feature is wired together, and the only reason monitor.lua
    -- ever learns of media at all. Presenting the right name is app agnostic and always
    -- matters, so this closure always calls into media, with or without Finder. Only the
    -- collision numbering needs to know the destination, which is why folder is the one
    -- thing conditional here, config.finderTarget names the adapter that knows where a
    -- paste would land, and only this closure, sitting in the composition root, knows
    -- that the answer to "where" is handed straight to media's numbering. Absent or
    -- unanswered, folder is nil and media already treats that as skip the numbering
    -- question entirely rather than as skip the whole call. Neither monitor.lua nor
    -- media.lua learns of the other because of this.
    resolveFilePaths = function(items)
      local folder = config.finderTarget and config.finderTarget.folder()
      return media.resolveForPaste(items, folder)
    end,
  })
  ui.configure(merged({
    store = store,
    monitor = monitor,
    util = util,
    media = media,
    isAccumulator = session.isAccumulator,
  }))

  store.load()
  ui.build()
  monitor.start()
  return M
end

return M
