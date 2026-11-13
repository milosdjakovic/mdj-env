-- The bridge's connection, step 2.2 of docs/PLAN-STANDALONE.md, the Lua side connecting to the
-- Unix socket Olm.app listens on, docs/PROTOCOL-BRIDGE.md's Who starts. A Humble Object over
-- hs.socket, so the framing is frame.lua's and the routing rpc.lua's, both pure.
--
-- It connects when started and whenever the app posts local.olm.Olm.listening, and otherwise tries
-- again after 0.25 s, doubling to 5 s. hs.socket says nothing when a connection goes, so a poll of
-- connected() notices, and a lost connection is told once, so the session above it starts over
-- from hello. Each read is a length line, tag 1, then exactly that many bytes, tag 2.

local M = {}

M.LISTENING_NOTE = "local.olm.Olm.listening"
M.FIRST_WAIT, M.LONGEST_WAIT, M.POLL = 0.25, 5, 1

local LENGTH, BODY = 1, 2

--- transport.new(opts) -> connection
--- opts.path       the socket the app listens on
--- opts.frame      frame.lua
--- opts.onMessage  function(text), one message as it arrived
--- opts.onUp       function(), connected, optional
--- opts.onDown     function(), the connection went, optional
--- opts.log        function(text), optional
function M.new(opts)
  local c = { up = false, wait = M.FIRST_WAIT }

  local function log(text)
    if opts.log then opts.log(text) end
  end

  local function down()
    if c.poll then c.poll:stop(); c.poll = nil end
    local was = c.up
    c.up = false
    if c.sock then pcall(function() c.sock:disconnect() end) end
    c.sock = nil
    if was and opts.onDown then opts.onDown() end
  end

  local schedule

  local function readLength()
    if c.sock then c.sock:read("\n", LENGTH) end
  end

  local function attempt()
    if c.stopped then return end
    down()
    -- No socket file means the app is not listening, so nothing is tried and nothing is said, and
    -- the app's listening note or the next retry tries again.
    if not hs.fs.attributes(opts.path, "mode") then return schedule() end
    local sock
    sock = hs.socket.new(function(data, tag)
      if sock ~= c.sock then return end
      if tag == LENGTH then
        local n, why = opts.frame.length(data)
        if not n then
          log("the app sent " .. why .. ", so the connection is closed")
          down()
          return schedule()
        end
        if n == 0 then return readLength() end
        sock:read(n, BODY)
      elseif tag == BODY then
        readLength()
        local ok, err = pcall(opts.onMessage, data)
        if not ok then log("a message raised in the bridge, " .. tostring(err)) end
      end
    end)
    c.sock = sock
    sock:connect(opts.path, function()
      if sock ~= c.sock then return end
      c.up = true
      c.wait = M.FIRST_WAIT
      if opts.onUp then opts.onUp() end
      readLength()
      c.poll = hs.timer.doEvery(M.POLL, function()
        if sock ~= c.sock then return end
        if not sock:connected() then
          down()
          schedule()
        end
      end)
    end)
    -- A connect that never answers leaves the socket unconnected, which the retry notices.
    c.retry = hs.timer.doAfter(c.wait, function()
      c.retry = nil
      if not c.up and not c.stopped then
        c.wait = math.min(c.wait * 2, M.LONGEST_WAIT)
        attempt()
      end
    end)
  end

  schedule = function()
    if c.stopped or c.retry then return end
    c.retry = hs.timer.doAfter(c.wait, function()
      c.retry = nil
      c.wait = math.min(c.wait * 2, M.LONGEST_WAIT)
      attempt()
    end)
  end

  --- connection:start() connects now and listens for the app saying it listens
  function c:start()
    c.stopped = false
    local notes = hs.distributednotifications
    if not c.note and notes and type(notes.new) == "function" then
      -- A listening note means a listener that has just bound the path, so whatever this side holds
      -- is a connection to one that is gone, even while it still reads as connected. hs.socket kept
      -- answering connected for a peer that had died, found in 3.1's live check on 2026-11-13, and
      -- a note ignored while up left the bridge on a dead connection for good.
      c.note = notes.new(function()
        if c.retry then c.retry:stop(); c.retry = nil end
        c.wait = M.FIRST_WAIT
        attempt()
      end, M.LISTENING_NOTE)
      if c.note then c.note:start() end
    end
    attempt()
    return c
  end

  --- connection:send(text) puts one message on the connection, dropped while it is down
  function c:send(text)
    if not (c.up and c.sock) then return false end
    c.sock:write(opts.frame.encode(text))
    return true
  end

  --- connection:stop() closes it and tries no more
  function c:stop()
    c.stopped = true
    if c.retry then c.retry:stop(); c.retry = nil end
    if c.note then c.note:stop(); c.note = nil end
    down()
  end

  return c
end

return M
