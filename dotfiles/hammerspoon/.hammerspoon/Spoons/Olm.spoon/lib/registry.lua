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
-- of their own, optional.
--
-- register(descriptor) validates, then records, and refuses rather than raises, so one
-- bad tool cannot empty the launcher. Every refusal is one log line at warning naming
-- the tool and the reason, and register answers true when it registered and false when
-- it refused. Four refusals exist. A descriptor with no name, or a name that is not a
-- string, is refused, and cannot be named in its own error, so the line says what it
-- can. A second registration under a name already taken is refused, naming the tool,
-- since first registration wins. A commands key colliding with any name already
-- indexed, whether a tool name or another tool's command, is refused, naming both
-- sides, since the flat index dispatch reads makes such a collision ambiguity rather
-- than a preference. An apiVersion that is missing, not an integer, or not equal to the
-- core's, is refused, naming the tool, the version it declared, and the version the
-- core offers, since the version is bumped only on a breaking change and equality is
-- the only check that respects that.
--
-- activate(names) takes a list of tool names and is called once after every
-- registration. A registered tool whose name is in the list is active, one not in the
-- list is registered and inactive. A name in the list that nothing registered produces
-- one warning line naming it and is otherwise ignored, since a typo in a roster should
-- be visible and harmless rather than fatal.
--
-- The read side. run(name) looks the name up in the flat index of tool names and
-- command names, and calls it when the owner is active, answering true when it ran
-- something and false when it did not, which is what lets a caller fall through.
-- get(name) hands back the descriptor of an active tool or nil, and answers nil for a
-- command name, since a command is not a tool. active() lists active tool names in
-- registration order. all() lists every registered tool name with its active flag, for
-- diagnostics only. An inactive tool answers nil and false to every read except all().
-- That is the whole of what inactive means in this packet. It does not yet unbind a
-- chord or remove a row, and later packets are what finish it.
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
    local commands = descriptor.commands or {}
    for key in pairs(commands) do
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

    toolsByName[name] = descriptor
    flatIndex[name] = { tool = name, fn = descriptor.open }
    order[#order + 1] = name
    for key, fn in pairs(commands) do
      flatIndex[key] = { tool = name, fn = fn }
    end
    return true
  end

  --- instance.activate(names)
  --- Replace the active set with the given list of tool names. A name nothing
  --- registered logs one warning and is otherwise ignored.
  function instance.activate(names)
    activeTools = {}
    for _, name in ipairs(names or {}) do
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
  --- Every registered tool name with its active flag, in registration order, for
  --- diagnostics only.
  function instance.all()
    local out = {}
    for _, name in ipairs(order) do
      out[#out + 1] = { name = name, active = activeTools[name] == true }
    end
    return out
  end

  return instance
end

return M
