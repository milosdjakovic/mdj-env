--- === Canvas field input ===
---
--- The event tap, the side effecting shell around model.lua and keymap.lua and the only
--- file under field/ that touches hs.eventtap. It reads a key down, resolves it through
--- the keymap, applies the named operation to the model, and hands anything neither one
--- claims to the consumer that owns this field. This file is not provable offline the
--- way model.lua is, driving a real hs.eventtap needs a real Hammerspoon, so the offline
--- unit case at test/cases/canvasfield.lua exercises model.lua directly and the probe at
--- Spoons/Olm.spoon/test/probe-canvasfield.lua is what exercises this file, on screen,
--- under a hand.
---
--- A surface drawn on hs.canvas never takes keyboard focus, hs.canvas offers mouse
--- tracking and nothing else, so the frontmost app keeps receiving every key macOS
--- delivers unless something else claims it first. That is decision six of the brief,
--- while the field is up this tap claims every key down it sees, printable or not, named
--- by the keymap or not, so nothing ever reaches the covered app while a hand believes it
--- is typing into this field instead. Escape is answered before the keymap is even
--- asked, since the way out of a field must not depend on any table below being wired
--- correctly, and it is the one key this file never hands onward.
---
--- There is one exception to claiming everything, and it is Hyper. Its dispatch sits
--- downstream of this tap, so a claimed Hyper press never reaches the bindings a list
--- declares, and confirm, move and the action panel would be dead while a picker is up. The
--- owner injects opts.yields, a predicate over the event, and a key down it answers true
--- for is passed on untouched. This file knows only that predicate, never what Hyper is.
---
--- One more owner seam sits beside it, opts.listKeys, asked next. It answers true for a key
--- down the open list binds for itself with no held leader, a chord such as Ctrl and J, and has
--- already run it, so this file claims the key and does nothing else with it. Phase B of the list
--- keys addendum to the keymap plan put it here, since this tap already sees every key down while
--- the field is up and nothing global has to claim the chord.
---
--- The tap starts on start and is torn down completely on stop, never left armed a
--- moment longer than the field is meant to be up. 1ccab6f is the record of what a
--- leader believed held rather than checked costs on this machine, a stuck engine
--- swallowing keys nobody meant to lose, and a field that claims every key down while it
--- runs is the same hazard with a wider reach, so this file leaves nothing running once
--- stop has been called.
---
--- Applying an operation runs inside a pcall, so a mistake here reports itself and
--- leaves the buffer exactly as it was rather than abandoning the key press halfway with
--- the field in some state nothing chose. Nothing model.lua exports should ever raise,
--- it is written to answer rather than to fail, so a pcall firing here is itself a
--- finding worth the print line it leaves behind.

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("Canvas field input: failed to load " .. name .. ", " .. tostring(err))
  end
  return chunk()
end

local model = load("model.lua")
local keymap = load("keymap.lua")

local ESCAPE_KEYCODE = 53

-- A private use character in the range NSEvent hands back for arrows, function keys,
-- and the like when asked for getCharacters on a key the keymap above does not already
-- name by its own keycode. Excluding this range, and the plain ascii control range
-- below it, is what keeps an unclaimed arrow or an unclaimed function key from being
-- typed into the buffer as a stray character instead of reaching the consumer's onKey
-- the way decision six asks for.
local FUNCTION_KEY_LOW, FUNCTION_KEY_HIGH = 0xF700, 0xF8FF

local function isPrintable(str)
  if not str or str == "" then return false end
  local ok, cp = pcall(utf8.codepoint, str, 1)
  if not ok or not cp then return false end
  if cp < 0x20 or cp == 0x7F then return false end
  if cp >= FUNCTION_KEY_LOW and cp <= FUNCTION_KEY_HIGH then return false end
  return true
end

local Field = {}
Field.__index = Field

--- Field.new(opts) answers a new instance. opts.text seeds the buffer, caret left after it, the
--- same convention model.newState already follows. opts.onChange(state) runs after
--- every applied key, printable or named, so the owner can redraw and reset its own
--- caret blink to visible on each keystroke, decision four leaves that timer to the
--- owner rather than holding one here. opts.onKey(event) runs for a key down neither the
--- keymap nor the printable check claims, and its answer is ignored, the key is claimed
--- either way per decision six, a consumer answering nothing simply swallows it.
--- opts.onDismiss(event) runs for each escape key down, its autorepeat included, which this
--- file always claims and never hands to onKey instead. opts.yields(event) answers true for a key down that belongs to
--- something downstream of this tap and must pass on unclaimed, which is how Hyper stays
--- alive while the field is up. It is asked after escape and before the keymap, and an
--- error in it is reported and counted as false.
---
--- opts.onEmptyBackspace() runs once when a resolved backward delete reaches this file
--- while the buffer is empty and nothing is selected, added for section one of the
--- canvas picker provider brief, so a provider can pop a level the way config.back
--- already does on the native side. This could not be answered through opts.onKey,
--- since the keymap claims backspace unconditionally as deleteBackward before onKey is
--- ever asked anything at all, so an empty buffer's own backspace press never reaches
--- onKey regardless of what the buffer holds. The one place that still knows both facts
--- together, that the resolved operation is deleteBackward and that the buffer is empty
--- with nothing selected, is the function below that resolves a key and applies it, in
--- the gap between those two steps, which is why this callback answers there rather
--- than through a plain onKey case.
function Field.new(opts)
  opts = opts or {}
  local self = setmetatable({
    state = model.newState(opts.text),
    onChange = opts.onChange,
    onKey = opts.onKey,
    onDismiss = opts.onDismiss,
    yields = opts.yields,
    listKeys = opts.listKeys,
    onEmptyBackspace = opts.onEmptyBackspace,
    tap = nil,
    _retiredTap = nil,
  }, Field)
  return self
end

--- getState answers the current model state, for a renderer to read.
function Field:getState()
  return self.state
end

--- setText replaces the whole buffer, caret left after it and nothing
--- selected, the same seeding rule new() itself follows. Answers self so a caller can
--- chain it straight into show, matching the spoons in this tree that answer self too.
function Field:setText(text)
  self.state = model.newState(text)
  self:_notify()
  return self
end

function Field:_notify()
  if self.onChange then self.onChange(self.state) end
end

-- Copy, cut and paste are not model operations, they are the one place this field
-- reaches hs.pasteboard, so the pasteboard read or write happens here and only the
-- resulting text, or the plain fact of a cut, is handed onward to model.apply. Every
-- other name, a typed character, movement, deletion, undo and redo among them, goes
-- straight to model.apply exactly as it arrived. apply is what decides whether an
-- edit joins the run already open or answers a run of its own, which is why nothing
-- here reaches model.ops directly any more, doing so would bypass that history
-- entirely and leave undo with nothing to walk back through.
local function applyNamed(state, opName, arg)
  if opName == "copy" then
    local text = model.selectedText(state)
    if text ~= "" then hs.pasteboard.setContents(text) end
    return state
  end
  if opName == "cut" then
    local text = model.selectedText(state)
    if text == "" then return state end
    hs.pasteboard.setContents(text)
    return model.apply(state, "cut")
  end
  if opName == "paste" then
    return model.apply(state, "paste", hs.pasteboard.getContents() or "")
  end
  return model.apply(state, opName, arg)
end

-- Applies one named operation and reports rather than raising, decision seven's own
-- words, leaving the buffer exactly as it was on a failure rather than abandoning the
-- key press with the state half changed. onChange only runs once the new state has
-- actually been produced, so a caller redraws the truth rather than a guess at it.
function Field:_apply(opName, arg)
  local ok, result = pcall(applyNamed, self.state, opName, arg)
  if not ok then
    print("Olm canvas field, " .. tostring(opName) .. " failed and the buffer was left as it was, " .. tostring(result))
    return
  end
  self.state = result
  self:_notify()
end

-- Asks the injected predicate whether this key down belongs downstream. A mistake in it
-- reports itself and counts as no, so a broken predicate falls back to claiming the key,
-- which is the behaviour this field had before the predicate existed.
function Field:_yields(ev)
  if not self.yields then return false end
  local ok, answer = pcall(self.yields, ev)
  if not ok then
    print("Olm canvas field, yields failed and the key was claimed, " .. tostring(answer))
    return false
  end
  return answer == true
end

-- The tap callback itself. Every path through this function answers true, claiming the
-- key down, which is decision six stated as code rather than as prose, nothing this
-- field is up for is allowed to reach the app underneath it. The one exception is a key
-- the injected yields predicate gives away, which answers false so it passes on.
function Field:_handle(ev)
  local code = ev:getKeyCode()

  if code == ESCAPE_KEYCODE then
    -- The event goes along so an owner can tell a held Escape's autorepeat from a fresh press.
    if self.onDismiss then self.onDismiss(ev) end
    return true
  end

  if self:_yields(ev) then return false end

  if self.listKeys then
    local ok, took = pcall(self.listKeys, ev)
    if not ok then
      print("Olm canvas field, listKeys failed and the key went on to the field, " .. tostring(took))
    elseif took == true then
      return true
    end
  end

  local flags = ev:getFlags()
  local opName = keymap.resolve(code, flags)
  if opName then
    -- Section one of the canvas picker provider brief. An empty buffer's own backward
    -- delete is a press a provider needs to see for itself, popping a level being
    -- config.back's own job rather than an edit on this buffer, so this checks for
    -- exactly that case before the operation is ever applied, and only when a
    -- consumer actually asked for the callback. Every other path through this
    -- function, a non empty buffer among them, is untouched.
    if opName == "deleteBackward" and self.onEmptyBackspace then
      local lo = model.selectionBounds(self.state)
      if self.state.text == "" and not lo then
        self.onEmptyBackspace()
        return true
      end
    end
    self:_apply(opName)
    return true
  end

  if not flags.cmd and not flags.ctrl and not flags.fn then
    local chars = ev:getCharacters()
    if isPrintable(chars) then
      self:_apply("insertText", chars)
      return true
    end
  end

  if self.onKey then
    local ok, err = pcall(self.onKey, ev)
    if not ok then
      print("Olm canvas field, onKey failed, " .. tostring(err))
    end
  end
  return true
end

--- start arms the tap. Idempotent, calling it again while already armed does
--- nothing, so an owner does not have to track whether it already called this once.
function Field:start()
  if self.tap then return end
  self._retiredTap = nil
  self.tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(ev)
    return self:_handle(ev)
  end)
  self.tap:start()
end

--- stop tears the tap down completely, the tap object itself dropped rather
--- than merely stopped, so nothing armed is left behind for start to find and skip past.
---
--- Fix round item eight, insurance rather than a known failure. escape reaches this
--- from inside the tap's own callback, on the same Lua stack that callback is still
--- running on, and the line below used to drop the last reference to that userdata,
--- self.tap, in that same moment. Lua will not collect it synchronously mid callback,
--- so nothing here is known to break, but if it ever did the finalizer would disable
--- and release a tap while its own callback was still on the stack, and Commit 1ccab6f
--- already carries what a tap left believed torn down costs on this machine. Holding
--- the retired userdata in self._retiredTap keeps a reference alive past the callback
--- that dropped it, cleared on the next start so nothing accumulates across opens, and
--- isRunning still answers exactly what it answered before, self.tap alone, since that
--- is the field a fresh start replaces.
function Field:stop()
  if self.tap then
    self.tap:stop()
    self._retiredTap = self.tap
    self.tap = nil
  end
end

--- isRunning answers whether the tap is currently armed, for a watchdog to check
--- before deciding it has anything left to tear down.
function Field:isRunning()
  return self.tap ~= nil
end

local M = { Field = Field, model = model, keymap = keymap }
return M
