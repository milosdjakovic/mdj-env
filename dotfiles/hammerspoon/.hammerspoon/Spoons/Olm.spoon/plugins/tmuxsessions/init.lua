--- === TmuxSessions ===
---
--- Lists every tmux session and jumps to one, launcher only with no dedicated key. Two
--- things this depends on: tmux running its own server independent of any terminal, which
--- is what makes listing possible from Hammerspoon at all, and one retarget primitive,
--- tmux's own switch-client, the exact mechanism the tmux session strip built for this same
--- dotfiles repo already uses.
---
--- Follows the DisplayProfiles shape, a spoon composed of an engine (the tmux mechanism,
--- knows nothing about a picker) and a chooser (pure command policy over an injected api),
--- configured twice by the composition root, the spoon then the chooser. Terminal backends
--- are swappable providers, the BrowserTabs shape, named and ordered by the root and
--- validated against one contract, so a new terminal is a new file plus one line.

local obj = {}
obj.__index = obj

obj.name = "TmuxSessions"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Load siblings by absolute path off this file's own location, the loadfile pattern the
-- spoons use since a spoon directory is not on package.path.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("TmuxSessions: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

obj.engine = load("engine.lua")
obj.chooser = load("chooser.lua")

--- TmuxSessions.providers - the terminal backends, exposed by reference so the composition
--- root names the concrete terminals and their order, the same shape BrowserTabs uses for
--- its browsers.
obj.providers = {
  ghostty = load("providers/ghostty.lua"),
  terminal = load("providers/terminal.lua"),
  iterm = load("providers/iterm.lua"),
  alacritty = load("providers/alacritty.lua"),
  wezterm = load("providers/wezterm.lua"),
}

function obj:init()
  self.engine:init()
  return self
end

--- TmuxSessions:configure(opts) delegates straight to the engine, opts.deps and
--- opts.providers, since the spoon carries no state of its own beyond the engine's.
function obj:configure(opts)
  self.engine:configure(opts)
  return self
end

function obj:available()
  return self.engine:available()
end

function obj:isShowing()
  return self.chooser.isShowing()
end

function obj:show()
  self.chooser.show()
end

return obj
