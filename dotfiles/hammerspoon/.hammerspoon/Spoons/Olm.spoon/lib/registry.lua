-- The tool registry, phase seven of the build plan, packet one. A registry keyed by
-- name, backing dispatch by name, Strategy with the strategy chosen at runtime by a
-- string. The launcher depends on the registry's read side and on nothing concrete. A
-- tool depends on nothing at all, which is the part worth protecting. It names no tool,
-- reads no configuration, and imports nothing from the tree beyond hs.logger, which is
-- what makes it the first part of this config testable in the unit runner rather than
-- only live.
--
-- M.new(opts) returns an independent instance, a factory in the same style as
-- lib/recency.lua, since a registry is state and the config builds one. opts.apiVersion
-- is the core version every registration is checked against, injected at construction
-- rather than read from spoon.Olm, since the registry must not reach for the spoon that
-- contains it. A missing or non numeric opts.apiVersion raises a readable error, the
-- same choice recency.lua makes for its own missing opts.settingsKey, since that is a
-- caller misusing the factory rather than a tool's own data.
--
-- opts.log is the logger every warning below is written through, defaulting to this
-- module's own hs.logger instance and existing only so a unit case can hand in a small
-- table answering w(message) and read the refusal back directly, without going through
-- hs.logger's own global, shared, process wide history buffer. The composition root
-- never passes it, and every default construction behaves exactly as if this option did
-- not exist.
--
-- One table per tool is handed to register, the descriptor. name is the tool's own key,
-- the identity its manifest declares and config/plugins.lua keys by, a string, required. apiVersion is the integer the tool was built
-- against, required. open is a function of no arguments, what running this tool's
-- launcher row does, optional, because a tool may exist only as a scope. commands was a map
-- of extra named actions belonging to a tool, each with its own row and shortcut, and it
-- retired in phase 2b of the keymap plan, since an action descriptor in a plugin's
-- provides.actions is the one way to declare something runnable. A descriptor still carrying
-- commands is refused, naming the tool.
--
-- row, added in that same packet, is optional, a table describing this tool's launcher
-- row, presentation data the launcher reads through rowFor rather than owning itself. A
-- tool with no row gets none on its launcher row, which is what a tool reachable only as
-- a scope will want. Its one required field, once present, is category, the word before
-- the separator in the subtitle the launcher renders, everything else inside it, keysName,
-- detail, glyph, keywords, and chord, is presentation data this module never reads, opaque
-- to the registry and meaningful only to the launcher on the other end of rowFor.
--
-- scope, added in phase seven's fourth packet, is optional, a table carrying exactly
-- the fields the composition root's own scope helper passes through today, matcher,
-- rows, run, peek, redirect, act, and, since phase eight's fourth packet, verbs. The
-- identity fields that helper adds on top, name, title, glyph, and aliases, are
-- deliberately not here, since three of them come from the manifest defaults and config/plugins.lua and this
-- registry reads no configuration, the same rule that keeps name the tool's only
-- identity above. rows and run are required once scope is present at all, since
-- QueryScope's own admissible function requires both, and refusing here names the
-- registration rather than leaving QueryScope to refuse the assembled scope later with
-- a line naming only the scope. matcher, peek, redirect and act are all optional,
-- matcher accepting false or a function since four scopes set it false today, and the
-- other three accepting only a function or absence. verbs is optional too, a map from
-- an action name to what running it takes, the tool saying once which of its verbs make
-- sense when a hosted list is holding its rows rather than its own picker. Each entry is
-- a bare function or a table carrying that function under fn plus a required closes,
-- described where verbParts is. closes says whether running this verb should close the list it ran
-- against, and it has no default, the same choice this phase already made for a
-- binding's kind, so the day a second verb is declared it joins the wrong side in
-- silence rather than being asked. Validated two levels deeper than the other four,
-- since it holds a table of its own shapes rather than being one, verbs present and not
-- a table is refused naming the tool, a verbs entry that is neither a bare function nor
-- a table with a callable fn is refused naming the tool and the action, and a verbs
-- entry whose closes is missing or is not a boolean, a bare function among the ways
-- that happens, is refused naming the tool and the action too, since a verb that never
-- says whether it closes is refused rather than guessed at.
--
-- surface, added in phase seven's second packet, is optional, a function of no
-- arguments returning this tool's navigation adapter, the object answering isShowing
-- and whatever navigation methods its context binds. It is a function and never the
-- surface itself because two of the nine tools this packet moved build that surface
-- inside their own configure and hand it back from a method, and that configure call
-- runs far below where the registration sits, so capturing the result at registration
-- time would capture nothing at all, permanently and silently. Every registration obeys
-- this discipline even where the surface is already a stable module reference and would
-- have survived either way, since a rule that holds for seven tools and quietly fails
-- two of them is worse than a rule applied everywhere. hosted, also added in that
-- packet, is optional, a plain boolean, true when choosing this tool's launcher row
-- should host its list in place rather than open its own picker, and nothing more.
--
-- shortcut, added in phase seven's fifth and last packet, is optional, one of exactly two
-- strings. leader means this tool's open is bound on a leader, and global means it is bound
-- as a plain combination. The key itself is deliberately not on the descriptor, it is the
-- tool's open row in the keymap, which the plugin suggests in defaults.bindings, and this
-- registry reads no configuration, the same rule name and row and scope already keep. A
-- shortcut present and not one of the two strings is refused, naming the tool and what it
-- said. A shortcut present with nothing to bind, no open on the tool, is refused too, since a
-- shortcut bound to nothing is worse than no shortcut at all.
--
-- register(descriptor) validates, then records, and refuses rather than raises, so one
-- bad tool cannot empty the launcher. Every refusal is one log line at warning naming
-- the tool and the reason, and register answers true when it registered and false when
-- it refused. A descriptor with no name, or a name that is not a string, is refused, and
-- cannot be named in its own error, so the line says what it can. A second registration
-- under a name already taken is refused, naming the tool, since first registration wins. A
-- descriptor still carrying commands is refused, naming the tool and what replaced them. An
-- apiVersion that is missing,
-- not an integer, or not equal to the core's, is refused, naming the tool, the version
-- it declared, and the version the core offers, since the version is bumped only on a
-- breaking change and equality is the only check that respects that. A surface that is
-- present and is not a function is refused, naming the tool, since a surface handed in
-- already built is exactly the mistake the discipline above exists to catch. A row that
-- is present and is not a table is refused, naming the tool. A row that is present and
-- has no category is refused, naming the tool too, since a subtitle rendered with no
-- category would render wrong rather than absent, and wrong is the worse failure of the
-- two. A scope that is present and is not a table is
-- refused, naming the tool. A scope present without a rows function, or without a run
-- function, is refused, naming the tool and which of the two is missing, since QueryScope
-- requires both and the registration is a better place to learn about the same mistake
-- than a line further along naming only the scope. A scope's matcher, present and neither
-- false nor a function, is refused naming the tool and the field, and a scope's peek,
-- redirect, or act, present and not a function, is refused the same way, naming the tool
-- and whichever field was wrong. A scope's verbs, present and not a table, is refused
-- naming the tool, a verbs entry that is neither a bare function nor a table with a
-- callable fn is refused naming the tool and the action, and a verbs entry whose closes
-- is missing or is not a boolean is refused the same way, naming the tool and the
-- action, since a verb that never says whether it closes is refused rather than
-- guessed at. A shortcut, present and neither leader nor global, is refused naming the tool
-- and what it said, and a shortcut present with nothing to bind, no open on the tool, is
-- refused too, naming the same.
--
-- activate(names) takes a list of tool names and is called once after every
-- registration. A registered tool whose name is in the list is active, one not in the
-- list is registered and inactive. A name in the list that nothing registered produces
-- one warning line naming it and is otherwise ignored, since a typo in a roster should
-- be visible and harmless rather than fatal. names answers to the same refuse rather
-- than raise principle register does. The composition root hands it every name that
-- registered, since whether a plugin runs is decided by the plan alone and this is not a
-- second switch. Anything that is not a table, nil aside, logs
-- one warning naming what it got and leaves the active set empty rather than raising
-- out of config load, which would otherwise take down the whole of Hammerspoon rather
-- than only the launcher.
--
-- The read side. run(name) looks the name up in the flat index of tool names, and calls
-- it when the tool is active, answering true when it ran something and false when it did
-- not, which is what lets a caller fall through. get(name) hands back the descriptor of an
-- active tool or nil. rowFor(name), added in phase seven's third packet, answers the row
-- table of an active tool, or nil, resolved through the same flat index run uses, so an
-- inactive tool answers nil. That is what makes an inactive tool's launcher row
-- disappear the moment the launcher asks rowFor for it, the mechanism this module owed
-- since phase seven's first packet and finally pays here, even though nothing is
-- deactivated by default today, so the disappearance has nothing yet to show against.
-- scopeFor(name), added in phase seven's fourth packet, answers the scope table of an
-- active tool in the same shape, resolved through the same flat index, so an inactive
-- tool and an unknown name both answer nil.
-- active() lists active tool names in registration order. all() lists every registered
-- tool name with its active flag, and, since phase seven's second and fourth packets,
-- whether it declared a surface, whether it declared hosted, and whether it declared a
-- scope, all five for diagnostics only and all five presence rather than resolved value,
-- since asking a live surface to resolve itself at snapshot time would ask the question
-- at a different moment than the live code asks it and could disagree with it for
-- reasons that are not defects. An inactive tool answers nil and false to every read
-- except all(). An inactive tool's chord is never bound in the first place, since
-- phase seven's fifth and last packet, rather than bound and then torn down. Nothing in
-- this config ever unbinds a key, HyperKey has no removal and hs.hotkey is never asked
-- for one, so inventing teardown here would be the single caller ceremony with a silent
-- failure mode the design principles reject. The composition root binds only what
-- shortcuts() below hands it, and that list already answers nil for anything inactive,
-- so the only thing left to do about an inactive tool's key is never reach the bind call
-- at all, which costs nothing and fails in no new way.
--
-- scopes(spec), added in phase seven's fourth packet, resolves an ordered list mixing
-- tool names and plain objects into an ordered list the root can fold into queryScopes.
-- A string entry names a registered tool and logs one warning naming it when nothing is
-- registered under that name at all. A registered but inactive tool is skipped without a
-- word, the same nil-and-false every other read already answers for it, and an active
-- tool that simply declared no scope this run is skipped without a word too, since that
-- is the emoji case this whole packet protects, a scope that registers only under a
-- condition and is legitimately absent when the condition does not hold, never the
-- mistake an unregistered name is. A resolved tool answers a small table carrying both
-- name and opts rather than a finished scope, since joining the identity fields
-- the manifest defaults and config/plugins.lua hold, name, title, glyph, and aliases, is the composition root's own
-- scope(name, opts) helper's job and stays there, in the one place that has always done
-- it, this module reading no configuration at all. Anything that is not a string passes
-- straight through unexamined, in the position it was given.
--
-- shortcuts(), added in phase seven's fifth and last packet, takes no spec, since unlike
-- scopes it names nothing the composition root already holds a competing object for, and
-- answers in registration order one entry per active tool that declares a shortcut, each
-- carrying name, kind, and fn, the function to bind. An inactive tool contributes nothing,
-- the same nil-and-false silence every other read already answers for it, which is the
-- whole mechanism that keeps an inactive tool's key unbound.
--
-- A surfaces(spec) door once stood beside scopes here, added in phase seven's second
-- packet and resolving the identical shape for navigation adapters instead of scopes.
-- The composition root never wired through it, building its own list by hand instead,
-- consumer map surprise 9.10, docs/CONSUMER-MAP-2026-08-27.md, so it sat dead from the
-- day it was added. Deleted in the chooser stage close out rather than left as a second,
-- unwired mechanism beside the one the root actually uses.
--
-- Every function below is a plain field on the returned instance and is meant to be dot
-- called, matching lib/recency.lua exactly, never colon called, since there is no
-- metatable here and no self to receive.

local M = {}

--- M.new(opts) returns instance.
--- Returns a fresh instance holding its own tools, its own flat dispatch index, and its
--- own active set, independent of any other instance. opts.apiVersion is required, the
--- integer every registration is checked against.
function M.new(opts)
  opts = opts or {}
  local coreApiVersion = opts.apiVersion
  if type(coreApiVersion) ~= "number" then
    error("registry new requires opts.apiVersion, the integer core version every registration is checked against")
  end

  local log = opts.log or hs.logger.new("Registry", "info")

  local instance = {}

  local toolsByName = {}  -- tool name to descriptor, as given to register
  local flatIndex = {}    -- a tool's own name to { tool = name, fn = function or nil, row, scope, presentation }
  local order = {}        -- tool names in registration order, what active() and all() walk
  local activeTools = {}  -- tool name to true, replaced whole on every activate call

  local function isInteger(v)
    return type(v) == "number" and v == math.floor(v)
  end

  -- A row is optional, and when present it is validated the same way a surface is, a
  -- table only, one required field inside it. Absent is fine and answers true, since
  -- optional means structural, absent rather than empty. name is the tool, used for both
  -- refusals.
  local function rowIsWellFormed(row, name)
    if row == nil then return true end
    if type(row) ~= "table" then
      log.w(string.format(
        "Registry refused '%s', its row is present and is not a table", name))
      return false
    end
    if row.category == nil then
      log.w(string.format(
        "Registry refused '%s', its row has no category", name))
      return false
    end
    return true
  end

  -- A verbs entry is a bare function or a table carrying that function under fn plus its own
  -- closes. A bare verb cannot mean the whole of what a verb is, because closes has no default, the same choice this phase already
  -- made for a binding's kind rather than letting a future one default to whichever side is
  -- convenient today. So this still recognises a bare function as carrying a callable, but
  -- never as carrying a closes, which is what makes the required
  -- check just below refuse it precisely for not saying rather than for the wrong reason,
  -- being the wrong shape. Anything else, closes included, answers a nil function, which
  -- scopeIsWellFormed below refuses rather than stores.
  local function verbParts(spec)
    if type(spec) == "function" then return spec, nil end
    if type(spec) == "table" and type(spec.fn) == "function" then return spec.fn, spec.closes end
    return nil, nil
  end

  -- A scope is optional, and when present it is validated the way a row is, structural
  -- rather than partial, refusing the whole registration rather than accepting a scope
  -- with a hole in it. rows and run are both required once a scope is present at all,
  -- since QueryScope's own admissible function requires both and would otherwise refuse
  -- the assembled scope later with a line naming the scope rather than the registration
  -- that produced it, a worse place to learn about the same mistake. matcher, peek,
  -- redirect and act are all optional. matcher is the one field that is not a function
  -- when present, it is false on four scopes today, so false or a function is accepted
  -- and anything else is refused. peek, redirect and act each accept only a function or
  -- absence, the same rule QueryScope's own admissible function already applies to them.
  local function scopeIsWellFormed(scope, name)
    if scope == nil then return true end
    if type(scope) ~= "table" then
      log.w(string.format(
        "Registry refused '%s', its scope is present and is not a table", name))
      return false
    end
    if type(scope.rows) ~= "function" then
      log.w(string.format(
        "Registry refused '%s', its scope has no rows function", name))
      return false
    end
    if type(scope.run) ~= "function" then
      log.w(string.format(
        "Registry refused '%s', its scope has no run function", name))
      return false
    end
    if scope.matcher ~= nil and scope.matcher ~= false and type(scope.matcher) ~= "function" then
      log.w(string.format(
        "Registry refused '%s', its scope's matcher is present and is neither false nor a function", name))
      return false
    end
    if scope.peek ~= nil and type(scope.peek) ~= "function" then
      log.w(string.format(
        "Registry refused '%s', its scope's peek is present and is not a function", name))
      return false
    end
    if scope.redirect ~= nil and type(scope.redirect) ~= "function" then
      log.w(string.format(
        "Registry refused '%s', its scope's redirect is present and is not a function", name))
      return false
    end
    if scope.act ~= nil and type(scope.act) ~= "function" then
      log.w(string.format(
        "Registry refused '%s', its scope's act is present and is not a function", name))
      return false
    end
    if scope.verbs ~= nil then
      if type(scope.verbs) ~= "table" then
        log.w(string.format(
          "Registry refused '%s', its scope's verbs is present and is not a table", name))
        return false
      end
      for action, spec in pairs(scope.verbs) do
        local fn, closes = verbParts(spec)
        if not fn then
          log.w(string.format(
            "Registry refused '%s', its scope's verbs entry '%s' is not a function or a table with a callable fn",
            name, tostring(action)))
          return false
        end
        if type(closes) ~= "boolean" then
          log.w(string.format(
            "Registry refused '%s', its scope's verbs entry '%s' does not say whether it closes the list",
            name, tostring(action)))
          return false
        end
      end
    end
    return true
  end

  -- A presentation is optional, and when present it is validated the way a scope is,
  -- structural rather than partial, refusing the whole registration rather than accepting a
  -- presentation with nothing to show, the identical discipline scopeIsWellFormed already
  -- keeps just above. rows and onSelect are both required, the same two the presentation
  -- contract itself, BRIEF-STAGE.md version one, calls required beside name, name being this
  -- registry's own to stamp on rather than anything a manifest declares. Every other field a
  -- presentation carries, intercept, back, onHighlight, onClose, peekPreview, onPresent,
  -- onPositioned, rowCount, and paneWidth, the geometry brief's own addition, is optional here,
  -- this function checking only that a presentation exists at all rather than the shape of
  -- any one field beyond rows and onSelect. rowCount and paneWidth are checked for their own
  -- type one layer up, in lib/registrar.lua, adversarial review finding H3, since that is
  -- where the manifest's own declaration is still in hand to name in a refusal, by the time a
  -- presentation table reaches this function both are already trustworthy, a plain number or,
  -- for paneWidth, true, and the stage itself already answers for what a presentation with a
  -- hole in any of the rest of them means.
  local function presentationIsWellFormed(presentation, name)
    if type(presentation) ~= "table" then
      log.w(string.format(
        "Registry refused '%s', its presentation is present and is not a table", name))
      return false
    end
    if type(presentation.rows) ~= "function" then
      log.w(string.format(
        "Registry refused '%s', its presentation has no rows function", name))
      return false
    end
    if type(presentation.onSelect) ~= "function" then
      log.w(string.format(
        "Registry refused '%s', its presentation has no onSelect function", name))
      return false
    end
    return true
  end

  -- A shortcut is optional, and when present it is one of exactly two strings, leader or
  -- global, checked the way row and scope are, refusing the whole registration rather
  -- than a partial acceptance. hasFn is whether the tool's own open actually exists, since
  -- a shortcut naming nothing to bind is worse than no shortcut at all.
  local function shortcutIsWellFormed(shortcut, hasFn, label)
    if shortcut == nil then return true end
    if shortcut ~= "leader" and shortcut ~= "global" then
      log.w(string.format(
        "Registry refused '%s', its shortcut is '%s', neither 'leader' nor 'global'",
        label, tostring(shortcut)))
      return false
    end
    if not hasFn then
      log.w(string.format(
        "Registry refused '%s', its shortcut has nothing to bind", label))
      return false
    end
    return true
  end

  --- instance.register(descriptor)
  --- Validate one tool's descriptor and record it. Refuses rather than raises, logging
  --- one warning naming the tool and the reason, and answers true when it registered,
  --- false when it refused.
  function instance.register(descriptor)
    descriptor = descriptor or {}
    local name = descriptor.name
    if type(name) ~= "string" or name == "" then
      log.w("Registry refused a descriptor, its name is missing or is not a string")
      return false
    end
    if flatIndex[name] then
      log.w(string.format(
        "Registry refused a second registration for '%s', the first registration keeps it", name))
      return false
    end
    -- Commands retired in phase 2b of the keymap plan. A descriptor still carrying them is
    -- refused whole rather than registered without them, since a tool that silently lost the
    -- rows and keys its commands declared is the quieter and worse failure.
    if descriptor.commands ~= nil then
      log.w(string.format(
        "Registry refused '%s', it carries commands, which retired, an action descriptor in provides.actions replaces each", name))
      return false
    end
    if not isInteger(descriptor.apiVersion) or descriptor.apiVersion ~= coreApiVersion then
      log.w(string.format(
        "Registry refused '%s', apiVersion %s does not match the core's %s",
        name, tostring(descriptor.apiVersion), tostring(coreApiVersion)))
      return false
    end
    if descriptor.surface ~= nil and type(descriptor.surface) ~= "function" then
      log.w(string.format(
        "Registry refused '%s', its surface is present and is not a function", name))
      return false
    end
    if not rowIsWellFormed(descriptor.row, name) then return false end
    if not scopeIsWellFormed(descriptor.scope, name) then return false end
    if not shortcutIsWellFormed(descriptor.shortcut, descriptor.open ~= nil, name) then return false end
    if descriptor.presentation ~= nil and not presentationIsWellFormed(descriptor.presentation, name) then
      return false
    end
    toolsByName[name] = descriptor
    flatIndex[name] = { tool = name, fn = descriptor.open, row = descriptor.row, scope = descriptor.scope,
      presentation = descriptor.presentation }
    order[#order + 1] = name
    return true
  end

  --- instance.activate(names)
  --- Replace the active set with the given list of tool names. Refuses rather than
  --- raises, the same principle register answers to. names that is not a table logs one
  --- warning naming what it got and leaves the active set empty. A name nothing
  --- registered logs its own warning and is otherwise ignored.
  function instance.activate(names)
    activeTools = {}
    if names == nil then return end
    if type(names) ~= "table" then
      log.w(string.format("Registry activate refused %s, a list of tool names is required", tostring(names)))
      return
    end
    for _, name in ipairs(names) do
      if toolsByName[name] then
        activeTools[name] = true
      else
        log.w(string.format("Registry activate ignored '%s', nothing registered under that name", tostring(name)))
      end
    end
  end

  --- instance.run(name)
  --- Call a tool's own open when the tool is active. Answers true when it ran something,
  --- false when it did not, whether because the name is unregistered, the tool is inactive,
  --- or it has no open.
  function instance.run(name)
    local entry = flatIndex[name]
    if not entry or not activeTools[entry.tool] or not entry.fn then return false end
    entry.fn()
    return true
  end

  --- instance.get(name)
  --- The descriptor of an active tool, or nil.
  function instance.get(name)
    if toolsByName[name] and activeTools[name] then return toolsByName[name] end
    return nil
  end

  --- instance.rowFor(name)
  --- The row table of an active tool, or nil. Resolves through the same flat index run
  --- uses, so an inactive tool answers nil, which is what makes an inactive tool's row
  --- disappear.
  function instance.rowFor(name)
    local entry = flatIndex[name]
    if not entry or not activeTools[entry.tool] then return nil end
    return entry.row
  end

  --- instance.scopeFor(name)
  --- The scope table of an active tool, or nil, in the same shape rowFor answers in.
  --- Resolved through the same flat index, so an inactive tool and an unknown name both
  --- answer nil.
  function instance.scopeFor(name)
    local entry = flatIndex[name]
    if not entry or not activeTools[entry.tool] then return nil end
    return entry.scope
  end

  --- instance.presentationFor(name)
  --- The presentation table of an active tool, or nil, the same shape rowFor and scopeFor
  --- already answer in. Phase three of the chooser stage build. nil for a tool that never
  --- declared one, which is what lets a launcher row fall through to the old close, defer,
  --- open path without the caller ever having to ask what migrated means, and nil for an
  --- inactive tool too, the same rule every other read through this flat index already keeps.
  function instance.presentationFor(name)
    local entry = flatIndex[name]
    if not entry or not activeTools[entry.tool] then return nil end
    return entry.presentation
  end

  --- instance.active()
  --- Active tool names, in registration order.
  function instance.active()
    local out = {}
    for _, name in ipairs(order) do
      if activeTools[name] then out[#out + 1] = name end
    end
    return out
  end

  --- instance.all()
  --- Every registered tool name with its active flag, whether it declared a surface,
  --- whether it declared hosted, and whether it declared a scope, in registration order,
  --- for diagnostics only. All three report presence on the descriptor rather than a
  --- resolved value, since resolving one here would ask the question at a different
  --- moment than the live code asks it. scope presence beside hosted is what lets a
  --- reader see a tool that is hosted with no scope behind it, which is legitimate for a
  --- tool whose scope registers only under a condition, and stable in a committed file
  --- rather than a warning nobody is watching for.
  function instance.all()
    local out = {}
    for _, name in ipairs(order) do
      local descriptor = toolsByName[name]
      out[#out + 1] = {
        name = name,
        active = activeTools[name] == true,
        surface = descriptor.surface ~= nil,
        hosted = descriptor.hosted == true,
        scope = descriptor.scope ~= nil,
      }
    end
    return out
  end

  --- instance.listing()
  --- Every ACTIVE registered tool that carries a row, in registration order. What a catalogue
  --- builds its rows from, so that a list of tools is asked for rather than kept by hand. Each
  --- entry names the tool twice, as name and as tool, the shape the catalogue reads, which
  --- once also held a tool's commands and still says which tool a row belongs to.
  function instance.listing()
    local out = {}
    for _, name in ipairs(order) do
      if activeTools[name] then
        local descriptor = toolsByName[name]
        if descriptor.row then
          out[#out + 1] = { name = name, tool = name }
        end
      end
    end
    return out
  end

  --- instance.scopes(spec)
  --- Resolve an ordered list mixing tool names and plain objects, the same shape
  --- surfaces reads, into an ordered list the root can fold into queryScopes. A string
  --- entry names a registered tool. Logged and skipped when nothing is registered under
  --- that name at all, the same mistake surfaces warns about. Skipped without a word when
  --- the tool is registered but inactive, and skipped without a word too when the tool is
  --- active and declared no scope this run, the emoji case this packet protects, a scope
  --- that registers only under a condition. A resolved tool answers { name = entry, opts
  --- = descriptor.scope } rather than a finished scope, since joining the identity fields
  --- from the manifest defaults and config/plugins.lua is the root's own scope(name, opts) helper's job and stays
  --- there. Anything that is not a string passes straight through unexamined, in the
  --- position it was given.
  function instance.scopes(spec)
    local out = {}
    if spec == nil then return out end
    for _, entry in ipairs(spec) do
      if type(entry) ~= "string" then
        out[#out + 1] = entry
      else
        local descriptor = toolsByName[entry]
        if not descriptor then
          log.w(string.format(
            "Registry scopes found no tool registered under '%s'", entry))
        elseif not activeTools[entry] then
          -- Inactive is the legitimate silent case, the same nil-and-false every other
          -- read already answers for it, so nothing is logged and nothing is added.
        elseif not descriptor.scope then
          -- An active tool with no scope is the other legitimate silence, the emoji case
          -- this packet protects, a scope registering only under a condition that did
          -- not hold this run, so nothing is logged here either.
        else
          out[#out + 1] = { name = entry, opts = descriptor.scope }
        end
      end
    end
    return out
  end

  --- instance.shortcuts()
  --- One entry per active tool that declares a shortcut, in registration order, each
  --- carrying name, kind (leader or global), and fn, the function to bind. An inactive tool
  --- contributes nothing, which is what keeps an inactive tool's key from ever being bound.
  function instance.shortcuts()
    local out = {}
    for _, name in ipairs(order) do
      if activeTools[name] then
        local descriptor = toolsByName[name]
        if descriptor.shortcut then
          out[#out + 1] = { name = name, kind = descriptor.shortcut, fn = descriptor.open }
        end
      end
    end
    return out
  end

  return instance
end

return M
