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
--- Every paste and every selection read this folder makes goes through the shared insertion
--- engine at Olm.spoon/lib/paste.lua, which arrives through configure as config.paste and is
--- threaded from here to the three files that need it. This file is the only one that knows
--- the engine came from outside the folder rather than from a sibling.
---
--- The outward pasteText and copySelection wrappers this file used to carry are gone. They
--- existed only so two consumers with no relation to clipboard history, the emoji picker and
--- the text case picker, had a door to a paste primitive, and that door is now the engine
--- itself, reached from the composition root. Keeping them would have this mechanism go on
--- advertising a primitive it no longer owns, and would give a future consumer a second and
--- wrong place to reach for one.
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
---   prune.lua     the manage history page, the duration grammar and the age slices a person
---                 deletes by hand, which is a different thing from retention above, one being
---                 asked for and the other automatic
---   readers.lua   per-type capture readers, a Chain of Responsibility
---   monitor.lua   the poll engine, reading the self-capture guard off the injected engine
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
local prune = load("prune.lua")
local readers = load("readers.lua")
local monitor = load("monitor.lua")
local session = load("session.lua")
local ui = load("ui.lua")

local HOME = os.getenv("HOME")
local DATA_DIR = HOME .. "/.cache/hs-clipboard"

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

  -- chooserWidthPct, paneMaxW, chooserRows, chooserRowH, chooserBaseH, previewW, previewH,
  -- uiGap, uiTopFrac, and minVPad all stood here once, ten restated atom defaults or exact
  -- matches for the atom's own hardcoded fallback, none of them a real override, and none of
  -- them read by manager/ui.lua's own cfg since the trickle migration moved this plugin onto
  -- the shared stage. previewPoll, beside pollInterval above, was the eleventh. Deleted in the
  -- chooser stage close out sweep, REVIEW-TRICKLE.md's own L3, which named nine of the ten cfg
  -- fields and Chooser itself; previewH and previewPoll were found unread by the identical grep
  -- this sweep applied to the rest and removed on the same ground, previewH's own comment
  -- naming a matchPreviewToChooser that no longer exists anywhere in this plugin.

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

--- The presentation contract's own members, the trickle migration onto the shared stage,
--- thin forwards onto the ui submodule the identical way every member below already is,
--- since the manifest names this module, manager, as the owner and ui is a plain local this
--- file never re-exports. rows and select are the contract's own words for ui's own
--- buildChoices and onSelect, so this plugin never has to expose the same two functions under
--- two different names depending on which part of the manifest is asking.
function M.rows(query)
  return ui.rows(query)
end

function M.select(item)
  ui.select(item)
end

function M.placeholder()
  return ui.placeholder()
end

function M.onPresent()
  ui.onPresent()
end

function M.intercept(item)
  return ui.intercept(item)
end

function M.back()
  return ui.back()
end

function M.onHighlight(item)
  ui.onHighlight(item)
end

function M.onScroll(points)
  ui.onScroll(points)
end

function M.onRightClick(item, row)
  ui.onRightClick(item, row)
end

function M.onPositioned(chooserFrame, companionFrame)
  ui.onPositioned(chooserFrame, companionFrame)
end

function M.onClose()
  ui.onClose()
end

--- M.isShowing() - is the chooser currently visible. Kept, unlike selectNext, selectPrev,
--- and insertSelected below, since providers/hammerspoon.lua's own toggle calls this and
--- M.hide directly, a caller the nav system's own five generic methods never was.
function M.isShowing()
  return ui.isShowing()
end

--- M.hide() - dismiss the chooser and its preview pane.
function M.hide()
  ui.hide()
end

-- selectNext, selectPrev, and insertSelected are gone, the trickle migration, deleted along
-- with the Chooser.new block that gave ui's own copies something to answer for. The
-- composition root now routes this plugin's own navigation through host/stage's own
-- surfaceFor once wiredRegistry.presentationFor("clipboard") answers a presentation.

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

--- M.manageHistory() - swap the open picker onto its manage history page, where a slice of
--- history is deleted by age, or step back off the page when it is already on. Reached from the
--- Hyper m binding while the list is open and from the launcher row with nothing open at all,
--- which is why it shows the picker itself when it has to.
function M.manageHistory()
  ui.manageHistory()
end

--- M.leaveManageHistory() - give the history list back. The Chooser atom already reads Backspace
--- on an empty field itself, so nothing binds this today and the surface declares it as a
--- listing rather than a chord. It exists because the declaration names it, and an action named
--- in a manifest that resolves to nothing is the kind of half true contract this plugin's own
--- history has more than one example of.
function M.leaveManageHistory()
  ui.leaveManageHistory()
end

--- M.isManagingHistory() - whether that page is on, read by the plugin's own `when` predicate so
--- the hint panel lists the way back out exactly while there is one.
function M.isManagingHistory()
  return ui.isManagingHistory()
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

--- M.setLogLevel(level) - raise or lower the log level of every module behind the mechanism at
--- once, taking any level hs.logger accepts. The append and the walk both work by writing the
--- pasteboard, sending a keystroke and waiting, so when one misbehaves the only evidence is a
--- timeline across all three, and at "debug" they print one. The insertion engine is in that
--- timeline even though it is not a file of this folder, because it is where the write and the
--- keystroke and the restore actually happen. Handy from the console, run
--- hs -c 'spoon.ClipboardHistory.manager.setLogLevel("debug")'
function M.setLogLevel(level)
  monitor.log.setLogLevel(level)
  session.log.setLogLevel(level)
  if config.paste then
    config.paste.log.setLogLevel(level)
  end
end

--- M.clear() - wipe history and media. Handy from the console:
--- hs -c "spoon.ClipboardHistory.providers.hammerspoon.clear()"
function M.clear()
  store.clear()
  ui.refresh()
end

--- M:configure(opts) - override any config default before start.
--
-- Colon here, not dot, because both the live top level init.lua and the shared wiring
-- pipeline in lib/wire.lua reach this submodule as manager:configure(opts). self arrives as
-- M and the body below never names it.
function M:configure(opts)
  if opts then
    for k, v in pairs(opts) do
      config[k] = v
    end
  end
  return M
end

--- M:start() - wire the pieces and begin monitoring. Called once by the outer
--- composition root. Safe across hs.reload(): reload tears down the whole Lua
--- state and history is read back from disk here.
function M:start()
  math.randomseed(os.time())
  config.util = util

  -- The insertion engine is a required collaborator rather than an optional one, so a missing
  -- one fails here with a sentence rather than as a nil call inside a keypress an hour later.
  -- A structural check, the way a contract is checked in a language with no interfaces, naming
  -- the one function whose absence would prove this is not the engine.
  local paste = config.paste
  if type(paste) ~= "table" or type(paste.paste) ~= "function" then
    error("the clipboard manager configure requires opts.paste, the shared insertion engine from Olm.spoon lib")
  end

  -- The reader chain, built once and used twice. The monitor walks it to capture a copy, and
  -- the engine asks it one much narrower question below.
  local readerChain = readers.build(util)

  -- The engine's own half of what used to be one configure. Only the two fields the insertion
  -- side ever read travel here, and the second and third are the two seams pointing outward,
  -- one letting this spoon rename a file on its way to the pasteboard and one letting the
  -- engine read back what file paths are on the pasteboard right now.
  paste.configure({
    pasteDelay = config.pasteDelay,
    -- The one place this feature is wired together, and the only reason the engine ever
    -- learns of media at all. Presenting the right name is app agnostic and always
    -- matters, so this closure always calls into media, with or without Finder. Only the
    -- collision numbering needs to know the destination, which is why folder is the one
    -- thing conditional here, config.finderTarget names the adapter that knows where a
    -- paste would land, and only this closure, sitting in the composition root, knows
    -- that the answer to "where" is handed straight to media's numbering. Absent or
    -- unanswered, folder is nil and media already treats that as skip the numbering
    -- question entirely rather than as skip the whole call. Neither the engine nor
    -- media.lua learns of the other because of this.
    resolveFilePaths = function(items)
      local folder = config.finderTarget and config.finderTarget.folder()
      return media.resolveForPaste(items, folder)
    end,
    -- What file paths sit on the pasteboard right now, which is the one reading the engine's
    -- restore guard needs and cannot do cheaply itself, since an opaque Finder reference url
    -- takes a subprocess to resolve. The file reader already answers exactly that, so it is
    -- handed over as one closure rather than the whole chain, which is this spoon's own shape
    -- and none of the engine's business.
    currentFilePaths = function()
      for _, reader in ipairs(readerChain) do
        if reader.kind == "file" then
          local entry = reader.read({})
          return entry and entry._paths or nil
        end
      end
      return nil
    end,
  })

  -- Hand the preview chain its tool paths, all three asked of the shared dependency door
  -- right here, so nothing in the chain probes and a missing tool just leaves that one
  -- generator unable to handle anything.
  --
  -- This used to read config.ffmpeg and config.ffprobe and say they were resolved outside
  -- this spoon and injected through configure. Nothing resolved them. No code anywhere in
  -- this plugin or above it ever assigned either field, so both arrived nil for as long as
  -- the fields existed and a video clipboard entry could never render a preview at all.
  -- Both tools are declared, mapped and installed, so every layer meant to guarantee them
  -- had done its job and the value simply stopped one hop short of the thing that needed
  -- it. Reading all three off the door in one place is what makes that unable to happen
  -- again, since there is no named field left for anyone to forget to fill.
  local function resolve(tool)
    return config.deps and config.deps.path(tool) or nil
  end
  preview.configure({
    util = util,
    ffmpeg = resolve("ffmpeg"),
    ffprobe = resolve("ffprobe"),
    sips = resolve("sips"),
  })

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
  -- the store and the insertion engine and holds no persistent state of its own, so it is
  -- configured here and never started. It gets the readers module rather than a built chain,
  -- since what it needs is textEntry, the one place a text entry's label is decided.
  session.configure({
    store = store,
    paste = paste,
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
    --
    -- notify on the way in, onMessage on the way down, and the rename is the fix rather than an
    -- inconsistency. It arrives under the root's own word for one line of feedback, shared with
    -- every other plugin that has something to say, because a root value is delivered by field
    -- name. Read as config.onMessage it was nil on every run, so appending to an entry and
    -- walking back through history both did their work in total silence, which for those two
    -- actions is the only feedback there is.
    onMessage = config.notify,
  })

  -- onCapture is what tells the session layer a pasteboard change was a real copy rather than
  -- one of our own pastes. Only the monitor still knows, which is why it is published from
  -- there rather than inferred from the store. onUserPaste is the same shape for a plain
  -- Cmd+V, which changes nothing on the pasteboard and so needs an event tap rather than the
  -- poll to see at all, and it is wired straight to resetSequence since a user paste ends a
  -- walk exactly the way a genuine copy already does.
  monitor.configure({
    readers = readerChain,
    store = store,
    util = util,
    paste = paste,
    skipTypes = config.skipTypes,
    pollInterval = config.pollInterval,
    onCapture = session.noteCapture,
    onUserPaste = session.resetSequence,
  })
  -- The manage history page, policy over the store and nothing else. It holds no state of its
  -- own between opens, so like the session layer it is configured and never started.
  prune.configure({ store = store })

  ui.configure(merged({
    store = store,
    prune = prune,
    paste = paste,
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
