--- === Dependencies ===
---
--- The one door to an external tool, and the only thing in this config that probes
--- for one. It is told what is declared, probes the whole set in one pass, and hands out a
--- small adapter that answers only for what its consumer declared.
---
--- It reads no declaration itself. Every plugin declares its tools in its own manifest,
--- under needs.tools, and the composition root aggregates those manifests into the flat list
--- passed to configure. This file used to walk the tree for separate declaration files
--- instead, and for a while it could do both, which meant one tool could be described twice
--- with nothing watching the two answers agree. One source is the whole point, so the walk is
--- gone and the manifests are it.
---
--- The adapter is scoped to a consumer rather than to a file, because the consumer is what
--- the composition root injects into and what wires its own providers. A declaration may
--- still name the unit inside a plugin that wanted a tool, and that label is carried
--- alongside for the console and for the manifest one layer up, which is what makes a missing
--- tool point at the provider responsible instead of at a whole plugin.
---
--- Why the door matters more than the probing. Anything that reaches for a tool it did
--- not declare gets nothing back and is named in the console, so an undeclared
--- dependency stops working on the machine of whoever is writing it rather than on the
--- next machine. That is the whole guarantee, and it is a consequence of the adapter
--- refusing to answer rather than of anybody remembering to run a checker.
---
--- A declaration may say where a tool comes from, since a plugin that travels needs to carry
--- that answer with it, but nothing here reads it and nothing here installs anything. Where
--- a tool comes from is carried upward by the manifest collector and reconciled one layer up,
--- which is the only layer that knows what a package manager is.
---
--- Four kinds of dependency exist, because this config already needs all four. A
--- `path` tool is a binary on the login PATH. A `system` tool is a binary at a fixed
--- absolute path shipped by macOS or the Xcode command line tools. An `app` is a macOS
--- application with no binary on the PATH, probed by bundle id. A `manual` tool is
--- installed by a clone or a script, so it declares a marker path to test instead.
--- Only the path kind needs a shell, and every path tool is probed in one shell call,
--- which is why this costs less than the four hand rolled probes it replaces.

local obj = {}
obj.__index = obj

obj.name = "Dependencies"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- dependency-resolver-door
-- This marker declares this file as its module's dependency door, the one place allowed to
-- probe for an external tool. The reconciler one layer up refuses a probe or a hardcoded
-- package manager path anywhere else, and skips a file carrying this marker, which is how
-- that check stays module agnostic rather than knowing this spoon by name. A second door in
-- a module would defeat the point, so the marker belongs in exactly one file.
local log = hs.logger.new("Dependencies", "info")

-- Owned state
obj._declared = nil     -- spoon name -> { [tool] = entry }
obj._order = nil        -- flat list of entries in read order, for the manifest and the report
obj._resolved = nil     -- tool -> absolute path or true, absent when missing
obj._probed = false
obj._undeclaredSeen = nil -- consumer .. "/" .. tool already logged, so a loop logs once

-- A tool name and a locator both reach a shell in the path probe, so they are
-- validated rather than trusted. Anything outside this set is refused as the declarations
-- are taken in, with a visible log line, which fails loudly instead of building a
-- surprising command.
local SAFE = "^[%w._+/-]+$"

local KINDS = { path = true, system = true, app = true, manual = true }
local POLICIES = { optional = true, required = true }

--- Dependencies:init()
--- Method
--- Initialize. No side effects, the declarations are read in configure.
function obj:init()
  self._declared = {}
  self._order = {}
  self._resolved = {}
  self._undeclaredSeen = {}
  return self
end

-- Expand a leading ~ so a manual marker path may be written the way a human writes it.
local function expand(p)
  if p:sub(1, 1) == "~" then
    return (os.getenv("HOME") or "") .. p:sub(2)
  end
  return p
end

-- Check one declared entry on the way in, or say what is wrong with it. The manifest layer
-- checks the same things when it reads a manifest, and this checks them again rather than
-- trusting that, because a locator reaches a shell from here and this is the file that would
-- build the surprising command. It is also the door for anything that aggregates its own
-- declarations, so it cannot assume which reader assembled the list.
local function faultIn(e)
  if type(e) ~= "table" then return "is a " .. type(e) .. " rather than a table" end
  if type(e.name) ~= "string" or e.name == "" then return "has no name" end
  if not KINDS[e.kind] then return "has unknown kind '" .. tostring(e.kind) .. "'" end
  if not POLICIES[e.policy] then return "has unknown policy '" .. tostring(e.policy) .. "'" end
  local locator = e.locator
  if locator == nil or locator == "" then locator = e.name end
  if type(locator) ~= "string" or not locator:match(SAFE) then
    return "has unsafe locator '" .. tostring(locator) .. "'"
  end
  return nil
end

--- Dependencies:configure(opts)
--- Method
--- Learn what is declared. Idempotent, so a reload rebuilds the set.
---
--- opts.declared is a flat list of entries already carrying name, kind, locator, policy,
--- reason, consumer, and optionally the owner label naming the unit that wanted the tool.
--- That is what a set of plugin manifests aggregates to, and it is the only source. Reading
--- files here as well was the arrangement where one tool could be described twice with
--- nothing watching the two answers agree.
---
--- A malformed entry is logged and skipped rather than refusing the whole list, so one bad
--- declaration costs one tool instead of every tool in the set.
function obj:configure(opts)
  opts = opts or {}
  self._declared, self._order = {}, {}

  for _, e in ipairs(opts.declared or {}) do
    local fault = faultIn(e)
    if fault then
      log.w(string.format("declaration for '%s' ignored, it %s",
        tostring(type(e) == "table" and e.owner or e), fault))
    else
      local consumer = e.consumer or "Olm"
      -- A locator defaults to the name here rather than at every read of it, so the probe and
      -- the report below can rely on one being present. A path kind tool is usually declared
      -- without one, since the name IS what a shell looks for.
      if e.locator == nil or e.locator == "" then e.locator = e.name end
      self._declared[consumer] = self._declared[consumer] or {}
      self._declared[consumer][e.name] = e
      self._order[#self._order + 1] = e
    end
  end
  return self
end

-- Probe every path kind tool in one shell call. A login shell costs tens of
-- milliseconds, so it runs once for the whole set rather than once per tool, which is
-- what makes this cheaper than the per spoon probes it replaced. Names were validated as
-- configure took them in, so they are safe to interpolate.
--
-- The command carries no shell variable and no quote, deliberately. hs.execute with the
-- user environment wraps the command in double quotes and hands it to another shell
-- first, so a dollar name would be expanded away to nothing before the login shell ever
-- saw it, and a quote would close the wrapper early. Passing every name to one
-- `command -v` and mapping the answers back by their last path segment needs neither,
-- and it is why this is a single call rather than a loop.
--
-- The exit status is ignored on purpose. `command -v` reports failure when any one name
-- is missing, which is the normal case here, so the output is the only signal.
local function probePaths(locators)
  local found = {}
  if #locators == 0 then return found end
  local out = hs.execute("command -v " .. table.concat(locators, " "), true) or ""
  for line in out:gmatch("[^\n]+") do
    -- Absolute paths only. An interactive login shell also answers here with aliases and
    -- shell builtins, and neither is something hs.task can be handed.
    if line:sub(1, 1) == "/" then
      local base = line:match("([^/]+)$")
      if base then found[base] = line end
    end
  end
  return found
end

--- Dependencies:start()
--- Method
--- Probe everything declared, once, and log one summary line. The path kinds go through
--- a single shell call and the other three resolve in process, so this is one shell
--- spawn no matter how many tools are declared. A missing optional tool is a warning
--- naming what it disables, a missing required one an error, and an all present set a
--- single quiet info line.
function obj:start()
  local pathLocators, seen = {}, {}
  for _, e in ipairs(self._order) do
    if e.kind == "path" and not seen[e.locator] then
      seen[e.locator] = true
      pathLocators[#pathLocators + 1] = e.locator
    end
  end
  local onPath = probePaths(pathLocators)

  self._resolved = {}
  local missing = {}
  for _, e in ipairs(self._order) do
    local hit = nil
    if e.kind == "path" then
      hit = onPath[e.locator]
    elseif e.kind == "system" then
      hit = (hs.fs.attributes(e.locator, "mode") == "file") and e.locator or nil
    elseif e.kind == "app" then
      hit = hs.application.pathForBundleID(e.locator)
    elseif e.kind == "manual" then
      local p = expand(e.locator)
      hit = hs.fs.attributes(p) and p or nil
    end
    if hit then
      self._resolved[e.consumer .. "/" .. e.name] = hit
    else
      missing[#missing + 1] = e
    end
  end
  self._probed = true

  local total = #self._order
  if #missing == 0 then
    log.i(string.format("%d dependencies declared, all present", total))
    return self
  end
  -- One warning, never an error, however many are missing and whatever their policy. An
  -- absent tool is a handled outcome, the feature is excluded and says so, not a defect,
  -- and an error on every reload for a machine that simply lacks an optional tool is the
  -- fastest way to teach someone to ignore this line. A required one is marked as such in
  -- the text instead, since what it costs is a whole feature rather than one backend.
  -- Errors are kept for real defects, a spoon asking for a tool it never declared and a
  -- declaration that does not parse.
  -- The owner rather than the consumer, so the line points at the file that declared the
  -- tool. Capture/macshot says which backend is gone, where Capture alone would not.
  local parts = {}
  for _, e in ipairs(missing) do
    local mark = (e.policy == "required") and "required, " or ""
    parts[#parts + 1] = string.format("%s (%s%s, %s)", e.name, mark, e.owner, e.reason)
  end
  log.w(string.format("%d dependencies declared, %d present, missing %s",
    total, total - #missing, table.concat(parts, ", ")))
  return self
end

--- Dependencies:scope(consumer)
--- Method
--- The per consumer adapter the root injects into a spoon. It answers only for what
--- that consumer declared, so a spoon can never reach a tool it did not write down,
--- and it never exposes the registry or the other consumers. Dot called, matching the
--- other injected surfaces in this config.
---
--- have(tool) is whether the tool resolved. path(tool) is its absolute path, or its
--- bundle id for an app kind, and nil when missing. satisfied() is whether every
--- required tool for this consumer resolved, which the root reads to decide whether to
--- wire the spoon at all. missing() lists the entries that did not resolve, so a
--- consumer can explain itself in its own words.
function obj:scope(consumer)
  local self_ = self
  local function entryFor(tool)
    local byName = self_._declared[consumer]
    local e = byName and byName[tool]
    if not e then
      local key = consumer .. "/" .. tool
      if not self_._undeclaredSeen[key] then
        self_._undeclaredSeen[key] = true
        log.e(string.format(
          "%s asked for undeclared tool '%s', declare it beside the file that uses it",
          consumer, tostring(tool)))
      end
      return nil
    end
    return e
  end
  return {
    have = function(tool)
      return entryFor(tool) ~= nil and self_._resolved[consumer .. "/" .. tool] ~= nil
    end,
    path = function(tool)
      if not entryFor(tool) then return nil end
      return self_._resolved[consumer .. "/" .. tool]
    end,
    missing = function()
      local out = {}
      for _, e in ipairs(self_._order) do
        if e.consumer == consumer and not self_._resolved[consumer .. "/" .. e.name] then
          out[#out + 1] = e
        end
      end
      return out
    end,
    satisfied = function()
      for _, e in ipairs(self_._order) do
        if e.consumer == consumer and e.policy == "required"
          and not self_._resolved[consumer .. "/" .. e.name] then
          return false
        end
      end
      return true
    end,
  }
end

--- Dependencies:report()
--- Method
--- Every declared entry with whether it resolved, for the console and for the `hs` CLI.
--- Read only, so a caller can print it without disturbing anything.
function obj:report()
  local out = {}
  for _, e in ipairs(self._order) do
    out[#out + 1] = {
      name = e.name, kind = e.kind, locator = e.locator, policy = e.policy,
      consumer = e.consumer, owner = e.owner, reason = e.reason,
      resolved = self._resolved[e.consumer .. "/" .. e.name] or false,
    }
  end
  return out
end

return obj
