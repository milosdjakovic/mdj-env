--- === LinkRouter ===
---
--- Routes a clicked link to a destination you pick, instead of to whichever browser macOS was
--- last told to send everything to. Hammerspoon holds the system handler for http and https,
--- every link on the machine arrives here, and this list is what decides where it goes.
---
--- A destination is finer than an application. A Chromium browser expands into one entry per
--- profile, and a second entry per profile for a private window, so Chrome with three profiles
--- offers six things you may show. Everything else is one entry. That difference is the
--- providers' business, never this file's.
---
--- There are no keyboard shortcuts here beyond the shared navigation keys. Everything is an
--- ordinary row you choose. Showing a destination and placing it in the order are the same
--- single act, choosing it on the configuration page, which appends it to the list, so picking
--- Safari then Chrome (Milos) then Chrome (Vicert) produces exactly that order and nothing has
--- to be remembered.
---
--- ROWS CARRY PLAIN DATA ONLY. A chooser row is serialised to native objects, so an entry must
--- never be put into one, since an entry holds a reference to its provider and a provider's
--- methods are functions that cannot be converted. Doing it makes the ENTIRE list fail to parse
--- and the chooser renders completely empty, with the reason visible only in the console. That
--- is not hypothetical, it shipped and it is what a row carrying only an id now prevents.
---
--- Two entry points share one registered presentation, because the composition root publishes
--- stagePresent(name) and nothing that hands the stage an arbitrary page, so an identity has
--- exactly one top level list. A waiting link makes it the router. No waiting link makes it the
--- configuration page. onPresent rewords the field for whichever just became current, and
--- onClose drops the waiting link so it can never be answered by a window opened later.

local M = {}

local log = hs.logger.new("LinkRouter", "info")

-- Loaded by path rather than required, since the spoon directory is not on the module path.
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local contract = dofile(here .. "contract.lua")
local engine = dofile(here .. "engine.lua")

-- The provider chain, in the order the engine asks them. Order is the whole policy here.
-- chromium claims only what proves to be Chromium by reading its own state file, and plain
-- claims everything, so plain must be last or nothing else would ever be asked.
local providers = {
  dofile(here .. "providers/chromium.lua"),
  dofile(here .. "providers/plain.lua"),
}

local cfg = {}

-- The link waiting to be routed, set by the urlevent callback immediately before it asks for
-- the stage and cleared the moment the window goes. Nil means the configuration page.
local pending = nil
-- The bundle id of the application the link was clicked in, when macOS told us.
local pendingApp = nil
-- Child presentation tables, kept only so a redraw can name the level it belongs to rather
-- than landing on whatever happens to be current.
local rulesChild = nil
local ruleTargetChild = nil
local moreChild = nil

--------------------------------------------------------------------------------
-- Row building
--------------------------------------------------------------------------------

local glyphCache = {}
local function emojiImage(str)
  if not str then return nil end
  local hit = glyphCache[str]
  if hit ~= nil then return hit or nil end
  local size = 28
  local cv = hs.canvas.new({ x = 0, y = 0, w = size, h = size })
  cv[1] = { type = "text", text = str, textSize = 21, textAlignment = "center",
            frame = { x = 0, y = 0, w = size, h = size } }
  local img = cv:imageFromCanvas()
  cv:delete()
  glyphCache[str] = img or false
  return img
end

local ICON_COPY = "📋"
local ICON_RULES = "⚡"
local ICON_BACK = "⬅️"
local ICON_ON = "🟢"
local ICON_OFF = "🔴"
local ICON_MORE = "➕"
local ICON_RESET = "↩️"

--- row(...) -> a chooser row
--- item must contain plain data only. See the file header for what putting an entry in one
--- costs, which is the whole list.
local function row(title, subTitle, image, item, enabled)
  return { title = title, subTitle = subTitle, image = image, item = item, enabled = enabled }
end

local function appIcon(bundle)
  local ok, img = pcall(hs.image.imageFromAppBundle, bundle)
  if ok then return img end
  return nil
end

--------------------------------------------------------------------------------
-- The router, the list a waiting link is answered from
--------------------------------------------------------------------------------

local function routerRows()
  local rows = {}
  for _, e in ipairs(engine.shown()) do
    rows[#rows + 1] = row(e.label, nil, appIcon(e.bundle), { open = e.id }, true)
  end
  if #rows == 0 then
    rows[#rows + 1] = row("Nothing is set to be shown here",
      "open Link routing from the launcher and choose your destinations",
      emojiImage(ICON_OFF), nil, false)
  end
  -- Everything not in the main list sits one level down rather than being unreachable, so a
  -- short list costs nothing. Only offered when there is genuinely something behind it.
  local rest = engine.hidden()
  if #rest > 0 then
    rows[#rows + 1] = row("More", #rest == 1 and "1 more destination" or (#rest .. " more destinations"),
      emojiImage(ICON_MORE), { nav = "more" }, true)
  end
  rows[#rows + 1] = row("Copy link", pending, emojiImage(ICON_COPY), { copy = true }, true)
  local host = engine.hostOf(pending)
  if host then
    rows[#rows + 1] = row("Always open " .. host .. " somewhere",
      "choose the destination on the next screen", emojiImage(ICON_RULES),
      { nav = "ruleTarget" }, true)
  end
  return rows
end

--------------------------------------------------------------------------------
-- The More page, a child of the router holding everything not in the main list
--------------------------------------------------------------------------------

local function moreRows()
  local rows = { row("Back", nil, emojiImage(ICON_BACK), { nav = "back" }, true) }
  for _, e in ipairs(engine.hidden()) do
    rows[#rows + 1] = row(e.label, nil, appIcon(e.bundle), { open = e.id }, true)
  end
  return rows
end

local function buildMoreChild()
  local child
  child = {
    placeholder = "Open this link in",
    -- No matcher declared, so the shared fuzzy strategy filters. Declaring false here would
    -- mean the widget does not filter at all, and since these rows ignore the query the list
    -- would simply not respond to typing, which is exactly what it did until somebody tried it.
    -- This is a destination picker and typing two letters of a browser name is the fastest way
    -- to answer it, so search matters more than keeping the Back row visible while typing.
    rows = moreRows,
    -- Opening from here finishes the interaction exactly as opening from the main list does, so
    -- this level completes rather than intercepting, and the window hides on its own.
    onSelect = function(item)
      if not item then return nil end
      if item.open then
        local entry = engine.entryById(item.open)
        if entry and pending and not engine.open(entry, pending) then
          hs.alert.show("Could not open the link in " .. tostring(entry.label))
        end
      end
      return nil
    end,
    intercept = function(item)
      if item.nav == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      return false
    end,
  }
  moreChild = child
  return child
end

--------------------------------------------------------------------------------
-- The rule target page, a child of the router
--------------------------------------------------------------------------------

local function ruleTargetRows()
  local host = engine.hostOf(pending) or "this site"
  local rows = { row("Back", nil, emojiImage(ICON_BACK), { nav = "back" }, true) }
  for _, e in ipairs(engine.shown()) do
    rows[#rows + 1] = row(e.label, "always open " .. host .. " here",
      appIcon(e.bundle), { rule = e.id }, true)
  end
  return rows
end

local function buildRuleTargetChild()
  local child
  child = {
    placeholder = "Always open this site in",
    -- Filters, for the same reason the More page does, this is a destination picker too.
    rows = ruleTargetRows,
    onSelect = function() end,
    intercept = function(item)
      if item.nav == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      if item.rule then
        local host = engine.hostOf(pending)
        local entry = engine.entryById(item.rule)
        if host and entry then
          engine.addRule("host", host, item.rule)
          if not engine.open(entry, pending) then
            hs.alert.show("Could not open the link in " .. tostring(entry.label))
          end
        end
        if cfg.stageHide then cfg.stageHide() end
        return true
      end
      return false
    end,
  }
  ruleTargetChild = child
  return child
end

--------------------------------------------------------------------------------
-- The rules page, a child of the configuration page
--------------------------------------------------------------------------------

local function ruleWords(r)
  local target = engine.entryById(r.entry)
  local where = target and target.label or "a destination this machine no longer has"
  if r.kind == "host" then return "Links on " .. r.value, "open in " .. where end
  local name = hs.application.nameForBundleID(r.value) or r.value
  return "Links from " .. name, "open in " .. where
end

local function rulesRows()
  local rows = { row("Back", nil, emojiImage(ICON_BACK), { nav = "back" }, true) }
  local live = engine.rules()
  if #live == 0 then
    rows[#rows + 1] = row("No rules yet",
      "make one while a link is waiting, from the bottom of that list",
      emojiImage(ICON_RULES), nil, false)
    return rows
  end
  for i, r in ipairs(live) do
    local title, words = ruleWords(r)
    rows[#rows + 1] = row(title, words .. ", choose to delete",
      emojiImage(ICON_RULES), { ruleIndex = i }, true)
  end
  return rows
end

local function buildRulesChild()
  local child
  child = {
    placeholder = "Link routing rules",
    -- Filters too, so a long rule list stays answerable by typing a site name.
    rows = rulesRows,
    onSelect = function() end,
    intercept = function(item)
      if item.nav == "back" then
        if cfg.stagePop then cfg.stagePop() end
        return true
      end
      if item.ruleIndex then
        -- Deleting mutates the list it stands on, so the page stays open and rebuilds with the
        -- rule gone. The redraw names this child by its own table, so the answer lands on this
        -- level or not at all.
        engine.removeRule(item.ruleIndex)
        if cfg.redrawPresented then cfg.redrawPresented("linkRouter", false, child) end
        return "stay"
      end
      return false
    end,
  }
  rulesChild = child
  return child
end

--------------------------------------------------------------------------------
-- The configuration page, the list the launcher row opens
--------------------------------------------------------------------------------

local function handlerRow()
  if engine.holdsHandler() then
    local first = engine.shown()[1]
    local words = first and ("links go back to " .. first.label)
      or "nothing is shown to hand them back to"
    return row("Links open through this list", words, emojiImage(ICON_ON),
      { handler = "release" }, true)
  end
  return row("Links open through this list", "links currently open somewhere else",
    emojiImage(ICON_OFF), { handler = "claim" }, true)
end

local function rulesRow()
  local count = #engine.rules()
  local words = count == 0 and "none yet"
    or (count == 1 and "1 rule" or (count .. " rules"))
  return row("Rules", words, emojiImage(ICON_RULES), { nav = "rules" }, true)
end

--- configRows()
--- Everything this machine can reach, shown destinations first in their own order and numbered,
--- then everything else. The number IS the position in the router, so the page reads as the
--- list it produces rather than as a set of flags you then have to arrange separately.
local function configRows()
  local rows = { handlerRow(), rulesRow() }
  -- Appending is the only way an entry joins the main list, so moving one already in it means
  -- emptying the list and picking again in the order wanted. This row is what makes that an
  -- offered action rather than something a person has to work out by removing rows one at a
  -- time. Always present, since starting over is as meaningful from the built in default as it
  -- is from an arrangement somebody already made.
  rows[#rows + 1] = row("Start over",
    "empty the main list, then choose destinations in the order you want them",
    emojiImage(ICON_RESET), { reset = true }, true)
  local all = engine.all()
  if #all == 0 then
    rows[#rows + 1] = row("This machine has no other application that opens links", nil,
      emojiImage(ICON_OFF), nil, false)
    return rows
  end
  local on, off = {}, {}
  for _, e in ipairs(all) do
    local at = engine.position(e.id)
    if at then on[#on + 1] = { e = e, at = at } else off[#off + 1] = e end
  end
  table.sort(on, function(a, b) return a.at < b.at end)
  for _, hit in ipairs(on) do
    rows[#rows + 1] = row(hit.at .. ". " .. hit.e.label, "in the main list, choose to remove it",
      appIcon(hit.e.bundle), { toggle = hit.e.id }, true)
  end
  for _, e in ipairs(off) do
    rows[#rows + 1] = row(e.label, "under More, choose to add it to the end of the main list",
      appIcon(e.bundle), { toggle = e.id }, true)
  end
  return rows
end

--------------------------------------------------------------------------------
-- The presentation
--------------------------------------------------------------------------------

function M.rows()
  if pending then return routerRows() end
  return configRows()
end

--- M.intercept(item) -> "stay", true, or false
--- The configuration page's own rows mutate the page they stand on, so they answer "stay",
--- which rebuilds with the numbers moved and holds the highlight on the row just chosen.
--- Leaving is the person's own Backspace or Escape. The router's rows fall through to select,
--- since routing a link genuinely finishes the interaction.
function M.intercept(item)
  if not item then return false end
  if item.toggle then
    engine.toggleShown(item.toggle)
    if cfg.redrawPresented then cfg.redrawPresented("linkRouter") end
    return "stay"
  end
  if item.handler then
    engine.claimHandler(item.handler)
    if cfg.redrawPresented then cfg.redrawPresented("linkRouter") end
    return "stay"
  end
  if item.reset then
    engine.clearShown()
    if cfg.redrawPresented then cfg.redrawPresented("linkRouter") end
    return "stay"
  end
  return false
end

--- M.select(item) -> presentation or nil
--- A row answering a table pushes a child. Everything else completes and the window hides.
function M.select(item)
  if not item then return nil end
  if item.nav == "rules" then return buildRulesChild() end
  if item.nav == "ruleTarget" then return buildRuleTargetChild() end
  if item.nav == "more" then return buildMoreChild() end
  if item.open then
    local entry = engine.entryById(item.open)
    if entry and pending then
      if not engine.open(entry, pending) then
        hs.alert.show("Could not open the link in " .. tostring(entry.label))
      end
    end
  end
  if item.copy and pending then
    hs.pasteboard.setContents(pending)
    if cfg.stageHide then cfg.stageHide() end
  end
  return nil
end

function M.placeholder()
  return "Link routing"
end

--- M.onPresent()
--- Told whenever this level becomes current, through present or push, never on a pop. The
--- provider caches are dropped here so a profile added or renamed in a browser appears without
--- a reload, and this is the one moment that can be done without paying for it per keystroke.
function M.onPresent()
  engine.refresh()
  if not cfg.stageSetPlaceholder then return end
  cfg.stageSetPlaceholder(pending and ("Open " .. pending) or "Link routing")
end

function M.onClose()
  pending = nil
  pendingApp = nil
end

function M.show()
  pending = nil
  pendingApp = nil
  if cfg.stagePresent then cfg.stagePresent("linkRouter") end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function M:init()
  return self
end

--- M:configure(opts)
--- opts.stagePresent        required, the door a clicked link reaches the shared stage through.
--- opts.stageSetPlaceholder optional, the field wording for whichever list is live.
--- opts.stageHide           optional, taking the window down after a copy or a new rule.
--- opts.redrawPresented     optional, moving the numbers after a configuration row is chosen.
--- opts.stagePop            optional, the door a child level's own Back row leaves through.
--- opts.deps                the dependency adapter, handed to the engine for the one provider
---                          that needs an external binary.
function M:configure(opts)
  opts = opts or {}
  cfg.stagePresent = opts.stagePresent
  cfg.stageSetPlaceholder = opts.stageSetPlaceholder
  cfg.stageHide = opts.stageHide
  cfg.redrawPresented = opts.redrawPresented
  cfg.stagePop = opts.stagePop
  engine.configure({ providers = providers, contract = contract, deps = opts.deps })
  return self
end

--- M:start()
--- Installs the callback. The system handler is deliberately not claimed here. A claim is a
--- LaunchServices change that outlives a reload on its own, so there is nothing to reclaim, and
--- macOS puts up a confirmation panel for every claim.
function M:start()
  hs.urlevent.httpCallback = function(_, _, _, fullURL, senderPID)
    if not fullURL then return end

    -- Who sent it, when macOS says. The callback documents the sending pid as unavailable in
    -- some cases and spells that as -1, and the lookup is protected because a link is far too
    -- expensive to lose to a raise in something only a rule would have used.
    local sender = nil
    if senderPID and senderPID ~= -1 then
      local ok, app = pcall(hs.application.applicationForPID, senderPID)
      if ok and app then
        local gotId, id = pcall(function() return app:bundleID() end)
        sender = gotId and id or nil
      end
    end

    -- The rules are asked before anything is shown, which is the whole point of a rule.
    local routed = engine.routeFor(fullURL, sender)
    if routed then
      if not engine.open(routed, fullURL) then
        hs.alert.show("Could not open the link in " .. tostring(routed.label))
      end
      return
    end

    pending = fullURL
    pendingApp = sender
    if cfg.stagePresent then
      cfg.stagePresent("linkRouter")
    else
      log.e("a link arrived with no stage to offer it on, it has been dropped")
    end
  end
  return self
end

return M
