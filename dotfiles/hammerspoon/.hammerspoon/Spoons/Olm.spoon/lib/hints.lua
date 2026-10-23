-- Presentation, and only presentation. What the action bar under a list shows for a live
-- context, what the action panel shows when it borrows one, which context is live, how an action
-- is classified, which tools carry a Hyper chord, and every bound chord as words for a keys page.
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
--                  chord engine, so the key and the action bar never disagree about whether a
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
--   labelsFor,     a function of a context name answering the labels the level showing it
--                  declares, a table with primary and secondary strings, or nil. The words
--                  follow the highlighted row, so it is asked on every call rather than kept.
--                  It answers nil for a context that is not the one showing, since the level
--                  that declares the words is only the one on screen.
--   ui,            the UI kit, lib/ui, which every toast this file builds is drawn through,
--                  its tokens answering the type and the colours for the half the system is on.

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
-- is reading the same fixed vocabulary lib/surface.lua already owns, the same way the key
-- panel's badges below already have to recognise the move keys to double them with an arrow.
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

-- camelCase action name to a Title Case label, the words a row wears when nothing else names it.
local function humanize(name)
  local s = tostring(name):gsub("(%l)(%u)", "%1 %2")
  s = s:gsub("^%l", string.upper)
  return s
end

-- A binding's chord label, shared by footerModel and rowsFor rather than each building its own
-- copy, which is the whole reason the action panel and the action bar cannot print two
-- different words for the same chord. The spelling itself is asked of deps.chordLabel and of
-- the leader's word rather than done here, so this file never learns how a leader's name or a
-- chord's words are put together, only that something answers both. The word is the binding's
-- own leader's, deps.leaderNames keyed by the name the binding spells its leader with, which a list
-- key carries once the root has placed it, and deps.leaderName for a binding built by hand that
-- names none, the list role's leader. Either missing degrades to the bare glyph, the same shape footerModel already
-- renders for a binding declaring chord = false, so a missing collaborator lands on a shape
-- this file already knows rather than an invented one.
function obj.chordFor(binding, deps)
  -- A list key the open list's own field answers with modifiers alone names no leader, leader
  -- false, so it is its glyph and modifiers alone, the way a plain combination is spelled.
  if binding.leader == false then
    local glyphFor = deps and deps.glyphFor
    return (glyphFor and glyphFor(binding.key, binding.mods)) or tostring(binding.key)
  end
  local chordLabel = deps and deps.chordLabel
  local leaderName = deps and deps.leaderName
  if binding.leader ~= nil and deps and deps.leaderNames then
    leaderName = deps.leaderNames[binding.leader] or leaderName
  end
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

-- A binding's label, the one lookup the action bar, its key panel and the action panel share,
-- so a wording that changes with the situation cannot say one thing in one and another in the
-- next. The order is the level's own labels for its primary and its secondary, asked live so a
-- word may follow the highlighted row or count what is checked, then liveLabels, then the
-- binding's own description, then Open for the primary and the action name spelled as words
-- for anything else. labels and liveLabels are supplied fresh by the caller rather than kept
-- here, since the words belong to the plugin that declares them and this file may not know one
-- by name.
function obj.labelFor(binding, contextName, liveLabels, labels)
  local shared = binding.shared
  local own = type(labels) == "table" and (shared == "primary" or shared == "secondary") and labels[shared]
  if type(own) == "string" and own ~= "" then return own end
  local live = liveLabels and liveLabels[binding.action]
  local word = live and live(contextName)
  if word then return word end
  if binding.description then return binding.description end
  if shared == "primary" then return "Open" end
  return humanize(binding.action)
end

-- The badges one binding is spelled with in the key panel. A key the chooser reads for itself,
-- chord false, is its bare glyph, since there is no chord to print in front of it and listing
-- it is the only reason it appears in a context at all. Every other binding is its chord, and a
-- shared verb the field also answers on a plain key carries that key's glyph beside it, the
-- move keys their arrows and close its Escape.
local DOUBLED = { selectNext = "down", selectPrev = "up", closeChooser = "escape" }
local function badgesFor(b, deps)
  local glyphFor = deps and deps.glyphFor
  if b.chord == false then
    return { (glyphFor and glyphFor(b.key, b.mods)) or tostring(b.key) }
  end
  -- The primary reads Return alone, the key a person presses, and never its held chord, which
  -- Milos found only added noise once the bar already says Return.
  if b.shared == "primary" then
    return { (glyphFor and glyphFor("return")) or "return" }
  end
  local badges = { obj.chordFor(b, deps) }
  local doubled = DOUBLED[b.action] or (b.shared == "close" and "escape" or nil)
  if doubled and glyphFor then badges[2] = glyphFor(doubled) end
  return badges
end

--- hints.footerModel(contextName, plan, deps) -> { right, keys, state }
--- What the action bar under a list says for one context, as pure data, answered fresh on every
--- call since a live gate and a live label both change while the list is open. It reads the same
--- bindings, the same gate and the same label lookup rowsFor reads, so the bar, its key panel and
--- the action panel cannot disagree.
---
--- right is the bar's right side, in order, each { label, chord, action }. The primary first on
--- the Return glyph, since Return chooses the row whichever chord the primary also sits on, then
--- the secondary on its own chord when the list declares one and its gate is open, then the
--- action panel on its chord. A list with no primary binding, one whose key the person freed or
--- a list no surface describes, still chooses on Return, so the primary is always listed.
---
--- keys is the key panel, each { badges, label, action }, every other key the open list answers
--- in declaration order, the primary's own chord among them, then the keys the chooser's field
--- reads for itself. Back on Backspace is listed only when deps.backs(contextName) answers true,
--- the level a press would leave being a pushed one, and never when the list already lists its own
--- binding on a plain Backspace, the launcher's way out of a hosted list or a page's way back.
--- A visible row on Command and a digit is always listed.
---
--- While the action panel is open over the list, deps.actionPanel answers the panel row under the
--- highlight, or an empty table, and the model describes the panel instead, since the panel
--- borrows the list's window and current() still names the list. Return runs the highlighted row,
--- so it is labelled with that row's title, Run when there is none, the secondary is not offered,
--- since a field key acts on the list rather than on a panel row, and the key panel lists only the
--- keys that still mean something there, the shared ones and Back.
---
--- state is the whole answer as one comparable string, so a surface polling this redraws only
--- when something it would draw changed.
function obj.footerModel(contextName, plan, deps)
  deps = deps or {}
  local glyphFor = deps.glyphFor
  local function glyph(key, mods) return (glyphFor and glyphFor(key, mods)) or tostring(key) end
  local panelRow = deps.actionPanel and deps.actionPanel() or nil
  local labels = (not panelRow) and deps.labelsFor and deps.labelsFor(contextName) or nil
  local ctx = plan and plan.contexts and plan.contexts[contextName]

  local primary, secondary, panel
  local keys = {}
  local ownBack = false
  for _, b in ipairs(ctx and ctx.bindings or {}) do
    if b.shared == "primary" and not primary then primary = b end
    if bindingActive(b, deps) then
      if b.key == "delete" and (b.mods == nil or #b.mods == 0) then ownBack = true end
      if b.shared == "secondary" then
        secondary = secondary or b
      elseif b.shared == "openActionPanel" then
        panel = panel or b
      elseif not panelRow or (b.shared ~= nil and b.shared ~= "primary") then
        keys[#keys + 1] = { badges = badgesFor(b, deps),
          label = obj.labelFor(b, contextName, deps.liveLabels, labels), action = b.action }
      end
    end
  end
  if panelRow or (not ownBack and deps.backs and deps.backs(contextName)) then
    keys[#keys + 1] = { badges = { glyph("delete") }, label = "Back" }
  end
  keys[#keys + 1] = { badges = { glyph("1", { "cmd" }), glyph("9", { "cmd" }) }, label = "Choose a visible row" }

  local right = {}
  local primaryLabel
  if panelRow then
    primaryLabel = (type(panelRow.title) == "string" and panelRow.title ~= "") and panelRow.title or "Run"
    secondary = nil
  elseif primary then
    primaryLabel = obj.labelFor(primary, contextName, deps.liveLabels, labels)
  else
    primaryLabel = obj.labelFor({ shared = "primary" }, contextName, nil, labels)
  end
  right[#right + 1] = { label = primaryLabel, chord = glyph("return"),
    action = (not panelRow) and primary and primary.action or nil }
  if secondary then
    right[#right + 1] = { label = obj.labelFor(secondary, contextName, deps.liveLabels, labels),
      chord = obj.chordFor(secondary, deps), action = secondary.action }
  end
  if panel then
    right[#right + 1] = { label = obj.labelFor(panel, contextName, deps.liveLabels, labels),
      chord = obj.chordFor(panel, deps), action = panel.action }
  end

  local parts = {}
  for _, r in ipairs(right) do parts[#parts + 1] = tostring(r.label) .. " " .. tostring(r.chord) end
  parts[#parts + 1] = "|"
  for _, k in ipairs(keys) do parts[#parts + 1] = table.concat(k.badges, "+") .. " " .. tostring(k.label) end
  return { right = right, keys = keys, state = table.concat(parts, " | ") }
end

-- The ordered rows the action panel would show for one context, Back first, then the primary
-- and the secondary, the two shared verbs that act on the highlighted row, then its verbs in
-- declaration order. The primary and the secondary come first because lib/surface.lua builds them
-- first, so declaration order is the order wanted. Each wears the same label the action bar does. hosted, when truthy, is not a bare flag, it is the scope's own
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
-- The hint bar asked this same question all along, so this was the panel catching up with it
-- rather than a new idea. The wiring time needs gate is still not repeated, since
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
  local labels = deps and deps.labelsFor and deps.labelsFor(contextName) or nil
  local sharedListed = {}
  for _, b in ipairs(ctx.bindings) do
    -- A shared binding is listed only as the primary or the secondary, once each, since the
    -- secondary sits on two keys and a shared verb's action may be classified a verb elsewhere.
    local listed
    if b.shared == "primary" or b.shared == "secondary" then
      listed = not sharedListed[b.shared]
      sharedListed[b.shared] = true
    else
      listed = b.shared == nil and kinds[b.action] == "verb"
    end
    if listed and bindingActive(b, deps)
      and (not hosted or hostedVerbDeclared(hosted, b.action)) then
      -- The primary's chord is Return, the key a person presses, the way the action bar spells it,
      -- whichever held chord it also sits on. The secondary's is its own, Command and Return.
      local chord = obj.chordFor(b, deps)
      if b.shared == "primary" then chord = (glyphFor and glyphFor("return")) or "return" end
      -- Every row carries an icon. A primary or a secondary naming none takes Olm's own, declared
      -- beside Back in the action panel's manifest and read against it.
      local icon, iconOwner = b.icon, owner and owner[contextName]
      if icon == nil and (b.shared == "primary" or b.shared == "secondary") then
        icon, iconOwner = b.shared, deps and deps.panelOwner
      end
      local closes
      if hosted then
        local owner = deps and deps.owners and deps.owners[contextName]
        local owned = owner and plan.effective[owner]
        local description = owned and owned.description
        chord = chord .. " in " .. (description or contextName)
        closes = hosted[b.action].closes
      end
      rows[#rows + 1] = { action = b.action, title = obj.labelFor(b, contextName, deps and deps.liveLabels, labels),
                          chord = chord, icon = icon, owner = iconOwner, closes = closes }
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
-- own admission. The primary action is navigation, and so are the two move keys, close and the
-- action panel chord, each a binding lib/surface.lua built for a shared verb and marked with it
-- as shared, and recognised by the fixed names GENERIC_NAV above too. A block built by hand that
-- marks no shared verb has its first binding taken as the primary, which is where lib/surface.lua
-- puts it, since the person's lists section may free the primary key and leave an extra first.
-- Every other binding a context carries came from that plugin's own surface.extra, so it is a verb.
--
-- kinds, when given, is a caller supplied table merged in last, an override rather than
-- another vote, for the rare action this derivation could not classify correctly on its own.
--
-- A shared binding's classification is weak. A shared verb's action is a plugin's own name, a
-- primary or a secondary, so one list's secondary may share its name with another list's extra
-- verb, and a navigation answer for it would hide that verb from the other list's action panel.
-- So every binding that is not shared is classified first, and a shared binding only fills an
-- action no other binding classified, never shadowing a verb and never recorded as a conflict.
--
-- The second return value lists every action name two different unshared bindings classified
-- two different ways before the override was applied, which can only happen when one plugin's
-- extra reuses a name another plugin's hand built block gave a different role, since the
-- derivation itself is otherwise a pure function of a binding's position and its own action name.
function obj.actionKinds(plan, kinds)
  local out, conflicts = {}, {}
  local weak = {}
  for _, ctx in pairs(plan.contexts or {}) do
    local marked = false
    for _, b in ipairs(ctx.bindings) do
      if b.shared ~= nil then marked = true break end
    end
    for i, b in ipairs(ctx.bindings) do
      if b.shared ~= nil then
        weak[#weak + 1] = b.action
      else
        local kind
        if GENERIC_NAV[b.action] then
          kind = "navigation"
        elseif i == 1 and not marked then
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
  end
  for _, action in ipairs(weak) do
    if out[action] == nil then out[action] = "navigation" end
  end
  for name, kind in pairs(kinds or {}) do
    out[name] = kind
  end
  return out, conflicts
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

--- hints.sheetRows(keymap, plan, leader, deps) -> entries
--- Every global chord the keymap holds on one leader, in the order a leader's cheat sheet draws
--- them, as plain entries { key, mods, action, description, when, group, app, owner }. Since phase 4 of
--- the keymap plan one sheet host draws every held leader, so this one rule serves them all. It
--- reads the keymap rather than the registry and the plan, so a tool's open key, a host's, a
--- plugin's bindings, a host's own actions among them, all reach a sheet through the one table that binds
--- them, and nothing here reads a key off a manifest field. A row the person's keymap set is one
--- of these sources too, the source of the action it runs, so it is ordered where that action's
--- own default would be.
---
--- The order is the one the Hyper sheet has always drawn. Every registered tool first, in
--- registration order, which is the order the keymap's bound list holds tool rows in. Then,
--- walking the plan order, each plugin's host key and then its own bindings in their declared
--- order. A chord already listed is not listed twice, identity being the key and the
--- modifiers, since two rows may share a key with different modifiers, screenshot and screenshot
--- to the clipboard. The lists' own keys are left out, since they are not global keys.
---
--- A row's label is the binding's own description, else the descriptor's, which the keymap
--- already merged into row.description, else a tool's registry detail or its name, a host's
--- directory, or the action name spelled out as words. A row standing for an app and stating no
--- description is left without one, since the sheet names it by the app's own name, which only
--- the sheet resolves. deps.registry, optional, lends a tool row
--- with no description the detail its launcher row wears. Entries are copies, so a caller
--- stamping something onto one cannot reach back into the keymap. Must be called once the keymap
--- is built, after register, or this answers an empty list.
function obj.sheetRows(keymap, plan, leader, deps)
  deps = deps or {}
  local registry = deps.registry
  local out, seen = {}, {}

  local function add(row, label)
    if row.key == nil then return end
    local mods = row.shownMods
    local mark = tostring(row.key) .. "/" .. table.concat(mods or {}, "+")
    if seen[mark] then return end
    seen[mark] = true
    out[#out + 1] = { key = row.key, mods = mods, action = row.action, description = label,
      when = row.when, group = row.group, app = row.app, owner = row.owner }
  end

  local rows = {}
  for _, row in ipairs((keymap or {}).bound or {}) do
    if row.leader ~= nil and row.leader == leader and row.layer == "global" then rows[#rows + 1] = row end
  end

  for _, row in ipairs(rows) do
    if row.source == "tool" then
      local reg = registry and registry.rowFor and registry.rowFor(row.owner)
      -- A detail may be a resolved function for a row whose subtitle is computed at open time,
      -- and an overlay label wants the stable words, so only a plain string is borrowed.
      local detail = reg and type(reg.detail) == "string" and reg.detail or nil
      add(row, row.description or detail or row.owner)
    end
  end

  local directoryOf = {}
  for _, directory in ipairs((plan or {}).order or {}) do
    directoryOf[(plan.identity or {})[directory] or directory] = directory
  end
  for _, directory in ipairs((plan or {}).order or {}) do
    for _, source in ipairs({ "host", "bindings" }) do
      for _, row in ipairs(rows) do
        if row.source == source and directoryOf[row.owner] == directory then
          local fallback = source == "host" and directory or humanize(row.action)
          if row.app ~= nil and source == "bindings" then fallback = nil end
          add(row, row.description or fallback)
        end
      end
    end
  end

  return out
end

--- hints.keyEntries(keymap, plan, deps) -> entries
--- Every chord the keymap binds, as a person reads it, for a page listing a person's keys. Each
--- entry is { chord, description, owner, list }, every field a string but list, which names the
--- list a list key is live in and is nil for a global key. It reads the keymap the root built and
--- never the person's file, and it answers words only, so whatever shows them learns no key to bind.
---
--- The global keys come first, a leader at a time in deps.leaders order, each in the order its
--- cheat sheet draws them and labelled the way the sheet labels them, since sheetRows answers both,
--- then the plain combinations with no leader. A row the binder leaves unbound, refused or quiet, is
--- left out, which is whatever deps.bindable refuses, lib/binder.lua's own test. Then every list's own keys, a list at a time in plan order, each in the order its
--- bindings are declared, which is the order the key panel under a list shows them.
---
--- A chord is a leader's word and the glyph through deps.chordLabel, the spelling the launcher and
--- the action bar use, and a plain combination is the glyph alone, as the launcher spells one. A row
--- standing for an app with no description of its own is named by deps.appName, else its action
--- spelled out as words, where a sheet would draw the app instead. An owner is named by its own
--- description, else its manifest's about title, else its identity.
---
---   leaders       held and named leaders in the order their keys are listed, by the name a row
---                 spells its leader with. A leader not listed has its keys left out.
---   leaderNames   that name to the word a person reads, Hyper or Meta.
---   bindable      required, a row to whether the binder binds it, lib/binder.lua's bindable.
---   chordLabel    the shared speller, glyphFor the shared glyph helper.
---   manifests     directory to manifest, for the owner's about title and which plugin owns a list.
---   registry      optional, lends a tool row with no description its launcher detail.
---   appName       optional, a bundle id to the app's own name.
function obj.keyEntries(keymap, plan, deps)
  deps = deps or {}
  plan = plan or {}
  local leaderNames = deps.leaderNames or {}
  local manifests = deps.manifests or {}
  local directoryOf = {}
  for _, directory in ipairs(plan.order or {}) do
    directoryOf[(plan.identity or {})[directory] or directory] = directory
  end
  local function ownerName(identity)
    local directory = directoryOf[identity] or identity
    local description = ((plan.effective or {})[directory] or {}).description
    if type(description) == "string" and description ~= "" then return description end
    local title = ((manifests[directory] or {}).about or {}).title
    if type(title) == "string" and title ~= "" then return title end
    return tostring(identity)
  end
  local function chordOf(leader, key, mods)
    local word = leader and leaderNames[leader]
    if word and deps.chordLabel then return deps.chordLabel(word, key, mods) end
    if deps.glyphFor then return deps.glyphFor(key, mods) end
    return tostring(key)
  end

  local out = {}
  local live = {}
  local bindable = assert(deps.bindable, "keyEntries needs deps.bindable, the binder's own test")
  for _, row in ipairs((keymap or {}).bound or {}) do
    if bindable(row) then live[#live + 1] = row end
  end
  local liveKeymap = { bound = live }
  local leaders = {}
  for _, name in ipairs(deps.leaders or {}) do leaders[#leaders + 1] = name end
  leaders[#leaders + 1] = false
  for _, leader in ipairs(leaders) do
    local entries
    if leader then
      entries = obj.sheetRows(liveKeymap, plan, leader, { registry = deps.registry })
    else
      -- The plain combinations, which no sheet draws, in the order the binder binds them, labelled
      -- by the same rule.
      entries = {}
      for _, row in ipairs(live) do
        if row.leader == nil and row.layer == "global" then
          entries[#entries + 1] = { key = row.key, mods = row.shownMods, action = row.action,
            description = row.description, app = row.app, owner = row.owner }
        end
      end
    end
    for _, e in ipairs(entries) do
      local description = e.description
      if description == nil and e.app ~= nil and deps.appName then
        local name = deps.appName(e.app)
        if type(name) == "string" and name ~= "" then description = name end
      end
      out[#out + 1] = { chord = chordOf(leader or nil, e.key, e.mods),
        description = description or humanize(e.action), owner = ownerName(e.owner) }
    end
  end

  local listOwners = obj.contextOwners(plan, manifests)
  local listsByDirectory = {}
  for listName, directory in pairs(listOwners) do listsByDirectory[directory] = listName end
  for _, directory in ipairs(plan.order or {}) do
    local listName = listsByDirectory[directory]
    local block = listName and (plan.contexts or {})[listName]
    if block then
      -- Each list key at the place its action is first declared, one action's two keys by key.
      local place = {}
      for i, b in ipairs(block.bindings or {}) do
        if b.action ~= nil and place[b.action] == nil then place[b.action] = i end
      end
      local rows = {}
      for _, row in ipairs((keymap or {}).rows or {}) do
        if row.layer == listName then rows[#rows + 1] = row end
      end
      local function placeOf(row) return place[row.action] or math.huge end
      table.sort(rows, function(a, b)
        local pa, pb = placeOf(a), placeOf(b)
        if pa ~= pb then return pa < pb end
        return tostring(a.key) < tostring(b.key)
      end)
      local name = ownerName(directory)
      for _, row in ipairs(rows) do
        out[#out + 1] = { chord = chordOf(row.leader, row.key, row.shownMods),
          description = row.description or humanize(row.action), owner = name, list = name }
      end
    end
  end
  return out
end

--- hints.hostKeyBinding(eff, module, claimed) -> role, key, mods or nil
--- The one rule for a host that carries a key. Anything with an open bindings row and a way to
--- be shown, that the registry did not already claim, has that row bound on its leader, since a
--- host is not a registered tool and nothing else binds it. It answers the leader role and the
--- key and modifiers to bind, or nil when the rule does not apply. The root decides which engine
--- a role reaches, and the keymap reads the same answer, so the rule is written once.
function obj.hostKeyBinding(eff, module, claimed)
  if type(eff) ~= "table" or claimed then return nil end
  if not module or type(module.show) ~= "function" then return nil end
  for _, b in ipairs(eff.bindings or {}) do
    if type(b) == "table" and b.action == "open" and b.key ~= nil and b.leader ~= false then
      local role = b.leader or eff.leader
      if role then return role, b.key, b.mods end
      return nil
    end
  end
  return nil
end

return obj
