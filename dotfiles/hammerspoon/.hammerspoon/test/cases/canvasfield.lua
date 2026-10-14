-- Unit case for the pure model behind the canvas text field,
-- Spoons/Olm.spoon/lib/chooser/providers/default/field/model.lua, phase two of
-- docs/PLAN-CANVAS-CHOOSER.md and built from docs/BRIEF-CANVAS-FIELD.md. Every check here
-- drives model.lua alone, with no eventtap, no canvas, and no timer behind it, which is the
-- whole point of splitting the field into a pure core and a side effecting shell, this file
-- proves the core with nothing but plain Lua tables.
--
-- Copy, cut and paste read and write hs.pasteboard from input.lua rather than from model.lua,
-- so this file does not drive the pasteboard itself, it drives the text arithmetic those three
-- rest on instead, selectedText answering what copy and cut would place there and
-- deleteSelection answering what cut leaves behind, which is everything about them a state to
-- state function can be asked to prove.
--
-- Each check prints one line, PASS or FAIL followed by a plain description, and the runner
-- counts from those lines alone, the same convention every other case follows.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/lib/chooser/providers/default/field/model.lua"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

-- model.lua names no hs global and no timer, so the environment it loads under here is
-- plain Lua alone, the same proof the brief asks for, that this file needs nothing
-- installed and nothing running to be driven and checked.
-- error joined this list once apply gained a path that names an operation this file
-- does not have, a plain Lua builtin rather than anything hs offers, so it costs
-- nothing against the proof the comment above is making.
local env = {
  math = math, string = string, table = table, utf8 = utf8,
  type = type, pairs = pairs, ipairs = ipairs, tostring = tostring, print = print,
  error = error,
}

local function loadModel()
  local chunk, err = loadfile(modulePath, "t", env)
  if not chunk then
    error("could not load Olm.spoon canvas field model.lua, " .. tostring(err))
  end
  return chunk()
end

local model = loadModel()

-- A raw state table by hand, since most checks want a starting point the constructors
-- would not otherwise reach, a caret sitting mid selection or an anchor already open.
local function st(text, caret, anchor)
  return { text = text, caret = caret, anchor = anchor }
end

--------------------------------------------------------------------------------
-- Seeding a state
--------------------------------------------------------------------------------

do
  local s = model.newState("hello")
  check("a freshly seeded state leaves the caret after the text", s.caret == 5)
  check("a freshly seeded state opens with nothing selected", s.anchor == nil)
end

--------------------------------------------------------------------------------
-- Insert a character, decision two
--------------------------------------------------------------------------------

do
  local s = model.ops.insertText(st("helo", 2, nil), "l")
  check("insertText inserts at the caret", s.text == "hello" and s.caret == 3,
    "text " .. tostring(s.text) .. " caret " .. tostring(s.caret))
end

do
  local s = model.ops.insertText(st("hello world", 6, 11), "there")
  check("insertText replaces an open selection rather than inserting beside it",
    s.text == "hello there" and s.caret == 11 and s.anchor == nil)
end

do
  local s = model.ops.insertText(st("hello world", 6, nil), "there ")
  check("insertText accepts a whole string, which is how a paste reaches this file",
    s.text == "hello there world" and s.caret == 12)
end

--------------------------------------------------------------------------------
-- Delete backward and forward, decision two
--------------------------------------------------------------------------------

do
  local s = model.ops.deleteBackward(st("hello", 5, nil))
  check("deleteBackward removes the character before the caret", s.text == "hell" and s.caret == 4)
end

do
  local s = model.ops.deleteBackward(st("hello", 0, nil))
  check("deleteBackward at the very start answers the state unchanged",
    s.text == "hello" and s.caret == 0)
end

do
  local s = model.ops.deleteBackward(st("hello world", 5, 0))
  check("deleteBackward removes an open selection rather than one character",
    s.text == " world" and s.caret == 0 and s.anchor == nil)
end

do
  local s = model.ops.deleteForward(st("hello", 0, nil))
  check("deleteForward removes the character after the caret", s.text == "ello" and s.caret == 0)
end

do
  local s = model.ops.deleteForward(st("hello", 5, nil))
  check("deleteForward at the very end answers the state unchanged",
    s.text == "hello" and s.caret == 5)
end

do
  local s = model.ops.deleteForward(st("hello world", 0, 5))
  check("deleteForward removes an open selection rather than one character",
    s.text == " world" and s.caret == 0)
end

--------------------------------------------------------------------------------
-- Delete by word in both directions, decision two, honouring the rule in decision three
--------------------------------------------------------------------------------

do
  local s = model.ops.deleteWordBackward(st("foo/bar/baz.txt", 15, nil))
  check("deleteWordBackward stops at the punctuation right against the word and removes only it",
    s.text == "foo/bar/baz." and s.caret == 12, "got " .. tostring(s.text))
  local s2 = model.ops.deleteWordBackward(s)
  check("a second hop crosses that one separator then removes the word behind it",
    s2.text == "foo/bar/" and s2.caret == 8, "got " .. tostring(s2.text))
end

do
  local s = model.ops.deleteWordBackward(st("foo   ...bar", 12, nil))
  check("deleteWordBackward removes only the trailing word on the first hop",
    s.text == "foo   ..." and s.caret == 9, "got " .. tostring(s.text))
  local s2 = model.ops.deleteWordBackward(s)
  check("the second hop crosses a run mixing spaces and dots as one separator run before removing the leading word",
    s2.text == "" and s2.caret == 0, "got " .. tostring(s2.text))
end

do
  local s = model.ops.deleteWordForward(st("foo bar baz", 0, nil))
  check("deleteWordForward removes the word right at the caret", s.text == " bar baz" and s.caret == 0)
end

do
  local s = model.ops.deleteWordForward(st("   hello world", 0, nil))
  check("deleteWordForward crosses leading separators before removing the word past them",
    s.text == " world" and s.caret == 0, "got " .. tostring(s.text))
end

do
  local s = model.ops.deleteWordBackward(st("hello world", 5, 0))
  check("deleteWordBackward removes an open selection rather than a word",
    s.text == " world" and s.caret == 0)
end

--------------------------------------------------------------------------------
-- Delete to the start of the line, and the line end operation ctrl k needs, decision two
--------------------------------------------------------------------------------

do
  local s = model.ops.deleteToLineStart(st("hello world", 6, nil))
  check("deleteToLineStart removes everything before the caret", s.text == "world" and s.caret == 0)
end

do
  local s = model.ops.deleteToLineStart(st("hello world", 0, nil))
  check("deleteToLineStart at the very start answers the state unchanged",
    s.text == "hello world" and s.caret == 0)
end

do
  local s = model.ops.deleteToLineStart(st("hello world", 6, 0))
  check("deleteToLineStart removes an open selection rather than the whole prefix",
    s.text == "world" and s.caret == 0)
end

-- deleteToLineEnd is the operation this file's own header explains, ctrl k in the emacs
-- bindings decision two asks for has nowhere else to land, so it is checked here the same
-- as any other named operation.
do
  local s = model.ops.deleteToLineEnd(st("hello world", 5, nil))
  check("deleteToLineEnd removes everything from the caret onward", s.text == "hello" and s.caret == 5)
end

do
  local s = model.ops.deleteToLineEnd(st("hello", 5, nil))
  check("deleteToLineEnd at the very end answers the state unchanged", s.text == "hello" and s.caret == 5)
end

--------------------------------------------------------------------------------
-- What cut and copy rest on
--------------------------------------------------------------------------------

do
  local s = model.ops.deleteSelection(st("hello", 3, nil))
  check("deleteSelection with nothing selected answers the state unchanged, which is what keeps cut from deleting a character on its own",
    s.text == "hello" and s.caret == 3)
end

do
  local s = model.ops.deleteSelection(st("hello world", 0, 5))
  check("deleteSelection removes the open selection and lands the caret at its near edge",
    s.text == " world" and s.caret == 0 and s.anchor == nil)
end

do
  check("selectedText answers the selected slice regardless of which end the anchor sits on",
    model.selectedText(st("hello world", 6, 11)) == "world"
    and model.selectedText(st("hello world", 11, 6)) == "world")
end

do
  check("selectedText answers empty with nothing selected", model.selectedText(st("hello", 2, nil)) == "")
end

do
  local lo, hi = model.selectionBounds(st("hello", 2, 2))
  check("an anchor equal to the caret reads as no selection", lo == nil and hi == nil)
end

--------------------------------------------------------------------------------
-- Move by character and by word, and to either end, decision two
--------------------------------------------------------------------------------

do
  local s = model.ops.moveLeft(st("hello", 3, nil))
  check("moveLeft steps back one character", s.caret == 2 and s.anchor == nil)
end

do
  local s = model.ops.moveLeft(st("hello", 0, nil))
  check("moveLeft clamps at the very start rather than going negative", s.caret == 0)
end

do
  local s = model.ops.moveLeft(st("hello world", 8, 2))
  check("moveLeft with an open selection collapses to its left edge rather than stepping further left",
    s.caret == 2 and s.anchor == nil)
end

do
  local s = model.ops.moveRight(st("hello", 5, nil))
  check("moveRight clamps at the very end", s.caret == 5)
end

do
  local s = model.ops.moveRight(st("hello world", 2, 8))
  check("moveRight with an open selection collapses to its right edge rather than stepping further right",
    s.caret == 8 and s.anchor == nil)
end

do
  local s = model.ops.moveWordLeft(st("foo bar baz", 11, nil))
  check("moveWordLeft lands at the start of the word behind the caret", s.caret == 8)
end

do
  local s = model.ops.moveWordRight(st("foo bar baz", 0, nil))
  check("moveWordRight lands past the word ahead of the caret", s.caret == 3)
end

do
  check("moveToStart always lands on zero", model.ops.moveToStart(st("hello", 2, nil)).caret == 0)
  check("moveToEnd always lands on the character count", model.ops.moveToEnd(st("hello", 2, nil)).caret == 5)
end

--------------------------------------------------------------------------------
-- The same six moves again, extending a selection, decision two
--------------------------------------------------------------------------------

do
  local s = model.ops.moveLeftExtend(st("hello", 3, nil))
  check("moveLeftExtend opens a selection anchored at the caret it started from",
    s.caret == 2 and s.anchor == 3)
  local s2 = model.ops.moveLeftExtend(s)
  check("a second moveLeftExtend keeps the same anchor and steps the caret again",
    s2.caret == 1 and s2.anchor == 3)
end

do
  local s = model.ops.moveRightExtend(st("hello", 1, nil))
  check("moveRightExtend opens a selection anchored at the caret it started from",
    s.caret == 2 and s.anchor == 1)
end

do
  local s = model.ops.moveWordLeftExtend(st("foo bar baz", 11, nil))
  check("moveWordLeftExtend extends by a whole word rather than by one character",
    s.caret == 8 and s.anchor == 11)
end

do
  local s = model.ops.moveWordRightExtend(st("foo bar baz", 0, nil))
  check("moveWordRightExtend extends by a whole word rather than by one character",
    s.caret == 3 and s.anchor == 0)
end

do
  local s = model.ops.moveToStartExtend(st("hello", 2, nil))
  check("moveToStartExtend selects from the caret to the very start", s.caret == 0 and s.anchor == 2)
  local s2 = model.ops.moveToEndExtend(st("hello", 2, nil))
  check("moveToEndExtend selects from the caret to the very end", s2.caret == 5 and s2.anchor == 2)
end

do
  -- A hand that shift selects out and back to the same spot expects the far end still
  -- remembered for the next extend, which is the anchor pinning rule model.lua's own
  -- header states outright.
  local s1 = model.ops.moveRightExtend(st("hello", 2, 4))
  check("extending toward an existing anchor keeps that anchor rather than replacing it",
    s1.caret == 3 and s1.anchor == 4)
  local s2 = model.ops.moveRightExtend(s1)
  check("reaching the anchor collapses the visible selection but keeps the anchor in the state",
    s2.caret == 4 and s2.anchor == 4)
  local lo, hi = model.selectionBounds(s2)
  check("that collapsed moment reads as no selection to a caller asking what is selected",
    lo == nil and hi == nil)
  local s3 = model.ops.moveRightExtend(s2)
  check("extending onward from the collapsed moment still opens a selection from the pinned anchor",
    s3.caret == 5 and s3.anchor == 4)
end

do
  local s = model.ops.selectAll(st("hello", 2, nil))
  check("selectAll selects the whole buffer with the caret at its end",
    s.caret == 5 and s.anchor == 0)
end

--------------------------------------------------------------------------------
-- Clamping a caret or an anchor out of range, decision one
--------------------------------------------------------------------------------

do
  check("normalized clamps a caret past the end of the text",
    model.normalized(st("hello", 999, nil)).caret == 5)
  check("normalized clamps a caret below zero",
    model.normalized(st("hello", -5, nil)).caret == 0)
  check("normalized clamps an anchor past the end of the text",
    model.normalized(st("hello", 2, 999)).anchor == 5)
  check("normalized clamps an anchor below zero",
    model.normalized(st("hello", 2, -5)).anchor == 0)
end

do
  local ok, s = pcall(model.ops.moveRight, st("hi", 999, nil))
  check("an operation handed an out of range caret answers rather than raising",
    ok and s.caret == 2, tostring(s))
end

do
  local ok, s = pcall(model.ops.deleteBackward, st("hi", -3, nil))
  check("an operation handed a caret below zero answers rather than raising",
    ok and s.text == "hi" and s.caret == 0, tostring(s))
end

--------------------------------------------------------------------------------
-- A character caret over a multi byte character
--------------------------------------------------------------------------------

do
  local word = "café" -- the accented e is two bytes, one character
  check("charCount counts the accented character as one character rather than two bytes",
    model.charCount(word) == 4, "got " .. tostring(model.charCount(word)))
  local seeded = model.newState(word)
  check("newState seeds the caret after the last character rather than after the last byte",
    seeded.caret == 4)
end

do
  local seeded = model.newState("café")
  local s = model.ops.moveLeft(seeded)
  check("moveLeft steps back exactly one character over the accented one",
    s.caret == 3)
  check("the caret now sits right after the plain f, not part way through the accented character",
    model.textUpTo(s.text, s.caret) == "caf")
end

do
  local s = model.ops.deleteBackward(model.newState("café"))
  check("deleteBackward removes the whole accented character rather than one of its bytes",
    s.text == "caf" and s.caret == 3, "got " .. tostring(s.text))
end

do
  local s = model.ops.insertText(model.newState("café"), "!")
  check("insertText after an accented character lands the caret past both",
    s.text == "café!" and s.caret == 5)
end

do
  local s = model.ops.moveWordLeft(st("café bar", 8, nil))
  check("moveWordLeft treats the accented character as an ordinary word character",
    s.caret == 5, "got " .. tostring(s.caret))
  local s2 = model.ops.deleteWordBackward(st("café bar", 8, nil))
  check("deleteWordBackward removes a whole word carrying an accented character cleanly",
    s2.text == "café " and s2.caret == 5, "got " .. tostring(s2.text))
end

--------------------------------------------------------------------------------
-- Undo and redo, added in round two after a hand test found the pair missing
--------------------------------------------------------------------------------

-- Every check below drives model.apply rather than model.ops directly, since apply is
-- the seam that grows and walks the history undo and redo need, and nothing about that
-- history is provable through the plain operations alone.

do
  local ok, s = pcall(model.apply, model.newState("hello"), "undo")
  check("undo on an empty history answers rather than raising",
    ok and s.text == "hello" and s.caret == 5, tostring(s))
end

do
  local ok, s = pcall(model.apply, model.newState("hello"), "redo")
  check("redo on an empty history answers rather than raising, the same as undo",
    ok and s.text == "hello" and s.caret == 5, tostring(s))
end

do
  local s1 = model.apply(model.newState(""), "insertText", "a")
  local s2 = model.apply(s1, "insertText", "b")
  local s3 = model.apply(s2, "insertText", "c")
  check("typing three characters in a row builds the word", s3.text == "abc", "got " .. tostring(s3.text))
  local u = model.apply(s3, "undo")
  check("consecutive plain character insertions join one group, so one undo removes the whole word",
    u.text == "", "got " .. tostring(u.text))
end

do
  local s1 = model.apply(model.newState("hello"), "deleteBackward")
  local s2 = model.apply(s1, "deleteBackward")
  local s3 = model.apply(s2, "deleteBackward")
  check("three backward deletes in a row remove three characters", s3.text == "he", "got " .. tostring(s3.text))
  local u = model.apply(s3, "undo")
  check("consecutive backward deletions join one group, so one undo restores all three",
    u.text == "hello", "got " .. tostring(u.text))
end

do
  -- Typing over a live selection replaces it, which the brief names as its own step
  -- rather than as a plain character insertion, even though the underlying operation
  -- is the very same insertText a bare keystroke uses.
  local selecting = { text = "hello world", caret = 6, anchor = 11 }
  local replaced = model.apply(selecting, "insertText", "there")
  check("typing over a selection replaces it rather than inserting beside it",
    replaced.text == "hello there", "got " .. tostring(replaced.text))
  local u = model.apply(replaced, "undo")
  check("undoing a replacement of a selection restores the text and the selection both",
    u.text == "hello world" and u.caret == 6 and u.anchor == 11, "got " .. tostring(u.text))
end

do
  -- A replacement never leaves a run open behind it, so the very next keystroke, even
  -- though it is an ordinary character insertion with nothing selected any more, opens
  -- a run of its own rather than joining the replacement it followed.
  local selecting = { text = "hello world", caret = 6, anchor = 11 }
  local replaced = model.apply(selecting, "insertText", "there")
  local typed = model.apply(replaced, "insertText", "!")
  check("a character typed right after a replacement still lands", typed.text == "hello there!")
  local u1 = model.apply(typed, "undo")
  check("undoing that character alone leaves the replacement in place rather than undoing both at once",
    u1.text == "hello there", "got " .. tostring(u1.text))
  local u2 = model.apply(u1, "undo")
  check("a second undo is what it takes to also undo the replacement itself",
    u2.text == "hello world", "got " .. tostring(u2.text))
end

do
  -- A paste, a cut, a word delete and a line kill are the remaining four cases the
  -- brief names as their own step, none of them joining a run even when the very same
  -- one repeats right after itself.
  local s1 = model.apply(model.newState(""), "paste", "foo")
  local s2 = model.apply(s1, "paste", "bar")
  check("two pastes in a row both land", s2.text == "foobar", "got " .. tostring(s2.text))
  local u1 = model.apply(s2, "undo")
  check("a paste answers its own step, so one undo removes only the second paste",
    u1.text == "foo", "got " .. tostring(u1.text))
  local u2 = model.apply(u1, "undo")
  check("a second undo removes the first paste as well, each paste having opened its own step",
    u2.text == "", "got " .. tostring(u2.text))
end

do
  local selecting = { text = "hello world", caret = 6, anchor = 11 }
  local cutOnce = model.apply(selecting, "cut")
  check("cut removes the selection", cutOnce.text == "hello ", "got " .. tostring(cutOnce.text))
  local u = model.apply(cutOnce, "undo")
  check("undoing a cut restores the text and the selection it removed",
    u.text == "hello world" and u.caret == 6 and u.anchor == 11)
end

do
  local s1 = model.apply({ text = "foo bar baz", caret = 11, anchor = nil }, "deleteWordBackward")
  local s2 = model.apply(s1, "deleteWordBackward")
  check("two word deletes in a row both land", s2.text == "foo ", "got " .. tostring(s2.text))
  local u1 = model.apply(s2, "undo")
  -- The first hop only ever removes the word itself and leaves the separator run
  -- against it in place, the same rule decision three already states, so what one
  -- undo restores here still carries the space that sat between the two words.
  check("a word delete answers its own step, so one undo restores only the second word",
    u1.text == "foo bar ", "got " .. tostring(u1.text))
end

do
  local s1 = model.apply({ text = "hello world", caret = 5, anchor = nil }, "deleteToLineEnd")
  check("deleteToLineEnd removes the rest of the line", s1.text == "hello", "got " .. tostring(s1.text))
  local s2 = model.apply(s1, "deleteBackward")
  check("a plain backward delete right after a line kill still lands", s2.text == "hell", "got " .. tostring(s2.text))
  local u1 = model.apply(s2, "undo")
  check("a line kill answers its own step, so the backward delete right after it undoes on its own",
    u1.text == "hello", "got " .. tostring(u1.text))
  local u2 = model.apply(u1, "undo")
  check("a second undo is what restores the line the kill removed",
    u2.text == "hello world", "got " .. tostring(u2.text))
end

do
  -- Caret movement touches no text, so it answers no step of its own, but it must
  -- still close whatever run was open, otherwise a character typed after moving away
  -- would wrongly join a run that belongs to an entirely different part of the buffer.
  local s1 = model.apply(model.newState(""), "insertText", "a")
  local s2 = model.apply(s1, "insertText", "b")
  local moved = model.apply(s2, "moveLeft")
  check("moveLeft answers no undo step of its own", #moved.undoStack == #s2.undoStack)
  local s3 = model.apply(moved, "insertText", "c")
  check("the character typed after the move lands where the moved caret sits",
    s3.text == "acb", "got " .. tostring(s3.text))
  local u1 = model.apply(s3, "undo")
  check("undoing after a move only removes the character typed since the move",
    u1.text == "ab", "got " .. tostring(u1.text))
  local u2 = model.apply(u1, "undo")
  check("a second undo is what removes the run that was open before the move closed it",
    u2.text == "", "got " .. tostring(u2.text))
end

do
  -- selectAll touches no text either, and closing whatever run was open is the same
  -- rule caret movement follows, checked here since select all reaches that rule
  -- through its own operation name rather than through one of the move names.
  local s1 = model.apply(model.newState(""), "insertText", "a")
  local s2 = model.apply(s1, "insertText", "b")
  local selected = model.apply(s2, "selectAll")
  check("selectAll answers no undo step of its own", #selected.undoStack == #s2.undoStack)
  local s3 = model.apply(selected, "insertText", "c")
  check("typing over the selection replaces the whole buffer",
    s3.text == "c", "got " .. tostring(s3.text))
end

do
  -- Redo is thrown away by the next edit, whether that edit opens a step of its own or
  -- joins one already open, since a fresh edit invalidates whatever had been undone.
  local s1 = model.apply(model.newState("hello"), "deleteBackward")
  local u1 = model.apply(s1, "undo")
  check("undoing leaves something for redo to walk forward again", #u1.redoStack == 1)
  local edited = model.apply(u1, "insertText", "!")
  check("a fresh edit clears whatever redo had been holding", #edited.redoStack == 0)
end

do
  -- A full round trip, undo walking all the way back to an empty history and redo
  -- walking all the way forward again, should reach exactly the states in between
  -- that were built on the way out, in the same order, in both directions.
  local s0 = model.newState("")
  local s1 = model.apply(s0, "paste", "foo")
  local s2 = model.apply(s1, "paste", "bar")
  local s3 = model.apply(s2, "insertText", "!")
  check("the three step edit lands", s3.text == "foobar!", "got " .. tostring(s3.text))

  local back1 = model.apply(s3, "undo")
  local back2 = model.apply(back1, "undo")
  local back3 = model.apply(back2, "undo")
  check("undoing all three steps walks back through foobar and foo to empty",
    back1.text == "foobar" and back2.text == "foo" and back3.text == "",
    "got " .. tostring(back1.text) .. ", " .. tostring(back2.text) .. ", " .. tostring(back3.text))
  local back4 = model.apply(back3, "undo")
  check("a further undo past the very first step answers the empty state unchanged",
    back4.text == "")

  local fwd1 = model.apply(back3, "redo")
  local fwd2 = model.apply(fwd1, "redo")
  local fwd3 = model.apply(fwd2, "redo")
  check("redoing all three steps walks forward through foo and foobar to foobar exclamation mark",
    fwd1.text == "foo" and fwd2.text == "foobar" and fwd3.text == "foobar!",
    "got " .. tostring(fwd1.text) .. ", " .. tostring(fwd2.text) .. ", " .. tostring(fwd3.text))
  local fwd4 = model.apply(fwd3, "redo")
  check("a further redo past the very last step answers the latest state unchanged",
    fwd4.text == "foobar!")
end

do
  -- The history is capped rather than left to grow without limit, the oldest entry
  -- dropped once a fresh push would otherwise pass the cap. model.HISTORY_CAP is read
  -- here rather than repeated as a literal, so this check keeps proving the same rule
  -- the code enforces even if that number is ever revisited.
  local extra = 5
  local s = model.newState("")
  for _ = 1, model.HISTORY_CAP + extra do
    s = model.apply(s, "paste", "x")
  end
  check("the undo history never grows past the cap",
    #s.undoStack == model.HISTORY_CAP, "got " .. tostring(#s.undoStack))
  check("the entries older than the cap are the ones dropped, the oldest survivor is the one just past them",
    #s.undoStack[1].text == extra, "got " .. tostring(#s.undoStack[1].text))
end
