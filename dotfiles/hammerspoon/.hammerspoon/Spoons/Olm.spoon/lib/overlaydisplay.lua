-- The overlay display policy resolver.
--
-- This is a lib factory rather than a plugin because two shared atoms, the Chooser
-- and the CanvasPanel, each need a screen function before any plugin has loaded,
-- and a plugin only exists once the wiring stages run. So the composition root
-- builds one instance of this module first, wires self.screen into both atoms as a
-- closure that calls through the instance, and only then starts the plugin
-- pipeline.
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
--- deps.chooser        the shared Chooser factory, deps.chooser.new(config) builds the
---                      picker. Optional. Without it the mode and pin picker is never
---                      built and self.show, self.isShowing, and self.surface stay
---                      safe no ops, while self.screen keeps resolving a screen
---                      regardless, since the picker and the resolver are two
---                      separate things sharing one store.
--- deps.canvasPanel     the shared CanvasPanel atom. Accepted for parity with the
---                      deps shape every shared collaborator arrives through, and
---                      held on the instance for whatever a caller may want it for
---                      later. The ported picker below has no call site for it, its
---                      row icons are plain hs.canvas glyphs rather than a docked
---                      surface, so this file does not invent one.
--- deps.theme           the shared chooser theme, handed straight to deps.chooser.new.
--- deps.panel           the docked shortcut panel triple for this picker's own
---                      context, onPositioned, onActivity, onClose, built by the
---                      composition root the same way every other picker's is.
--- deps.currentProfile  a function with no arguments answering the active display
---                      arrangement's name, or nil when nothing matches. Read fresh
---                      every time a screen is resolved or the picker is opened,
---                      never cached, since the arrangement changes under both.
--- deps.displayplacer   the resolved absolute path to displayplacer, or nil when the machine
---                      has none. Passed in rather than named in a command here, because this
---                      module is not a dependency door and the composition root declares the
---                      tool on its behalf. Only fixed mode needs it, so nil costs the serial
---                      id bridge and nothing else.
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

  -- The picker, built lazily by configure. Declared here, ahead of the surface
  -- adapter below, so the adapter's closures capture this same upvalue and always
  -- see whatever the variable currently holds rather than whatever it held when the
  -- adapter was built.
  local picker
  local nav = { view = "root" }
  local reopenTimer

  -- Dot called navigation adapter over the colon called Chooser instance, so the
  -- shared navigation routing drives this picker like every other one. Built once,
  -- since every function inside it reads the picker upvalue at call time rather
  -- than closing over its current value, it stays correct across a configure that
  -- rebuilds the picker and it stays safe to call before the first configure at
  -- all, answering the same as a closed picker would.
  local surfaceAdapter = {
    isShowing = function() return (picker ~= nil) and picker:isShowing() or false end,
    selectNext = function() if picker then picker:selectNext() end end,
    selectPrev = function() if picker then picker:selectPrev() end end,
    insertSelected = function() if picker then picker:insertSelected() end end,
    hide = function() if picker then picker:hide() end end,
  }

  --- self.surface()
  --- Returns the navigation adapter above. A function rather than the table
  --- itself, matching the other lib surfaces, though the table it hands back is
  --- built once and always the same one.
  function self.surface()
    return surfaceAdapter
  end

  --- self.isShowing()
  --- Whether the picker is on screen right now. False when no picker has been
  --- built yet, which is the honest answer rather than an error.
  function self.isShowing()
    return surfaceAdapter.isShowing()
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

  -- Build the current view's rows, then filter by the typed query, a plain case
  -- folded substring test over the title and the subtitle, matching how a filter
  -- mode field behaves everywhere else this picker opts out of the shared matcher.
  -- The query is not remembered across a view change, so it clears on every drill.
  local function buildRows(query)
    local out = {}
    if nav.view == "root" then
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
    elseif nav.view == "pin" then
      out[#out + 1] = { title = "Back", image = emojiIcon(ICON_BACK), item = { nav = "root" } }
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
    end
    local q = (query or ""):lower()
    if q == "" then return out end
    local filtered = {}
    for _, r in ipairs(out) do
      local hay = ((r.title or "") .. " " .. (r.subTitle or "")):lower()
      if hay:find(q, 1, true) then filtered[#filtered + 1] = r end
    end
    return filtered
  end

  -- hs.chooser dismisses on every select, so a drill or a commit that should leave
  -- the picker open records the target view and reopens on a short timer, the same
  -- idiom menu search uses. The handle lives on the instance rather than a bare
  -- local, since a Hammerspoon timer nothing refers to can be collected before it
  -- fires, which is the one rule every timer in this config follows.
  local function reopen()
    if self._reopenTimer then self._reopenTimer:stop() end
    self._reopenTimer = hs.timer.doAfter(0.04, function()
      self._reopenTimer = nil
      if picker then picker:show() end
    end)
  end

  local function onSelect(item)
    if not item then return end
    if item.nav then
      nav = { view = item.nav }
      reopen()
    elseif item.commit == "mode" then
      local s = storeValue()
      s.mode = item.mode
      hs.settings.set(STORE_KEY, s)
      nav = { view = "root" } -- committed, the picker is left to close
    elseif item.commit == "pin" then
      -- Setting a pin is configuration only, it never touches the active mode,
      -- which is chosen separately from the root view, so pinning a display never
      -- silently switches where overlays appear.
      local s = storeValue()
      s.fixed = s.fixed or {}
      s.fixed[item.profile] = item.serial
      hs.settings.set(STORE_KEY, s)
      reopen() -- stay on the pin view so the new highlight is visible
    end
  end

  --- self.configure(opts)
  --- opts.mode   the seed mode, one of the M.modes values, defaulting to activeWindow.
  --- opts.fixed  the seed pin map, arrangement name to serial id, defaulting to empty.
  --- Seeds the fallback policy, arms the screen watcher that invalidates the serial
  --- cache and refreshes the remembered names on a display change, and builds the
  --- mode and pin picker when deps.chooser was supplied. Safe to call again, an
  --- earlier watcher and an earlier picker are torn down first rather than leaked.
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

    if picker then picker:hide() end
    if deps.chooser then
      local triple = deps.panel or {}
      picker = deps.chooser.new({
        theme = deps.theme,
        placeholder = "Overlay display",
        fieldMode = deps.chooser.fieldModes.filter,
        -- A drill in menu whose supplier morphs its rows per view and does its own
        -- substring filter in buildRows, so it opts out of the atom's own matcher.
        -- Leaving the shared matcher in would rerank the morphing rows and could
        -- hide the Back row.
        matcher = false,
        rows = buildRows,
        onSelect = onSelect,
        onPositioned = triple.onPositioned,
        onActivity = triple.onActivity,
        onClose = triple.onClose,
      })
    else
      picker = nil
      log.i("configure received no deps.chooser, the mode and pin picker will not be built")
    end

    return self
  end

  --- self.show()
  --- Opens the picker on its root view. A safe no op when configure was never
  --- given a chooser factory, since there is nothing to show.
  function self.show()
    nav = { view = "root" }
    if picker then picker:show() end
    return self
  end

  --- self.stop()
  --- Stops the screen watcher and any pending reopen timer, and hides the picker
  --- if it is open. Both handles are read off the instance, since either being held
  --- only in a bare local would let it be collected while still needed.
  function self.stop()
    if self._reopenTimer then
      self._reopenTimer:stop()
      self._reopenTimer = nil
    end
    if self._watcher then
      self._watcher:stop()
      self._watcher = nil
    end
    if picker then picker:hide() end
    return self
  end

  return self
end

return M
