-- The overlay display policy resolver.
--
-- This is a lib factory rather than a plugin because two shared atoms, the Chooser
-- and the CanvasPanel, each need a screen function before any plugin has loaded,
-- and a plugin only exists once the wiring stages run. So the composition root
-- builds one instance of this module first, wires self.screen into both atoms as a
-- closure that calls through the instance, and only then starts the plugin
-- pipeline.
--
-- Migrated onto host/stage, contract v3, docs/BRIEF-CONTRACT-V3.md. The mode and pin
-- picker used to be a fourteenth Chooser.new instance the root itself owned, consumer map
-- surprise 9.1, unnavigable and with a dead docked panel, surprise 9.2, since nothing ever
-- put its own hand rolled surface into the nav registry and nothing ever supplied it a
-- panel triple. Having no manifest, it cannot declare a presentation the ordinary way
-- either, so root/compose.lua builds the presentation table by hand and hands it to
-- Stage:present directly from the same launcher special row that always opened this tool,
-- root policy over a lib module needing no manifest to still reach the shared stage. This
-- module now exposes self.rows and self.select in exactly the shape a presentation wants,
-- root and pin views alike, and root/compose.lua is the one file that wraps them into the
-- table Stage:present takes. The picker mechanically works exactly as before, Return, a
-- click, and Escape all reach it through the atom's own native behaviour, unrelated to any
-- manifest, and the docked panel now arms and positions itself for this presentation the
-- identical way it does for every other one, since host/stage's own panel resolver asks
-- only Stage:current(), never a manifest. What still does not follow from being on the
-- stage is j and k, which are bound per Hyper context from plan.contexts, itself built
-- from a manifest.surface declaration this module has none of, so this migration leaves
-- that half of surprise 9.2 exactly where it was rather than claiming a fix it cannot
-- reach without a manifest to declare a context in.
--
-- Pin drills into its own presentation, contract v3's child mechanism, decision one,
-- pushed the moment the Pin row is chosen and popped through cfg.stagePop, decision three's
-- reserved intercept case, the identical shape displayprofiles' own levels use. A commit,
-- writing the chosen mode or pin to hs.settings, either completes for real, closing the
-- whole tool the way choosing a mode always has, or stands on the pin level with the new
-- choice marked, the identical two outcomes onSelect's own retired commit branches always
-- gave, reached now through intercept rather than a private reopen timer.
--
-- Strategy is the shape of the resolver. A small table maps a mode name to a
-- function returning an hs.screen, opts.mode names the seed choice, and a runtime
-- picker can move the live choice from whichever mode was seeded to another one
-- with no reload. Neither atom, and nothing that calls self.screen, needs to know
-- the caller is a chooser or a canvas panel, only that a screen comes back.
--
-- Ported from the live root's overlay display block. Two things changed on
-- purpose rather than by accident. First, every read of config/settings.lua is
-- replaced by opts handed to configure or by deps handed to new, since this module
-- carries no config file of its own. Second, and this is the one place the port is
-- not a straight copy, the live picker lets a person browse every saved display
-- profile and set a pin for each of them, and that list comes from a plugin this
-- module is forbidden to name. Only the active arrangement's own name is handed in,
-- through deps.currentProfile, so the picker configures a pin for the arrangement a
-- person is standing in right now rather than browsing a roster this module has no
-- way to ask for. That is also the one arrangement worth testing a pin against at
-- the moment it is being set, so the loss is smaller than it first sounds.

local M = {}

local log = hs.logger.new("OverlayDisplay", "info")

-- The mode names, exposed on the module table for the same reason
-- config/settings.lua used to export overlayModes, so a caller building the seed
-- opts for configure names a mode once and a typo becomes a nil reference here
-- rather than a silently wrong string carried all the way to the resolver table.
local MODE_ACTIVE_WINDOW = "activeWindow"
local MODE_CURSOR = "cursor"
local MODE_FIXED = "fixed"
M.modes = {
  activeWindow = MODE_ACTIVE_WINDOW,
  cursor = MODE_CURSOR,
  fixed = MODE_FIXED,
}

--- M.new(deps) returns instance.
--- deps.canvasPanel     the shared CanvasPanel atom. Accepted for parity with the
---                      deps shape every shared collaborator arrives through, and
---                      held on the instance for whatever a caller may want it for
---                      later. Nothing in this file has a call site for it, its
---                      row icons are plain hs.canvas glyphs rather than a docked
---                      surface, so this file does not invent one.
--- deps.currentProfile  a function with no arguments answering the active display
---                      arrangement's name, or nil when nothing matches. Read fresh
---                      every time a screen is resolved or a row is built, never
---                      cached, since the arrangement changes under both.
--- deps.displayplacer   the resolved absolute path to displayplacer, or nil when the machine
---                      has none. Passed in rather than named in a command here, because this
---                      module is not a dependency door and the composition root declares the
---                      tool on its behalf. Only fixed mode needs it, so nil costs the serial
---                      id bridge and nothing else.
--- deps.stagePop        contract v3's own addition, docs/BRIEF-CONTRACT-V3.md, a function of
---                      no arguments asking the shared stage to leave the pin level and
---                      restore root, the one thing a child pushed from self.select cannot
---                      express on its own. Optional, and its absence leaves the Back row
---                      inert rather than raising, the identical degradation every other
---                      root published word this migration reaches for already keeps.
function M.new(deps)
  deps = deps or {}

  local self = {}
  self._canvasPanel = deps.canvasPanel
  self._displayplacer = deps.displayplacer

  -- The runtime store keys, kept local rather than read from a config table, since
  -- a fresh install needs somewhere for a picker choice to persist before any
  -- config file exists to name one, and nothing outside this file ever reads them.
  local STORE_KEY = "overlayDisplayPolicy" -- { mode, fixed = { [arrangement] = serial } }
  local NAMES_KEY = "overlayDisplayNames"  -- remembered { [id] = friendly name }

  -- The seed policy handed to configure, config/settings.lua's own overlayDisplay
  -- block in the live root. Defaulted here so self.screen answers something sane
  -- even the moment this instance is built, before configure has run at all.
  local seed = { mode = MODE_ACTIVE_WINDOW, fixed = {} }

  local function activeWindowScreen()
    local w = hs.window.focusedWindow()
    return (w and w:screen()) or hs.screen.mainScreen() or hs.screen.primaryScreen()
  end
  local function cursorScreen()
    return hs.mouse.getCurrentScreen() or hs.screen.primaryScreen()
  end

  -- The persisted choice, layered over the seed. A picker commit writes here, under
  -- one hs.settings key, so the choice survives a reload and a reboot the same way
  -- the launcher's own remembered order does. effectiveMode and effectiveFixed read
  -- the stored value first and fall back to the seed, so a picker choice takes
  -- effect on the next screen resolve with no reload, and an unset key still honours
  -- whatever configure was seeded with.
  local function storeValue()
    return hs.settings.get(STORE_KEY) or {}
  end
  local function effectiveMode()
    return storeValue().mode or seed.mode
  end
  local function effectiveFixed(profile)
    if not profile then return nil end
    local stored = storeValue()
    local fromStore = stored.fixed and stored.fixed[profile]
    if fromStore then return fromStore end
    return (seed.fixed or {})[profile]
  end

  -- Fixed mode turns a displayplacer serial id into a live hs.screen. hs.screen
  -- exposes no serial id of its own, so the bridge shells out to displayplacer
  -- once, caches the two way map, and clears it on a screen change. Keeping serial
  -- ids as the currency here, rather than switching to hs.screen's own persistent
  -- id, matters because a fixed mode seed a person writes by hand names the same
  -- serial ids the display arrangement config already uses, and a live picker
  -- choice should read and write that identical format.
  local serialToUUID = nil -- serial id to persistent id, the CoreGraphics display UUID
  local uuidToSerial = nil -- the reverse, so an attached screen resolves to its serial
  local function refreshSerialMap()
    serialToUUID, uuidToSerial = {}, {}
    -- No tool, no map, and both directions stay empty. Fixed mode then resolves no screen and
    -- falls back to the active window exactly as an unpinned arrangement already does, which is
    -- why the root declares this one optional.
    if not self._displayplacer then return end
    local out = hs.execute(self._displayplacer .. " list", true) or ""
    local persistent, serial
    local function flush()
      if serial and persistent then
        serialToUUID[serial] = persistent
        uuidToSerial[persistent] = serial
      end
    end
    for line in (out .. "\n"):gmatch("(.-)\n") do
      local p = line:match("Persistent screen id:%s*(%S+)")
      local s = line:match("Serial screen id:%s*(%S+)")
      if p then
        flush() -- close the previous screen block before starting this one
        persistent, serial = p, nil
      elseif s then
        serial = s
      end
    end
    flush()
  end
  local function screenForSerial(serial)
    if not serial then return nil end
    if not serialToUUID then refreshSerialMap() end
    local uuid = serialToUUID[serial]
    if not uuid then return nil end
    for _, s in ipairs(hs.screen.allScreens()) do
      if s:getUUID() == uuid then return s end
    end
    return nil
  end

  -- Remembered display names, so a detached display still reads by its friendly
  -- name rather than by a bare serial. hs.screen names a display only while it is
  -- attached, so every attached screen's name is captured against its serial
  -- whenever the display set changes and read back for a detached one later.
  local function rememberAttachedNames()
    if not uuidToSerial then refreshSerialMap() end
    local names = hs.settings.get(NAMES_KEY) or {}
    local changed = false
    for _, s in ipairs(hs.screen.allScreens()) do
      local serial = uuidToSerial[s:getUUID() or ""]
      local nm = s:name()
      if serial and nm and names[serial] ~= nm then
        names[serial] = nm
        changed = true
      end
    end
    if changed then hs.settings.set(NAMES_KEY, names) end
  end
  -- The friendly name for a serial, attached or not, the live hs.screen name when
  -- it is plugged in, else the remembered name, else the raw id so nothing shows
  -- blank.
  local function displayName(id)
    local screen = screenForSerial(id)
    if screen then return screen:name() end
    local names = hs.settings.get(NAMES_KEY) or {}
    return names[id] or id
  end

  -- The fixed warning fires once per arrangement rather than on every resolve, so
  -- an unpinned or stale serial does not flood the console on every overlay open.
  local fixedWarned = false
  local function fixedScreen()
    local profile = deps.currentProfile and deps.currentProfile()
    local serial = effectiveFixed(profile)
    local screen = serial and screenForSerial(serial)
    if screen then return screen end
    if not fixedWarned then
      fixedWarned = true
      log.w(string.format(
        "fixed mode has no display for arrangement '%s' (serial '%s'), using active window",
        tostring(profile), tostring(serial)))
    end
    return activeWindowScreen()
  end

  -- Keyed by the same mode constants exported above, so the valid mode names live
  -- in one place and self.screen cannot drift from the picker that writes them.
  local strategies = {
    [MODE_ACTIVE_WINDOW] = activeWindowScreen,
    [MODE_CURSOR] = cursorScreen,
    [MODE_FIXED] = fixedScreen,
  }

  --- self.screen()
  --- The injected contract every atom reads. Resolves the effective mode fresh on
  --- every call, the persisted picker choice when there is one, else the seed, so a
  --- mode switch takes effect on the next overlay with no reload. Tolerates being
  --- called before configure has run, since the seed default above already answers
  --- activeWindow, and falls back to the primary screen when a resolver still comes
  --- back with nothing.
  function self.screen()
    local fn = strategies[effectiveMode()] or activeWindowScreen
    return fn() or hs.screen.primaryScreen()
  end

  -- Row labels and glyphs for the picker's two views, root and pin. Icons are
  -- emoji rendered to a small image once and cached, matching how the launcher and
  -- the emoji picker build their own row icons, since this Hammerspoon exposes no
  -- SF Symbol api to draw from instead.
  local MODE_LABEL = {
    [MODE_CURSOR] = "Follow mouse cursor",
    [MODE_ACTIVE_WINDOW] = "Follow active window",
    [MODE_FIXED] = "Pin to a display",
  }
  local MODE_ICON = {
    [MODE_CURSOR] = "🖱️",
    [MODE_ACTIVE_WINDOW] = "🎯",
    [MODE_FIXED] = "📌",
  }
  local ICON_SELECTED, ICON_BACK, ICON_CONFIG, ICON_DISPLAY = "🟢", "⬅️", "⚙️", "🖥️"
  local iconCache = {}
  local function emojiIcon(glyph)
    if not glyph then return nil end
    if iconCache[glyph] == nil then
      local size = 72
      local c = hs.canvas.new({ x = 0, y = 0, w = size, h = size })
      c[1] = { type = "text", text = glyph, textSize = 52, textAlignment = "center",
               frame = { x = "0%", y = "8%", w = "100%", h = "100%" } }
      iconCache[glyph] = c:imageFromCanvas() or false
      c:delete()
    end
    return iconCache[glyph] or nil
  end

  -- The short status line under the root row that leads into pin mode, read fresh
  -- on every build rather than cached, since both the arrangement and its pin can
  -- change while the picker sits closed.
  local function pinStatusLine()
    local profile = deps.currentProfile and deps.currentProfile()
    if not profile then return "No display arrangement recognised" end
    local serial = effectiveFixed(profile)
    if not serial then return "Pinned to nothing yet" end
    return "Pinned to " .. displayName(serial)
  end

  -- Filter a built row list by the typed query, a plain case folded substring test over
  -- the title and the subtitle, matching how a filter mode field behaves everywhere else
  -- this picker opts out of the shared matcher. Shared by both views' own row builder below
  -- rather than folded into either, since the two now live as two separate presentations,
  -- root and pin, contract v3, rather than one supplier switching on a shared nav.view.
  local function filterRows(out, query)
    local q = (query or ""):lower()
    if q == "" then return out end
    local filtered = {}
    for _, r in ipairs(out) do
      local hay = ((r.title or "") .. " " .. (r.subTitle or "")):lower()
      if hay:find(q, 1, true) then filtered[#filtered + 1] = r end
    end
    return filtered
  end

  -- The root view's own rows, the three modes plus the door into pin. Public, named on the
  -- presentation table root/compose.lua builds by hand, root policy over a lib module
  -- needing no manifest to declare one the ordinary way.
  function self.rows(query)
    local out = {}
    local mode = effectiveMode()
    for _, m in ipairs({ MODE_CURSOR, MODE_ACTIVE_WINDOW, MODE_FIXED }) do
      out[#out + 1] = {
        title = MODE_LABEL[m],
        image = emojiIcon(mode == m and ICON_SELECTED or MODE_ICON[m]),
        item = { commit = "mode", mode = m },
      }
    end
    out[#out + 1] = {
      title = "Pin this display setup…",
      subTitle = pinStatusLine(),
      image = emojiIcon(ICON_CONFIG),
      item = { nav = "pin" },
    }
    return filterRows(out, query)
  end

  -- The pin view's own rows, the Back row leading per the chooser menu convention, then
  -- one row per attached display when an arrangement is recognised.
  local function pinRows(query)
    local out = { { title = "Back", image = emojiIcon(ICON_BACK), item = { nav = "root" } } }
    local profile = deps.currentProfile and deps.currentProfile()
    if not profile then
      out[#out + 1] = {
        title = "No display arrangement recognised",
        enabled = false,
        subTitle = "There is nothing to pin a display to right now",
      }
    else
      local chosen = effectiveFixed(profile)
      if not uuidToSerial then refreshSerialMap() end
      for _, s in ipairs(hs.screen.allScreens()) do
        local serial = uuidToSerial[s:getUUID() or ""] or s:getUUID()
        out[#out + 1] = {
          title = s:name(),
          subTitle = serial,
          image = emojiIcon(chosen == serial and ICON_SELECTED or ICON_DISPLAY),
          item = { commit = "pin", profile = profile, serial = serial },
        }
      end
    end
    return filterRows(out, query)
  end

  -- The pin level, a child of root, contract v3, built lazily the moment the Pin row is
  -- chosen and pushed by host/stage. Back leaves through cfg.stagePop, decision three's
  -- reserved intercept case, and choosing a display is the identical case, writing the
  -- pin and standing on the same level with the new choice marked rather than leaving,
  -- the retired onSelect's own commit == "pin" branch reached the same way Back is now
  -- rather than through its own private reopen timer.
  local function buildPinPresentation()
    return {
      placeholder = "Overlay display",
      matcher = false,
      rows = pinRows,
      onSelect = function() end,
      intercept = function(item)
        if not item then return true end
        if item.nav == "root" then
          if deps.stagePop then deps.stagePop() end
          return true
        end
        if item.commit == "pin" then
          -- Setting a pin is configuration only, it never touches the active mode,
          -- which is chosen separately from the root view, so pinning a display never
          -- silently switches where overlays appear.
          local s = storeValue()
          s.fixed = s.fixed or {}
          s.fixed[item.profile] = item.serial
          hs.settings.set(STORE_KEY, s)
          return true
        end
        return false
      end,
    }
  end

  --- self.select(item) -> presentation or nil
  --- The root view's own onSelect, public for the identical reason self.rows is. The Pin
  --- row drills into buildPinPresentation above, a genuine child, decision one, host/stage
  --- pushing whatever comes back. Choosing a mode is a genuine completion instead, writing
  --- the choice and answering nothing, the ordinary meaning this contract gives nil, the
  --- whole tool closing exactly as choosing a mode always has.
  function self.select(item)
    if not item then return nil end
    if item.nav == "pin" then return buildPinPresentation() end
    if item.commit == "mode" then
      local s = storeValue()
      s.mode = item.mode
      hs.settings.set(STORE_KEY, s)
      return nil
    end
    return nil
  end

  --- self.configure(opts)
  --- opts.mode   the seed mode, one of the M.modes values, defaulting to activeWindow.
  --- opts.fixed  the seed pin map, arrangement name to serial id, defaulting to empty.
  --- Seeds the fallback policy and arms the screen watcher that invalidates the serial
  --- cache and refreshes the remembered names on a display change. Safe to call again,
  --- an earlier watcher is stopped first rather than leaked. Builds no picker any more,
  --- the trickle migration, root/compose.lua building the one shared instance's own
  --- presentation table instead of asking this file for a Chooser factory.
  function self.configure(opts)
    opts = opts or {}
    seed.mode = opts.mode or MODE_ACTIVE_WINDOW
    seed.fixed = opts.fixed or {}

    if self._watcher then self._watcher:stop() end
    self._watcher = hs.screen.watcher.new(function()
      serialToUUID, uuidToSerial = nil, nil
      fixedWarned = false
      rememberAttachedNames()
    end)
    self._watcher:start()
    rememberAttachedNames() -- seed from whatever is attached right now

    return self
  end

  --- self.stop()
  --- Stops the screen watcher. Held off the instance, since a bare local would let it be
  --- collected while still needed. Builds no picker any more, the trickle migration, so
  --- there is nothing left here to hide, root/compose.lua's own cfg.stageHide reaching the
  --- shared instance instead on whatever path this tool is ever torn down from.
  function self.stop()
    if self._watcher then
      self._watcher:stop()
      self._watcher = nil
    end
    return self
  end

  return self
end

return M
