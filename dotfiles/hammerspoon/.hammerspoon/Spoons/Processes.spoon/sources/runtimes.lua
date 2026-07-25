--- Processes source, development runtimes holding no port.
---
--- The other half of the picture. The ports source can only see a process that
--- holds a listening socket, so everything you leave running that never binds one
--- is invisible to it. A watch build, a test runner waiting on a file change, a
--- compiler that wedged, a worker orphaned when its parent went away. Those cost
--- the same memory and the same fan noise as a dev server and nothing else on the
--- machine will tell you they are there, because a process list shows them as one
--- more "node" among six hundred rows.
---
--- Identity is built the same way, cwd first and the command line as supporting
--- detail, for the same argv rewriting reason. A webpack watcher on this machine
--- reports itself as "webpack" while the kernel still calls it node, and its cwd is
--- the only field that names the project.
---
--- Rows sit in the tier below the port holders and the containers. A thing holding
--- a port is what you are usually hunting, so a portless watcher should never push
--- one down the list.
---
--- The selection rule is the same two policy keys the listener source reads, ANDed
--- rather than ORed. A port is strong evidence on its own and a listener can afford
--- to qualify on either half, but with the port gone each half alone is far too
--- weak. On this machine the working directory half alone would surface nine biome
--- language servers, a sourcekit-lsp, and four MCP servers, because an editor and
--- an agent both inherit the cwd of whatever opened them. So a portless process
--- qualifies only when its kernel process name is on the allowlist AND its working
--- directory sits under a dev root, and the price of that is an unfamiliar
--- toolchain no longer being caught for free.
---
--- Rows are one per process group rather than one per process, since a watch build
--- is a tree exactly like a dev server is. The shallowest qualifying member
--- represents it, so the row still reads as the thing you started rather than as a
--- hashed build worker underneath it, and the whole group travels on the row
--- because the whole group is what a stop takes.
---
--- The order of the three shellouts is where the cost lives, see the CLAUDE.md
--- beside this spoon for the measurements behind it.

local sourcePath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(sourcePath .. "../util.lua")()

local M = {}
M.name = "runtimes"

local PS = "/bin/ps"
local LSOF = "/usr/sbin/lsof"
local KILL = "/bin/kill"

local COMMAND_MAX = 120

-- Injected by the composition root through configure, the same slice the ports
-- source reads. This file never opens the config, so the root stays the one place
-- that knows where policy lives.
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

--- available() - the tools exist and both halves of the rule have something to say.
---
--- Both halves are required rather than either one, unlike the ports source, for
--- the conjunction reason above. A missing runtimes list or a missing dev roots
--- list means the rule can match nothing at all, so reporting it makes a scan that
--- races the config coming up fail visibly rather than quietly return an empty list
--- that reads as a clean machine.
function M.available()
  if not hs.fs.attributes(PS) then return false, "ps not found" end
  if not hs.fs.attributes(LSOF) then return false, "lsof not found" end
  if not next(M._runtimes) then return false, "not configured, no runtimes" end
  if #M._devRoots == 0 then return false, "not configured, no dev roots" end
  return true
end

-- Matched as a prefix so a family of helper processes is covered by one entry, and
-- so the entries written for lsof's nine character command names still match the
-- sixteen character name ps reports. That is why "com.docke" in the config covers
-- the "com.docker.backe" seen here.
local function ignored(name)
  local c = (name or ""):lower()
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

-- The kernel accounting name per pid, which is what the allowlist is written
-- against. It cannot come from the table above, because ps pads this column to a
-- fixed width and the name itself may contain a space, so putting it beside the
-- command line would leave two free form fields on one line and nothing to split
-- them on. Hence a second, small query, and the pattern takes the leading number
-- and then the whole trimmed remainder.
local function parseNames(out)
  local byPid = {}
  for line in util.lines(out) do
    local pid, name = line:match("^%s*(%d+)%s+(.-)%s*$")
    if pid and name and name ~= "" then byPid[tonumber(pid)] = name end
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

--- scan(cb) - three shellouts, two of them concurrent.
---
--- The two process queries do not depend on each other so they run together, and
--- the working directory lookup runs afterwards because it needs the pid list the
--- allowlist produces. The uid restriction lives on the name query rather than on
--- the table query, so that one call answers both what a process is called and
--- whether it is yours, while the table stays whole and a process group is never
--- reported with members missing from it.
function M.scan(cb)
  local ok, reason = M.available()
  if not ok then cb({}, reason) return end

  local user = os.getenv("USER")
  local procsByPid, procsByPgid, names
  local candidates = {}

  local function afterCwds(cwdOut)
    local cwds = parseCwds(cwdOut or "")
    local now = os.time()

    -- Collapse the surviving candidates onto their process groups, since a watch
    -- tree qualifies several of its own members and is still one thing to stop.
    local groups = {}
    for pid in pairs(candidates) do
      groups[procsByPid[pid].pgid] = true
    end

    local rows = {}
    for pgid in pairs(groups) do
      -- Ordered parent before child, which this source relies on for more than the
      -- pane's indentation. Walking that order is also how the representative below is
      -- picked, since the first qualifying entry in it is by construction the
      -- shallowest one, so a change to the ordering would quietly change which process
      -- names the row.
      local ordered = util.orderGroup(procsByPgid[pgid] or {}, COMMAND_MAX)
      -- The second half of the rule, applied here because this is the first point
      -- the working directory exists. The shallowest qualifying member represents
      -- the group, so the row reads as the thing you started rather than as some
      -- worker underneath it.
      local rep
      for _, entry in ipairs(ordered) do
        if candidates[entry.pid] and underDevRoot(cwds[entry.pid]) then
          rep = entry.pid
          break
        end
      end
      local proc = rep and procsByPid[rep]
      if proc then
        rows[#rows + 1] = {
          source = M.name,
          -- Keyed by the group rather than by the pid, because the group is what
          -- the row stands for and what a stop takes, and because the leaf pid a
          -- watcher runs under changes every time it restarts itself.
          key = "pgid:" .. pgid,
          runtime = candidates[rep],
          pid = rep,
          pgid = pgid,
          -- Empty rather than absent, so the merge and the list surface both see
          -- the same shape they see on a listener row.
          ports = {},
          cwd = cwds[rep],
          command = util.elide(proc.args, COMMAND_MAX),
          -- Both forms, for the same reason the ports source carries both. The
          -- subtitle wants one line and the preview pane wants the whole invocation.
          -- It matters more here than there, since a portless row is usually a build
          -- or a watcher and the flags are what tell you which one it is.
          commandFull = proc.args,
          status = "up " .. util.humanDuration(proc.uptime),
          startedAt = now - proc.uptime,
          rss = proc.rss,
          tier = 2,
          tree = ordered,
        }
      end
    end
    cb(rows)
  end

  local function join()
    if not procsByPid or not names then return end
    -- The cheap half of the rule, over data already in hand. Everything downstream
    -- of this is paid per candidate, so this is the only place the cost of a scan
    -- is really decided.
    local pids = {}
    for pid, name in pairs(names) do
      if procsByPid[pid] and M._runtimes[name:lower()] and not ignored(name) then
        candidates[pid] = name
        pids[#pids + 1] = tostring(pid)
      end
    end
    if #pids == 0 then cb({}) return end
    util.run(LSOF, { "-a", "-p", table.concat(pids, ","), "-d", "cwd", "-Fpn" },
      M._timeout, afterCwds)
  end

  util.run(PS, { "-Ao", "pid=,ppid=,pgid=,rss=,etime=,args=" }, M._timeout, function(out)
    procsByPid, procsByPgid = util.parseProcs(out or "")
    join()
  end)

  -- Restricted to your own processes, the same choice the listener scan makes with
  -- its -u. A root daemon is never something this tool offers to stop, so it is
  -- excluded at the source rather than filtered out later, and a pid absent from
  -- this answer can never become a candidate.
  local nameArgs = { "-Ao", "pid=,ucomm=" }
  if user and user ~= "" then
    nameArgs = { "-U", user, "-o", "pid=,ucomm=" }
  end
  util.run(PS, nameArgs, M._timeout, function(out)
    names = parseNames(out or "")
    join()
  end)
end

--- stop(row, opts, cb) - signal the process group, escalating if it does not go.
---
--- The same discipline the listener source follows, and for the same reasons. The
--- group is re-read live rather than trusted from the scan, because the picker may
--- have been open a while and a watch tree grows and shrinks under it constantly as
--- it respawns workers. Over the confirm threshold the stop refuses and reports
--- instead, so the caller can ask first, which keeps the decision in the UI where
--- the user is while the count stays here where the live data is.
---
--- The table is read whole here rather than restricted to your own processes the
--- way the scan does it, deliberately. A member the scan could not see must still
--- be counted before the size guard and the launchd guard answer, since both of
--- them are only worth anything when the group they are looking at is complete.
function M.stop(row, opts, cb)
  opts = opts or {}
  local target = row.pgid or row.pid
  if not target or target <= 1 then
    cb(false, "refusing, no safe target")
    return
  end

  util.run(PS, { "-Ao", "pid=,ppid=,pgid=,rss=,etime=,args=" }, M._timeout, function(out)
    local byPid, byPgid = util.parseProcs(out or "")
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
