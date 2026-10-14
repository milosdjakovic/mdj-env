--- === Canvas list render ===
---
--- Content, not a surface. One function, elements(state, rect, layout, style), answering
--- canvas elements for a rect at an origin, the same division field render.lua already
--- takes and the same division lib/panel.lua takes against a consumer that owns its own
--- canvas. This file answers what a state looks like and never opens a canvas of its
--- own, which is what lets a caller draw this list under its own field inside the one
--- canvas both already share, prepending CanvasPanel.surfaceElements for the chrome, this
--- file's own elements for the rows on top of it, exactly the pattern lib/panel.lua
--- documents as the second way to use that atom.
---
--- layout and style are the two things a caller passes and this file never invents its
--- own version of either. layout carries the geometry and the row typography, geometry.lua's
--- DEFAULT_LAYOUT, which carries no type, plus the type fields, which the caller must pass
--- from the UI kit's tokens, and elements raises an error naming the first one missing. The
--- type is three roles. font, textSize and textLine are the body role, the row title. subFont,
--- subSize and subLine are the caption role, the row subtitle. numFont and numSize are the
--- body role, the row's shortcut. A line is the role's line height. Stage two of docs/DESIGN-UI-KIT.md made that table the one canvas layout
--- source. textSize is named for what it is, the whole surface's own text size, shared with
--- the field text sitting above this list, round four's own choice over native's titleSize.
--- padX, iconSize and iconGap name what a row needs that the native layout has
--- no word for at all, since a real hs.chooser row is drawn by the operating system's own
--- nib. showRowNumbers is round four's own flag, described in full below where the numbers
--- themselves are drawn. Any other geometry field a caller omits falls back to geometry's own value.
--- style carries the colours and the dim alpha, titleColor, subColor, highlightColor,
--- numberColor and dimAlpha, every one resolved by the provider from the kit's tokens, and
--- this file reads none of settings.chooserTheme, decision six of the original brief
--- stated plainly. The one set of colours it keeps answers only a caller passing no style.
---
--- A row is drawn from the shape lib/chooser/providers/legacy.lua's own head already
--- documents, title, subTitle, image, enabled and item, filterText playing no part once
--- list model.lua has already ranked by it. The icon column is reserved at a fixed width
--- whether or not a row carries an image, matching the reasoning legacy.lua's own row
--- measurement rests on, a title never drifts sideways depending on which rows around it
--- happen to carry an icon. A disabled row draws its title and subTitle dimmed and is not
--- treated any differently otherwise, the highlight still able to sit on it, since
--- decision seven of the original brief only asks that it cannot be chosen, a question
--- for whatever reads model.highlightedRow rather than for this file.
---
--- The vertical rule. A row carrying a subTitle centres the pair's letters in the row, from
--- the top of the title's capitals to the subtitle's baseline, the two baselines subLine
--- apart, the step lib/chooser/rowheight.lua derives, so the space above the title and below the subtitle is equal and is the kit's
--- inset, since lib/chooser/rowheight.lua sizes rowH to exactly that span plus the inset
--- twice. The field centres its one line the same way, so the two read alike. A row with no subTitle, or an empty one, centres its
--- title in the row instead, using the row's own real font metrics rather than a guessed
--- fraction of rowH, the same reasoning field render.lua's own header already lays out
--- for why a canvas text element has to be placed from a measured baseline rather than
--- centred as a box against another box. Optically centring one line of Latin text means
--- centring the cap height band, the span from the baseline up to the top of a capital
--- letter, rather than the full ascender to descender box, for the reason field
--- render.lua's own header states, the ascender reserves headroom a plain capital never
--- reaches and centring the taller box reads as the text sitting low. Both branches share
--- the one font metrics lookup this file makes for the title's own font and textSize,
--- taken once before the row loop rather than once per row, since every title on this
--- list shares the same font and size and asking hs.styledtext.fontInfo for the same
--- answer twenty five times a redraw would be work this file does not need to do.
---
--- Round five's own clipping. scrollTop in list model.lua is now a point offset rather
--- than a row index, so the row at the top of the viewport and the row at its bottom can
--- each be only partly inside it, and this file draws every one of those rows in full and
--- lets hs.canvas's own clip action cut whatever sits outside the row band, rather than
--- this file trying to compute how much of a partial row to draw by hand. One rectangle
--- element with action clip, set to exactly the rect M.bandHeight already answers for
--- this layout, opens the row loop, and one resetClip element closes it, so nothing
--- above or below this file's own elements in a caller's array is ever affected by a clip
--- region this file leaves behind. That pairing is also why the caller no longer has to
--- reason about a canvas sized a few points short of the band it asked this file to fill,
--- round two's own short last row, a row now either wholly inside the band or cut clean
--- at its own edge, never merely omitted or overdrawn.
---
--- Round four's other addition, a quiet row number. Cmd plus a digit chooses one of the
--- first nine rows the viewport currently shows, list model.lua's own
--- rowAtVisibleSlot answering exactly which row that is, and a shortcut nobody can see is
--- a shortcut nobody presses, so this file draws that same digit on the trailing edge of
--- each of those rows, dim, small, and in the column the native chooser reserves for
--- exactly this. showRowNumbers is the flag that turns the whole feature off without
--- touching anything else in this file, in case it turns out to cost more attention than
--- it earns.
---
--- M.bandHeight(layout) answers the one number every caller sizing a surface around this
--- list has to agree with this file about, how tall the whole row band stands, the
--- visible row count times the row height, plus the padding under the last row. It exists because that
--- multiplication used to happen twice, once inside the drawing loop below simply by
--- walking forward one rowH per row, and once wherever a caller had to decide how much
--- room to leave for this list before it ever called elements. Two places computing the
--- same number is exactly how the two quietly stop agreeing as later rounds retune rowH
--- or rowCount, and round two of this track's build plan found the cost of that first
--- hand, a caller that sized its own surface a few points short of the band this file
--- actually draws, with the shortfall landing on the last row since every row above it
--- still had room. The fix is not a bigger fudge number, it is one function neither this
--- file nor a caller ever multiplies around a second time, and it is also, as of round
--- five, the exact rect this file clips its own row band to.
---
--- What this file does not do. It does not decide which row is highlighted, which rows
--- are visible, or what a query matches, list model.lua answers all three and this file
--- only draws whatever that answer already settled. It draws no scrollbar, a keyboard and
--- a wheel driven viewport both read correctly on screen with nothing else beside the
--- rows themselves. It owns no timer and no eventtap of its own, a caller redraws this
--- list exactly when its own state changes, the same discipline field render.lua already
--- keeps for the caret blink, and the probe owns whatever tap or easing timer moves
--- scrollTop in response to a wheel, this file only ever draws whatever state it is
--- handed. And it never reserves any margin between the row band and whatever a caller
--- draws around it, that margin is the caller's own decision, one this file only ever
--- hands the caller an exact number to plan it against.

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("Canvas list render, failed to load " .. name .. ", " .. tostring(err))
  end
  return chunk()
end

local model = load("model.lua")
local geometry = load("../geometry.lua")

local M = {}

-- The one canvas layout, geometry.lua's own, since stage two of docs/DESIGN-UI-KIT.md. This
-- file used to carry a copy of its own that disagreed with it on the width, the row height,
-- the row count and the field height, and the provider always handed in geometry's values,
-- so its own copy only ever answered a caller that passed nothing. A field geometry no
-- longer carries, the font and the two text sizes, arrives from the provider, which reads
-- them from the UI kit's tokens.
local DEFAULT_LAYOUT = geometry.DEFAULT_LAYOUT

local function px(n) return math.floor(n + 0.5) end

-- What this file draws for a caller that hands in no style at all, the unit case among them,
-- kept from before stage two so such a caller still sees a highlight and readable rows. The
-- provider never leans on these, it hands in every colour and the dim alpha from the kit's
-- tokens, so nothing a person sees is drawn from them.
local NO_STYLE = {
  titleColor = { white = 0.9 },
  subColor = { white = 0.6 },
  highlightColor = { white = 0.5, alpha = 0.28 },
  dimAlpha = 0.4,
}

-- A colour dimmed by the dim alpha the provider hands in from the kit's tokens, the way a
-- disabled row's title has always been dimmed, a plain alpha cut rather than a second colour
-- a caller would have to supply. A missing colour or alpha answers the colour unchanged.
local function dim(color, factor)
  if not color or not factor then return color end
  local c = {}
  for k, v in pairs(color) do c[k] = v end
  c.alpha = (c.alpha or 1) * factor
  return c
end

local function resolveLayout(layout)
  layout = layout or {}
  return {
    width = layout.width or DEFAULT_LAYOUT.width,
    rowH = layout.rowH or DEFAULT_LAYOUT.rowH,
    rowCount = layout.rowCount or DEFAULT_LAYOUT.rowCount,
    baseH = layout.baseH or DEFAULT_LAYOUT.baseH,
    font = layout.font,
    textSize = layout.textSize,
    textLine = layout.textLine,
    subFont = layout.subFont,
    subSize = layout.subSize,
    subLine = layout.subLine,
    numFont = layout.numFont,
    numSize = layout.numSize,
    padX = layout.padX or DEFAULT_LAYOUT.padX,
    iconSize = layout.iconSize or DEFAULT_LAYOUT.iconSize,
    iconGap = layout.iconGap or DEFAULT_LAYOUT.iconGap,
    iconFrame = layout.iconFrame,
    numW = layout.numW,
    padBottom = layout.padBottom or 0,
    showRowNumbers = (layout.showRowNumbers == nil) and DEFAULT_LAYOUT.showRowNumbers or layout.showRowNumbers,
  }
end

-- Answers whether a row carries a subtitle worth stacking against, nil and the empty
-- string both answered as no, matching how row render already treats subTitle
-- everywhere else it is read in this file.
local function hasSubTitle(row)
  local sub = row.subTitle
  if sub == nil then return false end
  -- A styled subtitle is asked for its plain string, and one holding only spaces counts as
  -- none, so such a row centres its title rather than leaving an empty line under it.
  if type(sub) ~= "string" then
    sub = (type(sub) == "userdata" and sub.getString) and sub:getString() or tostring(sub)
  end
  return sub:match("%S") ~= nil
end

-- One font metrics lookup, shared by every caller that needs a line centred at the
-- middle of a band rowH tall starting at rowY, the exact reasoning field render.lua's own
-- header lays out in full for why a canvas text element has to be placed from a measured
-- baseline rather than from a box centred against another box. metrics carries ascender,
-- descender and capHeight already answered once for the font and size in question, so
-- this function costs nothing beyond the arithmetic itself.
local function centredLine(rowY, rowH, metrics)
  local baseline = rowY + rowH / 2 + metrics.capHeight / 2
  local lineTop = baseline - metrics.ascender
  local lineH = metrics.ascender - metrics.descender
  return lineTop, lineH
end

local function fontMetrics(font, size)
  local m = hs.styledtext.fontInfo({ name = font, size = size }) or {}
  return {
    ascender = m.ascender or size,
    descender = m.descender or 0,
    capHeight = m.capHeight or size,
  }
end

--- M.bandHeight(layout) answers the exact height of the whole row band this list draws
--- for the given layout, the visible row count times the row height plus padBottom, the
--- padding that scrolls with the rows. A caller sizing a canvas, a rect, or anything else this list
--- will sit inside asks this function rather than repeating the multiplication itself,
--- which is what keeps that outer size and what this file actually draws from ever
--- drifting apart as rowH or rowCount change in a later round, and it is also the exact
--- rect this file clips its own row band to as of round five. layout is every field
--- optional exactly the way M.elements takes it, missing fields falling back the same
--- way.
function M.bandHeight(layout)
  local resolved = resolveLayout(layout)
  return resolved.rowCount * resolved.rowH + resolved.padBottom
end

--- clip is optional, the rect the band is cut to when it is not the band itself, which is
--- how a caller keeps a row from being drawn over a border its surface paints at the edge.
---
--- M.elements(state, rect, layout, style, clip) answers a list of canvas elements for one row
--- list. rect is x y w h, the box this list occupies inside the caller's own canvas,
--- ordinarily sitting directly under the field at layout.baseH and standing exactly
--- M.bandHeight(layout) tall, though this function only ever reads rect.x, rect.y and
--- rect.w, since every row's own height already comes from layout.rowH and stacking
--- rowCount of them is what answers rect.h in the first place rather than the other way
--- around. layout and style are both every field optional, described at the head of this
--- file.
function M.elements(state, rect, layout, style, clip)
  for _, field in ipairs({ "font", "textSize", "textLine", "subFont", "subSize", "subLine",
                           "numFont", "numSize" }) do
    if not layout or layout[field] == nil then
      error("canvas list render, layout." .. field .. " is required, the caller passes the "
        .. "body, caption and section type from the kit's tokens", 2)
    end
  end
  layout = resolveLayout(layout)
  style = style or {}
  local dimAlpha = style.dimAlpha or NO_STYLE.dimAlpha
  local titleColor = style.titleColor or NO_STYLE.titleColor
  local subColor = style.subColor or NO_STYLE.subColor
  local highlightColor = style.highlightColor or NO_STYLE.highlightColor
  local numberColor = style.numberColor or dim(subColor, dimAlpha)

  local ns = model.normalized(state)
  local visible = model.visibleRows(ns)

  local bandH = layout.rowCount * layout.rowH + layout.padBottom
  local titleMetrics = fontMetrics(layout.font, layout.textSize)
  local subMetrics = fontMetrics(layout.subFont, layout.subSize)
  local numberMetrics = layout.showRowNumbers and fontMetrics(layout.numFont, layout.numSize) or nil

  local els = {}
  local iconPad, iconPadLeft = geometry.iconPad(layout)
  local textX = rect.x + iconPadLeft + layout.iconSize + layout.iconGap
  local textW = math.max(0, rect.w - (textX - rect.x) - layout.padX)

  -- The whole row band is clipped to its own rect before anything below is drawn into
  -- it, which is what lets a row sit half in and half out of it on purpose, round five's
  -- own point based scrollTop, rather than by accident the way round two's short last
  -- row once did. resetClip below closes the region again so nothing a caller appends
  -- after this file's own elements is ever affected by a clip this file leaves open.
  els[#els + 1] = {
    type = "rectangle", action = "clip",
    frame = clip and { x = px(clip.x), y = px(clip.y), w = px(clip.w), h = px(clip.h) }
      or { x = px(rect.x), y = px(rect.y), w = px(rect.w), h = px(bandH) },
  }

  for slot = 1, #visible do
    local entry = visible[slot]
    local row = entry.row
    local rowY = rect.y + entry.top
    local enabled = row.enabled ~= false

    -- Fix round item twelve, extended by the coordinator to cover the subtitle too.
    -- geometry.textBudget already reserves a numeral column exactly layout.iconSize
    -- wide off the trailing edge for a consumer formatting against the budget, but
    -- this file's own title and subtitle frames used to run all the way to textW
    -- regardless, so a supplier handing over either line long enough to truncate drew
    -- its own ellipsis under the numeral this same file paints for the first nine
    -- visible rows. The title and the subtitle both reserve this same column for the
    -- same reason, so a later change to one is a prompt to check the other, the same
    -- agreement geometry.lua's own header already states for its own textBudget.
    -- Subtracting that column from reservedW, only for those rows and only when
    -- showRowNumbers is on, and using reservedW for both lines rather than textW, is
    -- what brings all three back into agreement.
    local reservedW = textW
    if numberMetrics and slot <= 9 then
      reservedW = math.max(0, textW - (layout.numW or layout.iconSize))
    end

    if entry.index == ns.highlight then
      els[#els + 1] = {
        type = "rectangle", action = "fill", fillColor = highlightColor,
        frame = { x = px(rect.x), y = px(rowY), w = px(rect.w), h = px(layout.rowH) },
      }
    end

    if row.image then
      -- iconSize is the artwork's side and iconFrame the image's, larger by the transparent
      -- margin an icon carries, so the image is centred on the artwork's box and the margin
      -- falls into the padding around it.
      local art = layout.iconSize
      local side = layout.iconFrame or art
      local artX, artY = rect.x + iconPadLeft, rowY + iconPad
      els[#els + 1] = {
        type = "image", image = row.image, imageScaling = "scaleProportionally",
        frame = {
          x = px(artX - (side - art) / 2), y = px(artY - (side - art) / 2),
          w = px(side), h = px(side),
        },
      }
    end

    if hasSubTitle(row) then
      -- The letters of the pair, the title's capital height and the subtitle step down to
      -- the subtitle's baseline, centred in the row, each text frame placed from its own
      -- baseline and real font metrics.
      local inkH = titleMetrics.capHeight + layout.subLine
      local titleBase = rowY + (layout.rowH - inkH) / 2 + titleMetrics.capHeight
      local subBase = titleBase + layout.subLine
      -- Each frame is twice the ascender to descender span tall. The text is anchored at the
      -- frame's top, so the extra height moves nothing, it only keeps a descender such as g
      -- from being cut where the canvas lays the line out a little lower than the metrics say.
      local titleTop, titleH = titleBase - titleMetrics.ascender, 2 * (titleMetrics.ascender - titleMetrics.descender)
      local subTop, subH = subBase - subMetrics.ascender, 2 * (subMetrics.ascender - subMetrics.descender)
      els[#els + 1] = {
        type = "text", text = row.title or "",
        textFont = layout.font, textSize = layout.textSize,
        textColor = enabled and titleColor or dim(titleColor, dimAlpha),
        textAlignment = "left",
        frame = { x = px(textX), y = px(titleTop), w = px(reservedW), h = px(titleH) },
      }
      els[#els + 1] = {
        type = "text", text = row.subTitle,
        textFont = layout.subFont, textSize = layout.subSize,
        textColor = enabled and subColor or dim(subColor, dimAlpha),
        textAlignment = "left",
        frame = { x = px(textX), y = px(subTop), w = px(reservedW), h = px(subH) },
      }
    else
      -- No subtitle to stack against, so the title centres in the row instead of sitting
      -- high with a gap under it where a subtitle would have gone, round four's own
      -- rule, answered from the one titleMetrics lookup taken before this loop began.
      local lineTop, lineH = centredLine(rowY, layout.rowH, titleMetrics)
      els[#els + 1] = {
        type = "text", text = row.title or "",
        textFont = layout.font, textSize = layout.textSize,
        textColor = enabled and titleColor or dim(titleColor, dimAlpha),
        textAlignment = "left",
        frame = { x = px(textX), y = px(lineTop), w = px(reservedW), h = px(2 * lineH) },
      }
    end

    if numberMetrics and slot <= 9 then
      -- Decision four of round four's own consequence, a shortcut nobody can see is a
      -- shortcut nobody presses, so the first nine visible rows quietly name the digit
      -- cmd would choose them with, written as the shortcut itself, the command sign and the
      -- digit, in the row title's size and the subtext colour, on the trailing edge rather than
      -- beside the title, the column the native chooser reserves for exactly this,
      -- centred against the same row band the title and the icon both already centre or
      -- align against rather than a fraction of rowH guessed fresh for one more element.
      local numTop, numH = centredLine(rowY, layout.rowH, numberMetrics)
      local numW = layout.numW or layout.iconSize
      els[#els + 1] = {
        type = "text", text = "\u{2318}" .. tostring(slot),
        textFont = layout.numFont, textSize = layout.numSize,
        textColor = numberColor,
        textAlignment = "right",
        frame = {
          x = px(rect.x + rect.w - layout.padX - numW), y = px(numTop),
          w = px(numW), h = px(2 * numH),
        },
      }
    end
  end

  els[#els + 1] = { type = "resetClip" }

  return els
end

M.DEFAULT_LAYOUT = DEFAULT_LAYOUT

return M
