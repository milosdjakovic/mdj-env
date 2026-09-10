--- === Canvas field model ===
---
--- The pure core of the canvas text field, phase two of docs/PLAN-CANVAS-CHOOSER.md and
--- built from docs/BRIEF-CANVAS-FIELD.md. A buffer, a caret, a selection anchor, and one
--- function per editing operation, each taking a state and answering the next state
--- rather than mutating the one it was given. Nothing here touches hs, a timer, or a
--- canvas, and nothing here raises, which is what lets this file be driven by loadfile
--- with no screen and no Hammerspoon behind it, exactly the way test/cases/canvasfield.lua
--- drives it.
---
--- State is a plain table, text, caret, anchor. anchor is nil when nothing is selected.
--- caret and anchor are counted in characters rather than bytes, since a buffer holding
--- one accented character is not a hypothetical and a byte caret would split it in two.
--- Every operation clamps whatever it is handed rather than refusing it, since the shell
--- around this file can pass along a caret or an anchor that drifted out of range and
--- this file would rather answer something sane than stop the field working.
---
--- The editing set is the one macOS honours in every text field, insert, delete backward
--- and forward, delete by word in both directions, delete to the start of the line, move
--- by character, by word, and to either end, the same six moves again extending a
--- selection, and select all. Copy, cut and paste read and write hs.pasteboard, the one
--- place this file may not answer alone, so the shell around this file owns the
--- pasteboard call and hands the resulting text to insertText or reads it back through
--- selectedText, the model only ever seeing plain strings.
---
--- Undo and redo, added once a hand test found the field working but the pair missing,
--- also live here rather than in the shell, through one further function, apply, that
--- wraps every operation above with the history the two of them walk. A state built by
--- apply also carries undoStack, redoStack and openGroup alongside text, caret and
--- anchor, a bounded run of prior snapshots, the same run held the other way once
--- something has been undone, and the name of whichever run of edits is still open to
--- being joined by the next one. Every rule for when a run joins, when it closes, and
--- when redo is thrown away lives beside apply itself, further down this file.

local M = {}

--------------------------------------------------------------------------------
-- Character and byte bookkeeping
--------------------------------------------------------------------------------

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- utf8.len answers nil on data that is not valid utf8, an ordinary possibility for
-- whatever a paste or a synthesized event hands this field rather than a fault, so the
-- byte length stands in rather than this file raising over it.
local function charCount(text)
  return utf8.len(text) or #text
end

-- The byte position that sits right after the given number of characters, so a
-- substring up to that position minus one holds exactly that many characters. Character
-- zero sits at byte one, the very start of the string, and asking for the character
-- count itself or anything past it clamps to one past the string's own byte length
-- rather than asking utf8.offset for a character that is not there.
local function byteOffsetForChar(text, charIdx)
  if charIdx <= 0 then return 1 end
  local n = charCount(text)
  if charIdx >= n then return #text + 1 end
  return utf8.offset(text, charIdx + 1) or (#text + 1)
end

-- The first charIdx characters of text, clamped to whatever the string actually holds.
local function textUpTo(text, charIdx)
  charIdx = clamp(charIdx, 0, charCount(text))
  return text:sub(1, byteOffsetForChar(text, charIdx) - 1)
end

-- The characters from loChar up to but not including hiChar, in whichever order the
-- caller hands them, since a selection can run either direction from its anchor.
local function textRange(text, loChar, hiChar)
  local n = charCount(text)
  loChar = clamp(loChar, 0, n)
  hiChar = clamp(hiChar, 0, n)
  if hiChar < loChar then loChar, hiChar = hiChar, loChar end
  local a = byteOffsetForChar(text, loChar)
  local b = byteOffsetForChar(text, hiChar)
  return text:sub(a, b - 1)
end

-- The character sitting at the one based position idx, or nil past either end. Used
-- only by the word boundary search below, one character at a time.
local function charAt(text, idx)
  local n = charCount(text)
  if idx < 1 or idx > n then return nil end
  local a = utf8.offset(text, idx)
  local b = utf8.offset(text, idx + 1) or (#text + 1)
  return text:sub(a, b - 1)
end

--------------------------------------------------------------------------------
-- Word boundaries, decision three of the brief
--------------------------------------------------------------------------------

-- A word is a maximal run of characters that are not whitespace and not punctuation. A
-- character outside the plain ascii range matches neither Lua pattern class and is
-- always treated as part of a word, which is the right default for a name written in
-- another alphabet. Moving by word crosses any separators sitting against the caret
-- first, then crosses the word run on the far side of them, landing past it rather than
-- stopping on the boundary itself. This is what makes deleting back through a path or a
-- snippet take the whole segment rather than stopping one separator early, and it is
-- also why a run of spaces between two words counts as nothing of its own, only as the
-- gap a move by word steps across on the way to the next real word.
local function isSeparator(ch)
  return ch:match("%s") ~= nil or ch:match("%p") ~= nil
end

local function wordBoundaryForward(text, idx)
  local n = charCount(text)
  local i = idx
  while i < n and isSeparator(charAt(text, i + 1)) do i = i + 1 end
  while i < n and not isSeparator(charAt(text, i + 1)) do i = i + 1 end
  return i
end

local function wordBoundaryBackward(text, idx)
  local i = idx
  while i > 0 and isSeparator(charAt(text, i)) do i = i - 1 end
  while i > 0 and not isSeparator(charAt(text, i)) do i = i - 1 end
  return i
end

--------------------------------------------------------------------------------
-- State construction and the total, never raising normalize every operation opens with
--------------------------------------------------------------------------------

-- undoStack and redoStack default to an empty run and openGroup to nothing open, so a
-- state built by any of the plain operations below, which never pass these four along,
-- still answers a table apply can read safely. Those operations answering an empty run
-- rather than the real one costs nothing, since apply always rebuilds the final state
-- from the real run it already holds beside the text, caret and anchor an operation
-- answered, and never reads these four back off an operation's own return value.
local function newRawState(text, caret, anchor, undoStack, redoStack, openGroup)
  return {
    text = text, caret = caret, anchor = anchor,
    undoStack = undoStack or {}, redoStack = redoStack or {}, openGroup = openGroup,
  }
end

-- Every operation below opens by asking for this, so a state built by hand, seeded from
-- outside, or drifted by a caller between calls always arrives clamped to something the
-- rest of the function can trust, rather than each operation guarding its own arithmetic
-- a second time. A state with no history fields at all, which is every state this file
-- answered before undo and redo existed, normalizes to an empty run and nothing open,
-- so the older shape still reads cleanly here.
local function normalizeState(rawState)
  local text = (rawState and rawState.text) or ""
  local n = charCount(text)
  local caret = clamp((rawState and rawState.caret) or n, 0, n)
  local anchor = rawState and rawState.anchor
  if anchor ~= nil then anchor = clamp(anchor, 0, n) end
  local undoStack = (rawState and rawState.undoStack) or {}
  local redoStack = (rawState and rawState.redoStack) or {}
  local openGroup = rawState and rawState.openGroup
  return newRawState(text, caret, anchor, undoStack, redoStack, openGroup)
end

-- An anchor equal to the caret is kept rather than cleared, since a hand that shift
-- selects out and back to the same spot expects the far end still remembered for the
-- next extend, so this is the only place that decides whether a stored anchor currently
-- reads as a visible selection.
local function hasSelection(ns)
  return ns.anchor ~= nil and ns.anchor ~= ns.caret
end

--------------------------------------------------------------------------------
-- The editing operations, one function per name, each state to state
--------------------------------------------------------------------------------

local ops = {}

-- Replaces the selection when there is one, otherwise inserts at the caret. This one
-- function serves both a single typed character from the keymap and a whole pasted
-- string from the shell, so paste is nothing more than this with the pasteboard's text
-- as the argument.
ops.insertText = function(rawState, str)
  str = str or ""
  local ns = normalizeState(rawState)
  local lo, hi = ns.caret, ns.caret
  if hasSelection(ns) then
    lo, hi = math.min(ns.caret, ns.anchor), math.max(ns.caret, ns.anchor)
  end
  local before = textUpTo(ns.text, lo)
  local after = textRange(ns.text, hi, charCount(ns.text))
  return newRawState(before .. str .. after, lo + charCount(str), nil)
end

-- Removes the current selection and answers a state with none, or answers the state
-- unchanged when there was nothing selected. This is its own operation because cut,
-- unlike backward delete, must never fall back to removing a character when nothing is
-- selected, a plain cmd x with the caret merely sitting somewhere does nothing on every
-- text field macOS ships.
ops.deleteSelection = function(rawState)
  local ns = normalizeState(rawState)
  if not hasSelection(ns) then return newRawState(ns.text, ns.caret, nil) end
  local lo, hi = math.min(ns.caret, ns.anchor), math.max(ns.caret, ns.anchor)
  local before = textUpTo(ns.text, lo)
  local after = textRange(ns.text, hi, charCount(ns.text))
  return newRawState(before .. after, lo, nil)
end

ops.deleteBackward = function(rawState)
  local ns = normalizeState(rawState)
  if hasSelection(ns) then return ops.deleteSelection(ns) end
  if ns.caret <= 0 then return newRawState(ns.text, ns.caret, nil) end
  local before = textUpTo(ns.text, ns.caret - 1)
  local after = textRange(ns.text, ns.caret, charCount(ns.text))
  return newRawState(before .. after, ns.caret - 1, nil)
end

ops.deleteForward = function(rawState)
  local ns = normalizeState(rawState)
  if hasSelection(ns) then return ops.deleteSelection(ns) end
  local n = charCount(ns.text)
  if ns.caret >= n then return newRawState(ns.text, ns.caret, nil) end
  local before = textUpTo(ns.text, ns.caret)
  local after = textRange(ns.text, ns.caret + 1, n)
  return newRawState(before .. after, ns.caret, nil)
end

ops.deleteWordBackward = function(rawState)
  local ns = normalizeState(rawState)
  if hasSelection(ns) then return ops.deleteSelection(ns) end
  local newCaret = wordBoundaryBackward(ns.text, ns.caret)
  if newCaret == ns.caret then return newRawState(ns.text, ns.caret, nil) end
  local before = textUpTo(ns.text, newCaret)
  local after = textRange(ns.text, ns.caret, charCount(ns.text))
  return newRawState(before .. after, newCaret, nil)
end

ops.deleteWordForward = function(rawState)
  local ns = normalizeState(rawState)
  if hasSelection(ns) then return ops.deleteSelection(ns) end
  local n = charCount(ns.text)
  local newCaret = wordBoundaryForward(ns.text, ns.caret)
  if newCaret == ns.caret then return newRawState(ns.text, ns.caret, nil) end
  local before = textUpTo(ns.text, ns.caret)
  local after = textRange(ns.text, newCaret, n)
  return newRawState(before .. after, ns.caret, nil)
end

ops.deleteToLineStart = function(rawState)
  local ns = normalizeState(rawState)
  if hasSelection(ns) then return ops.deleteSelection(ns) end
  if ns.caret <= 0 then return newRawState(ns.text, ns.caret, nil) end
  local after = textRange(ns.text, ns.caret, charCount(ns.text))
  return newRawState(after, 0, nil)
end

-- Kill to the end of the line, what ctrl k asks of this field among the emacs bindings
-- decision two of the brief lists. That decision names delete to the start of the line
-- as the one whole line deletion beyond a single character or a single word, and does
-- not separately name a mirror of it, yet ctrl k has nowhere else to land without one,
-- since every other named operation is either the wrong direction or the wrong unit.
-- This function is the one place this file carries an operation the brief's own
-- enumeration does not name, added because the same paragraph also states the goal
-- plainly, the full macOS set rather than a chosen subset, and a bound key with no
-- operation behind it would be exactly the silent gap that paragraph warns against.
-- Reported rather than resolved quietly, since a gap between two sentences of the
-- brief itself is what it asks a builder to surface.
ops.deleteToLineEnd = function(rawState)
  local ns = normalizeState(rawState)
  if hasSelection(ns) then return ops.deleteSelection(ns) end
  local n = charCount(ns.text)
  if ns.caret >= n then return newRawState(ns.text, ns.caret, nil) end
  local before = textUpTo(ns.text, ns.caret)
  return newRawState(before, ns.caret, nil)
end

-- Arrow keys collapse a live selection to whichever edge sits on their own side rather
-- than stepping one further character past the caret that made it, which is what every
-- native macOS field does and what a hand coming from one expects here too.
ops.moveLeft = function(rawState)
  local ns = normalizeState(rawState)
  local newCaret
  if hasSelection(ns) then
    newCaret = math.min(ns.caret, ns.anchor)
  else
    newCaret = math.max(0, ns.caret - 1)
  end
  return newRawState(ns.text, newCaret, nil)
end

ops.moveRight = function(rawState)
  local ns = normalizeState(rawState)
  local n = charCount(ns.text)
  local newCaret
  if hasSelection(ns) then
    newCaret = math.max(ns.caret, ns.anchor)
  else
    newCaret = math.min(n, ns.caret + 1)
  end
  return newRawState(ns.text, newCaret, nil)
end

ops.moveWordLeft = function(rawState)
  local ns = normalizeState(rawState)
  local base = hasSelection(ns) and math.min(ns.caret, ns.anchor) or ns.caret
  return newRawState(ns.text, wordBoundaryBackward(ns.text, base), nil)
end

ops.moveWordRight = function(rawState)
  local ns = normalizeState(rawState)
  local base = hasSelection(ns) and math.max(ns.caret, ns.anchor) or ns.caret
  return newRawState(ns.text, wordBoundaryForward(ns.text, base), nil)
end

ops.moveToStart = function(rawState)
  local ns = normalizeState(rawState)
  return newRawState(ns.text, 0, nil)
end

ops.moveToEnd = function(rawState)
  local ns = normalizeState(rawState)
  return newRawState(ns.text, charCount(ns.text), nil)
end

-- The same six moves again, this time holding the far end in place as an anchor rather
-- than clearing it, so the selection grows or shrinks with the caret. The anchor is
-- whatever was already stored, or the caret's own current position the moment a
-- selection is not already open, which is the one instant a fresh anchor is needed.
ops.moveLeftExtend = function(rawState)
  local ns = normalizeState(rawState)
  local anchor = ns.anchor or ns.caret
  return newRawState(ns.text, math.max(0, ns.caret - 1), anchor)
end

ops.moveRightExtend = function(rawState)
  local ns = normalizeState(rawState)
  local anchor = ns.anchor or ns.caret
  local n = charCount(ns.text)
  return newRawState(ns.text, math.min(n, ns.caret + 1), anchor)
end

ops.moveWordLeftExtend = function(rawState)
  local ns = normalizeState(rawState)
  local anchor = ns.anchor or ns.caret
  return newRawState(ns.text, wordBoundaryBackward(ns.text, ns.caret), anchor)
end

ops.moveWordRightExtend = function(rawState)
  local ns = normalizeState(rawState)
  local anchor = ns.anchor or ns.caret
  return newRawState(ns.text, wordBoundaryForward(ns.text, ns.caret), anchor)
end

ops.moveToStartExtend = function(rawState)
  local ns = normalizeState(rawState)
  local anchor = ns.anchor or ns.caret
  return newRawState(ns.text, 0, anchor)
end

ops.moveToEndExtend = function(rawState)
  local ns = normalizeState(rawState)
  local anchor = ns.anchor or ns.caret
  return newRawState(ns.text, charCount(ns.text), anchor)
end

ops.selectAll = function(rawState)
  local ns = normalizeState(rawState)
  return newRawState(ns.text, charCount(ns.text), 0)
end

--------------------------------------------------------------------------------
-- Undo and redo, the pair a hand test found missing from the field entirely
--------------------------------------------------------------------------------

-- The history lives in this state rather than in the shell around it, so every
-- grouping rule below is provable offline with no Hammerspoon and no screen, which is
-- the whole reason this file was split out from the tap in the first place. A run of
-- edits stays one undo step only when macOS would treat it as one. Typing an ordinary
-- character joins the run opened by the character typed just before it, and a
-- backward delete joins the run opened by the backward delete just before it, since
-- undoing a typed word or a held backspace one character at a time reads as the key
-- repeating rather than the undo working. Every other edit answers a step of its own,
-- a paste, a cut, a word delete, a line kill, and typing or deleting over a live
-- selection, since each of those replaces something rather than continuing a run the
-- hand is still in the middle of. Any caret movement, plain or extending a selection,
-- and select all, close whatever run was open without opening a step of their own,
-- since none of them touch the text, and joining an edit made after such a move to one
-- made before it would undo two unrelated changes at once. Redo is thrown away by
-- every edit that reaches apply, whether that edit opens a fresh step or joins one
-- already open, since a fresh edit invalidates whatever had been undone before it,
-- which is the ordinary rule everywhere else this exists.

local HISTORY_CAP = 100

-- Answers a new array, the given run with the given snapshot appended, its oldest
-- entry dropped once the count would otherwise pass the cap. A fresh array rather
-- than an append in place, since a state handed to an operation must read the same
-- afterward as it did before, its runs included.
local function pushSnapshot(run, snapshot)
  local grown = {}
  local first = 1
  if #run >= HISTORY_CAP then first = #run - HISTORY_CAP + 2 end
  for i = first, #run do grown[#grown + 1] = run[i] end
  grown[#grown + 1] = snapshot
  return grown
end

-- Answers a new array holding every entry but the last, the one undo or redo is about
-- to hand back as the state to restore.
local function popSnapshot(run)
  local shrunk = {}
  for i = 1, #run - 1 do shrunk[i] = run[i] end
  return shrunk
end

-- Rebuilds a raw state from a plain operation's own text, caret and anchor together
-- with the history fields apply has already worked out, since none of the operations
-- above know these three fields exist and would otherwise answer them empty.
local function withHistory(mutated, undoStack, redoStack, openGroup)
  return newRawState(mutated.text, mutated.caret, mutated.anchor, undoStack, redoStack, openGroup)
end

-- Answers the state unchanged when there is nothing to undo, the round two rule that
-- an empty history must answer rather than raise. Otherwise the top of the undo run
-- becomes the restored state, the state being left behind is pushed onto the redo run
-- so the same edit can be walked forward again, and openGroup is cleared, since
-- whatever was open before this undo has nothing left in the text to join.
local function undo(ns)
  if #ns.undoStack == 0 then
    return newRawState(ns.text, ns.caret, ns.anchor, ns.undoStack, ns.redoStack, nil)
  end
  local restored = ns.undoStack[#ns.undoStack]
  local shrunkUndo = popSnapshot(ns.undoStack)
  local grownRedo = pushSnapshot(ns.redoStack, { text = ns.text, caret = ns.caret, anchor = ns.anchor })
  return newRawState(restored.text, restored.caret, restored.anchor, shrunkUndo, grownRedo, nil)
end

-- The same walk in the other direction, answering the state unchanged when there is
-- nothing to redo, and otherwise moving the top of the redo run back onto the undo
-- run the same way undo moves the other way, so the two stay exact mirrors of each
-- other.
local function redo(ns)
  if #ns.redoStack == 0 then
    return newRawState(ns.text, ns.caret, ns.anchor, ns.undoStack, ns.redoStack, nil)
  end
  local restored = ns.redoStack[#ns.redoStack]
  local shrunkRedo = popSnapshot(ns.redoStack)
  local grownUndo = pushSnapshot(ns.undoStack, { text = ns.text, caret = ns.caret, anchor = ns.anchor })
  return newRawState(restored.text, restored.caret, restored.anchor, grownUndo, shrunkRedo, nil)
end

-- Caret movement and select all touch nothing but the caret and the anchor, so none of
-- them answers an undo step of its own, and every one of them closes whatever step was
-- open, since moving away means the next edit is happening somewhere else and joining
-- it to one made before the move would undo two unrelated changes at once.
local MOVEMENT_OPS = {
  moveLeft = true, moveRight = true,
  moveWordLeft = true, moveWordRight = true,
  moveToStart = true, moveToEnd = true,
  moveLeftExtend = true, moveRightExtend = true,
  moveWordLeftExtend = true, moveWordRightExtend = true,
  moveToStartExtend = true, moveToEndExtend = true,
  selectAll = true,
}

-- The two operation names that can join a run of their own kind, named for the tag
-- apply stores in openGroup when one of them is the run currently open. Neither name
-- is allowed to join when the state it is handed already carries a live selection,
-- since typing or deleting over a selection replaces it rather than continuing a run,
-- which classify below checks before it ever answers one of these two names.
local GROUPABLE_KIND = {
  insertText = "insertChar",
  deleteBackward = "deleteBackward",
}

-- Cut and paste are not names model.ops answers under, a cut is exactly deleteSelection
-- and a paste is exactly insertText with whatever text the shell already read off the
-- pasteboard, the two are given their own names here purely so apply can tell a paste
-- or a cut apart from an ordinary keystroke that happens to reach the very same
-- underlying function.
local OP_ALIAS = { cut = "deleteSelection", paste = "insertText" }

-- Answers the kind apply should treat this call as, insertChar or deleteBackward when
-- it may join a run already open, movement when the call touches no text at all, and
-- boundary for everything else, a paste, a cut, a word delete, a line kill, or an
-- ordinary keystroke that lands on a live selection rather than an empty caret.
local function classify(opName, ns)
  if MOVEMENT_OPS[opName] then return "movement" end
  local groupable = GROUPABLE_KIND[opName]
  if groupable and not hasSelection(ns) then return groupable end
  return "boundary"
end

--- apply is the one seam a shell should use for every operation once undo and redo
--- exist, since it is the function that knows how to grow and walk the history the
--- two of them need and the plain operations above know nothing about. It normalizes
--- the state it is handed, classifies the operation against the state as it stood
--- before the edit, runs the named operation exactly as the plain table above already
--- would, and then decides whether the edit joins the run already open or answers a
--- new one of its own, pushing a snapshot of the state from before the edit only when
--- a new step is needed. undo and redo are answered directly here rather than through
--- the operation table, since walking the history is their entire behaviour.
function M.apply(rawState, opName, arg)
  local ns = normalizeState(rawState)

  if opName == "undo" then return undo(ns) end
  if opName == "redo" then return redo(ns) end

  local kind = classify(opName, ns)
  local fn = ops[OP_ALIAS[opName] or opName]
  if not fn then
    error("Canvas field model: apply was given an operation it does not have, " .. tostring(opName))
  end
  local mutated = fn(ns, arg)

  if kind == "movement" then
    return withHistory(mutated, ns.undoStack, ns.redoStack, nil)
  end

  -- kind never reads as boundary and equals ns.openGroup at once, since openGroup is
  -- never set to boundary below, but the check is written out plainly anyway rather
  -- than resting on that fact quietly, so a reader never has to reconstruct why a
  -- boundary edit could not slip through as a join.
  if kind ~= "boundary" and kind == ns.openGroup then
    return withHistory(mutated, ns.undoStack, {}, kind)
  end

  local grownUndo = pushSnapshot(ns.undoStack, { text = ns.text, caret = ns.caret, anchor = ns.anchor })
  local nextGroup = (kind ~= "boundary") and kind or nil
  return withHistory(mutated, grownUndo, {}, nextGroup)
end

M.HISTORY_CAP = HISTORY_CAP

--------------------------------------------------------------------------------
-- Public surface
--------------------------------------------------------------------------------

M.ops = ops

-- A fresh state for a seeded string, caret left after the text and nothing selected,
-- matching the same rule the native chooser already applies when it seeds a query, seen
-- text is placed with the caret after it rather than the whole thing standing selected.
M.newState = function(text)
  text = text or ""
  return newRawState(text, charCount(text), nil)
end

M.normalized = normalizeState
M.charCount = charCount
M.textUpTo = textUpTo

-- The selected range as two character indices with lo at or before hi, or nil when
-- there is nothing currently selected to draw or to copy.
M.selectionBounds = function(rawState)
  local ns = normalizeState(rawState)
  if not hasSelection(ns) then return nil, nil end
  return math.min(ns.caret, ns.anchor), math.max(ns.caret, ns.anchor)
end

-- The selected text itself, or an empty string when there is no selection, which is
-- what copy and cut both read before either one touches the pasteboard.
M.selectedText = function(rawState)
  local lo, hi = M.selectionBounds(rawState)
  if not lo then return "" end
  local ns = normalizeState(rawState)
  return textRange(ns.text, lo, hi)
end

return M
