--- The view contract, the seam between the chooser engine and whatever draws it.
---
--- lib/chooser/engine/init.lua owns every picker rule and all of a picker's state, and a view
--- owns only drawing and raw input. The engine depends on this contract and never on a concrete
--- view, and a view depends on the engine's own small set of calls listed further down, so the
--- canvas view at lib/chooser/providers/default/canvas.lua and a native one can each sit under
--- the one engine and neither carries a copy of its rules. This is the Bridge pattern, the
--- engine the abstraction and a view its implementor. docs/CONTRACT-PICKER.md has the section
--- that explains it, read that first.
---
--- Lua has no compiled interface, so this is a documented list of method names with their
--- arities and a validate(view), checked by the same rules lib/chooser/contract.lua checks a
--- provider by, presence and declared arity and nothing more. What a method means is written
--- beside its name below, and that part a reviewer has to read.
---
--- The field's text editing belongs to the view. The engine never edits text, it reads the
--- text, sets it with the caret after it, and is told every time it changes. That is what lets
--- a view whose field edits natively, with its own caret, selection, undo and input methods,
--- stand where the canvas field stands.

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local chunk, err = loadfile(spoonPath .. "contract.lua")
if not chunk then error("Chooser view contract: failed to load contract.lua, " .. tostring(err)) end
local contract = chunk()

local M = {}

-- What the engine calls on a view, every name required. Zero means no argument beyond self.
--
-- restyle() resolves the view's own styles from the engine's scene, called on every show
-- right after the engine has picked the tokens for the half the system is on.
--
-- place(rects) puts the surface at rects.canvas, the rectangles geometry resolved in absolute
-- screen points, on show and on reposition.
--
-- presentRows(rows) answers the ranked rows in the form the view draws them, a list of the same
-- length in the same order, each keeping its item, its enabled flag and every field the engine
-- reads. The engine holds what this answers and never ranks it again.
--
-- text() answers the field's current text as a string.
--
-- setText(text) replaces the field's text with the caret after it and nothing selected, and
-- tells the engine through fieldChanged before it returns, the way a keystroke would.
--
-- feedKey(event) handles a key down that reached the list by another route than the view's own
-- input, the focus hold's relay, exactly as a key the view heard itself.
--
-- redraw() draws what the engine's scene says now. It does nothing before the first place.
--
-- show() reveals the surface.
--
-- start() begins reading keys and the pointer, and any timer the view runs while it is up.
--
-- stop() ends all of that, the input first and the timers after, and is called first on every
-- dismissal so nothing the view armed outlives the open.
--
-- stopScroll() ends any scroll animation the view is running, called whenever the engine is
-- about to move the highlight or replace the rows, so an animation never fights a fresh list.
--
-- hide() hides the surface and forgets whatever the pointer was doing, after stop.
--
-- isVisible() answers whether the surface is genuinely on screen, as a plain boolean.
--
-- One capability a view may answer and the engine asks once, right after the view is built.
-- spansFooter() true means the view draws one surface across the canvas, the gap and the
-- companion, so the action bar runs under both and the companion stops above it. A view that
-- answers nothing keeps the bar under the canvas alone and the companion at the canvas's height.
-- footerHeight(tokens) answers the action bar's height in points for a view whose bar is not the
-- default row, and a view that answers nothing takes the default row's height.
-- floatsActionPanel() true means the view draws the action panel's rows in a popover over the
-- list rather than in place of the list's rows, so the panel offers no Back row.
M.requiredMethods = {
  "restyle", "place", "presentRows",
  "text", "setText", "feedKey",
  "redraw", "show", "start", "stop", "stopScroll", "hide", "isVisible",
}

M.requiredArity = {
  restyle = 0, place = 1, presentRows = 1,
  text = 0, setText = 1, feedKey = 1,
  redraw = 0, show = 0, start = 0, stop = 0, stopScroll = 0, hide = 0, isVisible = 0,
}

-- What a view calls on the engine, written here so both halves of the seam are read in one
-- place. The engine is the one implementation, so these are documented rather than validated.
--
-- scene() answers what to draw, a fresh table of rects, layout, drawLayout, tokens, type, list,
-- rankedQuery, placeholder, bare, footer and keysOpen. list is the list model's state, read
-- through list/model.lua's pure functions and never written.
--
-- isActive() and hide() are the picker contract's own.
--
-- fieldChanged(text) after every change to the field's text, an edit, a caret move that left
-- the text alone, or a setText. The engine reranks only when the text itself changed.
--
-- A key down is asked in this order, which is the order the canvas field already asks it in
-- lib/chooser/providers/default/field/input.lua, and a native view asks it the same way.
-- dismissKey(event) first, for Escape and its autorepeat, which the view always claims.
-- yieldsKey(event) next, true meaning the key must pass on unclaimed. listKey(event) next, true
-- meaning the open list took the key and the view claims it. Only then does the field edit,
-- and emptyBackspace() stands in for a backward delete on an empty field with nothing selected.
-- leftoverKey(event) last, for a key down the field neither edits nor types, which the view
-- claims whatever the engine does with it.
--
-- highlightIndex(index) moves the highlight to a row of the ranked list, a pointer hover.
-- chooseIndex(index) chooses that row exactly as Return would. rightClickIndex(index) tells the
-- consumer a row was right clicked. toggleKeys() opens or closes the key panel. scrollTo(points)
-- and scrollBy(points) move the list's viewport. companionScroll(points) hands a scroll over the
-- companion pane to the consumer.

--- M.validate(view) -> ok, reason
--- Answers true when view carries every required method at its stated arity, or false and one
--- phrase naming the first gap. Never throws, so the caller owns the failure policy.
function M.validate(view)
  return contract.conforms(view, M.requiredMethods, M.requiredArity)
end

return M
