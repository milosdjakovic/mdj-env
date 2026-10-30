--- === Canvas field render ===
---
--- Content, not a surface. One function, elements(state, rect, style, caretVisible),
--- answering canvas elements for a rect at an origin, the same division lib/cheatsheet.lua
--- already takes against lib/panel.lua, this file answers what a state looks like and
--- never opens a canvas of its own. That is what keeps this field placeable anywhere
--- inside a caller's own canvas, at whatever origin the caller is already drawing at,
--- rather than only ever sitting at a canvas's own top left corner the way a CanvasPanel
--- content strategy does. A caller that owns the surface prepends
--- CanvasPanel.surfaceElements for the chrome and this file's own elements for what sits
--- on top of it, the second documented way to use that atom.
---
--- Theming is inherited rather than invented. style carries the font, the size, every
--- colour and the caret width, and this file reads none of it from settings.chooserTheme
--- or from a literal of its own. The provider resolves them from the UI kit's tokens and
--- the canvas layout and hands the result in as a plain table, stage two of
--- docs/DESIGN-UI-KIT.md. The one default left here is the caret colour, which is the text
--- colour unless a caller names another.
---
--- Caret x position is measured, never summed. hs.drawing.getTextDrawingSize runs once
--- against the whole prefix up to the caret on every call, rather than a memoised per
--- character sum the way lib/chooser/providers/legacy.lua speeds up a whole page of
--- rows, since that sum runs about zero point seven percent high, invisible in
--- truncation and visible here as a caret sitting off the glyph it belongs to. One
--- measure of a query length string costs about a tenth of a millisecond, which a single
--- field can afford where a hundred rows could not. The call goes through style.measure,
--- the kit's measurer, whose exact answer is the same call cached, because every
--- getTextDrawingSize builds a hidden canvas window that outlives its delete until a
--- reload, and the canvas view redraws this field on each caret blink, each keystroke and
--- each tick of its scroll ease. Uncached, that left a window behind up to sixty times a
--- second. A caller with no measurer, the standalone probe, gets the direct call.
---
--- Vertical placement is a font metric question, not a drawing size question, and a
--- hand test is the reason that distinction matters here. The first build measured a
--- box with getTextDrawingSize and centred the text element and the selection highlight
--- inside it separately, so the text sat oddly and the highlight left uneven room above
--- an ascender and below a descender, because a canvas text element places its glyphs
--- by its own rule inside the frame it is handed rather than by centring inside that
--- measured box, and two boxes centred independently land wherever neither of them
--- predicted. The fix is one baseline, derived once from hs.styledtext.fontInfo for the
--- font and size the style names, and every element placed from that same baseline
--- rather than from a separately centred box of its own. Optically centring a single
--- line of Latin text means centring the cap height band, the span from the baseline up
--- to the top of a capital letter, rather than the full ascender to descender box, since
--- the ascender reserves headroom for diacritics and unusual glyphs a plain capital
--- never reaches while the descender reserves much less, and centring the larger box
--- reads as the text sitting low. So the baseline is chosen to put that cap height band
--- at the centre of rect, the text frame's own top is set to baseline minus the
--- ascender, and the selection highlight and the caret share that same top and the same
--- ascender minus descender height, a band around the line rather than a band around
--- the control, and because all three read from one baseline they cannot drift apart
--- from each other again.
---
--- Where the canvas puts that first baseline was measured rather than assumed. A canvas
--- text element was drawn off any real screen with hs.canvas, captured to an image with
--- imageFromCanvas, and read back outside Hammerspoon to find exactly which row the ink
--- sits on, for frames of several different heights and for glyphs chosen to show the
--- top and the bottom of a line. The baseline sits a constant distance below the
--- frame's own top edge, that distance matching the font's ascender, regardless of how
--- much taller the frame is drawn than the text needs, which is what rules out the
--- frame being centred on its own content instead of anchored from its top, and a frame
--- no taller than the ascender minus the descender still shows the whole glyph with
--- nothing clipped, which is why the text frame, the highlight and the caret below are
--- all sized to exactly that height.
---
--- The caret does not blink here. caretVisible is a plain boolean the caller passes in
--- on every call, the owner runs the timer and decides when it is on or off, decision
--- four of the brief keeps every clock out of this file and out of model.lua alike.
---
--- What this file does not do. It does not wrap or scroll a buffer wider than rect, a
--- string past the edge is clipped by the canvas the same way any text element clips,
--- nothing in the brief's decisions asks for a scrolled viewport and this file does not
--- invent one, which is one of the places noted back to the brief rather than guessed at
--- quietly.
---
--- The placeholder, added during the canvas provider fix round rather than in the
--- three rounds of hand judgement above, since the gap was found by that later review
--- and not by a hand test of this file. elements takes a fifth argument, placeholder, a
--- plain string, drawn dim in place of the buffer only when the buffer itself is empty,
--- on the identical lineTop and lineH the real text is placed from, so the two can
--- never drift apart the way two separately measured boxes once did above. Nothing
--- about a non empty buffer changes in any way, the placeholder element is simply never
--- added in that case. The caret still draws after it in the element list, so it paints
--- on top the same way it already does over the real text.

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("Canvas field render: failed to load " .. name .. ", " .. tostring(err))
  end
  return chunk()
end

local model = load("model.lua")

local M = {}

local function px(n) return math.floor(n + 0.5) end

--- render.elements(state, rect, style, caretVisible) answers a list of canvas elements.
--- rect is { x, y, w, h }, the box this field occupies inside the caller's own canvas,
--- and every element answered here is already positioned at that origin, nothing above
--- this file needs to shift anything afterward. style carries every field below, the
--- caret colour alone optional.
---   font           text font name.
---   fontSize       text point size.
---   textColor      an hs colour table for the buffer and the caret.
---   selectionColor an hs colour table for the highlight behind a selection.
---   caretColor     an hs colour table for the caret, default textColor.
---   caretWidth     the caret's pixel width.
---   placeholderColor an hs colour table for the placeholder.
---   measure        optional, the kit's measurer, whose exact(str, font, size) is cached.
--- placeholder is a plain string, drawn in place of the buffer only when the buffer is
--- empty, on the same baseline the real text uses.
function M.elements(state, rect, style, caretVisible, placeholder)
  style = style or {}
  local font = style.font
  local size = style.fontSize
  local textColor = style.textColor
  local selectionColor = style.selectionColor
  local caretColor = style.caretColor or textColor
  local caretWidth = style.caretWidth
  local placeholderColor = style.placeholderColor

  local measurer = style.measure
  local measureStyle = { font = font, size = size }

  -- The one width this file asks for a given prefix, the x the caret and the selection
  -- edges are placed at, through the kit's cache when the caller handed one in. Vertical
  -- placement no longer comes from this call at all, it comes from the font metrics
  -- below, which is the whole point of the fix documented at the top of this file.
  local function measure(prefixText)
    if prefixText == "" then return 0 end
    if measurer then return measurer:exact(prefixText, font, size) end
    local measured = hs.drawing.getTextDrawingSize(prefixText, measureStyle)
    return measured and measured.w or 0
  end

  -- The one baseline every element in this function is placed from. hs.styledtext
  -- fontInfo answers the live metrics for the exact font and size the style names, so
  -- nothing measured on this machine is ever written into this arithmetic, it is read
  -- fresh for whatever font a caller hands in. A metric the system leaves out falls back
  -- to the size or to zero rather than this file failing to draw anything.
  local metrics = hs.styledtext.fontInfo({ name = font, size = size }) or {}
  local ascender = metrics.ascender or size
  local descender = metrics.descender or 0
  local capHeight = metrics.capHeight or size

  local ns = model.normalized(state)

  -- Centring the cap height band, the span from the baseline up to the top of a
  -- capital letter, at the middle of rect is what reads as optically centred, rather
  -- than centring the taller ascender to descender box the way the first build did.
  -- The text frame's own top is then set to baseline minus the ascender, which is
  -- where the measurement at the top of this file found a canvas text element actually
  -- places its first line, and the frame is given exactly ascender minus descender of
  -- height, enough to show the whole glyph with nothing clipped and no more.
  local baseline = rect.y + rect.h / 2 + capHeight / 2
  local lineTop = baseline - ascender
  local lineH = ascender - descender

  local els = {}

  -- The selection highlight is drawn first, so the text itself paints over it rather
  -- than the highlight sitting on top and dimming the glyphs it covers. It shares
  -- lineTop and lineH with the text frame below rather than measuring its own box, so
  -- it reads as a band around the line, evenly clear of the ascender above and the
  -- descender below, and it cannot drift away from where the glyphs actually land.
  local lo, hi = model.selectionBounds(ns)
  if lo then
    local xLo = measure(model.textUpTo(ns.text, lo))
    local xHi = measure(model.textUpTo(ns.text, hi))
    els[#els + 1] = {
      type = "rectangle", action = "fill", fillColor = selectionColor,
      frame = { x = px(rect.x + xLo), y = px(lineTop), w = px(xHi - xLo), h = px(lineH) },
    }
  end

  els[#els + 1] = {
    type = "text", text = ns.text, textFont = font, textSize = size,
    textColor = textColor, textAlignment = "left",
    frame = { x = px(rect.x), y = px(lineTop), w = px(rect.w), h = px(lineH) },
  }

  -- Fix round item thirteen. Drawn only when the buffer is empty, so a non empty
  -- buffer's own text element above is untouched in every way, and placed on the
  -- identical lineTop and lineH that text element already uses, so the two cannot
  -- drift apart from each other the way two separately measured boxes once did before
  -- the fix documented at the top of this file. Added after the real text element and
  -- before the caret below, so the caret still draws over it exactly as it already
  -- draws over the real text.
  if ns.text == "" and placeholder and placeholder ~= "" then
    els[#els + 1] = {
      type = "text", text = placeholder, textFont = font, textSize = size,
      textColor = placeholderColor, textAlignment = "left",
      frame = { x = px(rect.x), y = px(lineTop), w = px(rect.w), h = px(lineH) },
    }
  end

  if caretVisible then
    -- The caret shares lineTop and lineH with the text and the highlight too, so all
    -- three sit on the same band rather than the caret being centred against rect on
    -- its own, which would only reintroduce the same kind of drift against a now
    -- correctly placed line that this whole fix exists to remove.
    local xCaret = measure(model.textUpTo(ns.text, ns.caret))
    els[#els + 1] = {
      type = "rectangle", action = "fill", fillColor = caretColor,
      frame = { x = px(rect.x + xCaret), y = px(lineTop), w = px(caretWidth), h = px(lineH) },
    }
  end

  return els
end

return M
