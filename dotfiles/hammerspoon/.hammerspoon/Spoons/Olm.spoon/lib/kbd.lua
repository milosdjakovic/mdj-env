--- === kbd ===
---
--- The one vocabulary of keys a person reads. A key is an object with a name and the glyph it is
--- drawn as, and a chord is a list of keys, one entry per key, never a string. Every surface that
--- shows a shortcut, the key caps of both choosers, the actions pane, the info pane, the cheat
--- sheets and the launcher's subtitles, receives a chord and draws or spells it through this file,
--- so a glyph is written here and nowhere else, and two keys of one chord are never joined by a
--- space. Settled by Milos on 2026-11-02, see decisions/olm-chooser-keys.md.
---
--- Code names a key by its constant, kbd.Cmd or kbd.Return, never by its glyph and never by a bare
--- string. The constants are capitalised because return is a Lua keyword and kbd.return does not
--- parse, and one casing for every constant reads better than one exception. A key name that is
--- data, a chord in config/keymap.lua or a binding's key field, crosses into this vocabulary once,
--- through kbd.named, which is the only door a string has. A key's glyph is presentation and may
--- become a picture later, which is why a chord carries keys rather than the characters they draw.
---
--- Pure, no state beyond the cache of named keys, and no hs, so it loads in plain Lua. Every file
--- loads it by path, and a key is recognised by its metatable, so the first load is kept in
--- package.loaded and every later one answers it, which keeps one vocabulary per Lua state.

local LOADED = "olm.kbd"
if package.loaded[LOADED] then return package.loaded[LOADED] end

local M = {}

local KEY = { __name = "kbd.key" }
local CHORD = { __name = "kbd.chord" }

local function readOnly(kind)
  return function(_, field)
    error("kbd: a " .. kind .. " is read only, tried to set " .. tostring(field), 2)
  end
end
KEY.__newindex = readOnly("key")
CHORD.__newindex = readOnly("chord")
KEY.__tostring = function(k) return "kbd." .. k.name end
CHORD.__tostring = function(c)
  local names = {}
  for i, k in ipairs(c.keys) do names[i] = k.name end
  return "kbd.chord{" .. table.concat(names, ", ") .. "}"
end

-- A key's fields live behind the metatable so nothing can write a glyph onto one afterwards. symbol
-- is the SF Symbol a key cap draws in place of the glyph, for a key whose glyph the keycap font
-- lacks and borrows from a fallback font, which drew it at another size than its neighbours. A
-- surface that prints text keeps the glyph.
local function key(name, glyph, kind, symbol)
  local fields = { name = name, glyph = glyph, kind = kind, symbol = symbol }
  return setmetatable({}, {
    __index = fields, __newindex = KEY.__newindex, __tostring = KEY.__tostring,
    __name = KEY.__name, __metatable = KEY,
  })
end

--- kbd.isKey(v) -> whether v is a key of this vocabulary.
function M.isKey(v) return type(v) == "table" and getmetatable(v) == KEY end
--- kbd.isChord(v) -> whether v is a chord built by kbd.chord.
function M.isChord(v) return type(v) == "table" and getmetatable(v) == CHORD end

-- The modifiers, in the order macOS prints them in a menu, which is the one order every chord
-- here spells its modifiers in whatever order a binding listed them.
M.Ctrl = key("ctrl", "\u{2303}", "modifier")
M.Alt = key("alt", "\u{2325}", "modifier")
M.Shift = key("shift", "\u{21E7}", "modifier")
M.Cmd = key("cmd", "\u{2318}", "modifier")
M.MODIFIERS = { M.Ctrl, M.Alt, M.Shift, M.Cmd }

M.Return = key("return", "\u{21A9}", "key", "return")
M.Enter = key("enter", "\u{2324}", "key")
M.Space = key("space", "\u{2423}", "key")
M.Tab = key("tab", "\u{21E5}", "key")
M.Escape = key("escape", "esc", "key")
M.Delete = key("delete", "\u{232B}", "key")
M.ForwardDelete = key("forwarddelete", "\u{2326}", "key")
M.Left = key("left", "\u{2190}", "key")
M.Right = key("right", "\u{2192}", "key")
M.Up = key("up", "\u{2191}", "key")
M.Down = key("down", "\u{2193}", "key")
M.Question = key("?", "?", "key")

-- The physical keys a held leader may sit on, which the info pane's legend draws as caps. Caps Lock
-- is its own glyph, drawn from its SF Symbol in a key cap, and a right hand modifier is the word
-- right before the modifier's own glyph, two keys of one chord, so it stays the glyph a person knows.
M.CapsLock = key("capslock", "\u{21EA}", "key", "capslock")
M.RightHand = key("righthand", "right", "side")

-- The shipped leaders, each a symbol rather than a word so a chord stays a row of glyphs, a star,
-- a diamond and a dot, three shapes none of which can be taken for another. A leader the person
-- names has none and reads as its own word, through kbd.leader.
M.Hyper = key("hyper", "\u{2726}", "leader", "sparkle")
M.Meta = key("meta", "\u{25C6}", "leader")
M.Super = key("super", "\u{25CF}", "leader")

-- Every name a binding or a keymap may spell a key with, to its key. Aliases are the names
-- Hammerspoon and the menu bar use for the same key.
local NAMED = {
  ctrl = M.Ctrl, control = M.Ctrl, alt = M.Alt, option = M.Alt, shift = M.Shift,
  cmd = M.Cmd, command = M.Cmd,
  ["return"] = M.Return, enter = M.Enter, pad_enter = M.Enter, space = M.Space, tab = M.Tab,
  escape = M.Escape, delete = M.Delete, forwarddelete = M.ForwardDelete,
  left = M.Left, right = M.Right, up = M.Up, down = M.Down, ["?"] = M.Question,
  hyper = M.Hyper, meta = M.Meta, super = M.Super,
  -- Every spelling of Caps Lock is the one key, so it draws as its symbol wherever it is named.
  capslock = M.CapsLock, caps = M.CapsLock, caps_lock = M.CapsLock, ["caps lock"] = M.CapsLock,
}


-- A key whose shifted character is what a person reads, so slash with Shift is a question mark
-- rather than Shift and slash.
local SHIFTED = { ["/"] = M.Question }

-- Every other key, a letter, a digit or a punctuation mark, made once per name so one name is
-- always the same object. Its glyph is the name upper cased.
local plain = {}

--- kbd.physical(name) -> chord. A held leader's physical key, a USAGE name from lib/keyremap.lua,
--- as the keys a person reads. A name of the right hand side and a modifier, rightOption or
--- rightShift, is right and that modifier's own key, read from the name rather than listed, so a key
--- added to the allow list draws with no edit here. Every other name is kbd.named's, Caps Lock its
--- symbol and a function key itself.
function M.physical(name)
  assert(type(name) == "string" and name ~= "", "kbd.physical takes a key name, got " .. tostring(name))
  local side = name:lower():match("^right(.+)$")
  local modifier = side and NAMED[side]
  if modifier and modifier.kind == "modifier" then return M.chord({ M.RightHand, modifier }) end
  return M.chord({ M.named(name) })
end

--- kbd.named(name) -> key. The one door a key name that is data crosses, a binding's key field or a
--- word from config/keymap.lua. A known name is its constant and any other is a plain key drawn as
--- the name upper cased. Code that knows which key it means names the constant instead.
function M.named(name)
  if M.isKey(name) then return name end
  assert(type(name) == "string" and name ~= "", "kbd.named takes a key name, got " .. tostring(name))
  local lower = name:lower()
  local known = NAMED[lower]
  if known then return known end
  local made = plain[lower]
  if not made then
    made = key(lower, name:upper(), "key")
    plain[lower] = made
  end
  return made
end

--- kbd.leader(name, word) -> key. A leader the person named, read as its own word. A shipped
--- leader's name answers its constant and its symbol.
function M.leader(name, word)
  local shipped = NAMED[tostring(name):lower()]
  if shipped and shipped.kind == "leader" then return shipped end
  return key(tostring(name):lower(), tostring(word or name), "leader")
end

--- kbd.chord(keys) -> chord. A list of keys, at least one, each a key of this vocabulary. Anything
--- else, a glyph string or a key name among them, is an error naming its position, since a chord
--- that carried a string would draw it as one cap glyph and lose the uniform spacing.
function M.chord(keys)
  assert(type(keys) == "table" and not M.isKey(keys) and not M.isChord(keys),
    "kbd.chord takes a list of keys, got " .. tostring(keys))
  local copy = {}
  for i, k in ipairs(keys) do
    if not M.isKey(k) then
      error("kbd.chord: entry " .. i .. " is a " .. type(k) .. " (" .. tostring(k)
        .. "), a chord takes kbd keys only, see lib/kbd.lua", 2)
    end
    copy[i] = k
  end
  assert(#copy > 0, "kbd.chord takes at least one key")
  return setmetatable({}, {
    __index = { keys = copy }, __newindex = CHORD.__newindex, __tostring = CHORD.__tostring,
    __name = CHORD.__name, __metatable = CHORD,
  })
end

--- kbd.binding(keyName, mods, leader) -> chord. A binding as data, a key name, its modifier names
--- and an optional leader key, as one chord, the leader first, then the modifiers in the one
--- order, then the key. Shift on a key with a shifted character is folded into that character.
function M.binding(keyName, mods, leader)
  local held = {}
  for _, m in ipairs(mods or {}) do held[M.named(m)] = true end
  local k = M.named(keyName)
  local shifted = SHIFTED[k.name]
  if shifted and held[M.Shift] then
    held[M.Shift] = nil
    k = shifted
  end
  local keys = {}
  if leader ~= nil then
    assert(M.isKey(leader), "kbd.binding takes a leader key, got " .. tostring(leader))
    keys[1] = leader
  end
  for _, m in ipairs(M.MODIFIERS) do
    if held[m] then keys[#keys + 1] = m end
  end
  keys[#keys + 1] = k
  return M.chord(keys)
end

--- kbd.of(...) -> chord. Shorthand for a chord written in code, kbd.of(kbd.Cmd, kbd.Return).
function M.of(...) return M.chord({ ... }) end

--- kbd.alternatives(v) -> a list of chords, the keys a person may press for one thing. Takes a
--- chord, a list of chords or nil for none, and refuses anything else, a string above all.
function M.alternatives(v)
  if v == nil then return {} end
  if M.isChord(v) then return { v } end
  assert(type(v) == "table" and not M.isKey(v),
    "kbd.alternatives takes a chord or a list of chords, got " .. type(v) .. " " .. tostring(v))
  local out = {}
  for i, c in ipairs(v) do
    if not M.isChord(c) then
      error("kbd.alternatives: entry " .. i .. " is a " .. type(c) .. " (" .. tostring(c)
        .. "), not a kbd chord", 2)
    end
    out[i] = c
  end
  return out
end

--- kbd.glyphs(chord) -> the glyph of each key, in order, one entry per key, for a renderer that
--- draws key by key.
function M.glyphs(chord)
  assert(M.isChord(chord), "kbd.glyphs takes a chord, got " .. tostring(chord))
  local out = {}
  for i, k in ipairs(chord.keys) do out[i] = k.glyph end
  return out
end

--- kbd.text(chord) -> string. The one spelling of a chord as text, for a surface that can only
--- print a string, a launcher subtitle or a cheat sheet badge, its glyphs with nothing between
--- them. A key cap draws its glyphs one by one instead, see the hint badge in lib/ui/style.lua.
function M.text(chord)
  if chord == nil then return "" end
  return table.concat(M.glyphs(chord))
end

--- kbd.wire(v) -> the alternatives as plain lists of keys, each { glyph, symbol }, symbol nil for a
--- key drawn as its glyph, the shape the swift chooser reads, so the bridge carries one entry per key.
function M.wire(v)
  local out = {}
  for i, c in ipairs(M.alternatives(v)) do
    local keys = {}
    for j, k in ipairs(c.keys) do keys[j] = { glyph = k.glyph, symbol = k.symbol } end
    out[i] = keys
  end
  return out
end

package.loaded[LOADED] = M
return M
