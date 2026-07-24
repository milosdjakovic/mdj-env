--- The poll engine and paste-back.
---
--- macOS emits no clipboard-changed event, so we poll changeCount, an integer
--- read that is effectively free, and only read content when it moves. On a
--- change the concealed-type skip runs first, then the reader chain, and the
--- first matching reader's entry (if any) goes to the store.
---
--- Paste-back lives here too, so the pasteboard write and the self-capture guard
--- sit together. Writing to the pasteboard bumps changeCount, so we record the
--- new value immediately or the next poll would re-ingest our own paste. A content
--- signature backs that up for apps that rewrite the pasteboard when they receive
--- our paste, a second bump the count guard alone cannot tell from a real copy.

local M = {}

local log = hs.logger.new("ClipboardNative", "info")

local readers = nil -- injected ordered reader chain
local store = nil
local util = nil
local skipTypes = nil
local pollInterval = 0.5
local pasteDelay = 0.1

local timer = nil
local lastChange = -1 -- last changeCount we have accounted for; the guard's state
-- True while copySelection owns the pasteboard for a read. It writes twice (the Cmd+C
-- copy, then the restore), so rather than sign each write it suppresses the poll outright
-- for the read window, which cannot race the 0.5s poll tick. Always cleared in the restore.
local reading = false

-- Content-signature backstop to the changeCount guard. The count guard stops the
-- poll re-ingesting our own paste's write, but only that one change. An app that
-- rewrites the pasteboard when it receives our paste (some editors do) bumps the
-- count a second time with the same content, which the count guard cannot tell from
-- a real copy. So we also remember a signature of what we just pasted for a short
-- window and skip a capture that matches it. This matters most for a batch paste,
-- whose newline-joined text is pasted but never stored, so its echo would otherwise
-- land as a brand new entry carrying the destination app's icon.
local selfSigs = {} -- signature -> expiry, seconds since epoch
local selfWindow = 3.0 -- how long a self-written signature suppresses a matching capture

-- A cheap content signature, shared by the paste side (recording what we wrote) and
-- the capture side (matching an echo). Text and url share one space keyed by the
-- string, since a url is written as plain text and may echo back as either kind.
-- Files key on their ordered paths. Images have no cheap identity, so they are not
-- signed and still rely on the changeCount guard alone.
local function contentSig(kind, text, paths)
  if kind == "text" or kind == "url" then
    return "s\31" .. (text or "")
  elseif kind == "file" then
    return "f\31" .. table.concat(paths or {}, "\31")
  end
  return nil
end

-- True when sig was written by our own recent paste. Prunes expired signatures on
-- the way, so the table stays as small as the last paste.
local function selfWritten(sig)
  local now = hs.timer.secondsSinceEpoch()
  for s, exp in pairs(selfSigs) do
    if exp < now then
      selfSigs[s] = nil
    end
  end
  return sig ~= nil and selfSigs[sig] ~= nil
end

--------------------------------------------------------------------------------
-- Capture
--------------------------------------------------------------------------------

local function capture()
  local set = util.typeSet(hs.pasteboard.contentTypes())

  -- Concealed-type skip. A password manager (or any concealed/transient source)
  -- marks a copy it does not want recorded. Runs before reading any content, so
  -- secrets never touch the store.
  for _, skip in ipairs(skipTypes) do
    if set[skip] then
      log.d("skipping concealed/transient copy")
      return
    end
  end

  -- The app frontmost when the pasteboard changed is the one that did the copy,
  -- recorded so the row can show that app's icon. A bundle id survives reload and
  -- resolves to an icon lazily in the ui.
  local front = hs.application.frontmostApplication()
  local sourceApp = front and front:bundleID() or nil

  local ctx = { set = set, avail = hs.pasteboard.typesAvailable() }
  for _, reader in ipairs(readers) do
    if reader.matches(ctx) then
      -- First matching reader owns this copy, even if it reads nothing usable,
      -- so a file-url present but unreadable does not fall through to text.
      local entry = reader.read(ctx)
      if entry then
        if selfWritten(contentSig(entry.kind, entry.text, entry._paths)) then
          -- Our own recent paste echoed back (the receiving app rewrote the
          -- pasteboard). The item is already at the top from the paste, so ignore
          -- this copy entirely rather than record it again.
          return
        end
        entry.sourceApp = sourceApp
        store.add(entry)
      end
      return
    end
  end
end

local function poll()
  if reading then
    return -- copySelection owns the pasteboard; its writes are not history
  end
  local c = hs.pasteboard.changeCount()
  if c == lastChange then
    return -- nothing new; the common case
  end
  lastChange = c
  capture()
end

--------------------------------------------------------------------------------
-- Paste back
--------------------------------------------------------------------------------

-- Percent-encode a path so it forms a valid file url, keeping the separators.
local function encodePath(p)
  return (p:gsub("[^%w%-%._~/]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

-- The filesystem paths we will actually paste, always preferring our snapshot so the
-- entry pastes our own copy, never the possibly-gone original. Falls back to the
-- original path only when there is no snapshot (a folder or an oversized file) and it
-- still exists. Order is preserved so the urls and the signature agree.
local function writtenFilePaths(entry)
  local paths = {}
  for _, el in ipairs(entry.files or {}) do
    local p = (el.stored and hs.fs.attributes(el.stored) and el.stored)
      or (hs.fs.attributes(el.path) and el.path)
      or nil
    if p then
      paths[#paths + 1] = p
    end
  end
  return paths
end

-- Build the file-url object(s) for writeObjects from those paths, a single object or
-- an array, or nil when nothing is left to paste.
local function fileURLObjects(paths)
  if #paths == 0 then return nil end
  local urls = {}
  for _, p in ipairs(paths) do
    urls[#urls + 1] = { url = "file://" .. encodePath(p) }
  end
  if #urls == 1 then return urls[1] end
  return urls
end

-- Put one entry (or a synthetic text op, a table with kind "text" and a joined
-- text field) on the pasteboard. Returns true when something was written, false
-- when the media is gone, so a caller pasting a sequence can skip and continue.
local function writeEntry(entry)
  local sig
  if entry.kind == "image" then
    local img = hs.image.imageFromPath(entry.full)
    if not img then
      log.w("image file missing, cannot paste")
      return false
    end
    hs.pasteboard.writeObjects(img)
    -- images are not signed; they rely on the changeCount guard alone
  elseif entry.kind == "file" then
    local paths = writtenFilePaths(entry)
    local objs = fileURLObjects(paths)
    if not objs then
      log.w("no pasteable file for entry")
      return false
    end
    hs.pasteboard.writeObjects(objs)
    sig = contentSig("file", nil, paths)
  else
    hs.pasteboard.setContents(entry.text or "")
    sig = contentSig(entry.kind, entry.text, nil)
  end
  -- Remember what we just wrote so an echo from the receiving app is not re-ingested.
  if sig then
    selfSigs[sig] = hs.timer.secondsSinceEpoch() + selfWindow
  end
  return true
end

--- M.paste(entry) - put the entry on the pasteboard and paste it into the
--- frontmost app, then float it to the top of history.
function M.paste(entry)
  if not entry then
    return
  end
  if not writeEntry(entry) then
    return
  end

  -- Self-capture guard, recorded before the Cmd+V so the poll ignores our write.
  lastChange = hs.pasteboard.changeCount()
  store.moveToFront(entry)

  -- A short delay lets focus return to the app the chooser covered.
  hs.timer.doAfter(pasteDelay, function()
    hs.eventtap.keyStroke({ "cmd" }, "v", 0)
  end)
end

-- Turn a collected batch into an ordered list of paste ops. Consecutive text and
-- url entries coalesce into one newline joined text op, so a run of snippets
-- lands as separate lines in a single paste, while each image or file stays its
-- own op. Order is preserved, so a text, image, text batch pastes in that order.
local function batchOps(entries)
  local ops, run = {}, {}
  local function flush()
    if #run > 0 then
      ops[#ops + 1] = { kind = "text", text = table.concat(run, "\n") }
      run = {}
    end
  end
  for _, e in ipairs(entries) do
    if e.kind == "text" or e.kind == "url" then
      run[#run + 1] = e.text or ""
    else
      flush()
      ops[#ops + 1] = e
    end
  end
  flush()
  return ops
end

--- M.pasteBatch(entries) - paste a collected batch into the frontmost app in the
--- order the items were gathered, then reorder history. This is the deferred
--- reorder: collecting never touches the store, so the list stays put while the
--- picker is open, and only here, on commit and close, does each collected entry
--- float to the top in collected order, saved once, so the next open reflects it.
function M.pasteBatch(entries)
  if not entries or #entries == 0 then
    return
  end
  for _, e in ipairs(entries) do
    store.moveToFront(e)
  end

  -- Each op writes the pasteboard, refreshes the guard so the poll ignores our
  -- write, waits for the paste to settle, then sends Cmd+V. The next op starts
  -- only after that settle, so a multi item paste does not race the pasteboard.
  local ops = batchOps(entries)
  local i = 0
  local function step()
    i = i + 1
    local op = ops[i]
    if not op then
      return
    end
    if writeEntry(op) then
      lastChange = hs.pasteboard.changeCount()
      hs.timer.doAfter(pasteDelay, function()
        hs.eventtap.keyStroke({ "cmd" }, "v", 0)
        hs.timer.doAfter(pasteDelay + 0.05, step)
      end)
    else
      step() -- an op whose media vanished is skipped, the rest still paste
    end
  end
  step()
end

-- How long after the Cmd+V to put the original pasteboard back. Long enough that the
-- receiving app has read our text, short enough that a user copy in between is unlikely.
-- Restoring sooner risks the app reading the restored content and pasting that instead.
local restoreDelay = 0.15

--- M.pasteText(text) - insert arbitrary text into the frontmost app by pasting it.
--- This is the reliable path for glyphs a synthesized keystroke mangles, an emoji or
--- any character outside the basic multilingual plane, which terminals and some native
--- apps drop or render as replacement boxes because they read the key event rather than
--- reassembling the surrogate pair. A real paste delivers the bytes intact everywhere.
--- The pasteboard is snapshotted across all its types, the text is written and pasted,
--- and the snapshot is put back after, so the clipboard is left untouched. Both writes
--- are hidden from the poll through the same guard M.paste uses, so nothing lands in
--- history. It reuses this module because the self-capture guard lives here and belongs
--- in one place.
function M.pasteText(text)
  if not text or text == "" then
    return
  end

  -- Snapshot every type so an image or file clipboard is restored too, not just text.
  local snapshot = hs.pasteboard.readAllData()
  hs.pasteboard.setContents(text)

  -- Suppress our write from the poll and its echo, exactly as writeEntry does.
  lastChange = hs.pasteboard.changeCount()
  selfSigs[contentSig("text", text, nil)] = hs.timer.secondsSinceEpoch() + selfWindow

  -- A short delay lets focus return to the app the picker covered, then paste.
  hs.timer.doAfter(pasteDelay, function()
    hs.eventtap.keyStroke({ "cmd" }, "v", 0)
    -- Put the original clipboard back once the paste has read ours, and keep that
    -- restore out of history as well. The restore is not pasted anywhere, so the
    -- changeCount guard alone covers it, no signature is needed.
    hs.timer.doAfter(restoreDelay, function()
      if snapshot and next(snapshot) then
        hs.pasteboard.writeAllData(snapshot)
      else
        hs.pasteboard.clearContents()
      end
      lastChange = hs.pasteboard.changeCount()
    end)
  end)
end

-- How long to wait for a copy to land on the pasteboard before giving up, and the poll
-- step. A copy bumps changeCount, so we watch it move; with nothing selected most apps do
-- nothing on Cmd+C and the count never moves, which we report as no selection.
local copyTimeout = 0.4
local copyStep = 0.03

--- M.copySelection(cb) - read the current selection without disturbing the clipboard.
--- The read-side mirror of pasteText, kept here so the snapshot/restore and the
--- self-capture guard live in one place. It snapshots the pasteboard, sends Cmd+C, and
--- polls changeCount until the copy lands, then reads the text, restores the snapshot, and
--- calls cb(text). The whole window runs with the `reading` flag set, so the background
--- poll ingests neither the copy nor the restore into history, and the restore also rides
--- the changeCount guard, so the clipboard and its history are left exactly as they were.
--- cb(nil) when nothing was copied within the window (no selection) or the selection is not
--- text. Callable only after configure/start, since it depends on this module's guard state.
function M.copySelection(cb)
  local snapshot = hs.pasteboard.readAllData()
  local before = hs.pasteboard.changeCount()
  reading = true
  hs.eventtap.keyStroke({ "cmd" }, "c", 0)

  local waited = 0
  local function restore()
    if snapshot and next(snapshot) then
      hs.pasteboard.writeAllData(snapshot)
    else
      hs.pasteboard.clearContents()
    end
    lastChange = hs.pasteboard.changeCount()
    reading = false
  end
  local function check()
    if hs.pasteboard.changeCount() ~= before then
      local text = hs.pasteboard.getContents()
      restore()
      cb(text)
    elseif waited < copyTimeout then
      waited = waited + copyStep
      hs.timer.doAfter(copyStep, check)
    else
      restore()
      cb(nil)
    end
  end
  hs.timer.doAfter(copyStep, check)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

--- M.start() - begin polling. Ignores whatever is already on the pasteboard.
function M.start()
  lastChange = hs.pasteboard.changeCount()
  timer = hs.timer.doEvery(pollInterval, poll)
  return M
end

--- M.configure(opts) - inject the reader chain, store, util, and timing.
function M.configure(opts)
  readers = opts.readers
  store = opts.store
  util = opts.util
  skipTypes = opts.skipTypes
  pollInterval = opts.pollInterval or pollInterval
  pasteDelay = opts.pasteDelay or pasteDelay
  return M
end

return M
