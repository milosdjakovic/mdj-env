--- === DockAutoHide ===
---
--- Turn the Dock's own auto hide setting on or off, and read whether it is on right now.
--- No chooser and no picker, one launcher row is the whole surface. It lost its standalone
--- hotkey when it moved into Olm, and it gained `rowTitle`, which answers the wording for
--- that row from live state, so the launcher can show what pressing it will do rather than
--- only the state the Dock is in.
---
--- Neither tool it shells out to is named as a bare command. `configure` receives the
--- shared dependency scope and resolves `defaults` and `osascript` through it, so this file
--- never hardcodes a path and never probes for one on its own.
---
--- This is the olm side plugin built from Spoons/DockAutoHide.spoon, moved in on the dock
--- plugin packet of 2026-08-09. See this plugin's own CLAUDE.md for why both external calls
--- stay, an empirical finding rather than a guess.

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
--- asks it for the two tools declared beside this file rather than naming a path itself.
function obj:configure(opts)
  opts = opts or {}
  local deps = opts.deps
  self._defaults = deps and deps.path("defaults") or nil
  self._osascript = deps and deps.path("osascript") or nil
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
--- Flip whatever the current state is.
function obj:toggle()
  if self:isEnabled() then
    self:disable()
  else
    self:enable()
  end
  return self
end

--- DockAutoHide:rowTitle() -> string
--- Method
--- The launcher row's wording, read from live state. Names the action the row is about to
--- take rather than the state the Dock happens to be in, so choosing the row never asks
--- anyone to work out the opposite of what it says. This is the only place either string is
--- written, reached through the launcher's injected title provider seam rather than by the
--- launcher knowing a Dock exists.
function obj:rowTitle()
  if self:isEnabled() then
    return "Turn Dock Hiding Off"
  end
  return "Turn Dock Hiding On"
end

return obj
