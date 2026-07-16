--- The poll engine and paste-back.
---
--- macOS emits no clipboard-changed event, so we poll changeCount, an integer
--- read that is effectively free, and only read content when it moves. On a
--- change the concealed-type skip runs first, then the reader chain, and the
--- first matching reader's entry (if any) goes to the store.
---
--- Paste-back lives here too, so the pasteboard write and the self-capture guard
--- sit together. Writing to the pasteboard bumps changeCount, so we record the
--- new value immediately or the next poll would re-ingest our own paste.

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
        entry.sourceApp = sourceApp
        store.add(entry)
      end
      return
    end
  end
end

local function poll()
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

-- Build the file-url object(s) to paste, always preferring our snapshot so the
-- entry pastes our own copy, never the possibly-gone original. Falls back to the
-- original path only when there is no snapshot (a folder or an oversized file)
-- and it still exists. Returns a single object or an array for writeObjects.
local function fileURLObjects(entry)
  local urls = {}
  for _, el in ipairs(entry.files or {}) do
    local p = (el.stored and hs.fs.attributes(el.stored) and el.stored)
      or (hs.fs.attributes(el.path) and el.path)
      or nil
    if p then
      urls[#urls + 1] = { url = "file://" .. encodePath(p) }
    end
  end
  if #urls == 0 then return nil end
  if #urls == 1 then return urls[1] end
  return urls
end

-- Put one entry (or a synthetic text op, a table with kind "text" and a joined
-- text field) on the pasteboard. Returns true when something was written, false
-- when the media is gone, so a caller pasting a sequence can skip and continue.
local function writeEntry(entry)
  if entry.kind == "image" then
    local img = hs.image.imageFromPath(entry.full)
    if not img then
      log.w("image file missing, cannot paste")
      return false
    end
    hs.pasteboard.writeObjects(img)
  elseif entry.kind == "file" then
    local objs = fileURLObjects(entry)
    if not objs then
      log.w("no pasteable file for entry")
      return false
    end
    hs.pasteboard.writeObjects(objs)
  else
    hs.pasteboard.setContents(entry.text or "")
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
