--- The poll engine.
---
--- macOS emits no clipboard-changed event, so we poll changeCount, an integer
--- read that is effectively free, and only read content when it moves. On a
--- change the concealed-type skip runs first, then the reader chain, and the
--- first matching reader's entry (if any) goes to the store.
---
--- Paste-back used to live here too, and now lives in the shared insertion engine at
--- Olm.spoon/lib/paste.lua, which every paste in this folder goes through. The self-capture
--- guard went with it, because the writes it hides are all on that side. Writing to the
--- pasteboard bumps changeCount, so the engine records the new value immediately or the next
--- poll would re-ingest its own paste. A content signature backs that up for apps that rewrite
--- the pasteboard when they receive our paste, a second bump the count guard alone cannot tell
--- from a real copy. This file asks the engine both questions rather than keeping its own copy
--- of either, through the three seams named below.
---
--- The capture side exposes one hook, onCapture, fired only after a genuine copy has been
--- stored. Nothing else here can tell a real copy from our own paste, and a consumer that
--- needs that distinction cannot recover it from the store, since a paste refreshes an
--- entry's recency and so looks brand new. So the distinction is published from the one
--- place that still has it.
---
--- One more thing is watched rather than polled. A plain Cmd+V changes nothing on the
--- pasteboard, so the poll above never sees it, and the session layer's paste walk needs to know
--- one happened so it can end a walk on it. An event tap is the only way to see a key that writes
--- nothing, and that is a real cost this module did not carry before, a global listener sitting in
--- the path of a very common keystroke. It is built to only ever observe, it reads the event and
--- returns false, never swallowing, delaying, or rewriting it, since breaking a plain paste
--- everywhere would cost far more than this feature is worth. The walk pastes by posting its own
--- synthetic Cmd+V through the insertion engine, and the tap would see that one too, so the
--- engine counts how many of its own pastes are between being written and their settle window
--- closing, reusing exactly the window the self capture guard already reasons about, and the tap
--- stays quiet while that count is above zero. onUserPaste is the optional observer told about a
--- Cmd+V the count says was not ours, published the same way onCapture already is.

local M = {}

--- M.log - this module's logger, exposed so the mechanism's log level can be raised from one
--- place. Silent by default.
local log = hs.logger.new("ClipboardNative", "info")
M.log = log

-- Seconds inside a hundred second window, shared with the session layer's trace and the
-- insertion engine's so the two sides of one press can be read as a single timeline.
local function clock()
  return hs.timer.secondsSinceEpoch() % 100
end

local readers = nil -- injected ordered reader chain
local store = nil
local util = nil
local skipTypes = nil
local onCapture = nil -- optional observer, called with each genuinely copied entry
local onUserPaste = nil -- optional observer, called when a plain Cmd+V lands that was not ours
local paste = nil -- the injected insertion engine, Olm.spoon/lib/paste.lua
local pollInterval = 0.5

local timer = nil
local pasteTap = nil

--------------------------------------------------------------------------------
-- Capture
--------------------------------------------------------------------------------

local function capture(count)
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
        -- Seam, the content signature backstop. The other end is paste.wroteRecently in
        -- Olm.spoon/lib/paste.lua, which owns the signatures because it is what wrote them.
        if paste.wroteRecently(entry.kind, entry.text, entry._paths) then
          -- Our own recent paste echoed back (the receiving app rewrote the
          -- pasteboard). The item is already at the top from the paste, so ignore
          -- this copy entirely rather than record it again.
          log.df("%.3f ignored our own paste echoing back from %s", clock(), tostring(sourceApp))
          return
        end
        entry.sourceApp = sourceApp
        -- add returns the live element, the new one or the existing one a duplicate
        -- collapsed onto, and nil when this store refuses the kind. The observer is handed
        -- that live reference, so a consumer can compare it against the list by identity.
        local stored = store.add(entry)
        log.df("%.3f captured %s from %s, count=%d", clock(), tostring(entry.kind), tostring(sourceApp), count)
        if stored and onCapture then
          onCapture(stored)
        end
      end
      return
    end
  end
end

local function poll()
  -- The insertion engine owns the pasteboard while it reads a selection, writing twice across
  -- that window, and neither of those writes is history.
  if paste.isReading() then
    return
  end
  local c = hs.pasteboard.changeCount()
  -- Seam, the changeCount guard. The other end is paste.accountChange in
  -- Olm.spoon/lib/paste.lua, which holds the count because every write it hides is its own. A
  -- false answer means this count is already accounted for, either nothing new, the common
  -- case, or a write the engine made.
  if not paste.accountChange(c) then
    return
  end
  capture(c)
end

--------------------------------------------------------------------------------
-- Paste watcher
--------------------------------------------------------------------------------

-- Resolved once rather than on every keystroke.
local vKeyCode = hs.keycodes.map.v

-- True for a plain Cmd+V with nothing else held. Exact rather than merely cmd down, since
-- Cmd Shift V and the like are a different command in whatever app receives them and are no
-- business of a watcher that exists only to end a paste walk.
local function isPlainCmdV(event)
  if event:getKeyCode() ~= vKeyCode then
    return false
  end
  local flags = event:getFlags()
  return flags.cmd and not flags.shift and not flags.alt and not flags.ctrl
end

-- The tap callback. It reads the event and nothing more, always returning false so the key
-- keeps going wherever it was headed, since this watcher exists to learn that a Cmd+V happened,
-- never to change what one does.
--
-- Seam, the synthetic paste count. The other end is paste.ownPasteInFlight in
-- Olm.spoon/lib/paste.lua, which counts its own Cmd+V in and back out across the settle window.
-- That is what tells a real user press apart from the walk's own synthetic one, which this same
-- tap would otherwise see and wrongly end the walk it belongs to.
local function watchPaste(event)
  if not paste.ownPasteInFlight() and isPlainCmdV(event) and onUserPaste then
    onUserPaste()
  end
  return false
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

--- M.start() - begin polling and watching for a plain Cmd+V. Ignores whatever is already on the
--- pasteboard, which is what accounting for the current count does. The tap is created fresh on
--- every call rather than trusted to survive from before, since hs.reload tears down the whole
--- Lua state and any tap from an earlier load goes with it, so this is the only place one is
--- ever made.
function M.start()
  paste.accountChange(hs.pasteboard.changeCount())
  timer = hs.timer.doEvery(pollInterval, poll)

  if pasteTap then
    pasteTap:stop()
  end
  pasteTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, watchPaste)
  pasteTap:start()

  return M
end

--- M.configure(opts) injects the reader chain, store, util, the insertion engine, the poll
--- interval, and the optional onCapture and onUserPaste observers, onCapture called with the
--- stored entry after every genuine copy and onUserPaste called with no argument after every
--- plain Cmd+V that was not one of the engine's own. opts.paste is not optional, since all four
--- questions this file asks about a pasteboard change live in the engine and there is nothing
--- honest to poll without them.
function M.configure(opts)
  readers = opts.readers
  store = opts.store
  util = opts.util
  skipTypes = opts.skipTypes
  onCapture = opts.onCapture
  onUserPaste = opts.onUserPaste
  paste = opts.paste
  pollInterval = opts.pollInterval or pollInterval
  return M
end

return M
