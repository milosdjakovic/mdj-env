--- === Dependencies ===
---
--- The one door to an external tool, and the only thing in this config that probes
--- for one. A spoon declares what it needs in a plain declaration file, this spoon reads
--- every such file, probes them all in one pass, and hands each spoon a small adapter that
--- answers only for what that spoon declared.
---
--- A declaration sits beside whatever actually knows the tool, which is how a provider
--- stays self contained. Two names are recognised anywhere under a spoon. A file called
--- `dependencies` declares needs of the spoon as a whole, so it belongs at the spoon root.
--- A file called `<base>.dependencies` declares needs of its sibling `<base>.lua`, so
--- `providers/mullvad.dependencies` is the mullvad provider's own contract, and adding a
--- second backend is a new provider file plus a new declaration with nothing shared to
--- edit.
---
--- Either way the adapter is scoped to the spoon rather than to the file, because the spoon
--- root is what the composition root injects into and what wires its own providers. So
--- placement decides which file owns a line, and the spoon still decides who may ask for
--- it. The owner label is carried alongside for the console and the manifest, which is what
--- makes a missing tool point at the file responsible instead of at a whole spoon.
---
--- Why the door matters more than the probing. A spoon that reaches for a tool it did
--- not declare gets nothing back and is named in the console, so an undeclared
--- dependency stops working on the machine of whoever is writing it rather than on the
--- next machine. That is the whole guarantee, and it is a consequence of the adapter
--- refusing to answer rather than of anybody remembering to run a checker.
---
--- A declaration names a tool and never names how to install one. Homebrew, casks,
--- taps and manual steps are the concern of the layer above this config, which reads
--- the collected manifest and maps each name to a concrete install. So nothing here,
--- and nothing in a spoon, may mention an installer.
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

-- The Spoons directory, resolved from this file's own location, since a spoon
-- directory is not on package.path. Every declaration file under a sibling `<Name>.spoon`
-- is read, so adding one is a new file and no wiring anywhere.
local selfPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local SPOONS_DIR = selfPath:match("^(.*)/[^/]+/$")

-- A tool name and a locator both reach a shell in the path probe, so they are
-- validated rather than trusted. Anything outside this set is refused at parse time
-- with a visible log line, which fails loudly instead of building a surprising
-- command.
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

-- Parse one declaration line into an entry, or nil plus a reason. The format is five
-- fields separated by a pipe, name, kind, locator, policy, reason. Blank lines and
-- lines opening with a hash are skipped by the caller.
local function parseLine(line)
  local fields = {}
  for field in (line .. "|"):gmatch("([^|]*)|") do
    fields[#fields + 1] = field:gsub("^%s+", ""):gsub("%s+$", "")
  end
  if #fields < 5 then return nil, "expected five pipe separated fields" end
  local name, kind, locator, policy, reason = fields[1], fields[2], fields[3], fields[4], fields[5]
  if name == "" then return nil, "empty tool name" end
  if not KINDS[kind] then return nil, "unknown kind '" .. kind .. "'" end
  if not POLICIES[policy] then return nil, "unknown policy '" .. policy .. "'" end
  if locator == "" then locator = name end
  if not locator:match(SAFE) then return nil, "unsafe locator '" .. locator .. "'" end
  return { name = name, kind = kind, locator = locator, policy = policy, reason = reason }
end

-- Read one declaration file. Returns a list of entries, logging and skipping any malformed
-- line rather than refusing the whole file, so one typo costs one tool instead of every tool
-- that file declares. consumer is the spoon the adapter will be scoped to, owner is the file
-- that declared the line, which is what a log or a manifest shows.
local function readFile(path, consumer, owner)
  local f = io.open(path, "r")
  if not f then return {} end
  local entries = {}
  local n = 0
  for line in f:lines() do
    n = n + 1
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
      local entry, err = parseLine(trimmed)
      if entry then
        entry.consumer = consumer
        entry.owner = owner
        entries[#entries + 1] = entry
      else
        log.w(string.format("%s declaration line %d ignored, %s", owner, n, err))
      end
    end
  end
  f:close()
  return entries
end

-- The suffix that marks a per file declaration, and its length, used to recover the base
-- name the declaration belongs to.
local SUFFIX = ".dependencies"

-- Every declaration file under one spoon, in a stable order. A file named `dependencies`
-- belongs to the spoon as a whole and carries no base, a file named `<base>.dependencies`
-- belongs to its sibling `<base>.lua` and carries that base as its owner label.
--
-- The walk is depth capped. Three levels reaches a spoon root, a subdirectory such as
-- providers or manager, and one level under that, which is deeper than anything here. A
-- spoon that needed more would be organising itself wrong rather than needing more depth,
-- and an uncapped walk in the resolver that runs before every other spoon is not worth the
-- risk of one stray directory.
local MAX_DEPTH = 3
local function declarationFiles(dir, depth, out)
  local ok, iterFn, dirObj = pcall(hs.fs.dir, dir)
  if not ok or not iterFn then return out end
  local names = {}
  for entry in iterFn, dirObj do
    if entry ~= "." and entry ~= ".." then names[#names + 1] = entry end
  end
  -- Sorted so the manifest and the report come out in a stable order rather than in whatever
  -- order the filesystem hands back, which keeps a generated manifest from churning in git.
  table.sort(names)
  for _, entry in ipairs(names) do
    local full = dir .. "/" .. entry
    local mode = hs.fs.attributes(full, "mode")
    if mode == "file" then
      if entry == "dependencies" then
        out[#out + 1] = { path = full }
      elseif #entry > #SUFFIX and entry:sub(-#SUFFIX) == SUFFIX then
        out[#out + 1] = { path = full, base = entry:sub(1, #entry - #SUFFIX) }
      end
    elseif mode == "directory" and depth < MAX_DEPTH then
      declarationFiles(full, depth + 1, out)
    end
  end
  return out
end

--- Dependencies:configure(opts)
--- Method
--- Read every spoon's declaration. opts.spoonsDir overrides where to look, which only
--- a test would pass. Idempotent, so a reload rebuilds the set from disk.
function obj:configure(opts)
  opts = opts or {}
  local dir = opts.spoonsDir or SPOONS_DIR
  self._declared, self._order = {}, {}
  if not dir then
    log.w("could not resolve the Spoons directory, no declarations read")
    return self
  end
  local names = {}
  local ok, iterFn, dirObj = pcall(hs.fs.dir, dir)
  if not ok or not iterFn then
    log.w("could not read the Spoons directory, no declarations read")
    return self
  end
  for entry in iterFn, dirObj do
    if entry:sub(-6) == ".spoon" then names[#names + 1] = entry end
  end
  -- Sorted so the manifest and the report come out in a stable order rather than in
  -- whatever order the filesystem hands back, which keeps a generated manifest from
  -- churning in git for no reason.
  table.sort(names)
  for _, entry in ipairs(names) do
    local consumer = entry:sub(1, -7)
    for _, file in ipairs(declarationFiles(dir .. "/" .. entry, 1, {})) do
      local owner = file.base and (consumer .. "/" .. file.base) or consumer
      for _, e in ipairs(readFile(file.path, consumer, owner)) do
        self._declared[consumer] = self._declared[consumer] or {}
        self._declared[consumer][e.name] = e
        self._order[#self._order + 1] = e
      end
    end
  end
  return self
end

-- Probe every path kind tool in one shell call. A login shell costs tens of
-- milliseconds, so it runs once for the whole set rather than once per tool, which is
-- what makes this cheaper than the per spoon probes it replaced. Names were validated
-- at parse time, so they are safe to interpolate.
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
