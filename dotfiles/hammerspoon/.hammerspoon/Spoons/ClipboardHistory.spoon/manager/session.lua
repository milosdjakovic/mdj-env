--- The transient session state layered over the persistent history.
---
--- Two behaviours live here, gluing a fresh copy onto the newest entry and stepping through
--- the list one entry per press. Both are session state rather than stored state, both are
--- policy over the store and the monitor rather than new mechanism, and both end on the same
--- signal, a genuine copy. That shared reset is what earns them one file instead of two. A
--- third behaviour would be the point to split them.
---
--- Nothing here is driven by a timer or a watcher, so it needs no start and no stop. Every
--- condition that ends a run is observable at the moment the next key is pressed, so it is
--- checked then rather than driven by a clock. The one timer it does own drives nothing, it
--- only releases a claim whose release never arrived, so a lost callback cannot leave both
--- behaviours dead for the rest of the session. The one thing it cannot see for itself is
--- whether a pasteboard change was a real copy or one of our own pastes, because a paste
--- refreshes an entry's recency and so leaves it looking brand new. The monitor still has
--- that distinction at capture time and publishes it through onCapture, which this module
--- records and both behaviours lean on.

local M = {}

--- M.log - this module's logger, exposed so the mechanism's log level can be raised from one
--- place. Both behaviours are a burst of presses against a pasteboard that only one app at a
--- time can see, so when one goes wrong the only way to tell what happened is a timeline. Every
--- trace line below is debug level, silent by default.
local log = hs.logger.new("ClipboardSess", "info")
M.log = log

-- Seconds inside a hundred second window, enough to line a trace line up against the paste
-- side's lines to the millisecond, which the logger's own timestamp cannot show.
local function clock()
  return hs.timer.secondsSinceEpoch() % 100
end

local store = nil
local monitor = nil
local readers = nil
local util = nil
local onEntryChanged = nil -- optional, told when an entry's content was rewritten in place
local onMessage = nil -- optional, shows a short message to the user
local separator = "\n"
local idleReset = 10
-- How long the pasteboard is left alone after a step, before the next queued press writes it or
-- the clipboard is put back. This is the one number that decides whether a burst pastes
-- everything, and it is not about our own speed. The gap between our Cmd+V and the next write is
-- all the time the receiving app has to read what we pasted, and an app slow to service a paste
-- reads whatever replaced it, so it pastes the wrong entry or nothing at all. Draining a queued
-- press the instant a paste settled is what made a fast burst deliver only some of it.
local drainDelay = 0.25

--------------------------------------------------------------------------------
-- Feedback
--------------------------------------------------------------------------------

-- Both actions change state the user cannot otherwise see, an entry growing offscreen or a
-- position in a walk, so the message is not decoration, it is the only feedback there is.
--
-- How it is shown is not decided here. This module says what happened and the composition root
-- owns the surface, which is what keeps the feedback on the shared overlay and on the display
-- the overlay policy picked, rather than on an hs.alert that knows nothing about either. Left
-- unwired both actions still work, silently.
local function notify(text)
  if onMessage then
    onMessage(text)
  end
end

local function frontmostID()
  local front = hs.application.frontmostApplication()
  return front and front:bundleID() or nil
end

-- True while a step of a walk has a paste that has not settled yet. Two overlapping pastes would
-- have the first one's restore land on top of the second one's content and paste the wrong thing,
-- so a press inside that window never starts a paste of its own.
--
-- It is remembered rather than dropped. A paste takes about a quarter of a second to settle and
-- tapping the key faster than that is ordinary, so dropping the press is what makes a fast burst
-- look like it pasted only some of what was asked for. Queued presses run in order as each paste
-- settles, capped, since past a handful the user has stopped meaning it.
--
-- Both sit up here rather than with the rest of the walk state below because the append reads them
-- too, and a local declared further down would not be in scope for it.
--
-- The claim is also released by a failsafe, because it gates both behaviours and a release that
-- never arrives would leave the whole feature dead until the config is reloaded, with no way for
-- the user to tell why. A settle is a chain of timers in another module and an error anywhere
-- along it swallows the release, so the claim carries its own expiry rather than trusting that
-- chain. It fires far later than any real settle, so it is only ever seen when something broke,
-- and it says so in the log.
local walking = false
local pendingSteps = 0
local maxPending = 8
local walkTimeout = 2.0
local watchdog = nil

--------------------------------------------------------------------------------
-- Append
--------------------------------------------------------------------------------

-- The entry the last genuine copy produced, and how many pieces have been glued onto it.
-- The target is held by reference and only ever used by comparing it against the head of
-- the live list, never by index, so a list that shifted underneath cannot make an append
-- land on the wrong row.
local target = nil
local pieces = 1

-- Whether the accumulator may grow the head of the list. Three things must hold. There has
-- to be a remembered target, it has to still be the head, and it has to carry text.
--
-- The head test is the one that matters. It keeps an append off an entry that reached the
-- top by being pasted out of the picker, which would silently rewrite a saved snippet the
-- user never meant to touch. An age test cannot stand in for it, because floating an entry
-- to the front refreshes its recency, so a decade old snippet pasted a second ago is
-- indistinguishable from a fresh copy by time alone. Only the capture side knows, which is
-- why the target comes from there.
local function appendable()
  local head = store.all()[1]
  return target ~= nil and head ~= nil and head == target
    and (head.kind == "text" or head.kind == "url")
end

-- Start a new accumulation from a string, which is exactly what a plain copy of that string
-- would have produced, plus the clipboard write. The frontmost app is stamped as the source
-- so the row icon reads the same as any other copy made from there. Returns the stored entry,
-- or nil when the store refused it.
local function startNew(text)
  local entry = readers.textEntry(util, text)
  entry.sourceApp = frontmostID()
  local stored = store.add(entry)
  if not stored then
    return nil
  end
  target = stored
  pieces = 1
  monitor.writeClipboard(stored)
  return stored
end

-- Grow the current target by one piece, relabelling it the way a fresh copy of the same
-- text would be labelled. Returns the new piece count, or nil when the target turned out
-- not to be in the list after all, so the caller can fall back to starting a new entry
-- rather than dropping the copy.
local function grow(text)
  local grown = readers.textEntry(util, (target.text or "") .. separator .. text)
  local h = store.replaceText(target, grown)
  if not h then
    return nil
  end
  target = h
  pieces = pieces + 1
  monitor.writeClipboard(h)
  -- An entry changing content after capture is unusual enough that consumers cache against
  -- it, so say so rather than leaving a stale row or a stale search index behind.
  if onEntryChanged then
    onEntryChanged(h)
  end
  return pieces
end

--- M.appendCopy() - read the selection and glue it onto the newest entry.
---
--- When the head of the list is text that arrived by a real copy, the selection is joined
--- onto it with the separator, the entry is relabelled, and the whole accumulation goes onto
--- the clipboard, so a plain paste keeps delivering everything gathered so far and no extra
--- key is needed to use the result. History gains no row.
---
--- Otherwise this behaves exactly like a plain copy and starts a new row, which is the case
--- on a fresh session, when the head is an image or a file, and after an entry was pasted out
--- of the picker. So the first press always does something sensible and only the presses
--- after it accumulate. A plain copy is what ends an accumulation, which is why there is no
--- key for that either.
function M.appendCopy()
  -- A read already in flight means a held key outran the previous press. Stay silent rather
  -- than reporting an empty selection, since a refused read is not an empty one. A step of a
  -- walk still settling holds the pasteboard just as firmly, so it blocks a read too, and the
  -- two actions never interleave over the same pasteboard.
  log.df("%.3f append press, reading=%s walking=%s", clock(), tostring(monitor.isReading()), tostring(walking))
  if monitor.isReading() or walking then
    return
  end

  local function accept(text)
    log.df("%.3f append read %s", clock(), (text and string.format("%q", text:sub(1, 40))) or "nothing")
    if not text or #(text:gsub("%s", "")) == 0 then
      notify("Nothing selected")
      return
    end

    if appendable() and grow(text) then
      notify(string.format("Appended, %d pieces", pieces))
    elseif startNew(text) then
      notify("Append started")
    end

    -- This was a copy, so it ends any walk in progress for the same reason a plain copy does.
    M.resetSequence()
  end

  -- The selection can usually be read straight off the focused element, which is instant and needs
  -- no keystroke, so a held chord cannot interfere with it and there is no beat to wait out. The
  -- Cmd+C behind copySelection works in anything, including a field with no accessibility at all,
  -- so it stays as the fallback. Same pair, same reasoning, as the walk's two ways in.
  local direct = monitor.readSelection()
  if direct then
    accept(direct)
  else
    monitor.copySelection(accept)
  end
end

--- M.isAccumulator(entry) -> bool, count
--- Whether this entry is the live accumulator and how many pieces it holds, asked by the ui
--- per row so a growing entry reads as one in the list. It is gated on the same appendable
--- test the append itself uses, so the row never advertises an accumulation the next press
--- would not actually continue. A single piece is not an accumulation, so a plain copy is
--- left unmarked.
function M.isAccumulator(entry)
  if pieces < 2 or entry ~= target or not appendable() then
    return false
  end
  return true, pieces
end

--------------------------------------------------------------------------------
-- Sequence
--------------------------------------------------------------------------------

-- A walk is a snapshot of the list, a position in it, the app it belongs to, the clipboard it
-- began with, and when it was last advanced. The list is snapshotted rather than read live so a
-- position keeps meaning the same thing for the whole walk, which is what makes the count shown
-- to the user honest. The clipboard is snapshotted once for the same reason it is restored at
-- all, so that after any number of steps a plain paste still means the newest entry, and taking
-- it per step would capture the previous step's own content instead.
local run = nil

-- Whether the walk in progress still applies. It does not once the frontmost app has
-- changed, since a walk belongs to the form being filled, and not once the gap since the
-- last press has grown past the idle window, since a walk is a burst and a long pause means
-- the next press is a fresh intent. Both are read here, at the press, rather than watched,
-- which is why this module carries no watcher and no timer.
local function runStillApplies()
  if not run then
    return false
  end
  local front = frontmostID()
  if run.app ~= front then
    log.df("walk ends, app changed from %s to %s", tostring(run.app), tostring(front))
    return false
  end
  local gap = hs.timer.secondsSinceEpoch() - run.at
  if gap > idleReset then
    log.df("walk ends, idle %.2fs past the %.1fs window", gap, idleReset)
    return false
  end
  return true
end

--- M.resetSequence() - end any walk in progress, so the next press starts from the top again.
--- Queued presses belong to the walk that is ending, so they go with it.
function M.resetSequence()
  if run then
    log.df("%.3f walk reset at %d of %d, %d queued dropped", clock(), run.index, #run.list, pendingSteps)
  end
  run = nil
  pendingSteps = 0
end

-- Release the walk and spend one queued press if there is one, which is what makes a burst of taps
-- paste in order instead of only as often as a paste settles. The press is spent a beat later
-- rather than at once, so the app we just pasted into keeps the pasteboard to itself for as long
-- as it would have between two hand timed presses.
local function releaseWalk()
  if watchdog then
    watchdog:stop()
    watchdog = nil
  end
  walking = false
  log.df("%.3f settled, %d queued", clock(), pendingSteps)
  if pendingSteps > 0 then
    pendingSteps = pendingSteps - 1
    hs.timer.doAfter(drainDelay, function()
      M.pasteNext()
    end)
  end
end

--- M.pasteNext() - paste the next entry in the walk, starting a walk when none is in
--- progress. The first press pastes the newest entry, so it does exactly what a plain paste
--- does, and only the presses after it advance. That keeps the whole cursor owned by one key,
--- with nothing to know about what the plain paste key did.
---
--- The walk reorders nothing and leaves the clipboard as it found it, so it can read the list
--- without rewriting the order it is reading, and a plain paste keeps meaning the newest
--- entry however far the walk has gone. At the end of the list it stops rather than wrapping,
--- since wrapping would quietly paste the wrong thing.
function M.pasteNext()
  log.df(
    "%.3f press, walking=%s queued=%d at=%s app=%s",
    clock(),
    tostring(walking),
    pendingSteps,
    (run and tostring(run.index)) or "no walk",
    tostring(frontmostID())
  )

  if walking then
    if pendingSteps < maxPending then
      pendingSteps = pendingSteps + 1
    end
    return
  end

  if runStillApplies() then
    if run.index >= #run.list then
      notify("End of history")
      run.at = hs.timer.secondsSinceEpoch()
      -- No paste follows, so no settle is coming to spend them, and left here they would be
      -- spent by the first settle of some later walk and paste entries nobody asked for.
      pendingSteps = 0
      return
    end
    run.index = run.index + 1
  else
    local live = store.all()
    if #live == 0 then
      notify("History is empty")
      return
    end
    -- Copy the list rather than holding the store's own table, which is mutated in place.
    local list = {}
    for i = 1, #live do
      list[i] = live[i]
    end
    run = {
      list = list,
      index = 1,
      app = frontmostID(),
      clipboard = monitor.snapshotClipboard(),
    }
    -- A queue only ever belongs to the walk it was pressed during, and a walk that ended while
    -- one was outstanding leaves it behind, so a fresh walk starts from nothing owed.
    pendingSteps = 0
    log.df("%.3f walk starts over %d entries in %s", clock(), #list, tostring(run.app))
  end

  run.at = hs.timer.secondsSinceEpoch()
  local total = #run.list
  local entry = run.list[run.index]
  log.df(
    "%.3f step %d of %d, kind=%s, %s",
    clock(),
    run.index,
    total,
    tostring(entry and entry.kind),
    string.format("%q", tostring(entry and (entry.title or entry.text)):sub(1, 40))
  )

  -- Text goes straight into the focused field when the field takes it, which lands in the instant
  -- the key was pressed. Nothing reached the pasteboard, so there is nothing to serialise on,
  -- nothing to put back, and no beat to wait out, and the next tap can follow immediately however
  -- fast it comes. That is the whole difference between a walk that feels like a key and a walk
  -- that feels like a machine, and it is also the only way past an app that ignores a synthetic
  -- Cmd+V while the chord that asked for it is still physically held, which some do.
  --
  -- Everything else, an image, a file, or a field that will not take text this way, goes through
  -- the pasteboard below and pays for it, because there is no other way in for those.
  if (entry.kind == "text" or entry.kind == "url") and monitor.insertText(entry.text) then
    notify(string.format("%d of %d", run.index, total))
    return
  end

  -- Claimed before the call, not from its return value, so the guard holds however the settle
  -- is delivered. Reading it back from the return would leave it stuck on for good if the
  -- callback ever ran before the call returned.
  walking = true
  if watchdog then
    watchdog:stop()
  end
  watchdog = hs.timer.doAfter(walkTimeout, function()
    watchdog = nil
    log.wf("no settle within %.1fs, releasing the walk so the keys keep working", walkTimeout)
    releaseWalk()
  end)
  local started = monitor.paste(entry, {
    reorder = false,
    restoreTo = run.clipboard,
    -- The same gap the next step would have left, so the last entry of a burst gets the reading
    -- window every entry before it got, rather than losing the pasteboard the moment the run ends.
    -- A hair longer than the gap, because a queued step is scheduled for exactly that moment and
    -- has to win the tie. It cancels the restore when it does, which is what leaves a burst with
    -- one restore at the end instead of a pointless one between every pair of entries.
    restoreWhenQuiet = drainDelay + 0.05,
    onSettled = releaseWalk,
  })

  if started then
    notify(string.format("%d of %d", run.index, total))
  else
    -- Nothing was written, so no settle is coming and the claim has to be released here. The
    -- position still advanced, so say what happened rather than looking like a silent no op.
    -- Only a vanished image or file reaches this, and releasing here rather than just clearing
    -- the flag means a queued press still steps past it instead of stalling on it.
    notify(string.format("%d of %d, nothing to paste", run.index, total))
    releaseWalk()
  end
end

--------------------------------------------------------------------------------
-- Capture
--------------------------------------------------------------------------------

--- M.noteCapture(entry) - the monitor's onCapture observer, called with the stored entry
--- after every genuine copy. That copy becomes the append target and ends any accumulation
--- on the previous one, which is how a plain copy starts a fresh accumulation with no key of
--- its own. It also ends a walk, since copying something new means the run being pasted is no
--- longer the run wanted.
function M.noteCapture(entry)
  -- Logged because this is the one reset a walk cannot see coming, and a paste of ours mistaken
  -- for a copy would show up here, mid walk, immediately before the walk ends for no visible
  -- reason. That is the difference between a guard that is working and one that is not.
  log.df("%.3f capture noted, kind=%s", clock(), tostring(entry and entry.kind))
  target = entry
  pieces = 1
  M.resetSequence()
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

--- M.configure(opts) - inject the store, the monitor, the readers, util, the optional
--- onEntryChanged and onMessage observers, the separator appended pieces are joined with, the
--- idle window that ends a walk, and how long each step of a walk leaves the pasteboard alone.
function M.configure(opts)
  store = opts.store
  monitor = opts.monitor
  readers = opts.readers
  util = opts.util
  onEntryChanged = opts.onEntryChanged
  onMessage = opts.onMessage
  separator = opts.appendSeparator or separator
  idleReset = opts.sequenceIdleReset or idleReset
  drainDelay = opts.sequenceDrainDelay or drainDelay
  return M
end

return M
