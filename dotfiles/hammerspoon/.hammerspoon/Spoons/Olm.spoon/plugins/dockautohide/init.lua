--- === DockAutoHide ===
---
--- Turn the Dock's own auto hide setting on or off, and switch its show delay between
--- instant and the macOS default. Reached from the launcher as a page with two rows, hiding
--- first then delay, and it owns every string those rows show. No chooser and no picker of
--- its own, the page is a QueryScope scope the composition root registers.
---
--- Hiding and delay apply themselves differently, and that difference is empirical rather
--- than a style choice. Hiding is felt at once because the running Dock is told about it
--- through System Events. The delay has no such lever, so a delay change is invisible until
--- the Dock re reads its preferences, which is what restarting it after a delay change is
--- for. See this plugin's own CLAUDE.md for the finding behind both.
---
--- Neither tool it shells out to is named as a bare command. `configure` receives the
--- shared dependency scope and resolves `defaults`, `osascript`, and `killall` through it,
--- so this file never hardcodes a path and never probes for one on its own.
---
--- This is the olm side plugin built from Spoons/DockAutoHide.spoon, moved in on the dock
--- plugin packet of 2026-08-09 and turned into a page on the dock page packet of the same
--- date's later work.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "DockAutoHide"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Injected via configure
obj._defaults = nil  -- resolved absolute path to the defaults tool, nil when it is not present
obj._osascript = nil -- resolved absolute path to the osascript tool, nil when it is not present
obj._killall = nil   -- resolved absolute path to the killall tool, nil when it is not present

--- DockAutoHide:init()
--- Method
--- Initialize the plugin. No collaborator is wired yet, that waits for configure.
function obj:init()
  return self
end

--- DockAutoHide:configure(opts)
--- Method
--- Wire the dependency scope. opts.deps is the per consumer adapter from Olm's shared
--- resolver, the same `depsFor("Olm")` every sibling plugin's wiring site reads, and this
--- asks it for the three tools declared beside this file rather than naming a path itself.
function obj:configure(opts)
  opts = opts or {}
  local deps = opts.deps
  self._defaults = deps and deps.path("defaults") or nil
  self._osascript = deps and deps.path("osascript") or nil
  self._killall = deps and deps.path("killall") or nil
  return self
end

--- DockAutoHide:isEnabled() -> bool
--- Method
--- Whether the Dock currently auto hides. False when the resolved tool is missing, the
--- same silent degradation every optional feature in this config takes, since a missing
--- system binary here would mean something else is badly wrong with the machine.
function obj:isEnabled()
  if not self._defaults then return false end
  local output = hs.execute('"' .. self._defaults .. '" read com.apple.dock autohide 2>/dev/null')
  return output:match("1") ~= nil
end

--- DockAutoHide:enable()
--- Method
--- Turn Dock auto hide on. Writes the preference and then tells the running Dock about it
--- through System Events, both calls kept because either alone was proven insufficient, see
--- this plugin's own CLAUDE.md for the finding.
function obj:enable()
  if self._defaults then
    hs.execute('"' .. self._defaults .. '" write com.apple.dock autohide -bool true')
  end
  if self._osascript then
    hs.execute('"' .. self._osascript ..
      [[" -e 'tell application "System Events" to tell dock preferences to set autohide to true']])
  end
  return self
end

--- DockAutoHide:disable()
--- Method
--- Turn Dock auto hide off. The same pair of calls as enable, in reverse.
function obj:disable()
  if self._defaults then
    hs.execute('"' .. self._defaults .. '" write com.apple.dock autohide -bool false')
  end
  if self._osascript then
    hs.execute('"' .. self._osascript ..
      [[" -e 'tell application "System Events" to tell dock preferences to set autohide to false']])
  end
  return self
end

--- DockAutoHide:toggle()
--- Method
--- Flip whatever the hiding state currently is.
function obj:toggle()
  if self:isEnabled() then
    self:disable()
  else
    self:enable()
  end
  return self
end

--- DockAutoHide:delayIsInstant() -> bool
--- Method
--- Whether the Dock's show delay is currently instant, meaning the autohide-delay key is
--- present and reads zero. False when the resolved tool is missing, the same silent
--- degradation every optional feature here takes, and false on the genuine default machine
--- too, where the key is absent rather than zero, which reads the same as any other value
--- that is not the instant one.
function obj:delayIsInstant()
  if not self._defaults then return false end
  local output = hs.execute('"' .. self._defaults .. '" read com.apple.dock autohide-delay 2>/dev/null')
  return tonumber(output) == 0
end

--- DockAutoHide:_restartDock()
--- Method
--- Ask the running Dock to relaunch, so it re reads whatever was just written to its
--- preferences. macOS brings it straight back, the same way any other agent process
--- restarts after `killall`. This is the only door the delay has, System Events has no
--- delay property to push through, see this plugin's own CLAUDE.md for the finding.
function obj:_restartDock()
  if self._killall then
    hs.execute('"' .. self._killall .. '" Dock')
  end
end

--- DockAutoHide:makeDelayInstant()
--- Method
--- Write the show delay to zero and restart the Dock so the change is actually seen.
function obj:makeDelayInstant()
  if self._defaults then
    hs.execute('"' .. self._defaults .. '" write com.apple.dock autohide-delay -int 0')
  end
  self:_restartDock()
  return self
end

--- DockAutoHide:restoreDefaultDelay()
--- Method
--- Delete the show delay key rather than writing a number, since the original value is
--- unknowable on a machine where it has already been overridden and an absent key is the
--- genuine default state. Restarts the Dock so the change is actually seen.
function obj:restoreDefaultDelay()
  if self._defaults then
    hs.execute('"' .. self._defaults .. '" delete com.apple.dock autohide-delay')
  end
  self:_restartDock()
  return self
end

--- DockAutoHide:toggleDelay()
--- Method
--- Flip whatever the delay state currently is.
function obj:toggleDelay()
  if self:delayIsInstant() then
    self:restoreDefaultDelay()
  else
    self:makeDelayInstant()
  end
  return self
end

--- DockAutoHide:rows() -> rows
--- Method
--- The two rows this page shows, hiding first then delay, as the user asked. Each row's
--- title names the action choosing it takes rather than the state the Dock happens to be
--- in, so choosing it never asks anyone to work out the opposite of what it says. Rebuilt
--- fresh on every call, since nothing in a QueryScope page is ever cached, so the wording
--- is always exactly current rather than one open stale.
function obj:rows()
  local hidingTitle = self:isEnabled() and "Turn Dock Hiding Off" or "Turn Dock Hiding On"
  local delayTitle = self:delayIsInstant() and "Restore the Default Dock Delay" or "Make the Dock Instant"
  return {
    {
      title = hidingTitle,
      subTitle = "applies right away",
      glyph = "🗄️",
      item = "hiding",
    },
    {
      title = delayTitle,
      subTitle = "restarts the Dock to apply",
      glyph = "⏱️",
      item = "delay",
    },
  }
end

--- DockAutoHide:act(kind)
--- Method
--- Carry out whichever row named itself, "hiding" or "delay". The scope's own act, routed
--- home by QueryScope so the chooser stays open and the rows above are rebuilt with the
--- wording current again.
function obj:act(kind)
  if kind == "hiding" then
    self:toggle()
  elseif kind == "delay" then
    self:toggleDelay()
  end
end

return obj
