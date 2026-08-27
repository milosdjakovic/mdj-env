-- The registry side of composition, and nothing else.
--
-- lib/registry.lua is a plain keyed store that validates a descriptor and answers questions
-- about it later. It reads no configuration and names no plugin, which is exactly right for it
-- and exactly why something else has to build the descriptor it is handed. That something is
-- this file. It turns one plugin's own effective declarations, plus that plugin's own
-- manifest.registry block and whatever a person overrode on top of it, into the well formed
-- table register wants, resolves and binds the physical key that descriptor earns once it is
-- active, assembles the one list whose order decides who wins an alias collision, and adapts
-- the registry instance to the exact no argument contract lib/wire.lua's fifth stage already
-- calls it with.
--
-- The first attempt at this collapsed under its own genericness, and the audit names the exact
-- shape of the collapse. Every registration it built skipped apiVersion, so the real registry
-- refused all twenty seven of them and nothing anywhere read the false it handed back, so the
-- run reported success while the launcher lost every row it had. A default row with no category
-- was refused for the same reason a moment later. Surface arrived as the table itself rather
-- than a function, which the registry refuses on sight since two of the real tools build that
-- table inside their own configure and a value captured at registration time would have
-- captured nothing at all. The base open key was bound against entry.name, which is the tool's
-- registered IDENTITY, while the plan the rest of this build already computes keys everything
-- by the DIRECTORY a plugin was found in, and seven of the real tools spell those two names
-- differently, so seven silently lost their key, their row, their scope and their surface with
-- one warning line each and nothing that read as failure. Every one of those is a defect this
-- file exists to close, and the comment above each function below says which one.
--
-- A second attempt closed all of that and shipped a defect just as total in the opposite
-- direction. obj.describe asked only a root owned meta table for a registration, keyed by
-- identity, and answered nil the moment that table had nothing to say for a name, which on a
-- fresh install is every name, since nobody assembling cfg for a portable spoon has any reason
-- to know a second, wholly undocumented table called cfg.registry even exists. Every tool's
-- base open key bound nothing, the cheat sheet's own actions section listed nothing, and
-- nothing anywhere logged a problem, because wire.lua's own register stage only acts when
-- describe hands it something to register. The decision that closes this one is the same
-- ambient entitlement rule the rest of this contract already lives by. A plugin knows what it
-- is, so the plugin's own manifest is now the source of its registration, under a field called
-- registry, and cfg.registry becomes an override merged over that per field, never the one and
-- only door a registration can walk through. Fields that generically cannot come from a
-- manifest, a total order across every scoped tool being the one real example, stay root policy
-- and are documented as exactly that where they are read below.
--
-- What this file must never do matters as much as what it does. It never names a tool, never
-- hardcodes a roster, and never reads a keys catalog to find a physical key, because the plan
-- already resolved one for every plugin that declared it and asking a second source for the
-- same fact is exactly the kind of place two answers drift apart with nothing watching. The one
-- deliberate exception is commands, appendCopy and pasteNext being the concrete example a
-- reader can check this file against, since a command belongs to no plugin and so owns no entry
-- in the plan at all. Its key is root policy with nowhere else to live, and the seam that lets
-- it in is commented at the one place it is read, rather than folded quietly into the rule it is
-- the exception to.

local obj = {}

--- obj.member(module, path)
--- Resolves a dotted member name against a real module and answers whatever that member is.
--- A table member, a submodule kept on its parent the way the clipboard keeps its manager and
--- five pickers keep their chooser, is handed back exactly as it sits. A function member is
--- called once, with the table that carried it passed as the receiver, because two of the real
--- tools answer their own control surface from a colon method rather than from a stable field,
--- and a rule that only works for the plain case would silently fail the two tools it was
--- written to cover. This is the whole reason a plugin's own configuration never has to carry a
--- closure to say which member it means, a bare string is enough and this is what turns the
--- string into the real thing.
function obj.member(module, path)
  if module == nil or path == nil then return module end
  local owner, value = module, module
  for part in tostring(path):gmatch("[^.]+") do
    if type(value) ~= "table" then return nil end
    owner, value = value, value[part]
  end
  if type(value) == "function" then
    return value(owner)
  end
  return value
end

-- One member declaration read down to its name and its calling convention, the same two
-- shapes needs.siblings and a wiring step already accept elsewhere in this contract, a bare
-- string defaulting to method, or a table naming member and call. A manifest author reads one
-- rule for every place Olm resolves a name against a real module rather than a different rule
-- per field, and this is the one function that rule is written in.
local function memberSpec(spec)
  if spec == nil then return nil, nil end
  if type(spec) == "string" then return spec, "method" end
  if type(spec) == "table" then return spec.member, spec.call or "method" end
  return nil, nil
end

-- Whether a member NAME, already split from its own spec by memberSpec above, resolves to a
-- real function on module, walking the identical dotted path obj.member and callMember both
-- walk. Phase three of the chooser stage build, the adversarial review's own fourth finding,
-- docs/AUDIT-2026-08-13.md's failure class reopened, a manifest naming a member that resolves
-- to nothing with nothing anywhere reporting it. obj.action's own closure answers nil in
-- silence for exactly this case, by design, since most callers resolve against a module still
-- being assembled inside its own configure and cannot check any earlier than the first real
-- call. A presentation's own members are the one case that can check earlier, since they are
-- resolved at register, stage five, once every plugin's own wiring has already run, so this
-- exists for that one caller rather than folded into obj.action itself. A nil module answers
-- false rather than raising, since nothing loaded has nothing this could resolve against.
local function memberResolves(module, member)
  if module == nil or member == nil then return false end
  local value = module
  for part in tostring(member):gmatch("[^.]+") do
    if type(value) ~= "table" then return false end
    value = value[part]
  end
  return type(value) == "function"
end

-- Whether a member spec states its own call kind outright, dot or method, rather than
-- leaving memberSpec free to default it in silence. Phase three review's own residue on
-- finding four, a dot function declared with no call kind still passes memberResolves above,
-- since existence does not depend on calling convention, and callMember then calls it AS a
-- method, shifting every real argument along by one, the identical shape
-- docs/AUDIT-2026-08-13.md already recorded once for a sibling need bound the wrong way. A
-- presentation's own rows and select run on every keystroke a presenting tool's own list
-- receives, where a shifted argument answers the wrong thing rather than raising, so a
-- presentation member is the one place in this whole contract that refuses the silent
-- default every other member spec still keeps. A bare string can never state a call kind at
-- all, so this answers false for one, and a presentation member must always be written the
-- table way, { member = ..., call = ... }.
local function callKindStated(spec)
  return type(spec) == "table" and (spec.call == "dot" or spec.call == "method")
end

-- Walk a dotted member path against a real module and call whatever sits at the end of it,
-- forwarding every argument this call actually carries. method binds the table the walk
-- stopped at as the first argument, the same receiver a colon call would bind, since a
-- plugin's own colon methods, obj:show, obj:rows, expect exactly that. dot binds nothing
-- extra, since several of the real tools keep their picker on a submodule written as plain
-- dot called functions, function M.show(), and handing one of those a receiver it never
-- declared would shift every real argument along by one, corrupting a scope's own rest or
-- payload silently rather than failing loud, the exact class of defect obj.member's own
-- comment above already guards a colon call against. Answers nil for a path that does not
-- resolve to a function, rather than raising, since a malformed declaration is a defect the
-- registry's own register call already refuses and names on its own terms, not something a
-- lookup two stages earlier should stop the whole run over.
local function callMember(module, member, callKind, ...)
  if type(module) ~= "table" or member == nil then return nil end
  local owner, value = module, module
  for part in tostring(member):gmatch("[^.]+") do
    if type(value) ~= "table" then return nil end
    owner, value = value, value[part]
  end
  if type(value) ~= "function" then return nil end
  if callKind == "dot" then return value(...) end
  return value(owner, ...)
end

--- obj.action(modules, identity, fallbackName, spec, extra)
--- Builds the lazy, argument forwarding function a registration's own open, a scope's rows,
--- run, peek, act and redirect, and a command's fn all resolve through. spec is a member
--- declaration in the shape memberSpec above reads, and nil answers nil, the same "nothing
--- declared" silence describe's own row and surface already keep. The owning module is looked
--- up fresh inside the returned function rather than once while this function is being built,
--- the identical discipline the surface field already keeps and for the identical reason, a
--- plugin that assembles a member inside its own configure, menu search's open and its two
--- scope functions among the real cases, must still be found once that has actually run, and a
--- rule that holds for most tools and quietly fails a few of them is worse than a rule applied
--- everywhere.
---
--- extra, when given, is appended after every real argument the call already carries, and it
--- exists for exactly one seam. Two scoped tools, Vpn and BrowserTabs, ask their own launcher
--- to redraw once an async fetch lands, a direct call to Launcher in the retired root that a
--- manifest must never be asked to name. So each plugin's own rows method now takes a second
--- parameter, a redraw callback, and this is where that callback is actually handed over,
--- sourced from deps.redraw at the one call site that builds it rather than named here, so this
--- file still never learns what Launcher is. A method that declares no second parameter simply
--- never sees the extra argument arrive, the same silent, harmless drop any unused trailing
--- argument already gets in Lua.
function obj.action(modules, identity, fallbackName, spec, extra)
  local member, callKind = memberSpec(spec)
  if member == nil then return nil end
  return function(...)
    local owner = (modules and modules[identity]) or (modules and modules[fallbackName])
    local args = { ... }
    if extra ~= nil then args[#args + 1] = extra end
    return callMember(owner, member, callKind, table.unpack(args))
  end
end

--- obj.describe(name, plan, modules, manifests, meta, apiVersion, deps)
--- Builds one registry descriptor for the plugin the plan wired under this directory name, or
--- answers nil, and the nil case is deliberate rather than a gap. Not every plugin the plan
--- wires is a registry tool, most of the twenty seven manifests answer to no launcher row at
--- all, so this plugin's own manifest.registry, plus whatever meta, the root owned override
--- table, says for this identity, are both asked before anything is built, and a plugin naming
--- neither is quietly not a registration rather than a malformed one.
---
--- Which of the two is asked first is the whole point of this build's second pass. The plugin's
--- own manifest.registry is the base, since the plugin is the one thing that can honestly know
--- its own category, its own open action, its own scope, and meta, when it has an opinion for
--- this identity, merges OVER that base through deps.merge, lib/defaults.lua's own merge, field
--- by field, respecting the same NONE removal sentinel and the same list replaced wholesale, map
--- merged per key rules a person's own configuration already answers to everywhere else. A
--- plugin declaring a category of Tools and a root override changing only its glyph is one
--- merge call away rather than two competing tables neither of which alone is complete. meta may
--- also answer the boolean false for one identity, read the same way a person's own top level
--- false already reads for a whole plugin, and it means decline this one registration outright
--- even though the plugin itself proposed one, which is what lets an installer hide a tool's
--- launcher row without switching the tool itself off.
---
--- Nothing is built at all, not even an empty descriptor, when manifest.registry and meta's own
--- entry for this identity are both absent, and nothing is built either when the merge answers
--- false. Both are the honest meaning of a plugin that wants no registry row, never a machine
--- condition worth a warning, so both return nil in silence exactly where the row and surface
--- fields already stay silent for the same reason a line below.
---
--- eff, the plugin's own effective declarations already merged with whatever the person
--- overrode, gives description, glyph, aliases, key and leader, since those are what the plugin
--- itself proposed or the person changed through the ordinary defaults door, the same one every
--- other field in this config answers to. The merged registry table, info below, gives
--- everything else, category, detail, keywords, open, surface, hosted, shortcut, commands and
--- scope, since all of it is now the plugin's own claim about itself, reconciled against
--- whatever the root chose to override, rather than a second, competing source of truth about a
--- fact the manifest already states.
---
--- surface is never the value info names, it is always a fresh function built around it, unless
--- info hands over a function directly, the escape hatch a root override may still reach for
--- when a surface is genuinely policy rather than anything a manifest could ever carry. A
--- manifest itself may only ever name a member, a string obj.member resolves, or the literal
--- boolean true, meaning the plugin's own module is its own surface, vpn and caffeinate being the
--- real two, both flat single file plugins with no chooser submodule of their own. Resolution
--- happens lazily, on every call, never once here, the same discipline obj.member's own comment
--- above already explains and for the same reason, a plugin that builds its surface inside its
--- own configure must still be found once that has actually run.
---
--- open, and every scope and command action, resolve through obj.action above instead, since
--- unlike surface they are not asked for a value, they are run, later, with real arguments a
--- scope's own caller hands them on every keystroke or every chosen row, and obj.member's own
--- "call the function once and keep what it answered" contract would run a tool's open action
--- immediately, at describe time, rather than handing back something that runs it once a key is
--- actually pressed.
---
--- scope carries one field none of the twelve real tools' own manifest fields have needed
--- before, guard, a member resolved once, live, right here, answering whether this plugin's
--- scope should exist at all this run. Emoji is the real case. Its own facade picks a backend
--- at start, and the system Character Viewer has no rows of its own to hand over, so a scope
--- built regardless of which backend won would open onto an empty list rather than the plain
--- unscoped search that already works. guard is asked with obj.action's own colon or dot
--- discipline and is expected to answer true, and only true, before scope is built at all.
--- Every other manifest may simply omit it and always get the scope it declared.
---
--- apiVersion is never invented here. It arrives as an argument because the one number every
--- registration must equal belongs to the core, not to this file, and passing it through rather
--- than hardcoding it is what keeps a version bump a one line change at the one place that reads
--- spoon.Olm.apiVersion instead of a grep across every tool. Skipping it, or answering it with a
--- boolean, is exactly how the first attempt's registrations were refused twenty seven times over
--- with nothing anywhere reading the false that came back, audit findings eight and thirty.
function obj.describe(name, plan, modules, manifests, meta, apiVersion, deps)
  plan = plan or {}
  deps = deps or {}
  assert(type(deps.merge) == "function",
    "registrar.describe needs deps.merge, lib/defaults.lua's own merge, to reconcile a "
      .. "plugin's own manifest.registry against whatever the root chose to override")

  local identity = (plan.identity and plan.identity[name]) or name

  local manifest = (manifests and (manifests[identity] or manifests[name])) or {}
  local manifestSpec = manifest.registry
  local overrideSpec = meta and meta[identity]

  -- Neither side has an opinion, so this is not a registration, quietly, the same silence
  -- row and surface already keep a line below for the identical reason.
  if manifestSpec == nil and overrideSpec == nil then return nil end

  local info = deps.merge(manifestSpec or {}, overrideSpec)
  -- The root declined this one identity's registration outright, read the same way a
  -- person's own top level false already reads for a whole plugin.
  if info == false then return nil end

  local eff = (plan.effective and plan.effective[name]) or {}

  local rowSpec = info.row
  local row = nil
  if type(rowSpec) == "table" and rowSpec.category ~= nil then
    row = {
      category = rowSpec.category,
      detail = rowSpec.detail,
      keywords = rowSpec.keywords,
      glyph = rowSpec.glyph or eff.glyph,
      aliases = eff.aliases,
      description = eff.description,
      key = eff.key,
      leader = eff.leader,
    }
  end

  local open = nil
  if type(info.open) == "function" then
    open = info.open
  elseif info.open ~= nil then
    open = obj.action(modules, identity, name, info.open, nil)
  end

  local surface = nil
  if info.surface ~= nil then
    if type(info.surface) == "function" then
      surface = info.surface
    else
      local surfaceSpec = info.surface
      -- owner is looked up inside the closure rather than once out here, the same laziness
      -- the string case exists for in the first place, so a module handed in only partially
      -- built at describe time still resolves against whatever it grew into by the time
      -- something actually asks this surface for real.
      surface = function()
        local owner = (modules and modules[identity]) or (modules and modules[name])
        if surfaceSpec == true then return owner end
        return obj.member(owner, surfaceSpec)
      end
    end
  end

  local commands = nil
  if type(info.commands) == "table" then
    commands = {}
    for cmdName, cmdSpec in pairs(info.commands) do
      cmdSpec = cmdSpec or {}
      local fn = nil
      if type(cmdSpec.fn) == "function" then
        fn = cmdSpec.fn
      else
        fn = obj.action(modules, identity, name, cmdSpec.fn, nil)
      end
      -- The command's own key and mods are folded ONTO its row rather than left beside it.
      -- A command belongs to no plugin directory, so nothing downstream can look its key up
      -- the way a tool's own key is looked up through the plan, and a catalogue drawing a row
      -- for it needs the chord to write the subtitle. The row is the only thing that travels
      -- that far, so this is where the answer has to ride.
      local cmdRow = cmdSpec.row
      if type(cmdRow) == "table" and (cmdSpec.key or cmdSpec.mods) then
        cmdRow = {}
        for k, v in pairs(cmdSpec.row) do cmdRow[k] = v end
        cmdRow.key = cmdRow.key or cmdSpec.key
        cmdRow.mods = cmdRow.mods or cmdSpec.mods
      end
      commands[cmdName] = { fn = fn, row = cmdRow, shortcut = cmdSpec.shortcut }
    end
  end

  local scope = nil
  if type(info.scope) == "table" then
    local s = info.scope
    local admit = true
    if s.guard ~= nil then
      local gMember, gCall = memberSpec(s.guard)
      local owner = (modules and modules[identity]) or (modules and modules[name])
      admit = callMember(owner, gMember, gCall) == true
    end
    if admit then
      scope = {
        matcher = s.matcher,
        rows = obj.action(modules, identity, name, s.rows, deps.redraw),
        run = obj.action(modules, identity, name, s.run, deps.redraw),
        peek = obj.action(modules, identity, name, s.peek, deps.redraw),
        redirect = obj.action(modules, identity, name, s.redirect, deps.redraw),
        act = obj.action(modules, identity, name, s.act, deps.redraw),
      }
      if type(s.verbs) == "table" then
        scope.verbs = {}
        for action, verbSpec in pairs(s.verbs) do
          scope.verbs[action] = {
            fn = obj.action(modules, identity, name, verbSpec, deps.redraw),
            closes = verbSpec and verbSpec.closes,
          }
        end
      end
    end
  end

  -- presentation, phase three of the chooser stage build, docs/BRIEF-HANDOFF.md decision
  -- three. Read off the manifest directly rather than off info, since a presentation is not
  -- registry policy a person's own cfg.registry could reasonably override, it is a structural
  -- fact about how this plugin shows its own rows, so there is no second source to merge
  -- against here the way registry itself merges against meta.
  --
  -- rows and select are required, resolved through obj.action exactly as a scope's own rows
  -- and run already are, so the module is looked up fresh every time a row is chosen rather
  -- than once here, the identical laziness every other member this file resolves already
  -- keeps for a plugin that assembles its own module inside its own configure. select is the
  -- manifest's own word for the contract's onSelect, the same word this plugin's own
  -- provides.select and registry.scope.run already use for the identical function, so one
  -- plugin never has to name the same member two different ways.
  --
  -- placeholder is resolved differently, once, right here, rather than handed over as a
  -- closure, because the presentation contract wants a plain string a presentation carries,
  -- not a function to call later. By the time this file runs, register is the fifth of the
  -- eight fixed stages, every plugin's own wiring step has already run, so a member that
  -- reads live state, VPN's own available flag among them, answers the real answer rather
  -- than one frozen before that state existed.
  --
  -- The remaining contract fields, intercept, back, onHighlight, onClose, peekPreview,
  -- onPresent, and onPositioned, resolve the same way rows does, and a plugin naming none of
  -- them hands the stage a presentation with nothing under that name, exactly as an ordinary
  -- presentation table already allows. onPresent is the phase three review's own second
  -- finding, called by the stage whenever this presentation becomes current through present or
  -- push, the seam a plugin whose own rows depend on an async fetch, VPN among them, starts
  -- that fetch from rather than depending on some other door having already warmed it.
  -- onPositioned is the geometry brief's own addition, docs/BRIEF-GEOMETRY.md decision one,
  -- called by the stage with the chooser and companion frames whenever it repositions the pair
  -- for this presentation, mirroring the shape and the name lib/chooser/providers/native.lua's
  -- own config.onPositioned already carries, so a plugin migrating its own companion pane onto
  -- the stage in phase five hands over the identical function it already wrote for that field
  -- with nothing to rewrite. rowCount and paneWidth are both read as a plain value, a number
  -- or, for paneWidth, true, never a member, since the contract itself never asks either one to
  -- be computed. matcher, contract v2 decision one, joins them as a third plain value, false or
  -- a strategy name, checked below rather than in the loop above for the identical reason.
  -- enter, contract v2 decision two, is a member like rows and the rest, called with one
  -- function, proceed, in place of the stage showing this presentation immediately, for a tool
  -- whose own rows depend on gathering something first and whose own design record already
  -- rejected a show then correct flash, Processes' own documented scan rule among them.
  --
  -- Every named member is checked against the REAL, already loaded module before any of this
  -- is trusted, the phase three review's own fourth finding, docs/AUDIT-2026-08-13.md's
  -- failure class reopened, a manifest naming a member that resolves to nothing with nothing
  -- anywhere reporting it. obj.action's own closure answers nil in silence for exactly that
  -- case, by its own design, since a lookup made once here cannot see a module a plugin still
  -- assembles inside its own configure, but a presentation's rows and select are checked here
  -- BECAUSE this file runs at register, stage five, after every plugin's own wiring has
  -- already completed, so the module this checks against is the real, finished one rather than
  -- one still being built. callKindStated above is what makes that check honest rather than
  -- merely present, refusing a member whose own calling convention was left to a default this
  -- contract does not trust for a presentation.
  local presentation = nil
  if type(manifest.presentation) == "table" then
    local p = manifest.presentation
    local owner = (modules and modules[identity]) or (modules and modules[name])
    local presentationFields = {
      "rows", "select", "placeholder", "intercept", "back",
      "onHighlight", "onClose", "peekPreview", "onPresent", "onPositioned",
      -- enter, contract v2 decision two, docs/BRIEF-CONTRACT-V2.md. A member spec exactly
      -- like every other one in this list, resolved the same lazy way and checked the same
      -- way, since it is called with one argument, proceed, and a wrong call kind would shift
      -- that argument into whatever the receiver would have occupied, the identical silent
      -- failure the comment above this whole loop already worries about for rows and select.
      "enter",
    }
    local broken = false
    for _, field in ipairs(presentationFields) do
      local declared = p[field]
      if declared ~= nil then
        if not callKindStated(declared) then
          broken = true
          if deps.log then
            deps.log("e", string.format(
              "registrar refused '%s', its presentation.%s does not state call, dot or method, explicitly",
              name, field))
          end
        else
          local member = memberSpec(declared)
          if not memberResolves(owner, member) then
            broken = true
            if deps.log then
              deps.log("e", string.format(
                "registrar refused '%s', its presentation.%s names '%s', which does not resolve to a function on the real module",
                name, field, tostring(member)))
            end
          end
        end
      end
    end
    -- Adversarial review finding H3, the phase four geometry rework. rowCount and paneWidth
    -- are the two contract fields that are plain values rather than member specs, so the loop
    -- above never touches either, and until this fix neither was checked at all, anywhere,
    -- between the manifest and the stage. A bad rowCount, a string typed where a number was
    -- meant, or the member spec shape written by habit since nine of the eleven other fields
    -- take exactly that shape, reached math.min inside the atom's own _positionAndShow with
    -- nothing to stop it, raised there, and left layout.rowCount corrupted on the one instance
    -- the stage never rebuilds, wedging every future show of every presentation until the
    -- config reloads. paneWidth already survived a bad value, host/stage/init.lua's own
    -- _resolvePaneWidth refuses anything that is not a positive number or true, but only at
    -- runtime, on every call, with no console line naming the tool, which is a weaker and
    -- quieter protection than refusing the registration once, loudly, here, so it is checked
    -- here too, to close the asymmetry rather than leave one field better protected than the
    -- other for a reason nobody chose on purpose.
    -- Rider N4 of the geometry review, second pass. A plain number check alone still let
    -- zero, a negative, and a fraction through to math.min and then to rows(), each one a
    -- degenerate window rather than the crash the first fix already closed, and the refusal
    -- costs nothing to widen. paneMaxW gives the arithmetic a sane ceiling of its own
    -- already, so this only needs a floor and a wholeness check, not a matching cap.
    if p.rowCount ~= nil and (type(p.rowCount) ~= "number" or p.rowCount < 1 or p.rowCount % 1 ~= 0) then
      broken = true
      if deps.log then
        deps.log("e", string.format(
          "registrar refused '%s', its presentation.rowCount is '%s', not a positive whole number",
          name, tostring(p.rowCount)))
      end
    end
    if p.paneWidth ~= nil and p.paneWidth ~= true and type(p.paneWidth) ~= "number" then
      broken = true
      if deps.log then
        deps.log("e", string.format(
          "registrar refused '%s', its presentation.paneWidth is '%s', not a plain number or true",
          name, tostring(p.paneWidth)))
      end
    end
    -- Contract v2 decision one, docs/BRIEF-CONTRACT-V2.md. matcher is the third contract field
    -- that is a plain value rather than a member spec, false meaning the supplier owns
    -- filtering the way four unmigrated consumers already ask for today, or a string naming
    -- one of the strategies the Chooser atom itself exports, deps.matchers, the identical
    -- table root/compose.lua already resolves this same word against for every consumer that
    -- still builds its own Chooser.new. A string that names nothing there would otherwise
    -- reach host/stage/init.lua's own _resolveMatcher at runtime, which falls back to the root
    -- default in silence rather than raising, so a typo would read as "this presentation just
    -- inherited fuzzy" with nothing anywhere saying a word was misspelled. Checked here, once,
    -- loudly, naming the tool and the unknown strategy, the same discipline rowCount and
    -- paneWidth just above already keep. deps.matchers absent, which nothing in the ordinary
    -- wiring pass ever leaves true, degrades to skipping this one check rather than refusing
    -- every string outright, since a missing dependency of the CHECK is not the same claim as
    -- a bad VALUE from the plugin.
    if p.matcher ~= nil and p.matcher ~= false then
      if type(p.matcher) ~= "string" then
        broken = true
        if deps.log then
          deps.log("e", string.format(
            "registrar refused '%s', its presentation.matcher is '%s', not false or a string naming a matcher strategy",
            name, tostring(p.matcher)))
        end
      elseif deps.matchers and not deps.matchers[p.matcher] then
        broken = true
        if deps.log then
          deps.log("e", string.format(
            "registrar refused '%s', its presentation.matcher names '%s', which is not a strategy the Chooser atom exports",
            name, p.matcher))
        end
      end
    end
    -- Finding ten. A presenting plugin routes by identity, isShowingFor and the surface
    -- adapters loop both ask the registry by identity and the stage's own current() answers
    -- the identity the registrar stamped, but the docked hint bar still looks the answer up in
    -- plan.contexts, which is keyed by this plugin's own declared surface.context when it
    -- named one. The two agree today because every plugin that presents also spells its
    -- context exactly as its identity, and nothing enforces that agreement, so a plugin that
    -- ever let them diverge would route, gate, and present correctly while its hint bar quietly
    -- went empty. One console line, naming both words, so that divergence cannot happen in
    -- silence even though this phase does not fix the routing itself.
    local declaredContext = manifest.surface and manifest.surface.context
    if declaredContext and declaredContext ~= identity and deps.log then
      deps.log("w", string.format(
        "registrar found '%s' presenting under identity '%s' while its surface declares context '%s', the docked hint bar routes by identity and will not follow that context",
        name, identity, declaredContext))
    end
    if broken then
      -- Passed through as an empty, structurally invalid presentation rather than dropped
      -- or refused by returning nil here, phase three review's own second residue on finding
      -- four. Returning nil, the first pass at this fix, refused the tool just as hard but
      -- through silence, since lib/wire.lua's own self.register only ever calls
      -- pcall(registry.register, descriptor) when describe answered something, so a nil
      -- descriptor here left w.report() saying no problems while a tool had vanished from
      -- the catalogue with only the console line above as evidence. An empty table instead
      -- still reaches lib/registry.lua's own presentationIsWellFormed, which refuses it on
      -- the identical "has no rows function" it already gives a malformed scope, so
      -- instance.register answers false, and self.register's own fail records the problem in
      -- wire.record.problems the same way a malformed scope's refusal already does. The
      -- deps.log lines above already named the real reason, this is what carries the refusal
      -- the rest of the way to a report a person might actually read.
      presentation = {}
    else
      presentation = {
        name = identity,
        rows = obj.action(modules, identity, name, p.rows, nil),
        onSelect = obj.action(modules, identity, name, p.select, nil),
        intercept = obj.action(modules, identity, name, p.intercept, nil),
        back = obj.action(modules, identity, name, p.back, nil),
        onHighlight = obj.action(modules, identity, name, p.onHighlight, nil),
        onClose = obj.action(modules, identity, name, p.onClose, nil),
        peekPreview = obj.action(modules, identity, name, p.peekPreview, nil),
        onPresent = obj.action(modules, identity, name, p.onPresent, nil),
        onPositioned = obj.action(modules, identity, name, p.onPositioned, nil),
        -- enter, contract v2 decision two, resolved the identical lazy way every other member
        -- above already is, so a plugin that assembles it inside its own configure is still
        -- found once that has actually run.
        enter = obj.action(modules, identity, name, p.enter, nil),
        rowCount = p.rowCount,
        paneWidth = p.paneWidth,
        -- matcher, contract v2 decision one, carried through as the plain value the check
        -- above already trusts, false, a strategy name, or nil, never resolved into the
        -- actual matcher function here, since host/stage/init.lua's own _resolveMatcher is
        -- what holds the Chooser factory this would have to be looked up against.
        matcher = p.matcher,
      }
      if p.placeholder ~= nil then
        local resolvePlaceholder = obj.action(modules, identity, name, p.placeholder, nil)
        presentation.placeholder = resolvePlaceholder and resolvePlaceholder()
      end
    end
  end

  return {
    name = identity,
    apiVersion = apiVersion,
    open = open,
    hosted = info.hosted,
    shortcut = info.shortcut,
    commands = commands,
    scope = scope,
    row = row,
    surface = surface,
    presentation = presentation,
  }
end

--- obj.bind(entry, plan, deps)
--- Binds one entry from registry.shortcuts(), the base open key for an active, registered tool
--- or one of its commands. entry carries name, kind and fn, exactly what the registry answers
--- and nothing more, since the registry itself reads no configuration and holds no key.
---
--- entry.name is the tool's IDENTITY, colorPicker for the real tool that lives in a directory
--- called eyedropper, while plan.effective is keyed by the DIRECTORY, and seven of the twelve
--- real tools spell the two differently. Binding straight against entry.name, the way the first
--- attempt did, finds nothing for those seven and loses their key with one warning line each and
--- nothing that reads as failure, audit findings ten and thirty two. So the identity map the
--- plan already built is walked once here, backwards, to find which directory answers to this
--- identity, and only then is plan.effective asked for a key.
---
--- A command answers to neither. appendCopy and pasteNext are not tools of their own, they are
--- named actions the clipboard's own registration carries, so the reverse walk above finds no
--- directory for them and plan.effective has nothing to say either. Their key is root policy
--- with nowhere else to live, not a manifest concern and not something this plan was ever asked
--- to resolve, so deps.rootKey is the one seam this function leans on a named collaborator for,
--- a lookup the composition root builds over whatever it kept for its own commands, asked only
--- once the plan has already answered no for a name.
---
--- kind decides which engine binds it. leader goes through deps.bindLeader, the Hyper leader
--- every registered tool's own open key already goes through. global goes through
--- deps.bindGlobal, hs.hotkey underneath it, which the first attempt never wired a branch for at
--- all, so the clipboard's two global commands, the only entries that carry that kind, were
--- never bound and never wired, audit finding twelve. Neither engine is named here, both arrive
--- through deps, since which concrete thing binds a leader chord is the composition root's own
--- business and this file's job stops at deciding which of the two engines this entry wants.
function obj.bind(entry, plan, deps)
  plan = plan or {}
  deps = deps or {}

  local directory = nil
  for dirName, identity in pairs(plan.identity or {}) do
    if identity == entry.name then
      directory = dirName
      break
    end
  end

  local eff = directory and (plan.effective or {})[directory]
  if not eff and deps.rootKey then
    eff = deps.rootKey(entry.name)
  end

  if not eff or not eff.key then
    if deps.log then
      deps.log("w", "registrar has no key for '" .. tostring(entry.name) .. "', nothing bound")
    end
    return
  end

  if entry.kind == "leader" then
    if not deps.bindLeader then
      if deps.log then deps.log("w", "registrar has no deps.bindLeader, '" .. tostring(entry.name) .. "' is not bound") end
      return
    end
    deps.bindLeader(eff.key, eff.mods, entry.fn)
  elseif entry.kind == "global" then
    if not deps.bindGlobal then
      if deps.log then deps.log("w", "registrar has no deps.bindGlobal, '" .. tostring(entry.name) .. "' is not bound") end
      return
    end
    deps.bindGlobal(eff.mods, eff.key, entry.fn)
  else
    if deps.log then
      deps.log("w", "registrar does not know the shortcut kind '" .. tostring(entry.kind)
        .. "' for '" .. tostring(entry.name) .. "'")
    end
  end
end

--- obj.forWire(registry, activation, defaultRoster)
--- Adapts a real registry instance to the exact shape lib/wire.lua's fifth stage calls, three
--- fields, register, activate and shortcuts, activate and shortcuts both called with nothing
--- after them, pcall(registry.activate) and registry.shortcuts() with no argument at all. The
--- real instance already answers register and shortcuts in that shape, so both are handed
--- straight through, but activate takes a roster on the real instance and this stage never has
--- one to give it, so the roster the real activate wants is decided in here instead, once,
--- lazily, at the moment activate is actually called rather than at the moment this adapter is
--- built, since nothing has registered yet when forWire itself runs.
---
--- The roster answers to three sources in order. A setting a future roster picker writes always
--- wins, since it is the person's own runtime choice made after every reload this file will ever
--- see. Failing that, activation, whatever roster the caller configured, for a person who has
--- opinions but has not yet written them through a picker. Failing that too, defaultRoster, or,
--- when that was never supplied either, every name that registered this run, answered fresh off
--- the real instance's own all(), since that is what makes a fresh install activate everything
--- rather than nothing, exactly the two things the first attempt got backwards. It read only
--- user.settings.toolActivation, so an absent settings block silently activated nothing and
--- deactivated every tool's row, its scope and its key with nothing anywhere naming what
--- happened, audit findings twenty six and forty five, and the persisted setting a real roster
--- picker would one day write was never consulted at all.
function obj.forWire(registry, activation, defaultRoster)
  assert(registry, "registrar.forWire needs a real registry instance to adapt")

  -- Namespaced under Olm rather than left bare, since this is a portable spoon now and a bare
  -- key would collide with whatever else on the machine ever calls hs.settings.set with the same
  -- short word.
  local SETTINGS_KEY = "Olm.registryActivation"

  local function everyRegisteredName()
    local names = {}
    for _, entry in ipairs(registry.all() or {}) do
      names[#names + 1] = entry.name
    end
    return names
  end

  return {
    register = registry.register,
    shortcuts = registry.shortcuts,
    activate = function()
      local persisted = hs.settings.get(SETTINGS_KEY)
      local roster = persisted or activation or defaultRoster or everyRegisteredName()
      registry.activate(roster)
    end,
  }
end

--- obj.scopeSpec(plan, modules, meta)
--- Assembles the ordered list registry.scopes() is asked to resolve, preserving that order
--- exactly, because QueryScope gives a colliding alias to whichever scope claims it first, so
--- meta.scopeOrder is still read, and is still the one way to state a deliberate order, but it is
--- no longer how a contested word is meant to be settled and nothing in this config sets it. A
--- central list of plugin names, held outside every plugin, is a roster, and a roster is the shape
--- this whole design exists to remove, since adding a tool then means editing a file somewhere
--- else that nothing checks. What replaced it is below. Two scopes claiming one word are named as
--- a collision and one of the two declarations is changed, which ends the contest at its source
--- instead of ranking it forever.
---
--- A string entry is translated through plan.identity first, directory to identity, since
--- registry.scopes() resolves a string against the names tools are registered under, and a
--- root array authored against a directory name, the same slip that cost seven tools their key
--- elsewhere in this file, would otherwise resolve against nothing and log one warning per
--- plugin with the list quietly one entry short every time. A string already naming a registered
--- identity, one plan.identity has no directory answering to, passes through unchanged, and
--- every non string entry, the plain narrowing objects, passes through exactly as it arrived,
--- since registry.scopes() already knows to leave those alone.
--- What this answers is the assembled list QueryScope's own configure takes, one table per
--- scopable tool carrying name, title, aliases, glyph and every function half of the contract.
--- It used to answer a list of NAMES instead, which read as correct and was not, because
--- QueryScope refuses anything without a title, a rows and a run, so a bare string was rejected
--- the moment it arrived. With nothing in meta.scopeOrder on a fresh install the list came out
--- empty rather than wrong, which is worse, since an empty list is silent and every scoped tool
--- simply stopped being reachable by typing its word with no line anywhere saying so.
---
--- The two halves come from two places on purpose. names, the plan's own answer to the set
--- question about who provides rows and select, decides MEMBERSHIP, and the registry decides
--- what each member actually is, because only the registry knows which tools ended up
--- registered and active, and a tool that is present but switched off must not keep its word.
--- The presentation half, title and aliases and glyph, is read off the registry's own row first
--- and off the plan's effective values second, so a root override of a description reaches the
--- scope directory rather than only the launcher row.
function obj.scopeSpec(plan, registry, names, meta)
  plan = plan or {}
  local out = {}
  if not registry then return out end

  -- identity back to directory, since plan.effective is keyed by the directory while
  -- everything the registry holds is keyed by identity, and seven of the real tools spell the
  -- two differently. Getting this backwards is the same slip that cost those seven their key.
  local directoryOf = {}
  for dirName, identity in pairs(plan.identity or {}) do directoryOf[identity] = dirName end

  -- meta.scopeOrder leads where it is given, because who owns a contested word is a total
  -- order across unrelated plugins that no single manifest could express. Everything the set
  -- answered and the order did not name follows, in the order the plan already settled.
  local ordered, seen = {}, {}
  local function add(entry)
    local identity = (plan.identity and plan.identity[entry]) or entry
    if not seen[identity] then
      seen[identity] = true
      ordered[#ordered + 1] = identity
    end
  end
  for _, entry in ipairs((meta and meta.scopeOrder) or {}) do
    if type(entry) == "string" then add(entry) end
  end
  for _, identity in ipairs(names or {}) do add(identity) end

  for _, identity in ipairs(ordered) do
    local scope = registry.scopeFor and registry.scopeFor(identity)
    if scope then
      local row = registry.rowFor and registry.rowFor(identity)
      local eff = (plan.effective or {})[directoryOf[identity] or identity] or {}
      local aliases = (row and row.aliases) or eff.aliases
      out[#out + 1] = {
        name = identity,
        title = (row and row.description) or eff.description,
        glyph = (row and row.glyph) or eff.glyph,
        aliases = aliases,
        matcher = scope.matcher,
        rows = scope.rows,
        run = scope.run,
        peek = scope.peek,
        redirect = scope.redirect,
        act = scope.act,
        verbs = scope.verbs,
      }
    end
  end
  return out
end

--- obj.aliasCollisions(scopes)
--- Two scopes in one assembled list claiming the same typed word, reported rather than ranked.
---
--- This is what makes a hand written priority order unnecessary. Two scopes answering to one word
--- is a defect identical on every machine, exactly like two plugins proposing one key, and this
--- repository already refuses to resolve THAT by load order, on the grounds that picking a winner
--- turns a fixed defect into a different defect on every reload. A total order over unrelated
--- plugins, kept in one central list outside all of them, is the same silent winner picking with a
--- longer setup, and it hides the duplicate rather than ending it. So the duplicate is named, both
--- claimants in the line, and one of the two declarations gets changed.
---
--- Asked of the FINISHED list rather than from inside obj.scopeSpec, and that is the whole reason
--- it is its own function. Only some of these scopes reach a registered tool. The rest narrow a
--- host's own catalog and are appended afterwards, so a check living inside scopeSpec cannot see
--- them, and across this whole set the one word ever genuinely contested was contested by exactly
--- one of each kind.
---
--- Case insensitive, since a typed word is matched that way, and self collision is impossible by
--- construction because a scope is only ever compared against the ones before it.
function obj.aliasCollisions(scopes)
  local claimedBy, hits = {}, {}
  for _, scope in ipairs(scopes or {}) do
    for _, alias in ipairs((scope or {}).aliases or {}) do
      local word = tostring(alias):lower()
      local owner = claimedBy[word]
      if owner and owner ~= scope.name then
        hits[#hits + 1] = { alias = alias, first = owner, second = scope.name }
      elseif not owner then
        claimedBy[word] = scope.name
      end
    end
  end
  return hits
end

--- obj.aliasDirectory(deps)
--- The one scope that lists every other scope, and the last resort fallback for entering one, a
--- click whose row the accessibility tree could not resolve before the chooser it was in had
--- already closed. Both live on one function because both end on the same word, whichever scope
--- a row named, and splitting them would duplicate the one place that already knows how to ask
--- for it.
---
--- rows answers one row per resolvable scope, its title and its alias hint, sorted so a
--- reference list reads as one rather than in whatever order the catalog happened to answer.
--- redirect and run both ask deps.queryFor for the canonical word a chosen row means, since which
--- alias is canonical and what separates it from the rest of the query is the resolver's own
--- grammar and never this function's to decide or restate. redirect hands that word back so the
--- list already open can seed its own field with it, the ordinary path every row now takes. run
--- is the fallback path alone, used only when nothing already open can be handed a word, so it
--- opens deps.show's own list itself with the word seeded, and answers nothing, loudly, through
--- deps.log, when the name given resolves to no live alias at all rather than opening onto a
--- seed that would claim nothing.
---
--- deps.catalog, deps.queryFor and deps.show are the one named collaborator this function cannot
--- do without, the resolver a directory of every scope is fundamentally a policy over, so this
--- is the seam the brief for this file asks to be marked rather than hidden inside a rule meant
--- for ordinary plugins. Nothing here spells that collaborator's name, it arrives as plain
--- functions and this function never learns what built them. deps.aliasLabel is asked for too
--- and is not part of that seam, it is only how a set of aliases is worded, which the
--- composition root answers once so this file and a launcher row cannot word it differently.
function obj.aliasDirectory(deps)
  deps = deps or {}
  assert(type(deps.catalog) == "function", "aliasDirectory needs deps.catalog, every resolvable scope")
  assert(type(deps.queryFor) == "function", "aliasDirectory needs deps.queryFor, the canonical word for a name")
  assert(type(deps.show) == "function", "aliasDirectory needs deps.show, opening a list with a word seeded")
  assert(type(deps.aliasLabel) == "function", "aliasDirectory needs deps.aliasLabel, the one spelling of a set of aliases")

  local name = deps.name or "aliasDirectory"

  return {
    name = name,
    title = deps.title,
    glyph = deps.glyph,
    aliases = deps.aliases,
    rows = function()
      local out = {}
      for _, entry in ipairs(deps.catalog() or {}) do
        if entry.name ~= name then
          out[#out + 1] = {
            title = entry.title,
            subTitle = deps.aliasLabel(entry.aliases),
            glyph = entry.glyph,
            item = entry.name,
          }
        end
      end
      table.sort(out, function(a, b) return a.title < b.title end)
      return out
    end,
    redirect = function(itemName) return deps.queryFor(itemName) end,
    run = function(itemName)
      local query = deps.queryFor(itemName)
      if not query then
        if deps.log then
          deps.log("i", "no live alias for the " .. tostring(itemName) .. " scope, so there is nothing to enter")
        end
        return
      end
      deps.show(query)
    end,
  }
end

return obj
