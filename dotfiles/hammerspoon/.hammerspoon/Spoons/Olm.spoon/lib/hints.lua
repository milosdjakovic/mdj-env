-- Presentation, and only presentation. What the docked hint bar shows for a live context,
-- what the action panel shows when it borrows one, which context is live, how an action is
-- classified, and which tools carry a Hyper chord.
--
-- This file names no plugin. Every question it answers is asked of the plan a resolved run
-- already produced, plus a small deps table the composition root assembles once. Where the
-- live root once read a global, spoon.Olm.registry among them, or hand kept a roster, this
-- file takes the same thing as a parameter instead, and where the live root hand kept a
-- classification table, this file derives it from the plan.
--
-- The deps table threaded through most functions here carries only what presentation needs
-- and never a concrete module.
--   predicates,    name to a zero argument test function, the live gate a binding's own
--                  when name is checked against. The same table wire.lua installs into the
--                  chord engine, so the key and the hint bar never disagree about whether a
--                  gate is open.
--   glyphFor,      a function of a key and an optional mods list answering the printable
--                  glyph for that chord, the shared renderer the root injects so this file
--                  never names the atom that owns it.
--   liveLabels,    action name to a function of a context name, answering a live relabelling
--                  of that action's word for that one context, or nil to leave the binding's
--                  own description standing. The launcher's Run becoming Open while the
--                  highlight sits on an application row is the one case this exists for
--                  today, and it is supplied by whoever wires that plugin rather than named
--                  here, since knowing Launcher exists is not this file's business.
--   owners,        context name to plugin key, the answer obj.contextOwners gives, needed by
--                  rowsFor to qualify a hosted verb's chord with the tool it belongs to.
--   kinds,         the caller's own action kind overrides, merged last inside actionKinds,
--                  needed here too since rowsFor derives kinds a second time, and both
--                  doors must answer the same classification for the same action.
--   canvasPanel,   the shared docked panel atom's factory, exposing new(opts), used by
--                  shortcutPanelFor to build one panel per context.
--   ui,            the UI kit, lib/ui, which every panel and toast this file builds is
--                  drawn through, its tokens answering the type and the colours for the
--                  half the system is on.
--   settings,      may carry settings.shortcutsPanel.delayMs, the idle reveal delay every
--                  panel this file builds shares.
--   hideShortcuts, a function of no arguments that hides the shared hold overlay, called
--                  from a panel's onClose. Owning that overlay's own visibility flag belongs
--                  to whatever wires the hold reveal, not to this file, so this is a plain
--                  callback rather than a piece of state kept here.

local obj = {}

-- A plain stub keeps this file loadable outside a running Hammerspoon, the same discipline
-- lib/surface.lua already holds itself to, and it costs nothing once hs is really present.
local log
if hs and hs.logger then
  log = hs.logger.new("Hints", "info")
else
  log = { e = function() end, w = function() end, i = function() end }
end

-- chordFor runs for every binding on every reveal, so a missing collaborator warned there
-- would flood the console at that same rate. This flag is what keeps the warning to one line
-- for the life of the config instead.
local warnedNoChordLabel = false

-- Whether a binding's LIVE gate is open right now. A key gated on live state and printed
-- anyway is exactly the disagreement the two discoverability mandates exist to prevent, and
-- the dispatch side already refuses the key through this same predicates table. An unknown
-- name keeps the binding and says so, the same forgiving failure an unknown requirement gets
-- everywhere else in this tree. This is the LIVE half of the story only. The other half, a
-- binding naming a needs this plugin's own wiring could not meet, was already answered once
-- by lib/surface.lua's own keep, before the binding ever reached plan.contexts, so nothing
-- here repeats that question.
local function bindingActive(b, deps)
  if not b.when then return true end
  local predicates = deps and deps.predicates
  local test = predicates and predicates[b.when]
  if not test then
    log.w("hints, binding '" .. tostring(b.action) .. "' names unknown predicate '"
      .. tostring(b.when) .. "', keeping it")
    return true
  end
  return test() and true or false
end

-- Whether a hosted list's own verbs table declares anything at all for an action. A
-- presence check rather than a shape check, because the registry already refuses every
-- shape but a table carrying fn plus a required closes, so the only thing a scope that
-- actually registered can hold here is that one table shape.
local function hostedVerbDeclared(verbs, action)
  return verbs ~= nil and verbs[action] ~= nil
end

-- The generic navigation vocabulary lib/surface.lua itself hands out to every context it
-- builds, never a plugin's own choice. selectNext and selectPrev are the shared move keys,
-- closeChooser is the shared close default, and openActionPanel is the chord that module
-- appends to every block unconditionally. Naming these four here is not naming a plugin, it
-- is reading the same fixed vocabulary lib/surface.lua already owns, the same way footerFor
-- below already has to recognise them one at a time to double a badge with Return or Escape.
local GENERIC_NAV = {
  selectNext = true,
  selectPrev = true,
  closeChooser = true,
  openActionPanel = true,
}

-- The context name to plugin key index rowsFor's hosted chord qualification needs. Kept
-- here rather than inline in rowsFor because lib/resolve.lua keys plan.contexts by context
-- name and exposes no reverse map back to the plugin that owns one, the same gap that once
-- made a hosted row's qualifying phrase reach for a global config table by that name.
--
-- manifests is the raw manifest set rather than the plan, since the plan's own effective
-- table is what a caller wants to read once this map resolves a name, not what builds the
-- map itself. A plugin declaring no surface owns no context and is skipped, so a name
-- collision between an unsurfaced plugin's identity and a real context can never happen.
function obj.contextOwners(plan, manifests)
  local owners = {}
  for _, name in ipairs(plan.order) do
    local decl = manifests[name] and manifests[name].surface
    if decl then
      local contextName = decl.context or plan.identity[name] or name
      owners[contextName] = name
    end
  end
  return owners
end

-- A binding's chord label, shared by footerFor and rowsFor rather than each building its own
-- copy, which is the whole reason the panel and the docked hint bar cannot print two
-- different words for the same chord. The spelling itself is asked of deps.chordLabel and
-- deps.leaderName rather than done here, so this file never learns how a leader's name or a
-- chord's words are put together, only that something answers both. Either missing degrades
-- to the bare glyph, the same shape footerFor already renders for a binding declaring
-- chord = false, so a missing collaborator lands on a shape this file already knows rather
-- than an invented one.
function obj.chordFor(binding, deps)
  local chordLabel = deps and deps.chordLabel
  local leaderName = deps and deps.leaderName
  if chordLabel and leaderName then
    return chordLabel(leaderName, binding.key, binding.mods)
  end
  if log and not warnedNoChordLabel then
    warnedNoChordLabel = true
    log.w("hints, chordFor has no chordLabel or leaderName injected, so a chord prints as its bare glyph")
  end
  local glyphFor = deps and deps.glyphFor
  return (glyphFor and glyphFor(binding.key, binding.mods)) or tostring(binding.key)
end

-- A binding's label, the live wording when one applies to this context and this action,
-- else the binding's own description, else its bare action name. Shared by footerFor and
-- rowsFor for the same reason chordFor above is, so a wording that changes with the
-- situation cannot say one thing in the hint bar and another in the panel. liveLabels is
-- supplied fresh by the caller rather than kept here, since the one live case that exists
-- today, the launcher's Run reading as Open over an application row, is that plugin's own
-- business and not something this file may know by name.
function obj.labelFor(binding, contextName, liveLabels)
  local live = liveLabels and liveLabels[binding.action]
  local word = live and live(contextName)
  return word or binding.description or binding.action
end

-- The hints for one context, answered fresh each time rather than built once, since the
-- live gate above changes while the list is open, and so does the word on the primary key.
-- Reads plan.contexts[contextName].bindings directly, already carrying only the bindings
-- whose own needs were met at wiring time, so this never repeats that filter, it only asks
-- the live one.
function obj.footerFor(contextName, plan, deps)
  local hints = {}
  local ctx = plan.contexts and plan.contexts[contextName]
  if not ctx then return hints end
  local glyphFor = deps and deps.glyphFor
  for _, b in ipairs(ctx.bindings) do
    if bindingActive(b, deps) then
      local badges
      if b.chord == false then
        -- A key the chooser atom reads for itself, so there is no chord to print in front
        -- of it, the bare key is the whole badge. Listing it is the only reason it appears
        -- in a context at all, since a key nobody can see is a key nobody presses.
        badges = { (glyphFor and glyphFor(b.key, b.mods)) or tostring(b.key) }
      else
        local chord = obj.chordFor(b, deps)
        badges = { chord }
        local doubled
        if b.action == "insertSelected" or b.action == "enter" then doubled = "return"
        elseif b.action == "closeChooser" then doubled = "escape"
        elseif b.action == "selectNext" then doubled = "down"
        elseif b.action == "selectPrev" then doubled = "up"
        end
        if doubled and glyphFor then badges[2] = glyphFor(doubled) end
      end
      hints[#hints + 1] = { badges = badges, label = obj.labelFor(b, contextName, deps and deps.liveLabels),
                            action = b.action }
    end
  end
  return hints
end

-- The ordered rows the action panel would show for one context, Back first and then its
-- verbs in declaration order. hosted, when truthy, is not a bare flag, it is the scope's own
-- verbs table, already resolved by whoever called this against the real registry, since this
-- file never reads spoon.Olm.registry or any other global. A kept row's chord is qualified
-- with the tool's own description, read through deps.owners and plan.effective, so the row
-- reads as the chord followed by the name of the list it belongs to, honest about a chord
-- that will not fire until that tool is reached directly. A kept row also carries the verb's
-- own closes, read straight off the same table hostedVerbDeclared just proved holds this
-- action.
--
-- Filtered by kind AND by the live gate, which is a correction rather than the original design.
-- It filtered by kind alone, on the stated grounds that no verb anywhere carried a when, so
-- there was nothing for a second gate to disagree with. That stopped being true the moment a
-- picker grew a page, since the two verbs that act on one highlighted entry are gated off while
-- that page is up and were still listed here, offering a person two rows that do nothing.
-- footerFor has asked this same question all along, so this is the panel catching up with the
-- hint bar rather than a new idea. The wiring time needs gate is still not repeated, since
-- lib/surface.lua's own keep answered that before the binding ever reached plan.contexts.
function obj.rowsFor(contextName, plan, deps, hosted)
  local glyphFor = deps and deps.glyphFor
  local backChord = (glyphFor and glyphFor("delete")) or "delete"
  -- Back belongs to the panel and no plugin, so its icon key is read against the panel's own
  -- manifest, deps.panelOwner, and every verb's against the plugin that owns the context.
  local owner = deps and deps.owners
  local rows = { { title = "Back", chord = backChord, icon = "back", owner = deps and deps.panelOwner } }
  local ctx = plan.contexts and plan.contexts[contextName]
  if not ctx then return rows end
  local kinds = obj.actionKinds(plan, deps and deps.kinds)
  for _, b in ipairs(ctx.bindings) do
    if kinds[b.action] == "verb" and bindingActive(b, deps)
      and (not hosted or hostedVerbDeclared(hosted, b.action)) then
      local chord = obj.chordFor(b, deps)
      local closes
      if hosted then
        local owner = deps and deps.owners and deps.owners[contextName]
        local owned = owner and plan.effective[owner]
        local description = owned and owned.description
        chord = chord .. " in " .. (description or contextName)
        closes = hosted[b.action].closes
      end
      rows[#rows + 1] = { action = b.action, title = obj.labelFor(b, contextName, deps and deps.liveLabels),
                          chord = chord, icon = b.icon, owner = owner and owner[contextName], closes = closes }
    end
  end
  return rows
end

-- activeContext used to live here, answering which context is live right now off each
-- block's own when name. Its one caller, the hyper hold reveal in the composition root,
-- handed it a test of context names while this fed that test when names, so it never found
-- anything and the apps sheet revealed over every open list. The root asks its own
-- contextOwners walk now, and the function is removed rather than repaired because a helper
-- whose argument shape its only caller got wrong once is a helper the next caller gets
-- wrong the same way.

-- The kind every action carries, derived from the plan rather than hand kept, since a hand
-- kept table is exactly what went stale in the live root, missing one plugin's chord by its
-- own admission. The primary action, whichever binding a context lists first, is navigation.
-- The two move keys, close, and the action panel chord are navigation too, recognised by
-- the fixed names lib/surface.lua itself always gives them, GENERIC_NAV above. Every other
-- binding a context carries came from that plugin's own surface.extra, so it is a verb.
--
-- kinds, when given, is a caller supplied table merged in last, an override rather than
-- another vote, for the rare action this derivation could not classify correctly on its own.
--
-- The second return value lists every action name two different bindings classified two
-- different ways before the override was applied, which can only happen when one plugin's
-- primary or extra reuses a name another plugin gave a different role, since the derivation
-- itself is otherwise a pure function of a binding's position and its own action name.
function obj.actionKinds(plan, kinds)
  local out, conflicts = {}, {}
  for _, ctx in pairs(plan.contexts or {}) do
    for i, b in ipairs(ctx.bindings) do
      local kind
      if GENERIC_NAV[b.action] then
        kind = "navigation"
      elseif i == 1 then
        kind = "navigation"
      else
        kind = "verb"
      end
      if out[b.action] and out[b.action] ~= kind then
        conflicts[#conflicts + 1] = b.action
      end
      out[b.action] = kind
    end
  end
  for name, kind in pairs(kinds or {}) do
    out[name] = kind
  end
  return out, conflicts
end

-- Shortcut hints as a docked panel's content strategy. It knows nothing about placement,
-- only about the width the panel offers, and it is drawn through the UI kit, so the text and
-- the chips track light and dark through the kit's tokens on every draw. hints may be a
-- function rather than a list, resolved on every draw, which is what lets a binding gated on
-- live state appear and disappear with the state instead of being printed once and never
-- revisited.
--
-- The bar is a flow of hints, sixteen apart and eight between lines, and one hint is a row
-- of its badges and its label, six apart, centred on each other since the chip is taller than
-- the label. The key badge is the kit's hint size, its glyph in the section role, and the
-- label is the caption role, so the bar's type, its chip height and the centring of both
-- text lines all come from the kit and nothing here places a frame by hand.
local function shortcutsContent(ui, hints)
  local function current()
    if type(hints) == "function" then return hints() or {} end
    return hints or {}
  end
  local function tree(list)
    local chips = {}
    for _, h in ipairs(list) do
      local parts = {}
      for _, b in ipairs(h.badges or {}) do parts[#parts + 1] = ui.badge(b, "hint") end
      parts[#parts + 1] = ui.text(h.label or "", "caption",
        { lineBreak = ui.lineBreaks.wordWrap })
      chips[#chips + 1] = ui.row(parts, { gap = "s", fill = false, align = ui.rowAligns.center })
    end
    return ui.flow(chips, { gapX = "lg", gapY = "sm" })
  end

  return {
    -- What is currently being said, as one comparable string, so a visible panel can notice
    -- the answer changed and redraw. The badges and the label are both in the signature
    -- because either can change without the other, a key appearing or disappearing being the
    -- first and the primary key's word changing with the row being the second.
    state = function()
      local parts = {}
      for _, h in ipairs(current()) do
        parts[#parts + 1] = table.concat(h.badges or {}, "+") .. " " .. tostring(h.label)
      end
      return table.concat(parts, " | ")
    end,
    preferredSize = function(availW)
      local w = availW or 320
      if not ui then return { w = w, h = 0 } end
      local _, h = ui.layout(tree(current()), { x = 0, y = 0, w = w, h = 0 })
      return { w = w, h = h }
    end,
    draw = function(w)
      if not ui then return {} end
      return (ui.layout(tree(current()), { x = 0, y = 0, w = w, h = 0 }))
    end,
  }
end

-- The deferred shortcut hint panel, one per context, ordinarily. Builds a fresh docked panel
-- through deps.canvasPanel, inheriting the shared surface so it matches the native picker,
-- with that context's footerFor hints as its content, and returns the three callbacks a
-- native chooser is wired with. arm on onPositioned starts the idle countdown, poke on
-- onActivity resets it on each keypress, and hide on onClose tears it down and clears any
-- peeked overlay through the injected hideShortcuts. A caller must call this once per plugin
-- and never share one panel across two, since every call here builds a new one.
--
-- contextName is ordinarily a plain string, one context for the life of this panel, which is
-- true for every plugin that owns its own window. Phase three of the chooser stage build adds
-- the other shape, a function, for the one panel that does not, host/stage's own fixed,
-- constructor time panel, which outlives every presentation it will ever show hints for.
-- Asked fresh on every reveal rather than once here, since the panel is built long before
-- anyone can say which presentation it will be showing hints for on any one open, decision
-- seven of the handoff brief, contexts and hints follow current().
function obj.shortcutPanelFor(contextName, plan, deps)
  local shortcutsPanel = deps and deps.policy and deps.policy.shortcutsPanel
  local panel = deps.canvasPanel.new({
    placement = deps.canvasPanel.placements.below,
    gap = 8,
    delay = shortcutsPanel and shortcutsPanel.delayMs,
    -- Handed as a question rather than as an answer, so a binding whose predicate turns
    -- while the list is open is listed only while it means something, and so a caller naming
    -- a function rather than a string is asked again on every reveal rather than once here.
    content = shortcutsContent(deps and deps.ui, function()
      local name = type(contextName) == "function" and contextName() or contextName
      return obj.footerFor(name, plan, deps)
    end),
  })
  return {
    onPositioned = function(frame) panel:arm(frame) end,
    onActivity = function() panel:poke() end,
    onClose = function()
      if deps and deps.hideShortcuts then deps.hideShortcuts() end
      panel:hide()
    end,
  }
end

-- Three small CanvasPanel content strategies over a mutable state table, folded into one
-- factory because all are the same shape, routine feedback a feature cannot show any other
-- way, drawn once and reused across messages rather than stacking a column of panels. A
-- plugin never builds one of these itself, it is handed the mutable state table by whoever
-- wires it and only ever writes into it.
--
-- Each is drawn through the UI kit, deps.ui, one node laid out in each rect, so the type,
-- the colours and the chips come from the kit's tokens. The rects are this file's own
-- arithmetic, and every height in it is a role's line height plus a space token, so a size
-- set in config/typography.toml reflows the toasts. The roles are title for the message and
-- for the report's heading, code for the colour toast's hex value, body for a report row's
-- label and caption for its detail, its countdown and the Dismiss chip.
function obj.toast(deps)
  local ui = deps and deps.ui
  local toast = {}

  -- The whole width of one string in one variant, rounded up, the width every toast sizes
  -- itself and its columns by.
  local function textW(str, variant)
    return math.ceil(ui.measure:exact(tostring(str or ""), variant.font, variant.size))
  end

  -- One node laid out in one rect, its elements appended to els.
  local function place(els, node, rect, tokens)
    for _, el in ipairs((ui.layout(node, rect, { tokens = tokens }))) do els[#els + 1] = el end
  end

  local wordWrap = ui and ui.lineBreaks.wordWrap

  -- A one line text message, centered, for a plugin reporting something the user cannot see
  -- any other way, a clipboard append growing an entry offscreen or a walk moving through a
  -- history. state.text is the one field a caller mutates before showing the panel again.
  -- One title line tall.
  function toast.message(state)
    return {
      preferredSize = function()
        local v = ui.tokens().text.title
        return { w = textW(state.text, v), h = v.lineHeight }
      end,
      draw = function(w, h)
        local tokens = ui.tokens()
        local v = tokens.text.title
        local els = {}
        place(els, ui.text(state.text, "title", { align = ui.aligns.center, lineBreak = wordWrap }),
          { x = 0, y = (h - v.lineHeight) / 2, w = w, h = v.lineHeight }, tokens)
        return els
      end,
    }
  end

  -- A colour swatch beside its hex label, for a plugin whose feedback is a sampled colour
  -- rather than a sentence. state.hex and state.color are the two fields a caller mutates.
  -- The swatch stays a plain rectangle, since no primitive draws a sampled colour, and it
  -- reads its size, its corner and its stroke from the tokens, the stroke being the border
  -- colour, so a sample close to the panel fill still has an edge. The hex is code, since it
  -- is the one thing a person would copy, and the gap is the large space step.
  function toast.color(state)
    return {
      preferredSize = function()
        local tokens = ui.tokens()
        local swatch = tokens.icon.swatch
        return { w = swatch + tokens.space.l + textW(state.hex, tokens.text.code),
                 h = math.max(swatch, tokens.text.code.lineHeight) }
      end,
      draw = function(w, h)
        local tokens = ui.tokens()
        local swatch, r, v = tokens.icon.swatch, tokens.radius.nested, tokens.text.code
        local bw = tokens.stroke.border
        local gap = tokens.space.l
        local els = {
          { type = "rectangle", action = "fill", fillColor = state.color,
            roundedRectRadii = { xRadius = r, yRadius = r },
            frame = { x = 0, y = (h - swatch) / 2, w = swatch, h = swatch } },
          -- The outline is drawn inside the swatch, inset by half its width with its corner
          -- less half its width, so it follows the fill's curve rather than straddling it.
          { type = "rectangle", action = "stroke",
            strokeColor = tokens.colors.border, strokeWidth = bw,
            roundedRectRadii = { xRadius = math.max(0, r - bw / 2), yRadius = math.max(0, r - bw / 2) },
            frame = { x = bw / 2, y = (h - swatch) / 2 + bw / 2, w = swatch - bw, h = swatch - bw } },
        }
        place(els, ui.text(state.hex, "code", { lineBreak = wordWrap }),
          { x = swatch + gap, y = (h - v.lineHeight) / 2, w = w - swatch - gap,
            h = v.lineHeight }, tokens)
        return els
      end,
    }
  end

  -- A titled list of rows, each an optional icon, a label, and a short detail, with a footer
  -- carrying a countdown and a Dismiss button, for a plugin whose feedback is what happened
  -- to several things at once, the workspaces apply naming the apps in a layout that were not
  -- open. Sized like the Hyper cheat sheet, the same icon size, so the two overlays read as
  -- one instrument. state.title, state.rows, and state.secondsLeft
  -- are the fields a caller mutates, a row being { icon, label, detail, dim }. deps.onDismiss
  -- is told when the button is clicked, the caller owning the hide and the countdown alike.
  -- The Dismiss chip is the kit's button badge in a group carrying the click id, so the chip
  -- and its word both report dismiss.
  --
  -- The geometry is derived from the roles. The title band is the title line plus the medium
  -- space, a row is the taller of the sheet icon and a body line with the small space above
  -- and below, and the footer is the chip height with the small space above and below.
  function toast.list(state, onDismiss)
    local minW, maxW = 320, 640
    local function geometry(tokens)
      return {
        titleH = tokens.text.title.lineHeight + tokens.space.m,
        rowH = math.max(tokens.icon.sheet, tokens.text.body.lineHeight) + 2 * tokens.space.s,
        footerH = tokens.badge.button.height + 2 * tokens.space.s,
      }
    end
    local function rows() return state.rows or {} end
    local function footerText()
      local n = tonumber(state.secondsLeft)
      if not n or n <= 0 then return "" end
      return "Closing in " .. math.floor(n)
    end
    return {
      preferredSize = function()
        local tokens = ui.tokens()
        local g = geometry(tokens)
        local head, label, detail = tokens.text.title, tokens.text.body, tokens.text.caption
        local icon, gap = tokens.icon.sheet, tokens.space.m
        local w = textW(state.title, head)
        for _, r in ipairs(rows()) do
          local rw = icon + gap + textW(r.label, label) + gap * 2 + textW(r.detail, detail)
          if rw > w then w = rw end
        end
        return { w = math.min(math.max(w, minW), maxW),
                 h = g.titleH + #rows() * g.rowH + g.footerH }
      end,
      onClick = function(id)
        if id == "dismiss" and onDismiss then onDismiss() end
      end,
      draw = function(w, h)
        local tokens = ui.tokens()
        local g = geometry(tokens)
        local head, label, detail = tokens.text.title, tokens.text.body, tokens.text.caption
        local icon, gap = tokens.icon.sheet, tokens.space.m
        local els = {}
        place(els, ui.text(tostring(state.title or ""), "title", { lineBreak = wordWrap }),
          { x = 0, y = 0, w = w, h = head.lineHeight }, tokens)
        for i, r in ipairs(rows()) do
          local y = g.titleH + (i - 1) * g.rowH
          local alpha = r.dim and tokens.alpha.muted or 1
          local x = 0
          if r.icon then
            place(els, ui.group({ ui.icon(r.icon, "sheet") }, { alpha = alpha }),
              { x = x, y = y + (g.rowH - icon) / 2, w = icon, h = icon }, tokens)
          end
          x = x + icon + gap
          local detailW = textW(r.detail, detail)
          place(els, ui.group({ ui.text(tostring(r.label or ""), "body",
            { lineBreak = ui.lineBreaks.truncateTail }) }, { alpha = alpha }),
            { x = x, y = y + (g.rowH - label.lineHeight) / 2, w = w - x - detailW - gap,
              h = label.lineHeight }, tokens)
          place(els, ui.group({ ui.text(tostring(r.detail or ""), "caption",
            { align = ui.aligns.right, lineBreak = wordWrap }) },
            { alpha = alpha }),
            { x = w - detailW, y = y + (g.rowH - detail.lineHeight) / 2, w = detailW,
              h = detail.lineHeight }, tokens)
        end
        -- The footer, the countdown on the left and Dismiss as a chip on the right.
        local fy = h - g.footerH
        local word = "Dismiss"
        local button = tokens.badge.button
        local chipW = textW(word, tokens.text[button.text]) + 2 * button.padX
        place(els, ui.text(footerText(), "caption", { lineBreak = wordWrap }),
          { x = 0, y = fy + (g.footerH - detail.lineHeight) / 2, w = w - chipW - gap,
            h = detail.lineHeight }, tokens)
        place(els, ui.group({ ui.badge(word, "button") }, { id = "dismiss" }),
          { x = w - chipW, y = fy + (g.footerH - button.height) / 2, w = chipW, h = button.height },
          tokens)
        return els
      end,
    }
  end

  return toast
end

-- The Hyper hold overlay's ACTIONS section, replacing the hand kept list the live root
-- carried and had already let go stale by one entry. Walks registry.shortcuts, the tools
-- both registered and active right now, keeps every entry whose kind is leader, since a
-- global shortcut belongs to no hold overlay, and builds one row per tool from
-- registry.rowFor of that name plus plan.effective's key and description, the same two
-- values every other presentation piece in this file reads off the plan rather than off a
-- second copy of it.
--
-- Must be called after wire's own register and activate stages have run, since
-- registry.shortcuts only yields entries for a tool both registered and active, never
-- earlier, or this answers an empty list.
--
-- registry arrives as a parameter, per this whole file's own rule, so this never reaches for
-- spoon.Olm.registry itself.
function obj.sections(registry, plan, deps)
  local function keyForIdentity(identity)
    for _, key in ipairs(plan.order) do
      if (plan.identity[key] or key) == identity then return key end
    end
    return nil
  end

  -- Which leader's overlay this is being built for, as the role word a manifest already uses,
  -- app or window. A nil answers for every leader at once, which is what this did before it
  -- was asked the question at all, so an existing caller that never cared still works.
  local role = (deps or {}).leader

  local bindings = {}
  local seen = {}

  local function add(key, mods, action, description)
    if key == nil then return end
    -- Two entries may legitimately share a key with different modifiers, screenshot to the
    -- clipboard and screenshot to a file being the real pair, so identity here is the key
    -- AND the modifiers rather than the key alone.
    local mark = tostring(key) .. "/" .. table.concat(mods or {}, "+")
    if seen[mark] then return end
    seen[mark] = true
    bindings[#bindings + 1] = {
      key = key, mods = mods, action = action, description = description or action,
    }
  end

  -- A leader command is bound through the registrar's own key lookup, never through the plan,
  -- since a command belongs to no directory. Reading it through the plan alone found no key for
  -- one and dropped it from the sheet while the key worked, which is what phase four of the core
  -- split found. The root hands the lookup only to the sheet of the leader whose engine binds
  -- registry commands, so a command never lands on a sheet whose leader does not answer it.
  local commandKey = (deps or {}).commandKey

  for _, entry in ipairs(registry.shortcuts()) do
    local key = entry.kind == "leader" and keyForIdentity(entry.name) or nil
    if entry.kind == "leader" and key == nil then
      local bound = commandKey and commandKey(entry.name)
      if bound then
        local row = registry.rowFor(entry.name)
        local detail = row and type(row.detail) == "string" and row.detail or nil
        add(bound.key, bound.mods, entry.name, bound.description or detail or entry.name)
      end
    elseif entry.kind == "leader" then
      local eff = plan.effective[key] or {}
      -- A tool living on another leader has no business on this leader's overlay, and one
      -- that states no leader is left in rather than guessed at.
      if role == nil or eff.leader == nil or eff.leader == role then
        local row = registry.rowFor(entry.name)
        -- A detail may be a resolved function rather than a string for a row whose subtitle
        -- is computed at open time, and an overlay label wants the stable words, so only a
        -- plain string is borrowed here.
        local detail = row and type(row.detail) == "string" and row.detail or nil
        add(eff.key, eff.mods, entry.name,
          eff.description or detail or entry.name)
      end
    end
  end

  -- A registry row is not the only way to own a chord, and reading only those left four real
  -- Hyper keys off this overlay. Capture declares four bindings of its own and no launcher row
  -- at all, because a screenshot is an action rather than a list you open, so screenshot,
  -- screenshot to clipboard, OCR and record were each bound, each pressable, and each missing
  -- from the very overlay that exists to say what the leader does.
  --
  -- Walked through plan.order rather than by iterating the effective table, because pairs has
  -- no order and the overlay would otherwise draw its rows in a different sequence every load.
  -- The same walk answers two more sources, for the same reason. A plugin's own key, which is
  -- how a host like the launcher owns a chord without ever being a registry tool, and the
  -- special rows some plugin declares, which is where lock and sleep live. Both are bound and
  -- pressable, and neither appeared here. The first loop already added every registry tool, so
  -- the dedupe above is what keeps a tool from being listed twice by two different routes.
  --
  -- Fields are read by name rather than by knowing which plugin declares them, exactly as
  -- bindings already is, so this file still names nothing.
  for _, directory in ipairs(plan.order or {}) do
    local eff = (plan.effective or {})[directory] or {}
    if role == nil or eff.leader == role then
      add(eff.key, eff.mods, directory, eff.description)
      for _, b in ipairs(eff.bindings or {}) do
        add(b.key, b.mods, b.action, b.description)
      end
      for _, r in ipairs(eff.specialRows or {}) do
        -- Only the ones carrying a key. A special row without one opens from a list and
        -- nowhere else, so it has no chord to show and no business on a chord overlay.
        add(r.key, r.mods, r.name, r.description)
      end
    end
  end

  return { { title = "ACTIONS", bindings = bindings } }
end

--- hints.leaderBindings(plan, role)
--- Every binding any plugin declared on one leader, as plain entries and in a stable order,
--- the plan order and then each plugin's own order. It is the same walk the second half of
--- sections does, kept as its own answer because the window leader needs the raw entries
--- rather than overlay rows. Its cheat sheet wants the `when` gate and the launcher wants the
--- icon, and a row model drops both. Reading fields by name rather than by knowing who
--- declares them is what lets a plugin join a leader by writing leader = "window" and a
--- bindings list, with nothing here or in the root naming it.
---
--- Only the bindings list is read. A single key of a plugin's own, eff.key, is not, so a tool or
--- a host whose open key the keymap binds on the window leader is bound there and missing from
--- that leader's sheet. No shipped plugin does this, and the sheet's rows move to the keymap in a
--- later phase of the keymap plan, which closes the gap rather than a second walk here. Entries are copied, never the declared tables themselves, so a caller stamping a keycode
--- onto them cannot reach back into a plugin's effective record.
function obj.leaderBindings(plan, role)
  local out = {}
  for _, directory in ipairs((plan or {}).order or {}) do
    local eff = ((plan or {}).effective or {})[directory] or {}
    if eff.leader == role then
      for _, b in ipairs(eff.bindings or {}) do
        local copy = { owner = directory }
        for k, v in pairs(b) do copy[k] = v end
        out[#out + 1] = copy
      end
    end
  end
  return out
end

--- hints.hostKeyBinding(eff, module, claimed) -> role, key, mods or nil
--- The one rule for a host that carries a key. Anything with a key, a leader and a way to be
--- shown, that the registry did not already claim, has its key bound on that leader, since a
--- host is not a registered tool and nothing else binds it. It answers the leader role and the
--- key and modifiers to bind, or nil when the rule does not apply. The root decides which
--- engine a role reaches, and the leader sheet test reads the same answer, so the rule is
--- written once and neither side restates it.
function obj.hostKeyBinding(eff, module, claimed)
  if type(eff) ~= "table" or not (eff.key and eff.leader) or claimed then return nil end
  if not module or type(module.show) ~= "function" then return nil end
  return eff.leader, eff.key, eff.mods
end

return obj
