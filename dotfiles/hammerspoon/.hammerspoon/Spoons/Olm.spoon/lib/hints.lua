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
--   theme,         the shared chooser theme table, handed straight to a content builder.
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
  local rows = { { title = "Back", chord = backChord, glyph = "⬅️" } }
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
                          chord = chord, glyph = b.glyph, closes = closes }
    end
  end
  return rows
end

-- Which context is live right now, the highest priority one whose own when name answers
-- true, or one carrying no when at all. isActive is a function of a predicate name rather
-- than the predicates table itself, so a caller may hand this the exact same test the chord
-- engine runs, or a stand in for a test run, with this file never touching the table shape
-- either way.
function obj.activeContext(plan, isActive)
  local best
  for _, ctx in pairs(plan.contexts or {}) do
    local live = (not ctx.when) or (isActive and isActive(ctx.when))
    if live and (not best or (ctx.priority or 0) > (best.priority or 0)) then
      best = ctx
    end
  end
  return best
end

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

-- Shortcut hints as a docked panel's content strategy, the chord chips measuring and
-- wrapping renderer. It knows nothing about placement, only about the width the panel
-- offers, and it is theme aware per draw so the text tracks light and dark. hints may be a
-- function rather than a list, resolved on every draw, which is what lets a binding gated on
-- live state appear and disappear with the state instead of being printed once and never
-- revisited.
local function shortcutsContent(theme, hints)
  local chipGapX, rowGapY = 16, 8
  local hintGap = 6
  local badgeH, badgePadX, badgeR = 18, 6, 5
  local badgeSize, labelSize = 11, 12
  local font = ".AppleSystemUIFont"

  local function textW(str, size)
    local sz = hs.drawing.getTextDrawingSize(hs.styledtext.new(str, { font = { name = font, size = size } }))
    return math.ceil((sz and sz.w) or 0)
  end
  local function chipW(h)
    local w = textW(h.label or "", labelSize)
    for _, b in ipairs(h.badges or {}) do w = w + textW(b, badgeSize) + 2 * badgePadX end
    return w + hintGap * #(h.badges or {})
  end
  local function current()
    if type(hints) == "function" then return hints() or {} end
    return hints or {}
  end
  local function wrap(w, list)
    local rows, cur, curW = {}, {}, 0
    for _, h in ipairs(list) do
      local cw = chipW(h)
      if #cur > 0 and curW + chipGapX + cw > w then rows[#rows + 1] = cur; cur, curW = {}, 0 end
      local startX = (#cur == 0) and 0 or (curW + chipGapX)
      cur[#cur + 1] = { h = h, x = startX }
      curW = startX + cw
    end
    if #cur > 0 then rows[#rows + 1] = cur end
    return rows
  end
  local function rowsHeight(rows)
    return #rows * badgeH + math.max(0, #rows - 1) * rowGapY
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
      return { w = w, h = rowsHeight(wrap(w, current())) }
    end,
    draw = function(w)
      local dark = hs.host.interfaceStyle() == "Dark"
      local side = (dark and theme.dark) or theme.light or theme.dark or {}
      local fg = side.titleColor or { white = dark and 0.92 or 0.15 }
      local meta = side.subColor or { white = dark and 0.55 or 0.42 }
      local badgeBg = { white = dark and 1 or 0, alpha = dark and 0.12 or 0.06 }
      local els, rows = {}, wrap(w, current())
      for ri, row in ipairs(rows) do
        local rowTop = (ri - 1) * (badgeH + rowGapY)
        for _, chip in ipairs(row) do
          local cx = chip.x
          for _, b in ipairs(chip.h.badges or {}) do
            local bw = textW(b, badgeSize) + 2 * badgePadX
            els[#els + 1] = { type = "rectangle", action = "fill", fillColor = badgeBg,
              roundedRectRadii = { xRadius = badgeR, yRadius = badgeR },
              frame = { x = cx, y = rowTop, w = bw, h = badgeH } }
            els[#els + 1] = { type = "text", text = b, textFont = font, textSize = badgeSize,
              textColor = fg, textAlignment = "center",
              frame = { x = cx, y = rowTop + (badgeH - badgeSize) / 2 - 1, w = bw, h = badgeSize + 4 } }
            cx = cx + bw + hintGap
          end
          local lw = textW(chip.h.label or "", labelSize)
          els[#els + 1] = { type = "text", text = chip.h.label or "", textFont = font,
            textSize = labelSize, textColor = meta, textAlignment = "left",
            frame = { x = cx, y = rowTop + (badgeH - labelSize) / 2, w = lw + 4, h = labelSize + 4 } }
        end
      end
      return els
    end,
  }
end

-- The deferred shortcut hint panel, one per context. Builds a fresh docked panel through
-- deps.canvasPanel, inheriting the shared surface so it matches the native picker, with that
-- context's footerFor hints as its content, and returns the three callbacks a native chooser
-- is wired with. arm on onPositioned starts the idle countdown, poke on onActivity resets it
-- on each keypress, and hide on onClose tears it down and clears any peeked overlay through
-- the injected hideShortcuts. A caller must call this once per plugin and never share one
-- panel across two, since every call here builds a new one.
function obj.shortcutPanelFor(contextName, plan, deps)
  local shortcutsPanel = deps and deps.settings and deps.settings.shortcutsPanel
  local panel = deps.canvasPanel.new({
    placement = deps.canvasPanel.placements.below,
    gap = 8,
    padX = 14, padY = 10,
    delay = shortcutsPanel and shortcutsPanel.delayMs,
    -- Handed as a question rather than as an answer, so a binding whose predicate turns
    -- while the list is open is listed only while it means something.
    content = shortcutsContent(deps and deps.theme, function() return obj.footerFor(contextName, plan, deps) end),
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

-- Two small CanvasPanel content strategies over a mutable state table, folded into one
-- factory because both are the same shape, routine feedback a feature cannot show any other
-- way, drawn once and reused across messages rather than stacking a column of panels. A
-- plugin never builds one of these itself, it is handed the mutable state table by whoever
-- wires it and only ever writes into it.
function obj.toast(deps)
  local theme = deps and deps.theme
  local toast = {}

  -- A one line text message, centered, for a plugin reporting something the user cannot see
  -- any other way, a clipboard append growing an entry offscreen or a walk moving through a
  -- history. state.text is the one field a caller mutates before showing the panel again.
  function toast.message(state)
    local font, size = "Menlo", 18
    return {
      preferredSize = function()
        local measured = hs.drawing.getTextDrawingSize(
          hs.styledtext.new(state.text, { font = { name = font, size = size } }))
        return { w = math.ceil((measured and measured.w) or 0), h = size + 4 }
      end,
      draw = function(w, h)
        local dark = hs.host.interfaceStyle() == "Dark"
        local side = (dark and theme.dark) or theme.light or theme.dark or {}
        local fg = side.titleColor or { white = dark and 0.92 or 0.15 }
        return {
          { type = "text", text = state.text, textFont = font, textSize = size,
            textColor = fg, textAlignment = "center",
            frame = { x = 0, y = (h - size) / 2 - 1, w = w, h = size + 6 } },
        }
      end,
    }
  end

  -- A colour swatch beside its hex label, for a plugin whose feedback is a sampled colour
  -- rather than a sentence. state.hex and state.color are the two fields a caller mutates.
  function toast.color(state)
    local font = "Menlo"
    local hexSize, swatch, gap = 18, 26, 12
    local function textW(str)
      local sz = hs.drawing.getTextDrawingSize(hs.styledtext.new(str, { font = { name = font, size = hexSize } }))
      return math.ceil((sz and sz.w) or 0)
    end
    return {
      preferredSize = function()
        return { w = swatch + gap + textW(state.hex), h = swatch }
      end,
      draw = function(w, h)
        local dark = hs.host.interfaceStyle() == "Dark"
        local side = (dark and theme.dark) or theme.light or theme.dark or {}
        local fg = side.titleColor or { white = dark and 0.92 or 0.15 }
        local swStroke = { white = dark and 1 or 0, alpha = dark and 0.25 or 0.2 }
        return {
          { type = "rectangle", action = "strokeAndFill", fillColor = state.color,
            strokeColor = swStroke, strokeWidth = 1,
            roundedRectRadii = { xRadius = 5, yRadius = 5 },
            frame = { x = 0, y = (h - swatch) / 2, w = swatch, h = swatch } },
          { type = "text", text = state.hex, textFont = font, textSize = hexSize,
            textColor = fg, textAlignment = "left",
            frame = { x = swatch + gap, y = (h - hexSize) / 2 - 1, w = w - swatch - gap, h = hexSize + 6 } },
        }
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

  for _, entry in ipairs(registry.shortcuts()) do
    if entry.kind == "leader" then
      local key = keyForIdentity(entry.name)
      local eff = (key and plan.effective[key]) or {}
      -- A tool living on another leader has no business on this leader's overlay, and one
      -- that states no leader is left in rather than guessed at.
      if role == nil or eff.leader == nil or eff.leader == role then
        local row = registry.rowFor(entry.name)
        add(eff.key, eff.mods, entry.name,
          eff.description or (row and row.detail) or entry.name)
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

return obj
