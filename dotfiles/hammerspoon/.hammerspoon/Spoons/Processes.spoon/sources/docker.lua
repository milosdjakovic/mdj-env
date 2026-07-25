--- Processes source, docker containers.
---
--- Exists because a port scan alone is actively misleading on a machine that runs
--- containers. Every published container port is held by one long lived proxy
--- process, so the raw listener view shows the same daemon a dozen times over and
--- the only thing it offers to stop is Docker Desktop itself, which is never what
--- you meant. This source claims those ports first and republishes them as named
--- containers, so the port you are hunting resolves to the container that owns it
--- and stopping it stops that container alone.
---
--- Ownership of a port is all the engine needs to know. It drops any later row
--- whose ports are already claimed, so the collapse happens without the engine
--- learning the word docker, and a machine with no containers simply produces no
--- claims and changes nothing.

local sourcePath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(sourcePath .. "../util.lua")()

local M = {}
M.name = "docker"

-- hs.task takes a full path and does not consult PATH, and the docker CLI lands in
-- a different place depending on whether it came from Docker Desktop or Homebrew,
-- so the candidates are tried in order and the first that exists wins.
local CANDIDATES = {
  "/opt/homebrew/bin/docker",
  "/usr/local/bin/docker",
  (os.getenv("HOME") or "") .. "/.docker/bin/docker",
  "/Applications/Docker.app/Contents/Resources/bin/docker",
}

local FORMAT = "{{.ID}}|{{.Names}}|{{.Image}}|{{.Ports}}|{{.Status}}"

M._timeout = 5
M._grace = 3

function M.configure(opts)
  opts = opts or {}
  M._timeout = opts.timeoutSeconds or M._timeout
  M._grace = opts.graceSeconds or M._grace
  return M
end

--- available() - only that the CLI is installed.
---
--- Deliberately not a daemon probe. Asking the daemon whether it is up costs the
--- same call as asking it for the containers, and it is exactly the call that hangs
--- while Docker Desktop is starting, so probing first would double the cost in the
--- good case and change nothing in the bad one. The scan timeout is what actually
--- handles a wedged daemon, and an empty result from a stopped daemon is the
--- correct answer anyway, since a stopped daemon has no containers.
function M.available()
  local bin = util.firstExisting(CANDIDATES)
  if not bin then return false, "docker cli not found" end
  return true
end

-- Pull the published host ports out of the ports column. Docker prints a mix of
-- published mappings, "127.0.0.1:8000->8000/tcp", and bare container ports that are
-- not reachable from the host at all, "5671-5672/tcp". Only the published ones can
-- collide with anything you are running, so only those are claimed, and a range is
-- ignored rather than expanded since ranges are never what a dev server binds.
local function publishedPorts(field)
  local ports, seen = {}, {}
  for mapping in (field or ""):gmatch("[^,]+") do
    local hostPort = mapping:match("^%s*[%d%.%[%]:a-fA-F]-:(%d+)%->")
    local n = tonumber(hostPort)
    if n and not seen[n] then
      seen[n] = true
      ports[#ports + 1] = n
    end
  end
  table.sort(ports)
  return ports
end

--- scan(cb)
function M.scan(cb)
  local bin = util.firstExisting(CANDIDATES)
  if not bin then cb({}, "docker cli not found") return end

  util.run(bin, { "ps", "--format", FORMAT }, M._timeout, function(out, err)
    if not out then cb({}, err) return end
    local rows = {}
    for line in util.lines(out) do
      local id, name, image, ports, status = line:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
      if id and id ~= "" then
        rows[#rows + 1] = {
          source = M.name,
          key = "container:" .. id,
          -- The source names this row itself. A container has a real name already,
          -- so there is nothing for the engine's cwd derivation to improve on.
          title = name,
          runtime = "docker",
          containerId = id,
          containerName = name,
          ports = publishedPorts(ports),
          command = image,
          status = status,
          -- Left unknown on purpose. Containers sit in their own display tier below
          -- the local servers, so recency would never change their placement, and
          -- the timestamp docker exposes is when the container was created rather
          -- than when it last started, which would order them wrongly anyway.
          startedAt = 0,
          tier = 1,
          tree = {},
        }
      end
    end
    cb(rows)
  end)
end

--- stop(row, opts, cb)
---
--- Stops the container, never the daemon. docker stop already does the graceful
--- then forceful escalation internally, so the grace period is handed to it rather
--- than reimplemented here, and the task timeout is set past that grace so the
--- escalation has room to finish before the runner gives up on it.
function M.stop(row, opts, cb)
  opts = opts or {}
  local bin = util.firstExisting(CANDIDATES)
  if not bin then cb(false, "docker cli not found") return end
  local id = row.containerId
  if not id then cb(false, "refusing, no container on this row") return end

  local args = opts.force
    and { "kill", id }
    or { "stop", "--time", tostring(M._grace), id }
  local budget = (opts.force and M._timeout or M._grace + M._timeout)

  util.run(bin, args, budget, function(out, err)
    if err then
      cb(false, (opts.force and "kill failed, " or "stop failed, ") .. err)
    else
      cb(true, (opts.force and "killed " or "stopped ") .. (row.containerName or id))
    end
  end)
end

return M
