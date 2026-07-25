--- Processes source, local listening processes.
---
--- Discovers development servers by the socket they hold. A process listening on a
--- TCP port, owned by you, whose runtime is one you develop in or whose working
--- directory sits under a dev root. Port and working directory are the two things
--- you actually identify a server by and the two things a process list normally
--- throws away, which is the whole reason this source leads with them.
---
--- The working directory matters more than it looks. Node routinely rewrites its
--- own argv, so the command line of a running next dev reads "next-server
--- (v16.2.11)" and names no project at all, while its cwd names the project
--- exactly. So identity here is built from cwd first and the command line is only
--- ever supporting detail.
---
--- Stopping signals the process GROUP, not the pid. A dev server is the leaf of a
--- supervisor chain, a shell into a package manager into a runtime into the server,
--- and killing the leaf either gets it restarted by the parent or leaves the rest
--- orphaned holding memory. Every member of that chain shares one process group, so
--- the group is both the correct thing to signal and the correct thing to show
--- before signalling.

local sourcePath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(sourcePath .. "../util.lua")()

local M = {}
M.name = "ports"

local LSOF = "/usr/sbin/lsof"
local PS = "/bin/ps"
local KILL = "/bin/kill"

local COMMAND_MAX = 120

-- Injected by the composition root through configure. The source never reads the
-- config file itself, so the root stays the one place that knows where policy
-- lives and this file stays a mechanism over whatever it is handed.
M._runtimes = {}
M._ignore = {}
M._devRoots = {}
M._grace = 3
M._confirmAbove = 8
M._timeout = 5

--- configure(opts) - called by the composition root, never by the engine.
function M.configure(opts)
  opts = opts or {}
  M._runtimes = {}
  for _, name in ipairs(opts.runtimes or {}) do
    M._runtimes[name:lower()] = true
  end
  M._ignore = {}
  for _, name in ipairs(opts.ignoreCommands or {}) do
    M._ignore[#M._ignore + 1] = name:lower()
  end
  M._devRoots = {}
  local home = os.getenv("HOME")
  for _, rel in ipairs(opts.devRoots or {}) do
    -- Resolved against home here rather than stored absolute, so the config data
    -- carries no machine specific path.
    M._devRoots[#M._devRoots + 1] = (home or "") .. "/" .. rel
  end
  M._grace = opts.graceSeconds or M._grace
  M._confirmAbove = opts.confirmAbove or M._confirmAbove
  M._timeout = opts.timeoutSeconds or M._timeout
  return M
end

--- available() - lsof and ps are part of the base system, so this only fails on a
--- machine where they have been removed. Checked live like every other source, for
--- uniformity rather than because it is expected to change.
function M.available()
  if not hs.fs.attributes(LSOF) then return false, "lsof not found" end
  if not hs.fs.attributes(PS) then return false, "ps not found" end
  -- Unconfigured means no runtimes and no dev roots, so the positive rule below can
  -- match nothing and every scan would quietly return an empty list that looks like
  -- a machine with no servers on it. Reporting it makes a scan that races the config
  -- coming up fail visibly rather than lie, the same reason an unknown window
  -- predicate is treated as active rather than silently disabling its binding.
  if not next(M._runtimes) and #M._devRoots == 0 then
    return false, "not configured, no runtimes or dev roots"
  end
  return true
end

-- Is this command one we never want to see, matched as a prefix so a family of
-- helper processes is covered by one entry. lsof's field output gives full command
-- names rather than the nine character truncation of its column output, so these
-- match against the real name.
local function ignored(command)
  local c = (command or ""):lower()
  for _, prefix in ipairs(M._ignore) do
    if c:sub(1, #prefix) == prefix then return true end
  end
  return false
end

local function underDevRoot(cwd)
  if not cwd then return false end
  for _, root in ipairs(M._devRoots) do
    if cwd:sub(1, #root) == root then return true end
  end
  return false
end

-- Parse lsof field output. Records are a stream, not rows. A `p` line opens a
-- process, `c` names it, and each `n` after that is one of its addresses, until the
-- next `p`. Field mode is used rather than the default columns because the column
-- output truncates the command name and cannot be split reliably when a name
-- contains a space, which several of the daemons here do.
local function parseListeners(out)
  local byPid = {}
  local pid, command
  for line in util.lines(out) do
    local tag, value = line:sub(1, 1), line:sub(2)
    if tag == "p" then
      pid = tonumber(value)
      command = nil
      if pid then byPid[pid] = byPid[pid] or { pid = pid, ports = {}, seen = {} } end
    elseif tag == "c" and pid then
      command = value
      byPid[pid].command = command
    elseif tag == "n" and pid then
      local port = tonumber(value:match(":(%d+)$"))
      local entry = byPid[pid]
      -- One socket is commonly bound twice, once on IPv4 and once on IPv6, so the
      -- same port arrives more than once per process and is deduped here.
      if port and entry and not entry.seen[port] then
        entry.seen[port] = true
        entry.ports[#entry.ports + 1] = port
      end
    end
  end
  return byPid
end

local function parseCwds(out)
  local byPid = {}
  local pid
  for line in util.lines(out) do
    local tag, value = line:sub(1, 1), line:sub(2)
    if tag == "p" then
      pid = tonumber(value)
    elseif tag == "n" and pid then
      byPid[pid] = value
    end
  end
  return byPid
end

-- One full process table, keyed by pid, plus a pgid index. Fields are fixed width
-- numerics first and the command line last, so the split is five leading fields and
-- then the remainder, which is the only shape that survives a command line
-- containing arbitrary spaces.
local function parseProcs(out)
  local byPid, byPgid = {}, {}
  for line in util.lines(out) do
    local pid, ppid, pgid, rss, etime, args =
      line:match("^%s*(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%S+)%s*(.*)$")
    if pid then
      local p = {
        pid = tonumber(pid), ppid = tonumber(ppid), pgid = tonumber(pgid),
        rss = tonumber(rss), uptime = util.etimeSeconds(etime), args = args,
      }
      byPid[p.pid] = p
      byPgid[p.pgid] = byPgid[p.pgid] or {}
      table.insert(byPgid[p.pgid], p)
    end
  end
  return byPid, byPgid
end

-- Order a process group the way it was built, roots first then children beneath
-- them, carrying a depth so the preview pane can indent it. Sorting by pid would be
-- wrong, pids wrap around, and in a real dev server tree the leaf server routinely
-- holds a lower pid than the shell that started it.
local function orderGroup(members)
  local inGroup, children, roots = {}, {}, {}
  for _, p in ipairs(members) do inGroup[p.pid] = p end
  for _, p in ipairs(members) do
    if inGroup[p.ppid] then
      children[p.ppid] = children[p.ppid] or {}
      table.insert(children[p.ppid], p)
    else
      table.insert(roots, p)
    end
  end
  table.sort(roots, function(a, b) return a.pid < b.pid end)
  local ordered = {}
  local function walk(p, depth)
    ordered[#ordered + 1] = {
      pid = p.pid, ppid = p.ppid, depth = depth,
      label = util.elide(p.args, COMMAND_MAX) or "?",
    }
    local kids = children[p.pid] or {}
    table.sort(kids, function(a, b) return a.pid < b.pid end)
    for _, kid in ipairs(kids) do walk(kid, depth + 1) end
  end
  for _, root in ipairs(roots) do walk(root, 0) end
  return ordered
end

--- scan(cb) - three shellouts, two of them concurrent.
---
--- The listener scan and the process table do not depend on each other so they run
--- together, and the working directory lookup runs afterwards because it needs the
--- pid list the listener scan produces. The ignore list is applied before that
--- lookup so it runs over the handful of real candidates rather than every daemon
--- on the machine.
function M.scan(cb)
  local ok, reason = M.available()
  if not ok then cb({}, reason) return end

  local user = os.getenv("USER")
  local listeners, procsByPid, procsByPgid

  local function afterCwds(cwdOut)
    local cwds = parseCwds(cwdOut or "")
    local now = os.time()
    local rows = {}
    for pid, entry in pairs(listeners) do
      local proc = procsByPid[pid]
      local cwd = cwds[pid]
      local runtime = (entry.command or ""):lower()
      -- The positive rule. A known runtime, or an unknown one sitting inside a
      -- project you own, which catches a toolchain the allowlist has not met yet.
      if proc and (M._runtimes[runtime] or underDevRoot(cwd)) then
        table.sort(entry.ports)
        local members = procsByPgid[proc.pgid] or { proc }
        rows[#rows + 1] = {
          source = M.name,
          key = "pid:" .. pid,
          runtime = entry.command,
          pid = pid,
          pgid = proc.pgid,
          ports = entry.ports,
          cwd = cwd,
          command = util.elide(proc.args, COMMAND_MAX),
          status = "up " .. util.humanDuration(proc.uptime),
          startedAt = now - proc.uptime,
          rss = proc.rss,
          tier = 0,
          tree = orderGroup(members),
        }
      end
    end
    cb(rows)
  end

  local function join()
    if not listeners or not procsByPid then return end
    local pids = {}
    for pid, entry in pairs(listeners) do
      if ignored(entry.command) then
        listeners[pid] = nil
      else
        pids[#pids + 1] = tostring(pid)
      end
    end
    if #pids == 0 then cb({}) return end
    util.run(LSOF, { "-a", "-p", table.concat(pids, ","), "-d", "cwd", "-Fpn" },
      M._timeout, afterCwds)
  end

  -- The leading -a is load bearing. lsof ORs its selection criteria by default, so
  -- without it "-u you -iTCP -sTCP:LISTEN" asks for every file you have open OR any
  -- listening socket, which is tens of thousands of rows and seconds of work rather
  -- than the handful of listeners actually wanted. With it the criteria are ANDed
  -- and the same scan costs around sixty milliseconds.
  local listenArgs = { "-a", "-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn" }
  if user and user ~= "" then
    -- Restrict to your own processes. Root daemons holding a port are never
    -- something this tool offers to stop, so they are excluded at the source
    -- rather than filtered out later.
    table.insert(listenArgs, 2, user)
    table.insert(listenArgs, 2, "-u")
  end

  util.run(LSOF, listenArgs, M._timeout, function(out)
    listeners = parseListeners(out or "")
    join()
  end)
  util.run(PS, { "-Ao", "pid=,ppid=,pgid=,rss=,etime=,args=" }, M._timeout, function(out)
    procsByPid, procsByPgid = parseProcs(out or "")
    join()
  end)
end

--- stop(row, opts, cb) - signal the process group, escalating if it does not go.
---
--- The group is re-read live rather than trusted from the scan, because the picker
--- may have been open for a while and a tree can grow or shrink underneath it. Over
--- the confirm threshold the stop refuses and reports instead, so the caller can
--- ask first, which keeps the decision in the UI where it belongs while the count
--- stays here where the live data is.
function M.stop(row, opts, cb)
  opts = opts or {}
  local target = row.pgid or row.pid
  if not target or target <= 1 then
    cb(false, "refusing, no safe target")
    return
  end

  util.run(PS, { "-Ao", "pid=,ppid=,pgid=,rss=,etime=,args=" }, M._timeout, function(out)
    local byPid, byPgid = parseProcs(out or "")
    local members = row.pgid and byPgid[row.pgid] or (byPid[row.pid] and { byPid[row.pid] })
    if not members or #members == 0 then
      cb(true, "already gone")
      return
    end

    local mine = hs.processInfo and hs.processInfo.processID
    for _, p in ipairs(members) do
      if p.pid == 1 then
        cb(false, "refusing, group contains launchd")
        return
      end
      if mine and p.pid == mine then
        cb(false, "refusing, group contains Hammerspoon")
        return
      end
    end

    if #members > M._confirmAbove and not opts.confirmed then
      cb(false, string.format("%d processes, confirm to stop", #members))
      return
    end

    local label = string.format("%d process%s", #members, #members == 1 and "" or "es")
    local groupArg = row.pgid and ("-" .. row.pgid) or tostring(row.pid)

    local function signal(name, after)
      -- The double dash matters. A group is addressed as a negative number and
      -- without the separator kill reads the leading minus as the start of an
      -- option rather than as the group it is.
      util.run(KILL, { "-" .. name, "--", groupArg }, M._timeout, function(_, err)
        after(err)
      end)
    end

    if opts.force then
      signal("KILL", function(err)
        if err then cb(false, "kill failed, " .. err) else cb(true, "killed " .. label) end
      end)
      return
    end

    signal("TERM", function(err)
      if err then cb(false, "stop failed, " .. err) return end
      hs.timer.doAfter(M._grace, function()
        util.run(PS, { "-Ao", "pid=,pgid=" }, M._timeout, function(out2)
          local survivors = 0
          for line in util.lines(out2 or "") do
            local _, pgid = line:match("^%s*(%d+)%s+(%d+)%s*$")
            if row.pgid and tonumber(pgid) == row.pgid then survivors = survivors + 1 end
          end
          if survivors == 0 then
            cb(true, "stopped " .. label)
          else
            signal("KILL", function(err2)
              if err2 then
                cb(false, "would not die, " .. err2)
              else
                cb(true, string.format("forced after %ds, %s", M._grace, label))
              end
            end)
          end
        end)
      end)
    end)
  end)
end

return M
