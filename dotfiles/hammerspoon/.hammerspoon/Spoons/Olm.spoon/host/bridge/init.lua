-- Bridge, the Lua side of Olm.app, step 1.2 of docs/PLAN-STANDALONE.md.
--
-- It answers one question for the root, serves(identity), which is the function a tool's open key
-- runs instead of its own while Olm.app serves that tool on this machine, or nil to leave the key
-- alone. Olm.app serves a tool here when this machine's olmapp piece is on, the app is built where
-- src/setup-olmapp.sh puts it and the open tool resolved. Each condition that fails is said once in
-- the console, so a key that still opens the Lua list says why.
--
-- The key opens the app's list with `open -g`, which hands the URL to the app without bringing it
-- forward, since its chooser is a panel that takes key without activating the app. It runs as a
-- task, so a slow LaunchServices never holds the main thread, and the task's handle is kept until
-- it ends, since a task nothing refers to can be collected before it runs.

local obj = {}
obj.__index = obj

obj.name = "Bridge"
obj.version = "0.1"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("Bridge", "info")

-- Which tools Olm.app serves is the person's config, config/plugins.lua, since only that and a
-- plugin may name a plugin. A served tool's open key hands the app olm://<identity lowercased>,
-- docs/PROTOCOL-BRIDGE.md, file search's being olm://filesearch.
local function urlFor(identity) return "olm://" .. identity:lower() .. "?query=" end

local APP = os.getenv("HOME") .. "/.olm/app/Olm.app"

obj._pieces = {}
obj._serves = {}
obj._deps = nil
obj._tasks = {}
obj._said = {}

function obj:configure(opts)
  opts = opts or {}
  if type(opts.pieces) == "table" then self._pieces = opts.pieces end
  if type(opts.serves) == "table" then
    self._serves = {}
    for _, identity in ipairs(opts.serves) do
      if type(identity) == "string" and identity:match("^%a%w*$") then self._serves[identity] = true end
    end
  end
  if opts.deps ~= nil then self._deps = opts.deps end
  if opts.app ~= nil then self._app = opts.app end
  return self
end

local function sayOnce(self, why)
  if self._said[why] then return end
  self._said[why] = true
  log.i(why)
end

-- Whether Olm.app takes keys on this machine, and the open command when it does.
function obj:_ready()
  if self._pieces.olmapp ~= "on" then return nil end
  local app = self._app or APP
  if not hs.fs.attributes(app, "mode") then
    sayOnce(self, "the olmapp piece is on and " .. app .. " is not built, so every key opens the Lua list, src/setup-olmapp.sh builds it")
    return nil
  end
  local open = self._deps and self._deps.path and self._deps.path("open")
  if not open then
    sayOnce(self, "the olmapp piece is on and open did not resolve, so every key opens the Lua list")
    return nil
  end
  return open, app
end

--- obj:serves(identity) -> function or nil
--- The function the identity's open key runs while Olm.app serves it here, or nil.
function obj:serves(identity)
  -- The piece first and the identity after, so what is asked does not depend on a tool's name.
  local open, app = self:_ready()
  if not open then return nil end
  if type(identity) ~= "string" or not self._serves[identity] then return nil end
  local url = urlFor(identity)
  sayOnce(self, identity .. "'s open key opens Olm.app, the olmapp piece is on")
  return function()
    local task
    task = hs.task.new(open, function(code, _, err)
      self._tasks[task] = nil
      if code ~= 0 then log.w("Olm.app did not take " .. url .. ", " .. tostring(err)) end
    end, { "-g", "-a", app, url })
    if task then
      self._tasks[task] = true
      task:start()
    end
  end
end

return obj
