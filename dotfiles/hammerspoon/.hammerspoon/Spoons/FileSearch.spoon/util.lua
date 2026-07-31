--- Shared helpers for the File Search sources.
---
--- Two sources shell out and both need the same timeout and drain discipline, so the
--- runner lives here rather than being copied. It earns its place by having a second
--- consumer, which is the bar the design rules set.
---
--- These are deliberately this spoon's own copies rather than a reach into another
--- spoon's util. A spoon reaches only its own siblings, so a helper wanted in two spoons
--- is written out in each rather than borrowed across the boundary. The alternative would
--- couple two unrelated features through a file neither owns.

local M = {}

local log = hs.logger.new("FileSearch", "info")

--- util.log - the shared logger, so a source logs under one name.
M.log = log

-- The gap the runner waits for output to go quiet before deciding anything. The stream
-- callback keeps firing after the completion callback has already run, so reading the
-- accumulated chunks the moment a task reports its exit hands back output that is
-- truncated, or empty when every chunk is still in flight. Measured elsewhere in this
-- config, a command exiting almost immediately lost its output at the exit callback
-- sixteen times out of twenty under a concurrent burst. So the exit is treated as one
-- more event and the result is handed over only once the output stopped growing.
local DRAIN_GRACE = 0.015

--- util.run(binary, args, timeoutSeconds, cb) -> handle
--- Run a command and hand its stdout to cb, or nil plus a reason on failure. Returns a
--- handle carrying cancel(), so a caller can abandon it when a newer query supersedes it.
---
--- Always hs.task, never hs.execute or io.popen. The picker redraws from the main thread
--- and a blocking shellout would stutter it, and worse, Hammerspoon owns the event taps
--- for every leader key in this config, so a block freezes the whole keyboard rather than
--- just this tool.
---
--- ALWAYS the streaming form, never the plain buffered one. An hs.task built with only a
--- completion callback deadlocks once the child writes more than a pipe buffer of output,
--- because nothing drains the pipe until the child exits and the child cannot exit until
--- its writes are read. It fails silently, the callback never arrives, which reads as a
--- hang rather than an error. A file listing is exactly the kind of output that exceeds a
--- pipe buffer, so this matters here more than anywhere.
---
--- Success is the exit code rather than the presence of output, since a search that
--- legitimately found nothing exits clean and prints nothing. A non zero exit that still
--- printed something is passed through, because fzf exits non zero when it matched
--- nothing and grep style tools do the same.
function M.run(binary, args, timeoutSeconds, cb)
  local done, cancelled = false, false
  local timer, task, drainTimer
  local outChunks, errChunks = {}, {}
  local bytes, exitCode = 0, nil

  local function finish(out, err)
    if done then return end
    done = true
    if timer then timer:stop() end
    if drainTimer then drainTimer:stop() end
    if not cancelled then cb(out, err) end
  end

  -- Re arm while the output is still growing, so a slow trickle is waited out rather
  -- than cut off, settling after one grace period in the common case.
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
    return { cancel = function() end }
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

  return {
    cancel = function()
      if done then return end
      cancelled = true
      if timer then timer:stop() end
      if drainTimer then drainTimer:stop() end
      pcall(function() task:terminate() end)
      done = true
    end,
  }
end

-- Pending delayed steps, keyed so each releases only itself.
local pendingSteps = {}

--- util.after(delay, fn) -> handle
--- Run fn after delay, holding the timer until it fires.
---
--- Holding it is the whole point. A Hammerspoon timer is userdata whose finalizer stops
--- it, so a pending timer nothing refers to can be collected before it fires, and the step
--- then never happens with no error anywhere and nothing to grep for. The odds rise with
--- whatever else is allocating during the wait, which is exactly a picker rebuilding rows
--- on every keystroke, so this is the highest risk place in the spoon for that bug.
---
--- Keyed rather than a single slot, so two outstanding steps never cancel one another.
--- The returned handle cancels just this one, which is what the debounce needs when a
--- newer keystroke supersedes an older wait.
function M.after(delay, fn)
  local slot = {}
  local t = hs.timer.doAfter(delay, function()
    pendingSteps[slot] = nil
    fn()
  end)
  pendingSteps[slot] = t
  return {
    cancel = function()
      if pendingSteps[slot] then
        pendingSteps[slot]:stop()
        pendingSteps[slot] = nil
      end
    end,
  }
end

--- util.lines(s) -> iterator over non empty lines
function M.lines(s)
  return (s or ""):gmatch("[^\r\n]+")
end

--- util.basename(path) / util.dirname(path)
function M.basename(path)
  if not path or path == "" then return path end
  return (path:gsub("/+$", ""):match("([^/]+)$")) or path
end

function M.dirname(path)
  if not path or path == "" then return nil end
  return (path:gsub("/+$", ""):match("^(.*)/[^/]+$"))
end

--- util.ext(path) -> lowercased extension with no dot, or ""
--- A leading dot is not an extension, so ".zshrc" has none. That is what keeps a dotfile
--- from being filtered as though its whole name were a type.
function M.ext(path)
  local name = M.basename(path) or ""
  local e = name:match("^.+%.([%w]+)$")
  return e and e:lower() or ""
end

--- util.row(path, opts) -> a contract shaped row
--- One place builds a row, so every source produces the same shape and a field cannot be
--- forgotten by one of them.
function M.row(path, opts)
  opts = opts or {}
  return {
    path = path,
    -- The case folded path, built here rather than at match time because the shared words
    -- matcher folds only the query and compares the haystack verbatim. Handing it a raw path
    -- is what made an uppercase query match nothing at all, so the one place rows are built
    -- is the one place that fold belongs. Half a millisecond for two thousand rows.
    lower = (path or ""):lower(),
    name = M.basename(path),
    dir = M.dirname(path),
    isDir = opts.isDir or false,
    ext = opts.isDir and "" or M.ext(path),
    size = opts.size,
    modified = opts.modified,
    source = opts.source,
  }
end

--- util.shellQuote(s) -> a single quoted string safe to embed in a shell command
--- Wraps in single quotes and escapes any embedded single quote the only way a POSIX
--- shell allows, by closing the quote, emitting an escaped quote, and reopening.
---
--- This exists because ONE source genuinely needs a shell, see sources/hidden.lua, and a
--- query is arbitrary typed text. Everything else here runs a binary with an argument
--- list where quoting cannot apply.
function M.shellQuote(s)
  return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'"
end

--- util.expandHome(path) -> path with a leading tilde resolved
function M.expandHome(path)
  if not path then return nil end
  local home = os.getenv("HOME") or ""
  if path == "~" then return home end
  local rest = path:match("^~/(.*)$")
  if rest then return home .. "/" .. rest end
  return path
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------
-- How a fact is worded for a person. Here rather than in one surface because both the
-- row and the pane state the same three facts, and the same size or the same age must
-- not come out phrased two ways depending on which one you happen to be looking at.

local HOME = os.getenv("HOME") or ""

--- util.shortDir(dir) -> the directory with home collapsed to a tilde
--- The first thirty characters of nearly every path here are identical, and they cost
--- width the part that identifies the file needs.
function M.shortDir(dir)
  if not dir or dir == "" then return "" end
  if HOME ~= "" and dir:sub(1, #HOME) == HOME then
    return "~" .. dir:sub(#HOME + 1)
  end
  return dir
end

--- util.humanBytes(n) -> a byte count in the largest unit that keeps it short
function M.humanBytes(n)
  n = tonumber(n) or 0
  if n < 1024 then return string.format("%d B", n) end
  if n < 1024 * 1024 then return string.format("%d KB", math.floor(n / 1024 + 0.5)) end
  if n < 1024 * 1024 * 1024 then return string.format("%.1f MB", n / 1024 / 1024) end
  return string.format("%.1f GB", n / 1024 / 1024 / 1024)
end

--- util.humanAge(epoch) -> how long ago that was, in one coarse unit
--- Coarse on purpose. Nothing here is decided by the difference between two hours and
--- two hours twenty, and a precise figure would only be harder to read at a glance.
function M.humanAge(epoch)
  local secs = os.time() - (tonumber(epoch) or 0)
  if secs < 60 then return "just now" end
  if secs < 3600 then return math.floor(secs / 60) .. "m ago" end
  if secs < 86400 then return math.floor(secs / 3600) .. "h ago" end
  return math.floor(secs / 86400) .. "d ago"
end

return M
