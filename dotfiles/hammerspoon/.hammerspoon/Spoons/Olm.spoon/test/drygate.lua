-- The dry contract gate. Catches a bad plugin declaration at build time, with plain lua,
-- never Hammerspoon, so a builder agent who cannot start one stops shipping a mistake that
-- today only surfaces at the next live reload. docs/REVIEW-TRICKLE.md's own findings H1 and
-- H2 are the canonical examples this gate exists to have caught before either ever reached a
-- review, a presentation member naming a function that does not exist, and a root sourced
-- word nobody publishes.
--
-- THE SPLIT, the same one dependencies-collect.lua and dependencies-collect already use.
-- Finding files is what a shell is good at, reading and checking Lua is what Lua is good at,
-- so drygate.sh finds every manifest.lua under plugins/ and host/ and hands the paths over
-- as arguments, and this file never touches the filesystem beyond loadfile and io.open on a
-- path it was already given.
--
-- THE FOUR CHECKS, and where each one's answer actually comes from.
--
-- One, every manifest loads as pure data and satisfies the contract shape. loadfile plus
-- pcall, then the same small set of fields lib/plugins.lua's own readOne checks are tables
-- when present. Mirrored rather than called, since that module's own directory walking goes
-- through hs.fs, which this gate has no reason to stub when the shell already found every
-- path, and its readOne is not exposed for calling in isolation. If its own SHAPE table ever
-- grows a field this mirror does not know about, this one check quietly stops covering that
-- field, the one honest cost of not sharing it directly.
--
-- Two, every member path a manifest declares, presentation, registry, scope, wiring,
-- resolves to a real function on the module the plugin's own init.lua actually builds,
-- loaded once here under test/drygate-hsstub.lua's stub. Presentation reuses
-- lib/registrar.lua's own obj.validatePresentation outright, the exact rule a live reload
-- already applies, refactored out of obj.describe for this file to call, seam marked in
-- that file's own comments. registry.open, a command's own fn, and every scope member reuse
-- the same file's obj.memberSpec and obj.memberResolves directly, since obj.describe itself
-- never checks those eagerly, by its own documented design, they resolve lazily at call time
-- in the live config and answer nil in silence rather than refuse anything, which is exactly
-- the gap this gate closes ahead of a reload rather than after one. wiring mirrors
-- lib/wire.lua's own targetOf and its method lookup, small enough and local enough inside
-- that file to write again here rather than to justify exposing.
--
-- Three, every needs.data entry naming source root is checked against
-- test/drygate-composewords.lua's own structured scan of root/compose.lua, which names its
-- own limits in its own header rather than here.
--
-- Four, call kinds and the type guards, rowCount, paneWidth, and a scope or presentation
-- matcher against the real Chooser.matchers table, all ride along inside check two, since
-- lib/registrar.lua's own obj.validatePresentation already makes every one of those checks
-- as part of resolving a presentation, and lib/registry.lua's own register call, reused
-- wholesale rather than reimplemented, makes the rest, a row's own category, a scope's own
-- required rows and run, a shortcut naming leader or global, apiVersion equality, all
-- refused in the identical words a live reload would refuse them in.
--
-- WHAT COUNTS AS WHAT. A FINDING is a proven contract violation and is what makes this
-- script exit nonzero, unless it is also named in test/drygate-accepted.txt, one line
-- naming the exact finding text and the reason a person verified it by hand, in which case
-- it still prints, as its own ACCEPTED line, and stops counting. An accepted line that
-- stops matching any finding this run is itself a finding, so that file cannot rot into a
-- list nobody rechecks. A WARNING is informational, the one example today being a
-- presenting plugin whose declared surface.context diverges from its own identity, which
-- the live registrar itself only ever warns about rather than refuses, so this gate answers
-- it the same way. An UNKNOWN means a plugin's own module would not load, or would not
-- configure, under the stub at all, so every check needing that real module is skipped for
-- it and said so once, rather than guessed at as a pass or reported as a false failure. An
-- honest unknown beats a false green, and by default an unknown does not fail the gate any
-- more than a warning does, since it names a limit of this gate rather than a defect in a
-- manifest. DRYGATE_STRICT=1 in the environment, drygate.sh's own --strict, is the harder
-- stance for whoever wants it, promoting every unknown to a failure too.
--
-- A CLEAN TREE EXITS ZERO. That is the entire point of the accepted file and of leaving an
-- unknown unpunished by default, a gate that a clean tree still turns red gets ignored
-- within a week, and an ignored gate protects nothing. Exit nonzero must mean something
-- changed for the worse, never that this gate is merely being run.
--
-- A finding already reusing lib/registrar.lua's own wording is printed exactly as that file
-- would print it, "registrar refused '<name>', ...". A finding this gate makes on its own,
-- the eager member checks describe itself never makes, and wiring, reads "dry gate refused
-- '<name>', ..." in the identical voice, so a reader can tell at a glance whether a given
-- line would also appear in a live reload's own console the moment it happens, or is this
-- gate catching something ahead of one.

local scriptDir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

local spoonDir = arg[1]
if not spoonDir then
  io.stderr:write("usage: lua drygate.lua <Olm.spoon dir> <manifest.lua path> [more paths...]\n")
  os.exit(2)
end
if spoonDir:sub(-1) ~= "/" then spoonDir = spoonDir .. "/" end

local manifestPaths = {}
for i = 2, #arg do manifestPaths[#manifestPaths + 1] = arg[i] end

-- A clean tree exits zero, loudly checkable, is the whole contract this gate exists to
-- keep. Read before a gate that exits nonzero on a clean tree ever gets ignored within a
-- week, which is worse than not running one at all, since a red light nobody trusts stops
-- being a signal. strict is the harder stance for whoever wants it, promoting an honest
-- unknown to a failure, off by default because an unknown is a limit of this gate rather
-- than a defect in a manifest.
local strict = os.getenv("DRYGATE_STRICT") == "1"

----------------------------------------------------------------------------------------
-- Findings, and the accepted findings file beside this one.
--
-- A finding verified by hand and genuinely not worth blocking on, hypercheatsheet's own
-- needs.data.sections against test/drygate-composewords.lua's own documented blind spot
-- being the seed case, is named in test/drygate-accepted.txt rather than silenced by
-- editing this file, one line per accepted finding, the exact text this gate would
-- otherwise print, then " | " then the reason a person checked it by hand. An accepted
-- finding still prints, as its own line, so accepting one is never silent, it only stops
-- counting toward the exit code.
--
-- Matching is EXACT text, on purpose. A softer match, a substring or a pattern, would let
-- one accepted line quietly cover a second, different problem that happens to share a
-- word, which is worse than making someone re paste a line. The cost of exactness is
-- pointed the other way on purpose too, an accepted line that stops matching anything this
-- run, because the finding's own wording changed or the underlying question is now
-- answered differently, is ITSELF a finding, so the file cannot rot into a growing list of
-- lines nobody rechecks. Removing or rewording an accepted line is the fix, both are one
-- edit to a file this gate already reads.
local acceptedPath = scriptDir .. "drygate-accepted.txt"
local acceptedReason, acceptedSeen = {}, {}
do
  local f = io.open(acceptedPath, "r")
  if f then
    for line in f:lines() do
      local trimmed = line:match("^%s*(.-)%s*$")
      if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
        local text, reason = trimmed:match("^(.-)%s*|%s*(.+)$")
        if text and reason and text ~= "" then
          acceptedReason[text] = reason
          acceptedSeen[text] = false
        end
      end
    end
    f:close()
  end
end

local findings, warnings, unknowns, accepted = {}, {}, {}, {}

local function finding(line)
  if acceptedReason[line] then
    acceptedSeen[line] = true
    accepted[#accepted + 1] = string.format("accepted, %s (%s)", line, acceptedReason[line])
  else
    findings[#findings + 1] = line
  end
end
local function warning(line) warnings[#warnings + 1] = line end
local coverageLines = {}
local function unknown(dir, reason)
  unknowns[#unknowns + 1] = string.format("dry gate, '%s', unknown, %s", dir, reason)
end

----------------------------------------------------------------------------------------
-- The stub, and the pure lua collaborators this gate reuses rather than reimplements.
----------------------------------------------------------------------------------------

local hsstub = dofile(scriptDir .. "drygate-hsstub.lua")
hsstub.install(spoonDir)

local function loadPure(relPath)
  local chunk, err = loadfile(spoonDir .. relPath)
  if not chunk then
    io.stderr:write("drygate could not load " .. relPath .. ", " .. tostring(err) .. "\n")
    os.exit(2)
  end
  return chunk()
end

local registrarLib = loadPure("lib/registrar.lua")
-- Only for checkHeader, which is pure. Called rather than mirrored, so the apiVersion and
-- about rules this gate enforces are the very ones the live load enforces.
local pluginsLib = loadPure("lib/plugins.lua")
local registryLib = loadPure("lib/registry.lua")
local defaultsLib = loadPure("lib/defaults.lua")
local matchersLib = loadPure("lib/chooser/match.lua")
local composeWords = dofile(scriptDir .. "drygate-composewords.lua")

local rootWords, wordProblems = composeWords.published(spoonDir .. "root/compose.lua")
for _, p in ipairs(wordProblems or {}) do
  finding("dry gate, root/compose.lua, " .. p
    .. ", so check three cannot compare against this table's own words")
end
rootWords = rootWords or {}

local apiVersion
do
  local f = io.open(spoonDir .. "init.lua", "r")
  if f then
    local text = f:read("a")
    f:close()
    apiVersion = tonumber(text:match("obj%.apiVersion%s*=%s*(%-?%d+)"))
  end
  if not apiVersion then
    finding("dry gate, init.lua, no 'obj.apiVersion = <number>' found, "
      .. "so the apiVersion checks cannot run")
  end
end

----------------------------------------------------------------------------------------
-- Check one. Every manifest loads as pure data and satisfies the contract shape.
----------------------------------------------------------------------------------------

-- Mirrors lib/plugins.lua's own SHAPE table, see this file's own header for why this is a
-- mirror rather than a call.
local SHAPE = {
  needs = "table", provides = "table", defaults = "table", surface = "table",
  registry = "table", presentation = "table", wiring = "table",
}

local manifestsByDir = {}
local identityOfDir = {}
local pathOfDir = {}
local dirOfIdentity = {}

for _, path in ipairs(manifestPaths) do
  local dir = path:match("([^/]+)/manifest%.lua$") or path
  local chunk, loadErr = loadfile(path)
  if not chunk then
    finding(string.format("dry gate refused '%s', its manifest would not load, %s", dir, tostring(loadErr)))
  else
    local ok, value = pcall(chunk)
    if not ok then
      finding(string.format("dry gate refused '%s', its manifest errored while loading, %s", dir, tostring(value)))
    elseif type(value) ~= "table" then
      finding(string.format("dry gate refused '%s', its manifest returned %s rather than a table", dir, type(value)))
    else
      local shapeOk = true
      if value.name ~= nil and type(value.name) ~= "string" then
        finding(string.format("dry gate refused '%s', its manifest name is a %s rather than a string", dir, type(value.name)))
        shapeOk = false
      end
      for field, want in pairs(SHAPE) do
        local got = value[field]
        if got ~= nil and type(got) ~= want then
          finding(string.format("dry gate refused '%s', its manifest %s is a %s rather than a %s", dir, field, type(got), want))
          shapeOk = false
        end
      end
      local headerErr = pluginsLib.checkHeader(value, apiVersion)
      if headerErr then
        finding(string.format("dry gate refused '%s', its manifest %s", dir, headerErr))
        shapeOk = false
      end

      local identity = (type(value.name) == "string" and value.name) or dir
      local already = dirOfIdentity[identity]
      if already then
        finding(string.format(
          "dry gate refused '%s', identity '%s' is also declared by '%s', both ignored",
          dir, identity, already))
        finding(string.format(
          "dry gate refused '%s', identity '%s' is also declared by '%s', both ignored",
          already, identity, dir))
        manifestsByDir[already] = nil
        identityOfDir[already] = nil
        pathOfDir[already] = nil
      else
        dirOfIdentity[identity] = dir
        manifestsByDir[dir] = value
        identityOfDir[dir] = identity
        pathOfDir[dir] = path
      end
    end
  end
end

----------------------------------------------------------------------------------------
-- Load every surviving plugin's real module, under the stub, once, then attempt its own
-- configure, so check two and the registry side of check four resolve a member path
-- against the module the way it actually ends up, not the way dofile alone leaves it. Many
-- real tools assemble self.rows, self.select, self.open, exactly what check two goes
-- looking for, INSIDE their own configure rather than at module load, MenuSearch among
-- them, lib/registrar.lua's own comments describe the discipline at length. Checking only
-- the pre configure shape would report every one of those as unresolved, which is this
-- gate asking the wrong question rather than a real finding.
----------------------------------------------------------------------------------------

-- Loaded once, cached by lib name, so ten plugins asking for the same lib capability cost
-- one load rather than ten. A lib module that fails to load under the stub degrades every
-- plugin that named it to unknown rather than raising the whole gate down, the identical
-- honesty this file already keeps for a plugin's own module.
local libCache = {}
local function loadLib(modName)
  if libCache[modName] ~= nil then return libCache[modName] end
  local ok, modOrErr = pcall(loadfile, spoonDir .. "lib/" .. modName .. ".lua")
  local mod
  if ok and modOrErr then
    local okRun, result = pcall(modOrErr)
    if okRun then mod = result end
  end
  -- The storage lib refuses every path question until its roots are configured, and the live
  -- composition root configures them before any plugin's configure runs, so a plugin that
  -- asks for its directory at configure is correct and would still read here as one this
  -- gate cannot check. Two throwaway roots stand in, pure string work in that lib and no disk,
  -- which is exactly the part of the root every plugin declaring storage is entitled to.
  if modName == "storage" and mod and type(mod.configure) == "function" then
    pcall(mod.configure, { cacheRoot = "/tmp/olm-drygate/cache", olmRoot = "/tmp/olm-drygate/data" })
  end
  libCache[modName] = mod or false
  return mod
end

-- The opts table wire.lua's own optionsFor would hand this plugin's configure, built as
-- generously as this gate can manage without a real composition root. defaults.lua's own
-- merge is not used here on purpose, unlike a live reload this gate has no root override
-- layer to merge against, so a fresh install's own defaults ARE the effective values.
-- Every ambient service, ever field a sibling need or a piece of the person's own
-- configuration would have supplied, is a fresh autostub, present so an early guard on
-- shape passes, harmless so nothing it does once called touches anything real, since
-- hs itself is the identical stub underneath. A field this gate could not honestly build
-- at all is simply left absent, so a configure that genuinely required it raises, and that
-- raise degrades this plugin to unknown rather than being reported as a false finding.
local function buildOpts(manifest)
  local opts = {}
  for k, v in pairs(manifest.defaults or {}) do opts[k] = v end

  if manifest.surface then
    opts.chooser = opts.chooser or hsstub.autostub()
    opts.theme = opts.theme or hsstub.autostub()
    opts.placeholder = opts.placeholder or ""
    if manifest.surface.matcher ~= nil then
      opts.matcher = manifest.surface.matcher ~= false and matchersLib[manifest.surface.matcher] or false
    else
      -- A real number rather than an autostub, since a matcher is called and its answer is
      -- routinely compared or sorted, `score > 0`, `table.sort(rows, function(a, b) return
      -- a.score > b.score end)`, and a table there raises on the comparison rather than on
      -- anything this gate actually wants to know about.
      opts.matcher = function() return 0 end
    end
    if manifest.surface.pane then opts.surface = hsstub.autostub() end
  end
  if manifest.needs and manifest.needs.tools then
    opts.deps = hsstub.autostub()
  end
  opts.log = hsstub.autostub()
  opts.after = function() end

  for field, decl in pairs((manifest.needs or {}).lib or {}) do
    local modName, member
    if type(decl) == "table" then
      modName, member = decl.from or decl.module, decl.member
      if modName and not member then
        local a, b = tostring(modName):match("^([^.]+)%.(.+)$")
        if a then modName, member = a, b end
      end
    elseif type(decl) == "string" then
      modName, member = decl:match("^([^.]+)%.(.+)$")
      modName = modName or decl
    end
    local mod = modName and loadLib(modName)
    if mod then
      if member then
        local fn = mod[member]
        if type(fn) == "function" and (type(decl) ~= "table" or decl.call ~= "dot") then
          opts[field] = function(...) return fn(mod, ...) end
        else
          opts[field] = fn
        end
      else
        opts[field] = mod
      end
    end
  end

  -- needs.data cannot be answered with real data, this gate has no person's own
  -- configuration and no earlier composed root value to hand over, so every declared field
  -- gets an empty table, generous enough to pass a bare presence guard, `if not
  -- opts.storage then error(...)`, and, unlike an autostub, safe under `ipairs` or `pairs`,
  -- which an autostub answers forever, the concrete failure a handful of real configure
  -- calls hit while this file was being built, an opts field the plugin walks as a list it
  -- expects to run out.
  for field in pairs((manifest.needs or {}).data or {}) do
    if opts[field] == nil then opts[field] = {} end
  end

  return opts
end

local modules = {}     -- identity -> loaded, configured module table
local moduleErr = {}   -- dir -> reason, when load or configure did not produce a usable module

for dir, manifest in pairs(manifestsByDir) do
  local initPath = pathOfDir[dir]:gsub("manifest%.lua$", "init.lua")
  local mod, err = hsstub.loadModule(initPath)
  if not mod then
    moduleErr[dir] = err
  else
    local ok, confErr = hsstub.configureModule(mod, buildOpts(manifest))
    if ok then
      modules[identityOfDir[dir]] = mod
    else
      moduleErr[dir] = "loaded, but its own configure raised under this gate's stub opts, "
        .. tostring(confErr)
    end
  end
end

----------------------------------------------------------------------------------------
-- Checks two, three, and four, per plugin.
----------------------------------------------------------------------------------------

--- One member declaration, checked against a real, loaded module by lib/registrar.lua's own
--- rule, exposed as obj.memberSpec and obj.memberResolves. Used here for every member path
--- obj.describe itself never checks eagerly, registry.open, a command's own fn, and every
--- scope member, which resolve lazily at call time in the live config and answer nil in
--- silence there rather than refuse anything, docs/BRIEF ... the exact gap this gate closes
--- ahead of a reload.
local function checkMember(dir, identity, fieldPath, spec, mod)
  if spec == nil then return end
  local member = registrarLib.memberSpec(spec)
  if member == nil then return end
  if not registrarLib.memberResolves(mod, member) then
    finding(string.format(
      "dry gate refused '%s', its %s names '%s', which does not resolve to a function on the real module",
      identity, fieldPath, tostring(member)))
  end
end

--- registry.open, every registry.commands[*].fn, and every registry.scope member, none of
--- which lib/registrar.lua's own obj.describe checks eagerly today.
local function checkRegistryMembers(dir, identity, manifest, mod)
  local reg = manifest.registry
  if type(reg) ~= "table" then return end
  checkMember(dir, identity, "registry.open", reg.open, mod)
  -- A row's detail is display text when it is a string and a lazily resolved member when it
  -- is a table, so only the table form is checked, a bare string here being words and never
  -- a member name. A typo in the table form otherwise costs a live subtitle silently, the
  -- launcher falling back to the static one with no line anywhere.
  if type(reg.row) == "table" and type(reg.row.detail) == "table" then
    checkMember(dir, identity, "registry.row.detail", reg.row.detail, mod)
  end
  if type(reg.commands) == "table" then
    for cmdName, cmdSpec in pairs(reg.commands) do
      if type(cmdSpec) == "table" then
        checkMember(dir, identity, "registry.commands." .. tostring(cmdName) .. ".fn", cmdSpec.fn, mod)
      end
    end
  end
  if type(reg.scope) == "table" then
    local s = reg.scope
    checkMember(dir, identity, "registry.scope.rows", s.rows, mod)
    checkMember(dir, identity, "registry.scope.run", s.run, mod)
    checkMember(dir, identity, "registry.scope.peek", s.peek, mod)
    checkMember(dir, identity, "registry.scope.redirect", s.redirect, mod)
    checkMember(dir, identity, "registry.scope.act", s.act, mod)
    checkMember(dir, identity, "registry.scope.guard", s.guard, mod)
    if type(s.verbs) == "table" then
      for action, verbSpec in pairs(s.verbs) do
        checkMember(dir, identity, "registry.scope.verbs." .. tostring(action), verbSpec, mod)
      end
    end
  end
end

--- provides.launcherRows and provides.launcherRun, the two members a plugin offers the
--- launcher's own catalog. The composition root resolves both lazily through the registrar's
--- own door and names one that resolves to nothing on its console, which is after a reload, so
--- this asks the same question ahead of one.
local function checkLauncherMembers(dir, identity, manifest, mod)
  local provides = manifest.provides
  if type(provides) ~= "table" then return end
  checkMember(dir, identity, "provides.launcherRows", provides.launcherRows, mod)
  checkMember(dir, identity, "provides.launcherRun", provides.launcherRun, mod)
end

--- manifest.wiring, mirroring lib/wire.lua's own targetOf and its method lookup, call.lua
--- lines this gate never touched since neither is exposed and both are small enough to
--- write again here than to justify a seam for. Absent target means the plugin root, a
--- string names a submodule, and every step needs a real function at the far end, the
--- identical two facts lib/wire.lua's own stage three checks at the moment it actually runs
--- a step rather than ahead of one.
local function checkWiring(dir, identity, manifest, mod)
  if type(manifest.wiring) ~= "table" then return end
  for i, step in ipairs(manifest.wiring) do
    if type(step) ~= "table" or type(step.method) ~= "string" or step.method == "" then
      finding(string.format(
        "dry gate refused '%s', its wiring step %d has no method naming a string to call",
        identity, i))
    else
      local recv = mod
      local targetOk = true
      if step.target ~= nil then
        if type(step.target) ~= "string" or type(mod[step.target]) ~= "table" then
          targetOk = false
          finding(string.format(
            "dry gate refused '%s', its wiring step %d names target '%s', which has no submodule by that name on the real module",
            identity, i, tostring(step.target)))
        else
          recv = mod[step.target]
        end
      end
      if targetOk and type(recv[step.method]) ~= "function" then
        finding(string.format(
          "dry gate refused '%s', its wiring step %d has no %s to call%s",
          identity, i, step.method, step.target and (" on " .. step.target) or ""))
      end
    end
  end
end

--- needs.data entries naming source root, checked against test/drygate-composewords.lua's
--- own structured scan of root/compose.lua. Needs no module, since needs.data is manifest
--- data through and through.
local function checkRootWords(dir, identity, manifest)
  local dataFields = (manifest.needs or {}).data
  if type(dataFields) ~= "table" then return end
  for field, decl in pairs(dataFields) do
    if type(decl) == "table" and decl.source == "root" and not rootWords[field] then
      finding(string.format(
        "dry gate found '%s' declaring needs.data.%s with source root, and '%s' does not "
          .. "appear in this gate's structural scan of root/compose.lua, verify by hand "
          .. "before treating this as settled, see test/drygate-composewords.lua's own "
          .. "header for what that scan can and cannot see",
        identity, field, field))
    end
  end
end

for dir, manifest in pairs(manifestsByDir) do
  local identity = identityOfDir[dir]
  local mod = modules[identity]

  checkRootWords(dir, identity, manifest)

  local launcherMembers = type(manifest.provides) == "table"
    and (manifest.provides.launcherRows ~= nil or manifest.provides.launcherRun ~= nil)
  local needsModule = (manifest.registry ~= nil) or (manifest.presentation ~= nil)
    or (type(manifest.wiring) == "table" and #manifest.wiring > 0) or launcherMembers

  if needsModule and not mod then
    unknown(dir, string.format(
      "its module did not load under the dry gate's stub (%s), so its presentation, "
        .. "registry, scope, and wiring member paths could not be checked",
      moduleErr[dir] or "no reason recorded"))
  else
    -- Presentation without a registry block never reaches obj.describe at all, since that
    -- function declines to build anything when neither a manifest.registry nor a root
    -- override exists for this identity, docs/PLUGIN-CONTRACT.md's own registry section,
    -- "a plugin naming neither is quietly not a registration". No manifest in this tree
    -- does that today, every one that presents also registers, but a manifest that someday
    -- did would otherwise have its presentation silently unchecked, so it is checked
    -- directly here rather than only through the door describe already owns below.
    if manifest.presentation ~= nil and manifest.registry == nil then
      local logs = {}
      registrarLib.validatePresentation(dir, identity, manifest, { [identity] = mod }, {
        log = function(level, msg) logs[#logs + 1] = { level = level, msg = msg } end,
        matchers = matchersLib,
      })
      for _, entry in ipairs(logs) do
        if entry.level == "w" then warning(entry.msg) else finding(entry.msg) end
      end
    end

    if manifest.registry ~= nil then
      local logs = {}
      local plan = {
        identity = { [dir] = identity },
        effective = { [dir] = manifest.defaults or {} },
      }
      local descriptor = registrarLib.describe(dir, plan, { [identity] = mod },
        { [dir] = manifest }, {}, apiVersion, {
          merge = defaultsLib.merge,
          matchers = matchersLib,
          log = function(level, msg) logs[#logs + 1] = { level = level, msg = msg } end,
        })
      for _, entry in ipairs(logs) do
        if entry.level == "w" then warning(entry.msg) else finding(entry.msg) end
      end

      if descriptor then
        local registryLogs = {}
        local reg = registryLib.new({
          apiVersion = apiVersion or -1,
          log = { w = function(msg) registryLogs[#registryLogs + 1] = msg end },
        })
        local ok = reg.register(descriptor)
        if not ok then
          for _, msg in ipairs(registryLogs) do finding(msg) end
        end
      end

      checkRegistryMembers(dir, identity, manifest, mod)
      checkWiring(dir, identity, manifest, mod)
    elseif manifest.presentation == nil and type(manifest.wiring) == "table" then
      -- A plugin with no registry and no presentation but wiring steps of its own, a bare key
      -- binder for one, still has those steps checked, since checkWiring only needs the module.
      checkWiring(dir, identity, manifest, mod)
    end
    if launcherMembers then checkLauncherMembers(dir, identity, manifest, mod) end
  end
end

----------------------------------------------------------------------------------------
-- Five, the typography rule. A font name, a text size or a line height written by hand
-- outside lib/ui is drift from the kit's roles, the way a hex value written into a tool's
-- config is drift from the palette, so every Lua file under the spoon but the kit itself
-- and test/ is scanned by test/drygate-typography.lua, which holds the patterns and says what
-- counts. drygate.sh finds the files and hands them over in DRYGATE_SOURCES, one path per
-- line, since finding files is the shell's half of the split. A line carrying a type-exempt
-- declaration with a reason, an icon drawn into a small canvas, is not a finding, it is
-- counted as accepted and still printed, so an exemption is never silent. Run without the
-- variable, this check has nothing to read and says so as a warning rather than passing
-- quietly.
----------------------------------------------------------------------------------------

do
  local scanner = dofile(scriptDir .. "drygate-typography.lua")
  local list = os.getenv("DRYGATE_SOURCES")
  if not list or list == "" then
    warning("dry gate did not run the typography check, DRYGATE_SOURCES names no files, run it through test/drygate.sh")
  else
    for path in list:gmatch("[^\n]+") do
      local rel = path:sub(1, #spoonDir) == spoonDir and path:sub(#spoonDir + 1) or path
      local found = scanner.scanFile(path)
      if not found then
        warning(string.format("dry gate could not read '%s' for the typography check", rel))
      else
        for _, hit in ipairs(found) do
          if hit.exempt then
            accepted[#accepted + 1] = string.format("accepted, %s:%d, type-exempt, %s", rel, hit.line, hit.exempt)
          else
            findings[#findings + 1] = string.format(
              "dry gate refused '%s', line %d, %s outside lib/ui, '%s', move it onto a kit role or a radius derived from the surface, or if it is an icon drawn into a canvas declare it with a type-exempt comment and a reason",
              rel, hit.line, hit.what, hit.source)
          end
        end
      end
    end
  end
end

----------------------------------------------------------------------------------------
-- Six, the icon drawing rule. Olm draws every row icon, so a file under plugins that creates a
-- canvas and snapshots it with imageFromCanvas is a plugin drawing an icon of its own, see
-- test/drygate-drawing.lua. It reads the same DRYGATE_SOURCES list as the typography check,
-- restricted to plugins. A file that genuinely has to draw, content such as a thumbnail or a
-- glyph the engine cannot express, is declared in test/drygate-accepted.txt with its reason,
-- where this gate's other exemptions live, and goes through finding() like every other line.
----------------------------------------------------------------------------------------

do
  local scanner = dofile(scriptDir .. "drygate-drawing.lua")
  local list = os.getenv("DRYGATE_SOURCES")
  if list and list ~= "" then
    for path in list:gmatch("[^\n]+") do
      local rel = path:sub(1, #spoonDir) == spoonDir and path:sub(#spoonDir + 1) or path
      if rel:sub(1, 8) == "plugins/" then
        local line = scanner.scanFile(path)
        if line then
          finding(string.format(
            "dry gate refused '%s', it draws onto a canvas to produce an image, a plugin never draws a row icon, declare it under icons in the manifest and name it on the row, or if it is content or a drawing the icon engine cannot express list the file in test/drygate-accepted.txt with a reason",
            rel))
        end
      end
    end
  end
end

----------------------------------------------------------------------------------------
-- Seven, the icon declarations, see test/drygate-icons.lua. Two questions are asked here.
--
-- The first is static. A row literal icon = "key" in a plugin's own Lua must name a key its
-- manifest declares under icons, since a key nothing declares draws nothing and the plugin only
-- says so at run time. Every Lua file under a plugin or a host directory is read, the manifest
-- included, so defaults.icon and a binding's icon are held to the same rule.
--
-- The second is a report. For every icon source, one line says how many declared specs have an
-- entry for it, and a warning names each plugin and key that has none, so a set that does not
-- cover everything is visible rather than found by a row that draws nothing. A spec marked
-- content = true is left out of the counts. Content built at run time, an emoji picker's glyph
-- or a country flag, is not in a manifest and so is not counted at all.
----------------------------------------------------------------------------------------

do
  local iconsScan = dofile(scriptDir .. "drygate-icons.lua")
  local list = os.getenv("DRYGATE_SOURCES")
  local paths = {}
  if list and list ~= "" then
    for path in list:gmatch("[^\n]+") do paths[#paths + 1] = path end
  end

  for _, path in ipairs(paths) do
    local rel = path:sub(1, #spoonDir) == spoonDir and path:sub(#spoonDir + 1) or path
    local dir = rel:match("^plugins/([^/]+)/") or rel:match("^host/([^/]+)/")
    local manifest = dir and manifestsByDir[dir]
    if manifest then
      local f = io.open(path, "r")
      if f then
        local text = f:read("a")
        f:close()
        local declaredKeys = type(manifest.icons) == "table" and manifest.icons or {}
        for _, hit in ipairs(iconsScan.literalKeys(text)) do
          if declaredKeys[hit.key] == nil then
            finding(string.format(
              "dry gate refused '%s', line %d, icon = \"%s\" names a key the manifest of '%s' does not declare under icons, declare it there with an emoji and an sf entry or name one it has",
              rel, hit.line, hit.key, dir))
          end
        end
      end
    end
  end

  local declared = {}
  local dirs = {}
  for dir in pairs(manifestsByDir) do dirs[#dirs + 1] = dir end
  table.sort(dirs)
  for _, dir in ipairs(dirs) do
    local manifest = manifestsByDir[dir]
    -- The registrar's own check of the icons table and of defaults.icon, so a key the manifest
    -- names as its identity icon without declaring it is a finding here and not only a refused
    -- registration at load.
    registrarLib.validateIcons(identityOfDir[dir] or dir, manifest, {
      log = function(_, message) finding("dry gate, " .. message) end,
    })
    if type(manifest.icons) == "table" then
      for key, spec in pairs(manifest.icons) do
        if type(spec) == "table" then declared[#declared + 1] = { owner = dir, key = key, spec = spec } end
      end
    end
    local identity = type(manifest.defaults) == "table" and manifest.defaults.icon
    if type(identity) == "table" then
      declared[#declared + 1] = { owner = dir, key = "defaults.icon", spec = identity }
    end
  end

  local sources = iconsScan.sourceNames(paths)
  if #sources > 0 then
    local report = iconsScan.coverage(declared, sources)
    for _, source in ipairs(sources) do
      coverageLines[#coverageLines + 1] = string.format(
        "icon coverage, %s has an entry for %d of %d declared specs%s",
        source, report.covered[source], report.total,
        report.content > 0 and string.format(", %d content spec(s) not counted", report.content) or "")
      for _, item in ipairs(report.missing[source]) do
        warning(string.format("icon coverage, '%s' has no %s entry", item, source))
      end
    end
  end
end

----------------------------------------------------------------------------------------
-- An accepted line that no longer matches anything this run is itself a finding, appended
-- straight to the real list rather than through finding() above, so it is never itself
-- eligible to be accepted away, the one rule that keeps this file from rotting.
----------------------------------------------------------------------------------------

do
  local staleText = {}
  for text in pairs(acceptedReason) do
    if not acceptedSeen[text] then staleText[#staleText + 1] = text end
  end
  table.sort(staleText)
  for _, text in ipairs(staleText) do
    findings[#findings + 1] = string.format(
      "dry gate refused test/drygate-accepted.txt, its line '%s' does not match any finding this run, remove it or reverify and reword it",
      text)
  end
end

----------------------------------------------------------------------------------------
-- Output. One line per finding, then accepted findings, then warnings, then unknowns, then
-- a summary. Zero output noise on a clean tree means zero findings and zero warnings; an
-- accepted finding still prints, since accepting one is never silent, and an unknown still
-- prints, since silence about a module this gate could not verify would be the false green
-- the whole design of this file exists to refuse. Neither an accepted finding nor a plain
-- unknown fails the gate; a clean tree, meaning every finding is either genuinely absent or
-- explicitly accepted, exits zero, loudly checkable, rather than nonzero forever, which is
-- what a real regression on a genuinely clean tree needs to mean something.
----------------------------------------------------------------------------------------

table.sort(findings)
table.sort(accepted)
table.sort(warnings)
table.sort(unknowns)

for _, line in ipairs(findings) do print(line) end
for _, line in ipairs(accepted) do print(line) end
for _, line in ipairs(warnings) do print("warning, " .. line) end
for _, line in ipairs(unknowns) do print(line) end
for _, line in ipairs(coverageLines) do print(line) end

local pluginCount = 0
for _ in pairs(manifestsByDir) do pluginCount = pluginCount + 1 end

print(string.format(
  "olm dry gate, %d plugin(s) checked, %d finding(s), %d accepted, %d warning(s), %d unknown%s",
  pluginCount, #findings, #accepted, #warnings, #unknowns, strict and ", strict" or ""))

local failed = (#findings > 0) or (strict and #unknowns > 0)
os.exit(failed and 1 or 0)
