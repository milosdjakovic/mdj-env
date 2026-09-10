--- === Canvas field keymap ===
---
--- Pure data. Keycode plus modifier set to the name of one of model.lua's operations, a
--- table rather than a chain of conditionals, so what this field honours is readable in
--- one place and a gap is visible on sight rather than buried in a run of if statements
--- nobody reads end to end. Nothing here touches hs, the numbers below are the raw
--- virtual keycodes macOS itself assigns, read once from the running config's own
--- hs.keycodes.map rather than guessed, so this file needs nothing installed to be
--- loaded and checked on its own.
---
--- Three names, copy, cut and paste, are not operations model.lua answers, since those
--- three read and write hs.pasteboard, which is a side effect this file and model.lua
--- both stay clear of. input.lua, the one file here that is allowed to touch hs, is the
--- one that gives those three names their meaning, this file only says which keys carry
--- them.

local M = {}

-- The modifiers a signature considers, always in this order, so cmd shift and shift cmd
-- describe the same held keys and are still written down as the one string below,
-- rather than two entries needing to agree by hand. Caps lock and fn are left out on
-- purpose, holding either while pressing a printable key changes nothing this field
-- does, and fn already shows up as its own distinct keycode on the keys where it
-- matters, forwarddelete beside delete, home and end beside the plain arrows.
local MOD_ORDER = { "cmd", "alt", "ctrl", "shift" }

local function signature(flags)
  flags = flags or {}
  local parts = {}
  for _, name in ipairs(MOD_ORDER) do
    if flags[name] then parts[#parts + 1] = name end
  end
  return table.concat(parts, "+")
end

-- Named rather than left as bare numbers, so an entry below reads as the key it names
-- rather than as an integer nobody without hs.keycodes.map open can place. Queried
-- directly from the running Hammerspoon while this file was written rather than
-- assumed, since the whole point of naming these once here is that nowhere else in this
-- field guesses at them again.
local KEY = {
  LEFT = 123, RIGHT = 124,
  HOME = 115, END = 119,
  DELETE = 51, FORWARD_DELETE = 117,
  A = 0, B = 11, C = 8, D = 2, E = 14, F = 3, H = 4, K = 40, V = 9, X = 7, Z = 6,
}

-- Every entry this field honours, key, the exact modifier signature above, and the
-- operation name it names. Read top to bottom this is the whole editing contract, and a
-- key decision two of the brief asks for that is missing from here is a gap this file
-- failed to close rather than one hiding inside a conditional somewhere.
local ENTRIES = {
  -- Plain movement, one character or one word or to either end.
  { key = KEY.LEFT, mods = "", op = "moveLeft" },
  { key = KEY.RIGHT, mods = "", op = "moveRight" },
  { key = KEY.LEFT, mods = "alt", op = "moveWordLeft" },
  { key = KEY.RIGHT, mods = "alt", op = "moveWordRight" },
  { key = KEY.LEFT, mods = "cmd", op = "moveToStart" },
  { key = KEY.RIGHT, mods = "cmd", op = "moveToEnd" },
  { key = KEY.HOME, mods = "", op = "moveToStart" },
  { key = KEY.END, mods = "", op = "moveToEnd" },

  -- The same six moves again, extending a selection.
  { key = KEY.LEFT, mods = "shift", op = "moveLeftExtend" },
  { key = KEY.RIGHT, mods = "shift", op = "moveRightExtend" },
  { key = KEY.LEFT, mods = "alt+shift", op = "moveWordLeftExtend" },
  { key = KEY.RIGHT, mods = "alt+shift", op = "moveWordRightExtend" },
  { key = KEY.LEFT, mods = "cmd+shift", op = "moveToStartExtend" },
  { key = KEY.RIGHT, mods = "cmd+shift", op = "moveToEndExtend" },
  { key = KEY.HOME, mods = "shift", op = "moveToStartExtend" },
  { key = KEY.END, mods = "shift", op = "moveToEndExtend" },

  -- Deletion, one character, one word, or the rest of the line, in both directions.
  { key = KEY.DELETE, mods = "", op = "deleteBackward" },
  { key = KEY.FORWARD_DELETE, mods = "", op = "deleteForward" },
  { key = KEY.DELETE, mods = "alt", op = "deleteWordBackward" },
  { key = KEY.FORWARD_DELETE, mods = "alt", op = "deleteWordForward" },
  { key = KEY.DELETE, mods = "cmd", op = "deleteToLineStart" },

  -- Select all.
  { key = KEY.A, mods = "cmd", op = "selectAll" },

  -- The pasteboard three, given only a name here, input.lua decides what each does.
  { key = KEY.C, mods = "cmd", op = "copy" },
  { key = KEY.X, mods = "cmd", op = "cut" },
  { key = KEY.V, mods = "cmd", op = "paste" },

  -- The emacs bindings macOS honours in every text field, decision two of the brief
  -- names these seven by their physical keys precisely because a hand that reaches for
  -- them everywhere else expects them here too. Each names an operation already bound
  -- above under its ordinary key, except ctrl k, model.lua's own header explains why
  -- that one line names an operation the brief's enumerated list does not.
  { key = KEY.A, mods = "ctrl", op = "moveToStart" },
  { key = KEY.E, mods = "ctrl", op = "moveToEnd" },
  { key = KEY.B, mods = "ctrl", op = "moveLeft" },
  { key = KEY.F, mods = "ctrl", op = "moveRight" },
  { key = KEY.D, mods = "ctrl", op = "deleteForward" },
  { key = KEY.H, mods = "ctrl", op = "deleteBackward" },
  { key = KEY.K, mods = "ctrl", op = "deleteToLineEnd" },

  -- Undo and redo, named for a hand test to find missing rather than for the brief to
  -- ask for up front. Cmd z is in every macOS text field, and its absence reads as the
  -- field being broken, so it and cmd shift z for redo join the set here the same as
  -- any other entry, model.lua's apply answers both names directly.
  { key = KEY.Z, mods = "cmd", op = "undo" },
  { key = KEY.Z, mods = "cmd+shift", op = "redo" },
}

--- keymap.resolve(keycode, flags) answers the operation name, or nil when nothing here
--- claims it.
--- flags is the plain table hs.eventtap.event's getFlags method answers, read for cmd, alt,
--- ctrl and shift only. A linear scan over a few dozen entries costs nothing against a
--- single keystroke, and keeping the entries a plain list rather than a nested lookup is
--- what keeps this file readable in one pass.
function M.resolve(keycode, flags)
  local sig = signature(flags)
  for _, entry in ipairs(ENTRIES) do
    if entry.key == keycode and entry.mods == sig then
      return entry.op
    end
  end
  return nil
end

-- Published so a reader, or a future test, can walk the whole table without reaching
-- into this file's own local, the same reasoning CanvasPanel publishes its placements
-- and aligns for.
M.entries = ENTRIES
M.keys = KEY

return M
