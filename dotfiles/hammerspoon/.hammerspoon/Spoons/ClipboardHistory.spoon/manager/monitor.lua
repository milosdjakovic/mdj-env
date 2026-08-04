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
--- A delayed restore trusts that same signature before it writes anything back,
--- since the moved count that ends its quiet window is exactly as ambiguous as the
--- one on the capture side, and mistaking a genuine copy for our own echo would not
--- just mis-file it, it would destroy it outright by writing the old clipboard over it.
---
--- Every paste funnels through one primitive, pasteOp, and the callers differ only in the
--- options they hand it, whether to put the previous pasteboard back afterwards and what to run
--- once the paste has settled. Reordering history is the caller's policy rather than something
--- baked into the paste, which is what lets a walk through history paste from it without
--- rewriting the order it is walking. writeClipboard is the same write with no keystroke, for a
--- caller that wants the clipboard loaded but nothing pasted.
---
--- A paste is not the only way in, only the universal one. insertText hands text straight to the
--- focused field, involving neither the pasteboard nor the keyboard. The two are not
--- interchangeable and neither replaces the other. A paste carries any kind of content into
--- anything and costs a round trip through another app's clock. Direct insertion is instant and
--- costs nothing, but carries only text, and only into a field that accepts it. So the caller
--- picks, and a caller that can use the fast one falls back to the paste when the field refuses.
---
--- Every synthetic keystroke, the Cmd+C that reads a selection and the Cmd+V that pastes, goes out
--- through one helper that reports which modifiers the caller was holding, since a stroke sent
--- against a held chord can be quietly ignored by the app and that is invisible from in here.
--- Measured, not theorised, in one app it is ignored every time, which is what direct insertion
--- exists to get past.
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
--- synthetic Cmd+V through pasteOp below, and the tap would see that one too, so pasteOp counts
--- how many of its own pastes are between being written and their settle window closing, reusing
--- exactly the window the self capture guard already reasons about, and the tap stays quiet while
--- that count is above zero. onUserPaste is the optional observer told about a Cmd+V the count
--- says was not ours, published the same way onCapture already is.

local M = {}

--- M.log - this module's logger, exposed so the mechanism's log level can be raised from one
--- place. A paste is a write, a keystroke and a restore spread across two timers, and whether it
--- landed is only visible in the receiving app, so the debug lines below record that sequence with
--- millisecond timing. They are silent by default.
local log = hs.logger.new("ClipboardNative", "info")
M.log = log

-- Seconds inside a hundred second window, shared with the session layer's trace so the two sides
-- of one press can be read as a single timeline.
local function clock()
  return hs.timer.secondsSinceEpoch() % 100
end

local function frontID()
  local front = hs.application.frontmostApplication()
  return (front and front:bundleID()) or "unknown"
end

local readers = nil -- injected ordered reader chain
local store = nil
local util = nil
local skipTypes = nil
local onCapture = nil -- optional observer, called with each genuinely copied entry
local onUserPaste = nil -- optional observer, called when a plain Cmd+V lands that was not ours
local resolveFilePaths = nil -- optional injected transform over the { content, name } items writtenFilePaths builds
local pollInterval = 0.5
local pasteDelay = 0.1

local timer = nil
local pasteTap = nil

-- Every delayed step below runs through this, and holding the timer is the whole point. A
-- Hammerspoon timer is userdata whose finalizer stops it, so a pending timer nothing refers
-- to can be collected before it fires, and the step then never happens with no error
-- anywhere. Here that would mean a paste that writes the pasteboard and never sends the
-- keystroke, or worse a snapshot that is never put back, leaving our own text sitting on the
-- user's clipboard. Each call takes its own key and releases only that key, because these
-- are sequences where every step must run and a later one must never cancel an earlier one.
-- That is not hypothetical in here, a paste walk has several pasteOp windows overlapping,
-- and a single shared slot would drop the earlier one's restore on the floor.
local pendingSteps = {}
local function after(delay, fn)
  local slot = {}
  pendingSteps[slot] = hs.timer.doAfter(delay, function()
    pendingSteps[slot] = nil
    fn()
  end)
end

local lastChange = -1 -- last changeCount we have accounted for; the guard's state
-- True while copySelection owns the pasteboard for a read. It writes twice (the Cmd+C
-- copy, then the restore), so rather than sign each write it suppresses the poll outright
-- for the read window, which cannot race the 0.5s poll tick. Always cleared in the restore.
local reading = false

-- How many of this module's own synthetic Cmd+V pastes are between being written and their
-- settle window closing. The paste watcher near the end of this file would otherwise mistake
-- one of these for a user press and end a walk that never should have ended, so pasteOp counts
-- itself in and back out across exactly the window it already reasons about for the self capture
-- guard below, and the watcher stays quiet while the count is above zero. A count rather than a
-- flag, since the walk, a batch paste, and pasteText can each have one outstanding, and a later
-- one clearing a boundary an earlier one still owns would let a real keystroke straight through
-- mid overlap.
local ownPasteCount = 0

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
          log.df("%.3f ignored our own paste echoing back from %s", clock(), tostring(sourceApp))
          return
        end
        entry.sourceApp = sourceApp
        -- add returns the live element, the new one or the existing one a duplicate
        -- collapsed onto, and nil when this store refuses the kind. The observer is handed
        -- that live reference, so a consumer can compare it against the list by identity.
        local stored = store.add(entry)
        log.df("%.3f captured %s from %s, count=%d", clock(), tostring(entry.kind), tostring(sourceApp), lastChange)
        if stored and onCapture then
          onCapture(stored)
        end
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
-- Synthetic keystrokes
--------------------------------------------------------------------------------

-- Both synthetic strokes here, the Cmd+C that reads a selection and the Cmd+V that pastes, are
-- reported by the modifiers a caller was holding when it asked, which is the one thing that tells
-- a silent failure apart from an empty selection. Nothing is done about those modifiers here.
--
-- Two attempts to fix them from inside this module were measured and both removed. The stroke's
-- own flags never leak, an event tap sees exactly the modifiers asked for even mid chord. And
-- clearing the modifier state around the stroke, which does take a hand built flagsChanged event
-- since a key event on a modifier keycode changes nothing, cannot be timed correctly, because the
-- app processes the stroke long after the restore has already run. A real app copied happily with
-- the state asserted anyway. So the interference, if any, is the physically held keys rather than
-- the state, and a physically held key cannot be lifted from here. Whoever binds the key waits for
-- the release instead, which is where that decision belongs, since a caller with nothing held must
-- not wait at all.
local clearableMods = { "cmd", "alt", "ctrl", "shift" }

local function heldModifiers()
  local flags = hs.eventtap.checkKeyboardModifiers()
  local held = {}
  for _, name in ipairs(clearableMods) do
    if flags[name] then
      held[#held + 1] = name
    end
  end
  return held
end

-- Every synthetic stroke in this module goes out through here, returning what was held so a
-- caller can report it when the stroke visibly did not land.
local function stroke(mods, key)
  local held = heldModifiers()
  hs.eventtap.keyStroke(mods, key, 0)
  return held
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

-- Content and name are two independent things, never one. The bytes we paste always
-- prefer our snapshot so the entry pastes our own copy, never the possibly-gone original,
-- falling back to the original path only when there is no snapshot (a folder or an
-- oversized file) and it still exists. The name we present is always the basename of
-- el.path, since that field is authoritative, present for every entry regardless of
-- layout or whether the file was frozen or linked, and never rewritten. The cache path is
-- only ever a source of bytes and must never be trusted as a source of a name, since a
-- copy frozen under an older flat layout carries a generated basename of its own rather
-- than the one the user actually copied. An element contributes nothing when neither
-- stored nor path exists on disk. Order is preserved so the urls and the signature agree.
--
-- An optional injected transform, resolveFilePaths, gets the last look at this list of
-- { content, name } items before anything leaves this function, and the plain list of
-- paths it hands back is what is actually written to the pasteboard and what the
-- signature below is computed from, since the signature exists to describe what we truly
-- wrote rather than what we started with. This is the one seam where something outside
-- this module can turn a content path and its name into a different path to write, which
-- is how a destination aware renaming and staging policy is wired in without this module
-- ever learning what that destination is or what asked about it. Absent, or answering
-- nil, this just takes each item's content path straight through, so behaviour without
-- the adapter is exactly what it always was.
local function writtenFilePaths(entry)
  local items = {}
  for _, el in ipairs(entry.files or {}) do
    local content = (el.stored and hs.fs.attributes(el.stored) and el.stored)
      or (hs.fs.attributes(el.path) and el.path)
      or nil
    if content then
      items[#items + 1] = { content = content, name = el.path:match("([^/]+)$") or el.path }
    end
  end
  if resolveFilePaths then
    local resolved = resolveFilePaths(items)
    if resolved then
      return resolved
    end
  end
  local paths = {}
  for _, it in ipairs(items) do
    paths[#paths + 1] = it.content
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
-- Also returns the signature it recorded, or nil for an image, so a caller that
-- means to restore later can ask the same guard the capture side already trusts.
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
  return true, sig
end

-- How long after the Cmd+V the paste is considered settled, which is both when the previous
-- pasteboard may be put back and when a following op may write its own content. Long enough
-- that the receiving app has read ours, short enough that a user copy in between is
-- unlikely. Acting sooner risks the app reading the next content and pasting that instead.
local settleDelay = 0.15

-- A restore that has been asked to wait, held here rather than per paste because only the most
-- recent paste's restore can still be wanted. Whatever a superseded one would put back is about
-- to be replaced anyway, and letting it fire would drop the old clipboard on top of content the
-- next paste has just written, which the receiving app would then paste instead.
local pendingRestore = nil

local function cancelPendingRestore()
  if pendingRestore then
    pendingRestore:stop()
    pendingRestore = nil
  end
end

-- The signature of whatever is on the pasteboard right now, read the same narrow way
-- writeEntry read it rather than through the full capture reader chain, since the only
-- question a restore ever asks is whether this one write, or the receiving app's echo of
-- it, is still there, never what kind of thing arrived if it is not. The prefix a sig
-- carries already says which reading to do, "f" for the file reader's current paths, and
-- anything else for plain text, so no second kind has to travel alongside the signature.
local function currentSig(prefix)
  if prefix == "f" then
    for _, reader in ipairs(readers or {}) do
      if reader.kind == "file" then
        local entry = reader.read({})
        return entry and contentSig("file", nil, entry._paths) or nil
      end
    end
    return nil
  end
  return contentSig("text", hs.pasteboard.getContents(), nil)
end

-- What kind of thing is on the pasteboard right now, worded for the log line a
-- restore prints when it gives up, so it says what it found rather than only that it
-- gave up. Same file over image over url over text priority the reader chain uses, since
-- more than one type can be present and that order says which one actually arrived.
local function describePasteboard()
  local set = util.typeSet(hs.pasteboard.contentTypes())
  local avail = hs.pasteboard.typesAvailable()
  if set["public.file-url"] then
    return "a file"
  elseif avail.image then
    return "an image"
  elseif avail.URL then
    return "a url"
  elseif avail.string then
    return "text"
  end
  return "nothing recognisable"
end

-- The one guard behind every restore in this file, the paste-back's immediate restore,
-- its delayed quiet-window restore, and copySelection's restore around a synthetic
-- Cmd+C. changeCount answers most of it for free, an unmoved count means nothing has
-- touched the pasteboard since writtenCount was recorded and the restore is plainly
-- safe. A moved count is not by itself the verdict though, only the question, because the
-- very case selfSigs exists for, a receiving app rewriting the pasteboard with the same
-- content when it takes our paste, moves the count a second time carrying nothing new.
-- Treating that moved count alone as proof of a third party copy is the naive version of
-- this guard, and it fails in exactly this file's own documented case, mistaking our own
-- echo for someone else's copy would abandon a restore that was never actually at risk
-- and leave our own pasted text sitting on the user's clipboard, which is the very thing
-- the restore exists to prevent. So a moved count falls through to content, asking not
-- whether the count changed but whether what is on the pasteboard right now still is the
-- thing sig describes. A write with no signature, an image, has no second opinion to
-- fall back on and answers to the count alone, as it always has.
local function pasteboardStillOurs(writtenCount, sig)
  if hs.pasteboard.changeCount() == writtenCount then
    return true
  end
  if not sig then
    return false
  end
  return currentSig(sig:sub(1, 1)) == sig
end

-- Put a snapshot from readAllData back, or clear the pasteboard when there was nothing to
-- snapshot, and hide that write from the poll. A restore is never pasted anywhere, so the
-- changeCount guard alone covers it and no signature is needed.
local function restorePasteboard(snapshot)
  if snapshot and next(snapshot) then
    hs.pasteboard.writeAllData(snapshot)
  else
    hs.pasteboard.clearContents()
  end
  lastChange = hs.pasteboard.changeCount()
end

-- One paste, the primitive every paste path here is built from. It writes the op, hides the
-- write from the poll, lets focus return to the app the picker covered, and sends Cmd+V.
--
-- opts.restore snapshots the pasteboard across all its types beforehand and puts it back once
-- the paste has settled, so an image or file clipboard survives too and the paste leaves the
-- clipboard as it found it. opts.restoreTo does the same with a snapshot the caller already
-- holds, which is what a run of pastes wants, since snapshotting per paste would capture the
-- previous paste's own content rather than the clipboard the run started from. `done` runs at
-- that same settled moment, which is what lets a batch start its next op without racing the
-- pasteboard.
--
-- opts.restoreWhenQuiet, in seconds, holds the restore back that much longer, and any later
-- paste cancels it. Settling and restoring are the same moment for a single paste, but they
-- answer to different clocks. Settling is ours, how long before we may touch the pasteboard
-- again. The restore is the receiving app's, and the gap between our Cmd+V and the next write of
-- any kind is all the time it has to read what we pasted. A caller pasting a run of entries in
-- quick succession therefore wants the same gap ahead of a restore as it leaves between entries,
-- and it is the caller that knows that number, so it passes it rather than finding one here.
--
-- Returns false, having done nothing, when the op's media is gone, so a caller pasting a
-- sequence can skip it and continue.
local function pasteOp(op, opts, done)
  opts = opts or {}
  local snapshot = opts.restoreTo or (opts.restore and hs.pasteboard.readAllData()) or nil
  local quiet = opts.restoreWhenQuiet

  -- This paste supersedes any restore still waiting, and its snapshot is about to be written
  -- over regardless, so drop it before touching the pasteboard rather than racing it.
  cancelPendingRestore()

  local wrote, writeSig = writeEntry(op)
  if not wrote then
    return false
  end
  -- Self-capture guard, recorded before the Cmd+V so the poll ignores our write. writeCount
  -- is the same value handed to pasteboardStillOurs below, the count a later restore checks
  -- itself against rather than the count at the moment the restore actually fires.
  lastChange = hs.pasteboard.changeCount()
  local writeCount = lastChange

  -- Counted in now and released on its own timer, tied to the same pasteDelay and settleDelay
  -- this function already waits out before and after its own Cmd+V, so the release needs no new
  -- number of its own. It runs on its own timer rather than nested inside the settle callback
  -- below, so an error later in that chain cannot strand the count above zero and leave the
  -- watcher silently deaf to every Cmd+V from then on.
  ownPasteCount = ownPasteCount + 1
  after(pasteDelay + settleDelay, function()
    ownPasteCount = ownPasteCount - 1
  end)

  log.df("%.3f wrote %s, count=%d, app=%s", clock(), tostring(op.kind), lastChange, frontID())

  after(pasteDelay, function()
    local held = stroke({ "cmd" }, "v")
    log.df(
      "%.3f cmd+v sent, app=%s, held=%s",
      clock(),
      frontID(),
      (next(held) and table.concat(held, "+")) or "none"
    )
    -- Only arm the settle timer when something is waiting on it, so a plain single paste
    -- still costs exactly one timer as it always did.
    if snapshot or done then
      after(settleDelay, function()
        if snapshot and not quiet then
          -- If a genuine copy has already claimed the pasteboard by the time we would
          -- otherwise put the old one back, do not touch it. lastChange is deliberately
          -- left alone here, it still holds writeCount, so the next poll tick sees the
          -- claim as a change and captures it as the fresh entry it actually is, rather
          -- than this restore hiding it the way a successful restore hides itself.
          if pasteboardStillOurs(writeCount, writeSig) then
            restorePasteboard(snapshot)
            log.df("%.3f clipboard restored, count=%d", clock(), lastChange)
          else
            log.df("%.3f restore abandoned, pasteboard now holds %s", clock(), describePasteboard())
          end
        elseif snapshot then
          -- Armed before `done`, since done may start the next paste, and that paste cancelling
          -- this is exactly how a run of them ends with one restore instead of one per entry.
          pendingRestore = hs.timer.doAfter(quiet, function()
            pendingRestore = nil
            -- Same abandonment as above, checked again here since the quiet window is
            -- exactly the longer wait a genuine copy is more likely to land inside.
            if pasteboardStillOurs(writeCount, writeSig) then
              restorePasteboard(snapshot)
              log.df("%.3f clipboard restored after %.2fs quiet, count=%d", clock(), quiet, lastChange)
            else
              log.df(
                "%.3f restore abandoned after %.2fs quiet, pasteboard now holds %s",
                clock(),
                quiet,
                describePasteboard()
              )
            end
          end)
        end
        if done then
          done()
        end
      end)
    end
  end)
  return true
end

--- M.paste(entry, opts) -> bool
--- Put the entry on the pasteboard and paste it into the frontmost app. Returns whether the
--- paste started, false when the entry's media is gone and there was nothing to write.
---
--- opts.reorder, default true, floats the entry to the top of history afterwards, the
--- normal treatment for an entry picked out of the list. A caller stepping through history
--- passes false, so walking the list does not rewrite the order being walked.
---
--- opts.restore, default false, puts the previous pasteboard back once the paste has settled,
--- and opts.restoreTo does the same with a snapshot the caller already holds. A walk uses the
--- latter, so however far it has gone the clipboard still holds what it held when the walk
--- began, and a plain paste keeps meaning the newest entry.
---
--- opts.restoreWhenQuiet, in seconds, delays that restore and lets a later paste cancel it, so a
--- run of pastes leaves the receiving app the same reading window on its last entry as it had on
--- the ones before it. See pasteOp for why the restore answers to the app's clock.
---
--- opts.onSettled runs once the paste has settled and any restore has happened. A caller
--- pressing repeatedly uses it to serialise, since starting a second paste inside the first
--- one's window would have that first restore land on top of the second one's content.
function M.paste(entry, opts)
  if not entry then
    return false
  end
  opts = opts or {}
  local reorder = opts.reorder
  if reorder == nil then
    reorder = true
  end

  local started = pasteOp(entry, {
    restore = opts.restore,
    restoreTo = opts.restoreTo,
    restoreWhenQuiet = opts.restoreWhenQuiet,
  }, opts.onSettled)
  if not started then
    return false
  end
  if reorder then
    store.moveToFront(entry)
  end
  return true
end

--------------------------------------------------------------------------------
-- Direct insertion
--------------------------------------------------------------------------------

--- M.insertText(text) -> bool
--- Hand text straight to the focused element, returning whether it went in.
---
--- This is the fast way in, and the only one that is instant. It touches neither the pasteboard
--- nor the keyboard, so it needs no beat before it, no settle after it, and no clipboard to put
--- back, and a caller can do it again in the same instant the next key is pressed. A paste can
--- never be that, and not because of anything on our side. The unavoidable delay in a paste is the
--- receiving app reading the pasteboard, which is its work on its own clock, and until it has done
--- so nothing may write there again.
---
--- The cost is that not every field accepts it, so this asks first and reports what happened, and
--- a caller falls back to a real paste when the answer is no. Only text can go this way at all, an
--- image or a file has no equivalent, so those always go through the pasteboard.
function M.insertText(text)
  if not text or text == "" then
    return false
  end
  local focused = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  if not focused then
    log.df("%.3f nothing focused in %s, cannot insert directly", clock(), frontID())
    return false
  end
  if not focused:isAttributeSettable("AXSelectedText") then
    log.df("%.3f the focused field in %s refuses direct text", clock(), frontID())
    return false
  end
  local ok = focused:setAttributeValue("AXSelectedText", text) ~= nil
  log.df("%.3f inserted %d chars directly into %s, ok=%s", clock(), #text, frontID(), tostring(ok))
  return ok
end

--- M.readSelection() -> string or nil
--- The current selection straight from the focused element, the read side mirror of insertText and
--- instant for the same reason, no keystroke and no pasteboard. Returns nil when nothing is
--- focused, when the element exposes no selection, or when the selection is empty, and a caller
--- falls back to copySelection, which works anywhere but costs a round trip through Cmd+C.
---
--- Empty and unsupported are deliberately the same answer. They are not the same thing, but a
--- caller does the same either way, and telling them apart here would mean trusting an app that
--- reports an empty selection while showing one, which some do.
function M.readSelection()
  local focused = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  if not focused then
    return nil
  end
  local text = focused:attributeValue("AXSelectedText")
  if type(text) ~= "string" or text == "" then
    log.df("%.3f no direct selection from %s", clock(), frontID())
    return nil
  end
  log.df("%.3f read %d chars of selection directly from %s", clock(), #text, frontID())
  return text
end

--- M.snapshotClipboard() - the current pasteboard across every type, for a caller that will
--- hand it back to paste as restoreTo. Every pasteboard read and write goes through this
--- module, so the snapshot is taken here too rather than reached for directly.
function M.snapshotClipboard()
  return hs.pasteboard.readAllData()
end

--- M.writeClipboard(entry) - load the pasteboard from an entry without pasting anywhere,
--- hidden from the poll and from its own echo exactly as a paste is. The append accumulator
--- writes through this, so the growing text is always what a plain paste would deliver while
--- none of those writes come back as new history entries. Returns false when the entry's
--- media is gone.
function M.writeClipboard(entry)
  if not entry or not writeEntry(entry) then
    return false
  end
  lastChange = hs.pasteboard.changeCount()
  return true
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

  -- Each op pastes in turn, and the next one starts only once the previous has settled, so
  -- a multi item paste never races the pasteboard.
  local ops = batchOps(entries)
  local i = 0
  local function step()
    i = i + 1
    local op = ops[i]
    if not op then
      return
    end
    if not pasteOp(op, nil, step) then
      step() -- an op whose media vanished is skipped, the rest still paste
    end
  end
  step()
end

--- M.pasteText(text) - insert arbitrary text into the frontmost app by pasting it.
--- This is the reliable path for glyphs a synthesized keystroke mangles, an emoji or
--- any character outside the basic multilingual plane, which terminals and some native
--- apps drop or render as replacement boxes because they read the key event rather than
--- reassembling the surrogate pair. A real paste delivers the bytes intact everywhere.
--- The pasteboard is snapshotted across all its types and put back after, so the clipboard
--- is left untouched, and every write is hidden from the poll, so nothing lands in history.
--- It reuses this module because the self-capture guard lives here and belongs in one place.
--- The text is a synthetic op, the same shape a coalesced batch run already produces, so it
--- rides the shared primitive rather than repeating the write, guard, paste, restore dance.
function M.pasteText(text)
  if not text or text == "" then
    return
  end
  pasteOp({ kind = "text", text = text }, { restore = true })
end

-- How long to wait for a copy to land on the pasteboard before giving up, and the poll
-- step. A copy bumps changeCount, so we watch it move; with nothing selected most apps do
-- nothing on Cmd+C and the count never moves, which we report as no selection.
local copyTimeout = 0.4
local copyStep = 0.03

-- A beat before the synthetic Cmd+C, so the keypress that asked for the read has finished being
-- delivered first. Without it the Cmd+C is posted in the same instant the app is still handling
-- that keypress and some apps drop it, which is indistinguishable from an empty selection and was
-- exactly the fault a Ctrl and Option triggered append showed while a Hyper triggered one, going
-- through the same code, never did. The paste side always waited this beat and never showed the
-- fault, which is what pointed at the delay rather than at the modifiers.
local copyDelay = 0.1

--- M.isReading() - is a selection read in flight. A caller whose key can be held down asks
--- before starting one, so it can stay silent instead of reporting an empty selection, since
--- a refused read is not an empty one.
function M.isReading()
  return reading
end

--- M.copySelection(cb) - read the current selection without disturbing the clipboard.
--- The read-side mirror of pasteText, kept here so the snapshot/restore and the
--- self-capture guard live in one place. It snapshots the pasteboard, sends Cmd+C, and
--- polls changeCount until the copy lands, then reads the text and calls cb(text). The
--- whole window runs with the `reading` flag set, so the background poll ingests neither
--- the copy nor the restore into history. Putting the snapshot back answers to the same
--- content guard a delayed paste-back restore uses, narrower here since the window is
--- only from the copy landing to the next line running rather than a whole quiet period,
--- but the same hazard in principle, so a genuine copy that still manages to land in it is
--- left alone rather than overwritten by the pre-Cmd+C snapshot. cb(nil) when nothing was
--- copied within the window (no selection) or the selection is not text. Callable only
--- after configure/start, since it depends on this module's guard state.
function M.copySelection(cb)
  -- One read at a time. A second read starting inside the window of the first would
  -- snapshot the pasteboard the first one is holding and then restore that instead of the
  -- real clipboard, losing it. The guard lives here rather than in each caller because
  -- `reading` is this module's state and a held key can fire a caller faster than a read
  -- completes.
  if reading then
    cb(nil)
    return
  end

  local snapshot = hs.pasteboard.readAllData()
  local before = hs.pasteboard.changeCount()
  reading = true

  local held = {}
  local waited = 0
  local function restore(recordedCount, sig)
    if pasteboardStillOurs(recordedCount, sig) then
      restorePasteboard(snapshot)
    else
      log.df("%.3f selection restore abandoned, pasteboard now holds %s", clock(), describePasteboard())
    end
    reading = false
  end
  local function check()
    if hs.pasteboard.changeCount() ~= before then
      local text = hs.pasteboard.getContents()
      -- The count as of this read, not `before`, since that is the state a restore now has
      -- to still find unchanged (or echoed) to be safe, exactly as writeCount is for a paste.
      local copiedCount = hs.pasteboard.changeCount()
      restore(copiedCount, contentSig("text", text, nil))
      cb(text)
    elseif waited < copyTimeout then
      waited = waited + copyStep
      after(copyStep, check)
    else
      -- The pasteboard never moved, so either nothing was selected or the app never acted on
      -- our Cmd+C. Those look identical from here and only the second is a bug, so log what
      -- would tell them apart, which app was asked and what the user was holding at the time.
      local front = hs.application.frontmostApplication()
      log.i(string.format(
        "selection read timed out after %.2fs, app=%s, modifiers held=%s",
        copyTimeout,
        (front and front:bundleID()) or "unknown",
        (next(held) and table.concat(held, "+")) or "none"
      ))
      restore(before, nil)
      cb(nil)
    end
  end

  after(copyDelay, function()
    held = stroke({ "cmd" }, "c")
    after(copyStep, check)
  end)
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
-- never to change what one does. ownPasteCount above is what tells a real user press apart from
-- the walk's own synthetic one, which this same tap would otherwise see and wrongly end the walk
-- it belongs to.
local function watchPaste(event)
  if ownPasteCount == 0 and isPlainCmdV(event) and onUserPaste then
    onUserPaste()
  end
  return false
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

--- M.start() - begin polling and watching for a plain Cmd+V. Ignores whatever is already on the
--- pasteboard. The tap is created fresh on every call rather than trusted to survive from before,
--- since hs.reload tears down the whole Lua state and any tap from an earlier load goes with it,
--- so this is the only place one is ever made.
function M.start()
  lastChange = hs.pasteboard.changeCount()
  timer = hs.timer.doEvery(pollInterval, poll)

  if pasteTap then
    pasteTap:stop()
  end
  pasteTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, watchPaste)
  pasteTap:start()

  return M
end

--- M.configure(opts) injects the reader chain, store, util, timing, and the optional
--- onCapture and onUserPaste observers, onCapture called with the stored entry after every
--- genuine copy and onUserPaste called with no argument after every plain Cmd+V that was not
--- one of this module's own. opts.resolveFilePaths is the optional transform writtenFilePaths
--- applies to the { content, name } items it is about to turn into paths for the pasteboard,
--- absent by default, so nothing about a file paste changes unless a caller wires one in.
function M.configure(opts)
  readers = opts.readers
  store = opts.store
  util = opts.util
  skipTypes = opts.skipTypes
  onCapture = opts.onCapture
  onUserPaste = opts.onUserPaste
  resolveFilePaths = opts.resolveFilePaths
  pollInterval = opts.pollInterval or pollInterval
  pasteDelay = opts.pasteDelay or pasteDelay
  return M
end

return M
