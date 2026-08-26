--- === TmuxSessions.engine ===
---
--- Talks to the tmux server directly, the mechanism with no picker in it. tmux runs its own
--- server detached from any terminal window, so every read here works whether or not a
--- terminal is even open, and jumping to a session is tmux's own switch-client rather than
--- anything invented here, the exact primitive dotfiles/tmux's own session strip already
--- uses.
---
--- Two shapes are genuinely different and both are handled, decided by whether tmux
--- itself reports any attached client at all. Something already attached means some
--- terminal window, wherever it is, is showing a tmux client right now, so that client is
--- simply retargeted with switch-client, and the terminal is brought forward. Nothing
--- attached anywhere means there is no window to retarget, so the configured terminal
--- provider is asked to open a fresh one that attaches on arrival.
---
--- What this does not attempt, on purpose. It never asks which physical window a client's
--- tty belongs to, so when more than one terminal application is running at once it
--- cannot tell which one actually holds the attached client, and falls back to raising
--- whichever provider is currently configured. That is the right tradeoff for the ordinary
--- habit of one terminal window at a time, and the wrong one for running several terminal
--- apps concurrently each pinned to a different session, a case this does not solve.

local obj = {}
obj.__index = obj

obj.name = "TmuxSessions.engine"

local log = hs.logger.new("TmuxSessions", "info")

local enginePath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local contract = loadfile(enginePath .. "contract.lua")()

obj._tmux = nil          -- resolved absolute path to the tmux binary, injected via configure
obj._providers = nil     -- ordered, validated list of terminal providers
obj._recency = nil       -- Olm.lib.recency instance remembering which window was jumped to

-- The default sits on the field rather than inside configure, because configure now only ever
-- writes what it was actually handed, so a default applied there would never run for a caller
-- that had nothing to say about this.
obj._settingsKey = "TmuxSessions.terminal"

-- The last read of the tmux server, { at = nanoseconds, sessions = ... }, and how long one
-- stays good for. See _cachedSessions below for why this exists and what it is not.
obj._read = nil
obj._readTTL = 1.0

function obj:init()
  return self
end

--- TmuxSessions.engine:configure(opts)
--- opts.deps is the per consumer dependency scope, opts.providers the ordered terminal
--- backends, each validated against contract.lua before being kept. opts.recency is an
--- Olm.lib.recency instance, and leaving it out leaves windows() in plain session-then-index
--- order with nothing remembered.
---
--- Every field is written only when it was actually given, which is the whole point and is
--- what changed here. This is called twice by design, once by the plugin with the provider
--- chain it alone decides, and once by Olm's own wiring with the ambient services the
--- plugin's manifest earned, and neither caller knows the other's fields. The version that
--- reset all four on every call could not be called twice, so the plugin had to relay the
--- ambient half by hand, restating each field by name in a table it wrote itself. That list
--- is where recency went missing for the whole life of this plugin, and no list to forget a
--- name from is the only fix that holds.
function obj:configure(opts)
  opts = opts or {}

  if opts.deps ~= nil then self._tmux = opts.deps.path("tmux") end
  if opts.settingsKey ~= nil then self._settingsKey = opts.settingsKey end
  if opts.recency ~= nil then self._recency = opts.recency end

  if opts.providers ~= nil then
    local ok = {}
    for _, p in ipairs(opts.providers) do
      local valid, missing = contract.validate(p)
      if valid then
        ok[#ok + 1] = p
      else
        log.w("dropping a terminal provider, it does not implement " .. tostring(missing))
      end
    end
    self._providers = ok
  end

  return self
end

--- TmuxSessions.engine:available() -> tmux itself resolved, so there is a server worth
--- asking at all. False leaves the root free to not wire the whole tool.
function obj:available()
  return self._tmux ~= nil
end

local function shq(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- The field separator between tmux -F columns. Measured rather than assumed: hs.execute
-- hands back every control byte, a real tab included, sanitized to an underscore, so a
-- session or window that genuinely ended in a digit read as one joined, mangled name.
-- Pipe is the same choice processes/sources/docker.lua already made for its own -F style
-- output, for what is presumably the same reason.
local FIELD_SEP = "|"

-- Run a tmux subcommand and split each line on FIELD_SEP. A bare failure, no server
-- running because nothing has ever been started, is not treated as an error, it is
-- simply an empty answer.
function obj:_run(args)
  if not self._tmux then return {} end
  local output, ok = hs.execute('"' .. self._tmux .. '" ' .. args)
  if not ok or not output then return {} end
  local rows = {}
  for line in output:gmatch("[^\n]+") do
    local fields = {}
    for field in (line .. FIELD_SEP):gmatch("(.-)" .. FIELD_SEP) do
      fields[#fields + 1] = field
    end
    rows[#rows + 1] = fields
  end
  return rows
end

--- TmuxSessions.engine:sessions() -> ordered list of
--- { name, attached, windows = { { index, name, active } } }.
--- One round trip for the sessions and one for every window across all of them, rather
--- than one call per session, since this feeds a list that is rebuilt on every keystroke.
function obj:sessions()
  local order, byName = {}, {}
  local sessionFields = "#{session_name}" .. FIELD_SEP .. "#{session_attached}"
  for _, f in ipairs(self:_run("list-sessions -F '" .. sessionFields .. "'")) do
    local name = f[1]
    if name and name ~= "" and not byName[name] then
      local s = { name = name, attached = f[2] == "1", windows = {} }
      byName[name] = s
      order[#order + 1] = s
    end
  end
  local windowFields = "#{session_name}" .. FIELD_SEP .. "#{window_index}" .. FIELD_SEP
    .. "#{window_name}" .. FIELD_SEP .. "#{window_active}"
  for _, f in ipairs(self:_run("list-windows -a -F '" .. windowFields .. "'")) do
    local s = byName[f[1]]
    if s then
      table.insert(s.windows, { index = f[2], name = f[3], active = f[4] == "1" })
    end
  end
  return order
end

--- TmuxSessions.engine:invalidate() throws away the last read, so the next question goes to
--- the tmux server. Opening the picker calls this, since a deliberate open is exactly the
--- moment a person expects to be shown what is true right now.
function obj:invalidate()
  self._read = nil
end

-- A read of the tmux server, reused for a moment rather than repeated. Two shell calls cost
-- about twenty two milliseconds together, and the list they feed is rebuilt on every keystroke
-- by both this plugin's own picker and the launcher's hosted list, so every character typed
-- was paying for two fresh round trips to answer a question whose answer had not changed.
--
-- This caches the READ and never the ordering. Recency is applied over the result on every
-- call in windows() below, because a jump touches the remembered order and a cached ordering
-- would then be wrong in a way a cached read never is.
--
-- A window lifetime rather than a lifecycle, and the hosted list is the reason. This plugin's
-- own picker has an open and a close to hang freshness on, and invalidate above is called from
-- exactly there. The launcher's hosted rows have neither, it simply asks for rows on every
-- keystroke forever, so there is no moment there that could stand for now. A second is long
-- enough to cover a burst of typing and short enough that a session started in another window
-- shows up before anyone could finish reaching for it.
function obj:_cachedSessions()
  local now = hs.timer.absoluteTime()
  local last = self._read
  if last and (now - last.at) / 1e9 < self._readTTL then
    return last.sessions
  end
  local sessions = self:sessions()
  self._read = { at = now, sessions = sessions }
  return sessions
end

function obj:_firstClientTty()
  local rows = self:_run("list-clients -F '#{client_tty}'")
  return rows[1] and rows[1][1] or nil
end

--- TmuxSessions.engine:windows() -> ordered list of
--- { session, index, name, active, sessionAttached, target }, one row per window across
--- every session, flattened from sessions(). target is the tmux target string
--- "session:index" that both goTo and the recency key are built from, so a row, a jump,
--- and a remembered position all name the same window the same way. Ordered by recency
--- when one was injected, a remembered window leading in the order it was last reached
--- and every other window keeping its session-then-index arrival order behind them.
function obj:windows()
  local out = {}
  for _, s in ipairs(self:_cachedSessions()) do
    for _, w in ipairs(s.windows) do
      out[#out + 1] = {
        session = s.name,
        index = w.index,
        name = w.name,
        active = w.active,
        sessionAttached = s.attached,
        target = s.name .. ":" .. w.index,
      }
    end
  end
  if self._recency then
    out = self._recency.order(out, function(item) return item.target end)
  end
  return out
end

--- TmuxSessions.engine:pruneRecency() drops any remembered window whose target no longer
--- exists, a session that was killed or a window closed inside one, so a stale tally never
--- lingers and can never silently reappear if the same target string is reused later. A
--- no-op without an injected recency instance.
function obj:pruneRecency()
  if not self._recency then return end
  local valid = {}
  for _, s in ipairs(self:_cachedSessions()) do
    for _, w in ipairs(s.windows) do
      valid[#valid + 1] = s.name .. ":" .. w.index
    end
  end
  self._recency.prune(valid)
end

--- TmuxSessions.engine:providers() -> the validated, ordered provider list.
function obj:providers()
  return self._providers or {}
end

--- TmuxSessions.engine:currentProviderName() -> the persisted choice when it still names an
--- available provider, else the first available provider in the configured order, else nil
--- when nothing on this machine is installed at all.
function obj:currentProviderName()
  local stored = hs.settings.get(self._settingsKey)
  if stored then
    for _, p in ipairs(self._providers or {}) do
      if p.name == stored and p.available() then return stored end
    end
  end
  for _, p in ipairs(self._providers or {}) do
    if p.available() then return p.name end
  end
  return nil
end

function obj:currentProvider()
  local name = self:currentProviderName()
  if not name then return nil end
  for _, p in ipairs(self._providers or {}) do
    if p.name == name then return p end
  end
  return nil
end

--- TmuxSessions.engine:setProviderName(name) persists which terminal a fresh attach opens
--- into, the same hs.settings persisted-choice shape the overlay display policy and the
--- browser toggles already use.
function obj:setProviderName(name)
  hs.settings.set(self._settingsKey, name)
end

-- Raising the right app needs no window matching at all when only one terminal
-- application is actually running, which covers the ordinary single-window habit this
-- tool is built for. Several running at once is the one case this cannot disambiguate
-- without walking the process tree behind each tty, so it falls back to whichever
-- provider is configured, and may simply raise the wrong app rather than claim to know.
function obj:_raiseWhicheverIsRunning()
  local runningCount, runningOne = 0, nil
  for _, p in ipairs(self._providers or {}) do
    if p.running() then
      runningCount = runningCount + 1
      runningOne = p
    end
  end
  if runningCount == 1 then
    runningOne.activate()
    return
  end
  local preferred = self:currentProvider()
  if preferred then preferred.activate() end
end

--- TmuxSessions.engine:goTo(target) -> ok, err
--- target is a tmux target string, a session name or "session:index". Retargets whatever
--- tmux client is already attached, wherever it is, or asks the configured terminal to
--- open a fresh attach when nothing is attached anywhere. A successful jump touches
--- recency under target itself, so the key an ordered row was built from is exactly the
--- key a jump remembers, with nothing to keep in step between the two.
function obj:goTo(target)
  if not self._tmux then return false, "tmux is not available" end

  local tty = self:_firstClientTty()
  if tty then
    local _, ok = hs.execute('"' .. self._tmux .. '" switch-client -c ' .. shq(tty)
      .. ' -t ' .. shq(target))
    if not ok then return false, "tmux refused to switch that client" end
    self:_raiseWhicheverIsRunning()
    if self._recency then self._recency.touch(target) end
    return true
  end

  local provider = self:currentProvider()
  if not provider then return false, "no terminal is installed" end
  local ok, err = provider.openAttach(target)
  if ok and self._recency then self._recency.touch(target) end
  return ok, err
end

return obj
