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
-- One table per tool is handed to register, the descriptor. name is the tool's own key
-- in config/keys.lua, a string, required. apiVersion is the integer the tool was built
-- against, required. open is a function of no arguments, what running this tool's
-- launcher row does, optional, because a tool may exist only as a scope. commands is a
-- map of name to function, extra named actions belonging to this tool rather than tools
-- of their own, optional. A commands value may instead be a table carrying that function
-- under fn plus its own optional row, which is how appendCopy and pasteNext, added in
-- phase seven's third packet, keep their own launcher row while remaining commands of the
-- clipboard rather than tools of their own.
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
-- deliberately not here, since three of them come from config/keys.lua and this
-- registry reads no configuration, the same rule that keeps name the tool's only
-- identity above. rows and run are required once scope is present at all, since
-- QueryScope's own admissible function requires both, and refusing here names the
-- registration rather than leaving QueryScope to refuse the assembled scope later with
-- a line naming only the scope. matcher, peek, redirect and act are all optional,
-- matcher accepting false or a function since four scopes set it false today, and the
-- other three accepting only a function or absence. verbs is optional too, a map from
-- an action name to what running it takes, the tool saying once which of its verbs make
-- sense when a hosted list is holding its rows rather than its own picker. Each entry is
-- a bare function or a table carrying that function under fn plus a required closes, the
-- same dual shape a commands entry already takes below, with one difference, described
-- where verbParts is. closes says whether running this verb should close the list it ran
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
-- strings. leader means this tool's entry in config/keys.lua names a key that is bound
-- through the Hyper leader to this tool's open. global means the entry names a whole
-- modifier combination bound directly, which is what the two clipboard commands are and
-- the only thing they are. A command inside commands may carry the same field on its own
-- table, which is how appendCopy and pasteNext each answer global while remaining commands
-- of the clipboard rather than tools of their own. The key itself is deliberately not on
-- the descriptor, config/keys.lua holds it and this registry reads no configuration, the
-- same rule name and row and scope already keep. A shortcut present and not one of the two
-- strings is refused, naming the tool or the command and what it said. A shortcut present
-- with nothing to bind, no open on a tool or no callable fn on a command, is refused too,
-- since a shortcut bound to nothing is worse than no shortcut at all.
--
-- register(descriptor) validates, then records, and refuses rather than raises, so one
-- bad tool cannot empty the launcher. Every refusal is one log line at warning naming
-- the tool and the reason, and register answers true when it registered and false when
-- it refused. Twentyone refusals exist. A descriptor with no name, or a name that is not a
-- string, is refused, and cannot be named in its own error, so the line says what it
-- can. A second registration under a name already taken is refused, naming the tool,
-- since first registration wins. A commands key equal to the tool's own name is
-- refused, naming both, since the tool's own name is not yet in the flat index at the
-- point a command is checked, only a prior tool's is, and without this check a
-- descriptor could otherwise overwrite its own open with no warning at all. A commands
-- key colliding with any name already indexed, whether a tool name or another tool's
-- command, is refused, naming both sides, since the flat index dispatch reads makes
-- such a collision ambiguity rather than a preference. An apiVersion that is missing,
-- not an integer, or not equal to the core's, is refused, naming the tool, the version
-- it declared, and the version the core offers, since the version is bumped only on a
-- breaking change and equality is the only check that respects that. A surface that is
-- present and is not a function is refused, naming the tool, since a surface handed in
-- already built is exactly the mistake the discipline above exists to catch. A row that
-- is present and is not a table is refused, naming the tool. A row that is present and
-- has no category is refused, naming the tool too, since a subtitle rendered with no
-- category would render wrong rather than absent, and wrong is the worse failure of the
-- two. Both row refusals apply equally to a command's own row, refused under the owning
-- tool's name, since the whole registration is refused together whichever row inside it
-- is malformed. A commands entry that is neither a function nor a table with a callable
-- fn is refused, naming the tool and the command, since storing it anyway would let run
-- answer false forever with nothing logged, quieter than the raise such a value produced
-- before this packet and therefore worse. A scope that is present and is not a table is
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
-- guessed at. A shortcut, present and neither leader nor global, is
-- refused naming the tool or the command and what it said, and a shortcut present with
-- nothing to bind, no open on the tool or no callable fn on the command, is refused too,
-- naming the same. The second of those two is unreachable for a command in practice,
-- since a command with no callable fn is already refused above before its shortcut is
-- ever examined, and it is kept anyway so the one function answering a tool's shortcut
-- answers a command's exactly the same way rather than two functions drifting apart.
--
-- activate(names) takes a list of tool names and is called once after every
-- registration. A registered tool whose name is in the list is active, one not in the
-- list is registered and inactive. A name in the list that nothing registered produces
-- one warning line naming it and is otherwise ignored, since a typo in a roster should
-- be visible and harmless rather than fatal. names answers to the same refuse rather
-- than raise principle register does, since the activation list is meant to come from a
-- persisted setting a future roster writes, and a value of the wrong shape there is a
-- question of when rather than whether. Anything that is not a table, nil aside, logs
-- one warning naming what it got and leaves the active set empty rather than raising
-- out of config load, which would otherwise take down the whole of Hammerspoon rather
-- than only the launcher.
--
-- The read side. run(name) looks the name up in the flat index of tool names and
-- command names, and calls it when the owner is active, answering true when it ran
-- something and false when it did not, which is what lets a caller fall through.
-- get(name) hands back the descriptor of an active tool or nil, and answers nil for a
-- command name, since a command is not a tool. rowFor(name), added in phase seven's
-- third packet, answers the row table of an active tool or of a command of an active
-- tool, or nil, resolved through the same flat index run uses, so a command's row is
-- found under the command's own name and an inactive tool answers nil for itself and
-- for every command it owns. That is what makes an inactive tool's launcher row
-- disappear the moment the launcher asks rowFor for it, the mechanism this module owed
-- since phase seven's first packet and finally pays here, even though nothing is
-- deactivated by default today, so the disappearance has nothing yet to show against.
-- scopeFor(name), added in phase seven's fourth packet, answers the scope table of an
-- active tool in the same shape, resolved through the same flat index, so an inactive
-- tool, an unknown name, and a command name all answer nil, a command's nil because
-- nothing in this packet gives a command its own scope.
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
-- surfaces(spec), added in phase seven's second packet, takes an ordered list and
-- answers an ordered list. A string entry names a registered tool, and resolves to that
-- tool's surface when the tool is active and has one, is skipped silently when the tool
-- is registered and inactive, since that is what inactive already means, and logs one
-- warning naming it when nothing is registered under that name at all. An active tool
-- with no surface at all is neither of those legitimate cases, somebody named a tool in
-- a navigation list that has nothing to navigate, so this too logs one warning naming
-- the tool and is skipped, matching the shape of the two warnings beside it rather than
-- falling off the end of the check in silence. When a named tool's surface is resolved
-- and the result is missing, or is present but has no isShowing, one warning names the
-- tool and it is skipped the same way, so a hazard that would otherwise be silent is
-- loud at the moment it happens. Any entry that is not a string passes straight through
-- unexamined, which is how a surface with no tool behind it, built from root local code
-- with no descriptor of its own, keeps its place in the list. The mix is deliberate. A
-- string names something this registry knows about. Any other value is an object the
-- composition root holds and this registry has never heard of, and passing it through
-- untouched is the whole of what it owes that object. Resolution happens inside this
-- call and never at registration, which is the same discipline the surface field itself
-- observes above.
--
-- scopes(spec), added in phase seven's fourth packet, is the same door a second time,
-- resolving an ordered list mixing tool names and plain objects the same way surfaces
-- does, for the same reason, so the two mistakes that look alike are treated alike. A
-- string entry names a registered tool and logs one warning naming it when nothing is
-- registered under that name at all, exactly as surfaces warns for the same mistake. Two
-- silences stay silences here though, unlike surfaces. A registered but inactive tool is
-- skipped without a word, the same nil-and-false every other read already answers for
-- it, and an active tool that simply declared no scope this run is skipped without a
-- word too, since that is the emoji case this whole packet protects, a scope that
-- registers only under a condition and is legitimately absent when the condition does
-- not hold, never the mistake an unregistered name is. A resolved tool answers a small
-- table carrying both name and opts rather than a finished scope, since joining the
-- identity fields config/keys.lua holds, name, title, glyph, and aliases, is the
-- composition root's own scope(name, opts) helper's job and stays there, in the one
-- place that has always done it, this module reading no configuration at all. Anything
-- that is not a string passes straight through unexamined, in the position it was given,
-- the same shape surfaces already reads its own spec in.
--
-- shortcuts(), added in phase seven's fifth and last packet, takes no spec, since unlike
-- surfaces and scopes it names nothing the composition root already holds a competing
-- object for, and answers in registration order one entry per active tool or active
-- tool's command that declares a shortcut, each carrying name, kind, and fn, the function
-- to bind. An inactive tool contributes nothing, itself or its commands, the same
-- nil-and-false silence every other read already answers for it, which is the whole
-- mechanism that keeps an inactive tool's key unbound. A tool's own commands are walked
-- sorted by their own name rather than in whatever order pairs happens to answer for the
-- literal table a descriptor wrote them in, since Lua promises nothing about that order
-- and a snapshot needs one it can trust run over run, and the choice between two commands'
-- own order is otherwise arbitrary, each binding a different key with nothing to disagree
-- about.
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
  local flatIndex = {}    -- name (a tool's own name or one of its commands) to { tool = ownerName, fn = function or nil }
  local order = {}        -- tool names in registration order, what active() and all() walk
  local activeTools = {}  -- tool name to true, replaced whole on every activate call

  local function isInteger(v)
    return type(v) == "number" and v == math.floor(v)
  end

  -- A row is optional, and when present it is validated the same way a surface is, a
  -- table only, one required field inside it. Absent is fine and answers true, since
  -- optional means structural, absent rather than empty. name is the owning tool, used
  -- for both refusals so a command's malformed row is refused in the same words a
  -- tool's own malformed row would be, naming the tool the registration belongs to
  -- rather than the command inside it, since the whole registration is refused either
  -- way.
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
  -- closes, the same dual shape commandParts already parses further down, with one
  -- difference. A bare command means run it, nothing else to say. A bare verb cannot mean the
  -- whole of what a verb is, because closes has no default, the same choice this phase already
  -- made for a binding's kind rather than letting a future one default to whichever side is
  -- convenient today. So this still recognises a bare function as carrying a callable, the
  -- same as commandParts, but never as carrying a closes, which is what makes the required
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
  -- presentation carries, intercept, back, onHighlight, onClose, peekPreview, and rowCount, is
  -- optional and passed through untouched, since the stage itself already answers for what a
  -- presentation with a hole in one of those means.
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

  -- A commands entry is a bare function, the shape packet one gave it, or a table
  -- carrying that function under fn plus its own optional row and, since phase seven's
  -- fifth and last packet, its own optional shortcut, the shape this packet adds so
  -- appendCopy and pasteNext keep their rows and their global shortcuts while remaining
  -- commands of the clipboard rather than tools of their own. Anything else, a string, a
  -- number, or a table whose fn is missing or is not a function, answers a nil function,
  -- which register below refuses rather than stores. Before row and this shape existed a
  -- bad value was at least stored as is and would have raised when called, loud. Storing
  -- a nil function instead would let it register and let run answer false forever with
  -- nothing logged anywhere, quieter than the raise it replaces and therefore worse, so
  -- this is caught at registration instead.
  local function commandParts(spec)
    if type(spec) == "function" then return spec, nil, nil end
    if type(spec) == "table" and type(spec.fn) == "function" then return spec.fn, spec.row, spec.shortcut end
    return nil, nil, nil
  end

  -- A shortcut is optional, and when present it is one of exactly two strings, leader or
  -- global, checked the way row and scope are, refusing the whole registration rather
  -- than a partial acceptance. label is already the right words for either a tool or a
  -- command, since the caller below builds it, so this function stays ignorant of which
  -- one it is answering for. hasFn is whether the thing the shortcut would bind to, the
  -- tool's own open or the command's own fn, actually exists, since a shortcut naming
  -- nothing to bind is worse than no shortcut at all.
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
    -- A command key is checked against the tool's own name as well as against the flat
    -- index, since the tool's own name is not in that index yet at this point, only a
    -- prior tool's is. Without this a descriptor whose command shares its own name would
    -- pass here and then overwrite its own open below with no warning anywhere, the
    -- validator resolving an ambiguity silently to the wrong answer instead of refusing
    -- it.
    local commands = descriptor.commands or {}
    for key in pairs(commands) do
      if key == name then
        log.w(string.format(
          "Registry refused '%s', its command '%s' collides with its own tool name", name, key))
        return false
      end
      if flatIndex[key] then
        log.w(string.format(
          "Registry refused '%s', its command '%s' collides with '%s' already registered",
          name, key, flatIndex[key].tool))
        return false
      end
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
    for key, spec in pairs(commands) do
      local fn, commandRow, commandShortcut = commandParts(spec)
      if not fn then
        log.w(string.format(
          "Registry refused '%s', its command '%s' is not a function or a table with a callable fn",
          name, key))
        return false
      end
      if not rowIsWellFormed(commandRow, name) then return false end
      if not shortcutIsWellFormed(commandShortcut, fn ~= nil, name .. "'s command '" .. key .. "'") then return false end
    end

    toolsByName[name] = descriptor
    flatIndex[name] = { tool = name, fn = descriptor.open, row = descriptor.row, scope = descriptor.scope,
      presentation = descriptor.presentation }
    order[#order + 1] = name
    for key, spec in pairs(commands) do
      local fn, commandRow = commandParts(spec)
      flatIndex[key] = { tool = name, fn = fn, row = commandRow }
    end
    return true
  end

  --- instance.activate(names)
  --- Replace the active set with the given list of tool names. Refuses rather than
  --- raises, the same principle register answers to. names that is not a table, a
  --- setting written with the wrong shape being a question of when rather than whether,
  --- logs one warning naming what it got and leaves the active set empty. A name nothing
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
  --- Call whatever name resolves to, a tool's own open or one of its commands, when its
  --- owning tool is active. Answers true when it ran something, false when it did not,
  --- whether because the name is unregistered, its owner is inactive, or it names a tool
  --- with no open.
  function instance.run(name)
    local entry = flatIndex[name]
    if not entry or not activeTools[entry.tool] or not entry.fn then return false end
    entry.fn()
    return true
  end

  --- instance.get(name)
  --- The descriptor of an active tool, or nil. Nil for a command name too, since a
  --- command is not a tool.
  function instance.get(name)
    if toolsByName[name] and activeTools[name] then return toolsByName[name] end
    return nil
  end

  --- instance.rowFor(name)
  --- The row table of an active tool or of a command of an active tool, or nil.
  --- Resolves through the same flat index run uses, so a command's row is found under
  --- the command's own name, and an inactive tool answers nil for itself and for every
  --- command it owns, which is what will make an inactive tool's rows disappear once
  --- the activation list finally means that.
  function instance.rowFor(name)
    local entry = flatIndex[name]
    if not entry or not activeTools[entry.tool] then return nil end
    return entry.row
  end

  --- instance.scopeFor(name)
  --- The scope table of an active tool, or nil, in the same shape rowFor answers in.
  --- Resolved through the same flat index, so an inactive tool and an unknown name both
  --- answer nil, and a command name answers nil too, since a scope lives on a tool's own
  --- entry and never on a command's, nothing in this packet gives a command one.
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
  --- Every ACTIVE registered name that carries a row, tools and their commands alike, in
  --- registration order, each tool's commands directly after it. What a catalogue builds its
  --- rows from, so that a list of tools is asked for rather than kept by hand. all() cannot
  --- serve this, it answers tools only and is what the activation roster is built from, so
  --- putting a command in it would have the roster try to activate something that is not a
  --- tool. Commands are sorted by name within their own tool because they are held in a plain
  --- keyed table, and an order that came out of pairs would differ between two machines
  --- running identical code, which a list a person reads must never do.
  function instance.listing()
    local out = {}
    for _, name in ipairs(order) do
      if activeTools[name] then
        local descriptor = toolsByName[name]
        if descriptor.row then
          out[#out + 1] = { name = name, tool = name, isCommand = false }
        end
        local commandNames = {}
        for key in pairs(descriptor.commands or {}) do commandNames[#commandNames + 1] = key end
        table.sort(commandNames)
        for _, key in ipairs(commandNames) do
          local _, commandRow = commandParts(descriptor.commands[key])
          if commandRow then
            out[#out + 1] = { name = key, tool = name, isCommand = true }
          end
        end
      end
    end
    return out
  end

  --- instance.surfaces(spec)
  --- Resolve an ordered list mixing tool names and plain objects into an ordered list of
  --- navigation adapters. A string entry names a registered tool, resolved to that
  --- tool's surface() result when the tool is active and has one, skipped silently when
  --- the tool is registered but inactive, and logged and skipped when nothing is
  --- registered under that name. A resolved surface that is missing, or present but has
  --- no isShowing, is logged and skipped rather than passed through broken. Anything
  --- that is not a string, an object this registry was never told about, passes straight
  --- through unexamined, in the position it was given.
  function instance.surfaces(spec)
    local out = {}
    if spec == nil then return out end
    for _, entry in ipairs(spec) do
      if type(entry) ~= "string" then
        out[#out + 1] = entry
      else
        local descriptor = toolsByName[entry]
        if not descriptor then
          log.w(string.format(
            "Registry surfaces found no tool registered under '%s'", entry))
        elseif not activeTools[entry] then
          -- Inactive is the legitimate silent case, the same nil-and-false every other
          -- read already answers for it, so nothing is logged and nothing is added.
        elseif not descriptor.surface then
          log.w(string.format(
            "Registry surfaces skipped '%s', it is active and declared no surface to navigate", entry))
        else
          local surface = descriptor.surface()
          if type(surface) == "table" and type(surface.isShowing) == "function" then
            out[#out + 1] = surface
          else
            log.w(string.format(
              "Registry surfaces skipped '%s', its surface resolved to something with no isShowing", entry))
          end
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
  --- from config/keys.lua is the root's own scope(name, opts) helper's job and stays
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
  --- One entry per active tool or active tool's command that declares a shortcut, in
  --- registration order, each carrying name, kind (leader or global), and fn, the
  --- function to bind. An inactive tool contributes nothing, itself or its commands,
  --- which is what keeps an inactive tool's key from ever being bound at all.
  function instance.shortcuts()
    local out = {}
    for _, name in ipairs(order) do
      if activeTools[name] then
        local descriptor = toolsByName[name]
        if descriptor.shortcut then
          out[#out + 1] = { name = name, kind = descriptor.shortcut, fn = descriptor.open }
        end
        -- Sorted by the command's own name rather than walked in whatever order pairs
        -- happens to answer for the literal table a descriptor wrote them in, since Lua
        -- promises nothing about that order and this needs one it can trust run over
        -- run. Which of two commands' shortcuts binds first is otherwise arbitrary,
        -- each one claiming a different key with nothing to disagree about.
        local commandNames = {}
        for key in pairs(descriptor.commands or {}) do
          commandNames[#commandNames + 1] = key
        end
        table.sort(commandNames)
        for _, key in ipairs(commandNames) do
          local fn, _, shortcut = commandParts(descriptor.commands[key])
          if shortcut then
            out[#out + 1] = { name = key, kind = shortcut, fn = fn }
          end
        end
      end
    end
    return out
  end

  return instance
end

return M
