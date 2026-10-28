--- === Swift field keys ===
---
--- The keys the swift chooser's native field edits with, in the shape the canvas field's keymap
--- takes, lib/chooser/providers/default/field/keymap.lua, one entry per key code and modifier set
--- naming the edit. The native field does the editing itself, through Cocoa's text system, so
--- this file does not drive it. It says which keys reach it, and it is the one place that says so
--- for both readers. The provider's uses answers from resolve, so a list key a person binds is
--- checked against what this field reads, and the view hands the panel the Control keys here, so
--- every other Control chord, which Cocoa would answer with a line break or a transpose, is a
--- leftover instead, as it is under the canvas field.
---
--- Up and Down are absent, since the panel hands them to the engine with any modifiers. The
--- entries match the canvas field's, which is what a person already knows.

local M = {}

local MOD_ORDER = { "cmd", "alt", "ctrl", "shift" }

-- A modifier set as one string in a fixed order, the canvas keymap's own signature.
local function signature(flags)
  flags = flags or {}
  local parts = {}
  for _, name in ipairs(MOD_ORDER) do
    if flags[name] then parts[#parts + 1] = name end
  end
  return table.concat(parts, "+")
end

-- The macOS virtual key codes of the keys below.
local KEY = {
  LEFT = 123, RIGHT = 124, HOME = 115, END = 119, DELETE = 51, FORWARD_DELETE = 117,
  A = 0, B = 11, C = 8, D = 2, E = 14, F = 3, H = 4, K = 40, V = 9, X = 7, Z = 6,
}

local ENTRIES = {
  { key = KEY.LEFT, mods = "", op = "moveLeft" },
  { key = KEY.RIGHT, mods = "", op = "moveRight" },
  { key = KEY.LEFT, mods = "alt", op = "moveWordLeft" },
  { key = KEY.RIGHT, mods = "alt", op = "moveWordRight" },
  { key = KEY.LEFT, mods = "cmd", op = "moveToStart" },
  { key = KEY.RIGHT, mods = "cmd", op = "moveToEnd" },
  { key = KEY.HOME, mods = "", op = "moveToStart" },
  { key = KEY.END, mods = "", op = "moveToEnd" },
  { key = KEY.LEFT, mods = "shift", op = "moveLeftExtend" },
  { key = KEY.RIGHT, mods = "shift", op = "moveRightExtend" },
  { key = KEY.LEFT, mods = "alt+shift", op = "moveWordLeftExtend" },
  { key = KEY.RIGHT, mods = "alt+shift", op = "moveWordRightExtend" },
  { key = KEY.LEFT, mods = "cmd+shift", op = "moveToStartExtend" },
  { key = KEY.RIGHT, mods = "cmd+shift", op = "moveToEndExtend" },
  { key = KEY.HOME, mods = "shift", op = "moveToStartExtend" },
  { key = KEY.END, mods = "shift", op = "moveToEndExtend" },
  { key = KEY.DELETE, mods = "", op = "deleteBackward" },
  { key = KEY.FORWARD_DELETE, mods = "", op = "deleteForward" },
  { key = KEY.DELETE, mods = "alt", op = "deleteWordBackward" },
  { key = KEY.FORWARD_DELETE, mods = "alt", op = "deleteWordForward" },
  { key = KEY.DELETE, mods = "cmd", op = "deleteToLineStart" },
  { key = KEY.A, mods = "cmd", op = "selectAll" },
  { key = KEY.C, mods = "cmd", op = "copy" },
  { key = KEY.X, mods = "cmd", op = "cut" },
  { key = KEY.V, mods = "cmd", op = "paste" },
  { key = KEY.Z, mods = "cmd", op = "undo" },
  { key = KEY.Z, mods = "cmd+shift", op = "redo" },
  { key = KEY.A, mods = "ctrl", op = "moveToStart" },
  { key = KEY.E, mods = "ctrl", op = "moveToEnd" },
  { key = KEY.B, mods = "ctrl", op = "moveLeft" },
  { key = KEY.F, mods = "ctrl", op = "moveRight" },
  { key = KEY.D, mods = "ctrl", op = "deleteForward" },
  { key = KEY.H, mods = "ctrl", op = "deleteBackward" },
  { key = KEY.K, mods = "ctrl", op = "deleteToLineEnd" },
}

--- M.resolve(keyCode, flags) -> the edit the native field makes on exactly those modifiers, or
--- nil. flags is a set of cmd, alt, ctrl and shift.
function M.resolve(keyCode, flags)
  local sig = signature(flags)
  for _, entry in ipairs(ENTRIES) do
    if entry.key == keyCode and entry.mods == sig then return entry.op end
  end
  return nil
end

--- M.controlKeys() -> { control = key codes, backspace = key codes }, the Control keys the field
--- edits with, and those among them that delete backward and so stand for Backspace on an empty
--- field, which is what the panel is handed.
function M.controlKeys()
  local control, backspace = {}, {}
  for _, entry in ipairs(ENTRIES) do
    if entry.mods == "ctrl" then
      control[#control + 1] = entry.key
      if entry.op == "deleteBackward" then backspace[#backspace + 1] = entry.key end
    end
  end
  return { control = control, backspace = backspace }
end

M.entries = ENTRIES

return M
