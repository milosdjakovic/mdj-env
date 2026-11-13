-- The bridge's message routing, step 2.2 of docs/PLAN-STANDALONE.md, JSON-RPC 2.0 as
-- docs/PROTOCOL-BRIDGE.md frames it. It decodes each message, answers `hello` before anything else,
-- hands a request to the method that serves it and sends the answer, and catches a method that
-- raises, so a plugin that fails costs one answer and never the connection. Pure, everything it
-- touches is handed in, so test/bridgeserve.lua drives it over fakes.
--
-- A method may name what makes a newer request supersede an older one, `rows` its level. Such a
-- request is run on the next turn of the run loop rather than at once, and one superseded before
-- then is answered stale, -32011, and never run, the protocol's Generations. Hammerspoon hands the
-- bridge one message per read, so the turn is how it sees what else had already arrived.

local M = {}

M.PARSE, M.INVALID, M.UNKNOWN, M.PARAMS = -32700, -32600, -32601, -32602
M.VERSION, M.STALE, M.GONE, M.NOT_SERVED, M.RAISED = -32010, -32011, -32012, -32013, -32014

--- rpc.fail(code, message, data) raises an answer's error from inside a method
function M.fail(code, message, data)
  error({ rpcError = { code = code, message = message, data = data } }, 0)
end

--- rpc.new(opts) -> session
--- opts.json     { encode, decode }, hs.json or a stand in
--- opts.send     function(text) putting one message on the connection
--- opts.defer    function(fn) running fn on the next turn of the run loop
--- opts.methods  { [name] = { run = function(params) -> result, supersedes = function(params) -> key } }
--- opts.log      function(text), optional
function M.new(opts)
  local session = { open = false }
  local pending = {}

  local function log(text)
    if opts.log then opts.log(text) end
  end

  local function reply(id, result, err)
    if id == nil then return end
    local message = { jsonrpc = "2.0", id = id }
    if err then message.error = err else message.result = result end
    local ok, text = pcall(opts.json.encode, message)
    if ok and type(text) == "string" then
      opts.send(text)
    else
      log("could not encode the answer to " .. tostring(id) .. ", " .. tostring(text))
      opts.send(opts.json.encode({ jsonrpc = "2.0", id = id,
        error = { code = M.RAISED, message = "the answer could not be encoded" } }))
    end
  end

  -- A parse error has no id to answer, which JSON-RPC writes as null.
  local function replyUnknown(code, message)
    opts.send('{"jsonrpc":"2.0","id":null,"error":{"code":' .. code .. ',"message":"' .. message .. '"}}')
  end

  local function run(method, message)
    local ok, result = pcall(method.run, message.params or {}, session)
    if ok then
      reply(message.id, result)
    elseif type(result) == "table" and result.rpcError then
      reply(message.id, nil, result.rpcError)
    else
      log("the bridge's " .. tostring(message.method) .. " raised, " .. tostring(result))
      reply(message.id, nil, { code = M.RAISED, message = "the plugin raised",
        data = { message = tostring(result) } })
    end
  end

  --- session:receive(text) handles one message as it arrived
  function session:receive(text)
    local ok, message = pcall(opts.json.decode, text)
    if not ok or type(message) ~= "table" then return replyUnknown(M.PARSE, "not JSON") end
    if message.jsonrpc ~= "2.0" or type(message.method) ~= "string" then
      if message.id ~= nil then return reply(message.id, nil, { code = M.INVALID, message = "not a request" }) end
      return replyUnknown(M.INVALID, "not a request")
    end
    -- An answer to a request of ours. The Lua side sends none yet, so it is read and dropped.
    if message.result ~= nil or message.error ~= nil then return end
    if not session.open and message.method ~= "hello" then
      return reply(message.id, nil, { code = M.INVALID, message = "hello comes first" })
    end
    local method = opts.methods[message.method]
    if not method then
      if message.id == nil then return end
      return reply(message.id, nil, { code = M.UNKNOWN, message = "no method " .. message.method })
    end
    local key = method.supersedes and method.supersedes(message.params or {})
    if key == nil then return run(method, message) end
    key = message.method .. ":" .. tostring(key)
    local older = pending[key]
    if older then reply(older.id, nil, { code = M.STALE, message = "superseded" }) end
    pending[key] = message
    opts.defer(function()
      if pending[key] ~= message then return end
      pending[key] = nil
      run(method, message)
    end)
  end

  --- session:reset() forgets everything of the connection that went
  function session:reset()
    session.open = false
    pending = {}
  end

  return session
end

return M
