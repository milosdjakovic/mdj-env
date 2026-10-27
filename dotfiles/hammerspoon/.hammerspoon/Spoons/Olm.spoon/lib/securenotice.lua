-- Says which application holds secure input when a held leader is pressed under it.
--
-- Why this exists. A held leader is a function key read by the ChordKey tap, and while any
-- application holds macOS secure input every tap is blind, so a Hyper held over a password field
-- does nothing at all and reads as Olm being broken. Chrome keeps secure input for as long as its
-- password field has focus, whichever application is in front, measured 2026-10-27, so the field
-- need not even be visible. hs.hotkey still fires under secure input, the route a modifier Hyper
-- and the secure focus relay both take, so while secure input is on each held leader's function
-- key is claimed as a plain hotkey whose press only says why, naming the holder. While it is off
-- nothing is claimed and the tap hears the key as always. Tinycast answers the same press the same
-- way, a HUD naming the holder, read 2026-10-27.
--
-- The holder is read the way Tinycast reads it, the kCGSSessionSecureInputPID that the window
-- server records per console session in the IORegistry, through the ioreg the root declares. A
-- Mac with two accounts carries one per session, so the holder is the first of them that names an
-- application this session can see. The read is a task, so a press never waits on it.
--
-- start(opts) takes opts.keys, a list of { code, name }, the function key each held leader in use
-- listens on and the name a person reads it by, opts.ioreg, the path to ioreg or nil, and
-- opts.notify, a function(text) drawing a transient message. Calling it again replaces what an
-- earlier call armed.

local M = {}

-- How often secure input is asked about. A press inside the gap after it turns on is simply not
-- answered, which costs a message and nothing else.
local POLL_SECONDS = 0.25

local state = { keys = {}, on = false }

-- The application holding secure input, from ioreg's IOConsoleUsers, or nil.
function M.holderIn(text)
  for pid in tostring(text or ""):gmatch('"kCGSSessionSecureInputPID"=(%d+)') do
    local app = hs.application.applicationForPID(tonumber(pid))
    if app then return app:name() end
  end
  return nil
end

function M.message(holder, leaderName)
  if holder then
    return holder .. " holds secure input, so " .. leaderName
      .. " is not heard until its password field loses focus"
  end
  return "Secure input is on, so " .. leaderName .. " is not heard until the password field loses focus"
end

local function pressed(opts, leaderName)
  return function()
    if not opts.notify then return end
    if not opts.ioreg then
      opts.notify(M.message(nil, leaderName))
      return
    end
    -- The output is read as it streams. ioreg writes about a hundred kilobytes here, more than a
    -- pipe holds, and a task read only at its end left ioreg blocked on a full pipe forever,
    -- measured 2026-10-27, so the message never came.
    local chunks = {}
    state.task = hs.task.new(opts.ioreg, function(_, out)
      state.task = nil
      chunks[#chunks + 1] = out or ""
      opts.notify(M.message(M.holderIn(table.concat(chunks)), leaderName))
    end, function(_, out)
      chunks[#chunks + 1] = out or ""
      return true
    end, { "-r", "-k", "IOConsoleUsers", "-d", "1", "-w", "0" })
    if not state.task:start() then
      state.task = nil
      opts.notify(M.message(nil, leaderName))
    end
  end
end

function M.stop()
  if state.timer then state.timer:stop() end
  state.timer = nil
  for _, k in ipairs(state.keys) do k:delete() end
  state.keys, state.on = {}, false
end

function M.start(opts)
  M.stop()
  opts = opts or {}
  for _, spec in ipairs(opts.keys or {}) do
    local ok, key = pcall(hs.hotkey.new, {}, spec.code, pressed(opts, spec.name))
    if ok and key then
      state.keys[#state.keys + 1] = key
    else
      print("Olm secure notice, the key of " .. tostring(spec.name) .. " could not be claimed, " .. tostring(key))
    end
  end
  if #state.keys == 0 then return end
  local function sync()
    local want = hs.eventtap.isSecureInputEnabled()
    if want == state.on then return end
    state.on = want
    for _, k in ipairs(state.keys) do if want then k:enable() else k:disable() end end
  end
  sync()
  state.timer = hs.timer.doEvery(POLL_SECONDS, sync)
end

return M
