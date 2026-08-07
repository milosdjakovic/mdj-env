--- Shared helpers for the Processes sources.
---
--- Two sources shell out and both need the same timeout discipline, so the runner
--- lives here rather than being copied. It earns its place by having a second
--- consumer, which is the bar the design rules set before a helper is extracted.

local M = {}

local log = hs.logger.new("Processes", "info")

--- util.run(binary, args, timeoutSeconds, cb)
--- Run a command and hand its stdout to cb, or nil plus a reason on failure.
---
--- Always hs.task, never hs.execute. The picker redraws from the main thread and a
--- blocking shellout would stutter it, and the docker CLI in particular hangs
--- indefinitely while its daemon is starting, which would freeze Hammerspoon
--- outright. The timeout is the backstop for exactly that, it terminates the task
--- and reports rather than leaving the caller waiting on a callback that never
--- arrives.
---
--- ALWAYS the streaming form, never the plain buffered one, and this is not a
--- preference. An hs.task built with only a completion callback deadlocks once the
--- child writes more than a pipe buffer of output, because nothing drains the pipe
--- until the child exits and the child cannot exit until its writes are read. It
--- fails silently, the callback simply never arrives, which reads as a hang rather
--- than an error. Measured here, a full process table with command lines is around
--- 180KB, and the buffered form never returned at all while the streaming form
--- completed in 52 milliseconds. So the drain callback accumulates chunks and the
--- completion callback joins them, and the runner is safe at any output size.
---
--- Success is the exit code, not the presence of output. A clean exit that printed
--- nothing is a success, which matters because kill is silent when it works and an
--- output based test reported every successful stop as a failure. A non zero exit
--- that still printed something is also passed through, since some of these tools
--- exit non zero while producing usable output, and only a non zero exit with
--- nothing to show for it is reported as an error.
---
--- THE EXIT CALLBACK IS NOT THE END OF THE OUTPUT, and this is the subtle one. The
--- stream callback keeps firing after the completion callback has already run, so
--- reading the accumulated chunks the moment the task reports its exit can hand back
--- output that is truncated, or empty when every chunk is still in flight. The
--- completion callback's own stdout argument does not make up the difference, it was
--- measured at zero bytes in every single case, so there is nowhere else to look.
---
--- It shows up as an intermittent empty result rather than an error, which is what
--- makes it dangerous. A scan simply reports that nothing is running. Measured here
--- across a concurrent burst, a command that exits almost immediately lost its output
--- at the exit callback sixteen times out of twenty, and even ps and lsof lost theirs
--- once the picker had several sources scanning at once, which is exactly the normal
--- case. Running the same commands one at a time never reproduced it, which is why
--- this hid until a third source was added.
---
--- So the exit is treated as one more event rather than the finish line, and the
--- result is handed over only once the output has gone quiet for DRAIN_GRACE with the
--- task already exited. The late chunks were measured arriving within one millisecond
--- of the exit callback, so the grace is more than an order of magnitude above the
--- worst observed case, and it costs that much once per call rather than per chunk.
--- The overall timeout still bounds the whole thing, so a task that somehow never
--- goes quiet is abandoned rather than waited on forever.
local DRAIN_GRACE = 0.015

function M.run(binary, args, timeoutSeconds, cb)
  local done = false
  local timer
  local task
  local outChunks, errChunks = {}, {}
  local bytes, exitCode, drainTimer = 0, nil, nil

  local function finish(out, err)
    if done then return end
    done = true
    if timer then timer:stop() end
    if drainTimer then drainTimer:stop() end
    cb(out, err)
  end

  -- Wait for the output to stop growing before deciding anything. Re-arms itself
  -- whenever another chunk landed during the window, so a slow trickle is waited out
  -- rather than cut off, and settles after one grace period in the common case where
  -- everything had already arrived.
  local function settle()
    local seen = bytes
    drainTimer = hs.timer.doAfter(DRAIN_GRACE, function()
      if done then return end
      if bytes ~= seen then settle() return end
      local out = table.concat(outChunks)
      if exitCode == 0 or out ~= "" then
        finish(out, nil)
      else
        local stderr = table.concat(errChunks):gsub("%s+$", "")
        finish(nil, "exit " .. tostring(exitCode) .. (stderr ~= "" and (" " .. stderr) or ""))
      end
    end)
  end

  task = hs.task.new(binary,
    function(code)
      exitCode = code
      settle()
    end,
    function(_, stdout, stderr)
      if stdout and stdout ~= "" then
        outChunks[#outChunks + 1] = stdout
        bytes = bytes + #stdout
      end
      if stderr and stderr ~= "" then errChunks[#errChunks + 1] = stderr end
      return true
    end,
    args or {})

  if not task then
    cb(nil, "could not start " .. binary)
    return
  end

  if timeoutSeconds and timeoutSeconds > 0 then
    timer = hs.timer.doAfter(timeoutSeconds, function()
      if done then return end
      log.w(binary .. " timed out after " .. timeoutSeconds .. "s, abandoning")
      pcall(function() task:terminate() end)
      finish(nil, "timed out")
    end)
  end

  task:start()
end

-- Pending delayed steps, keyed so each releases only itself.
local pendingSteps = {}

--- util.after(delay, fn)
--- Run fn after delay, holding the timer until it fires.
---
--- Holding it is the whole point. A Hammerspoon timer is userdata whose finalizer stops
--- it, so a pending timer nothing refers to can be collected before it fires, and the
--- step then never happens with no error anywhere. Both sources use this for the pause
--- between signalling a process group and checking what survived, so losing one means a
--- stop that reports neither success nor failure and a row that never settles.
---
--- Keyed rather than a single slot, because stopping two processes in quick succession
--- leaves two checks outstanding and a later one must never cancel an earlier one.
--- Second consumer, so it is here rather than copied into both sources.
function M.after(delay, fn)
  local slot = {}
  pendingSteps[slot] = hs.timer.doAfter(delay, function()
    pendingSteps[slot] = nil
    fn()
  end)
end

--- util.etimeSeconds(s) -> number
--- Parse the elapsed time ps prints into seconds. BSD ps has no etimes keyword, so
--- the three width dependent forms it does print have to be parsed by hand. They
--- are MM:SS, HH:MM:SS, and DD-HH:MM:SS. Anything unrecognised reads as 0.
function M.etimeSeconds(s)
  if not s then return 0 end
  s = s:gsub("%s", "")
  local d, h, m, sec = s:match("^(%d+)%-(%d+):(%d+):(%d+)$")
  if d then return d * 86400 + h * 3600 + m * 60 + sec end
  h, m, sec = s:match("^(%d+):(%d+):(%d+)$")
  if h then return h * 3600 + m * 60 + sec end
  m, sec = s:match("^(%d+):(%d+)$")
  if m then return m * 60 + sec end
  return 0
end

--- util.humanDuration(seconds) -> string
--- A compact uptime, "19h", "2d", "4m". Coarse on purpose, the row is answering
--- whether something is from this morning or from last week, not timing anything.
function M.humanDuration(seconds)
  seconds = math.floor(tonumber(seconds) or 0)
  if seconds < 60 then return seconds .. "s" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
  if seconds < 86400 then return math.floor(seconds / 3600) .. "h" end
  return math.floor(seconds / 86400) .. "d"
end

--- util.humanBytes(kilobytes) -> string
--- Format an rss reading, which ps reports in kilobytes.
function M.humanBytes(kb)
  kb = tonumber(kb) or 0
  if kb < 1024 then return string.format("%d KB", kb) end
  if kb < 1024 * 1024 then return string.format("%d MB", math.floor(kb / 1024 + 0.5)) end
  return string.format("%.1f GB", kb / 1024 / 1024)
end

--- util.basename(path) / util.dirname(path)
function M.basename(path)
  if not path or path == "" then return nil end
  return (path:gsub("/+$", ""):match("([^/]+)$"))
end

function M.dirname(path)
  if not path or path == "" then return nil end
  return (path:gsub("/+$", ""):match("^(.*)/[^/]+$"))
end

--- util.elide(s, max) -> string
--- Collapse whitespace and cut a long command down to one tidy line. Display only,
--- the untruncated value stays on the row for the preview pane to show in full.
function M.elide(s, max)
  if not s then return nil end
  s = s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  if max and #s > max then s = s:sub(1, max - 1) .. "…" end
  return s
end

--- util.split(s) -> iterator over non empty lines
function M.lines(s)
  return (s or ""):gmatch("[^\r\n]+")
end

--- util.parseProcs(out) -> byPid, byPgid
--- One full process table keyed by pid, plus a pgid index.
---
--- Expects the five fixed width numerics first and the command line last, which is the
--- only ps layout that survives a command line containing arbitrary spaces. The pattern
--- takes five leading fields and then the whole remainder, so a Java invocation with
--- twenty space separated flags parses the same as `nginx`. A source asking for a
--- different set of columns cannot use this, and should say so rather than reordering
--- the ps call to fit.
---
--- Both sources that read the process table want exactly this, which is what moved it
--- here. Two byte identical copies is the case the second consumer rule is about.
function M.parseProcs(out)
  local byPid, byPgid = {}, {}
  for line in M.lines(out) do
    local pid, ppid, pgid, rss, etime, args =
      line:match("^%s*(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%S+)%s*(.*)$")
    if pid then
      local p = {
        pid = tonumber(pid), ppid = tonumber(ppid), pgid = tonumber(pgid),
        rss = tonumber(rss), uptime = M.etimeSeconds(etime), args = args,
      }
      byPid[p.pid] = p
      byPgid[p.pgid] = byPgid[p.pgid] or {}
      table.insert(byPgid[p.pgid], p)
    end
  end
  return byPid, byPgid
end

--- util.orderGroup(members, commandMax) -> list of { pid, ppid, depth, label }
--- Order a process group the way it was built, roots first then children beneath them,
--- carrying a depth so the preview pane can indent it rather than print a flat list.
---
--- Sorting by pid would be wrong. Pids wrap around, and in a real dev server tree the
--- leaf server routinely holds a lower pid than the shell that started it, so pid order
--- prints the tree upside down often enough to notice. Parentage is the only ordering
--- that is always right.
---
--- A member whose parent is outside the group is a root, which is what makes this
--- correct for a group whose leader has already exited. There is no single root to find
--- and looking for one would return nothing.
---
--- commandMax is the caller's, not ours. How wide a label may be is a display decision
--- belonging to the source that will show it, and baking one number in here would make
--- this mechanism carry a policy it has no business knowing.
function M.orderGroup(members, commandMax)
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
      label = M.elide(p.args, commandMax) or "?",
    }
    local kids = children[p.pid] or {}
    table.sort(kids, function(a, b) return a.pid < b.pid end)
    for _, kid in ipairs(kids) do walk(kid, depth + 1) end
  end
  for _, root in ipairs(roots) do walk(root, 0) end
  return ordered
end

return M
