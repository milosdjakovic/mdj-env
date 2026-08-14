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

--- TmuxSessions.providers - the terminal backends, exposed by reference so a person who
--- wants a different set or a different order can name them, the same shape BrowserTabs
--- uses for its browsers.
obj.providers = {
  ghostty = load("providers/ghostty.lua"),
  terminal = load("providers/terminal.lua"),
  iterm = load("providers/iterm.lua"),
  alacritty = load("providers/alacritty.lua"),
  wezterm = load("providers/wezterm.lua"),
}

--- The order used when nothing else is given, which is what makes this tool work on a
--- machine whose owner has said nothing about terminals. Ghostty leads because it is the
--- one most likely to be deliberately installed, Terminal and iTerm follow since both carry
--- their own AppleScript dictionary and need nothing handed in, and the two CLI based ones
--- come last since each needs a path resolved before it can attach.
obj._defaultProviders = {
  obj.providers.ghostty,
  obj.providers.terminal,
  obj.providers.iterm,
  obj.providers.alacritty,
  obj.providers.wezterm,
}

function obj:init()
  self.engine:init()
  return self
end

--- TmuxSessions:configure(opts) delegates to the engine, opts.deps and opts.providers,
--- since the spoon carries no state of its own beyond the engine's.
---
--- Two things are settled here first rather than by whoever configures this, and both moved
--- in from the composition root when this became a plugin that declares itself. The chain
--- falls back to this plugin's own order, so a fresh install lists sessions without anyone
--- having named a terminal. And the two backends that carry no AppleScript dictionary are
--- handed the one path they need, resolved out of the dependency scope this plugin was
--- already given, because which of its own providers wants what is this plugin's business
--- and nobody else's. A root that had to know that would have to be edited every time a
--- provider is added, which is exactly the edit a new file should not cost.
function obj:configure(opts)
  opts = opts or {}
  local chain = opts.providers or self._defaultProviders

  local openPath = opts.deps and opts.deps.path and opts.deps.path("open")
  if openPath then
    self.providers.alacritty.configure({ open = openPath })
    self.providers.wezterm.configure({ open = openPath })
  end

  self.engine:configure({ deps = opts.deps, providers = chain })

  -- The two things this plugin's own picker needs that no manifest could hand it. The engine
  -- is this plugin's own, a self reference nothing outside could name, and the message sink is
  -- a plain macOS alert, used for the one thing this tool ever has to say, a jump that failed.
  -- A landed jump is silent by design, so this is a failure that stopped an action rather than
  -- routine feedback, which is why it stays an alert rather than a shared surface.
  --
  -- Set here rather than in the picker's own configure step so whoever composes this can still
  -- override either one, since that step merges its options over these rather than replacing.
  self.chooser.configure({
    api = self.engine,
    onMessage = function(text) hs.alert.show(text) end,
  })

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
