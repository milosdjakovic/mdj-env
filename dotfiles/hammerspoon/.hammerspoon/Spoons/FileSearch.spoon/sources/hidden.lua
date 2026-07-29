--- Hidden source, the one that answers what Spotlight cannot see.
---
--- Spotlight holds no path containing a dot segment, so all of ~/.config, ~/.ssh, ~/.local
--- and every project's .github are invisible to it, measured as zero results. This source
--- covers that blind spot for an UNSCOPED hidden search only, since a scoped one is answered
--- by the walk source live and completely with no index at all.
---
--- WHY AN INDEX HERE AND NOWHERE ELSE. The blind spot is about 245 thousand paths and 33
--- megabytes on one machine, and walking it takes roughly a second. That is far too slow per
--- keystroke and far too much to hold in Lua, so it is written to a file once and filtered
--- with a tool. This is the only cache in the spoon, and it exists because there is no index
--- behind it rather than as an optimisation, which is the distinction that decides whether a
--- cache is worth its staleness. Dotfile trees barely move, so the staleness costs nothing,
--- and the stale answer stays on screen while a fresh index is built behind it.
---
--- THE CACHE LIVES OUTSIDE ~/.hammerspoon, and that is not tidiness. The config directory is
--- watched for changes and writing 33 megabytes into it would trigger a reload of the whole
--- config on every rebuild. It goes under ~/Library/Caches, the same place the Eyedropper
--- helper binary is cached and for the same reason.
---
--- WHY THE MATCHER IS fzf AND NOT ripgrep, which is the one place in this spoon a second tool
--- genuinely earns its keep. Measured over the full index, ripgrep is faster, zero to 20
--- milliseconds against 20 to 130, but it cannot rank. A one word query like nvim matches 42
--- thousand of these paths, so capping ripgrep's output hands back two hundred arbitrary rows
--- from wherever the walk happened to begin. fzf ranks first, so capping after it gives the
--- two hundred best, and it matches a subsequence, so a fumbled query like hmrspn still finds
--- hammerspoon paths in 60 milliseconds where a substring tool finds nothing at all.
---
--- THE ONE SHELL IN THE SPOON is here. fzf reads its candidates from standard input and takes
--- no file argument, and pushing 33 megabytes through the task's stdin from Lua on every
--- keystroke would be far worse than a redirect. So this single call goes through /bin/sh to
--- get `fzf --filter=... < index | head`, which also bounds the output at the pipe rather than
--- after the fact. The query is quoted through util.shellQuote, since it is arbitrary typed
--- text. Everything else in this spoon runs a binary with an argument list where no quoting
--- question arises.

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(spoonPath .. "../util.lua")()

local M = {}
M.name = "hidden"
M.tools = { "fd", "fzf" }

local cfg = {
  fdPath = nil,
  fzfPath = nil,
  prune = {},
  pruneLocal = {},
  maxAgeSeconds = 300,
}

local inflight = nil
local building = false
local pendingAfterBuild = {}

-- The index file, deliberately outside the watched config tree.
local function indexPath()
  local home = os.getenv("HOME") or ""
  return home .. "/Library/Caches/mdj-hammerspoon/filesearch-hidden.txt"
end

--- hidden.configure(opts)
--- opts.fdPath, opts.fzfPath   resolved tool locations, injected by the composition root
--- opts.prune, opts.pruneLocal directory names the index refuses to walk
--- opts.maxAgeSeconds          how stale the index may be before a rebuild starts
function M.configure(opts)
  opts = opts or {}
  cfg.fdPath = opts.fdPath
  cfg.fzfPath = opts.fzfPath
  cfg.prune = opts.prune or {}
  cfg.pruneLocal = opts.pruneLocal or {}
  cfg.maxAgeSeconds = opts.maxAgeSeconds or 300
  return M
end

function M.available()
  if not cfg.fdPath then return false, "fd not resolved" end
  if not cfg.fzfPath then return false, "fzf not resolved" end
  return true
end

--- Claims an unscoped hidden search only. A scope goes to the walk source, which sees the
--- same files live, so the index is never consulted when there is something better.
function M.supports(parsed)
  if parsed.scope then return false end
  return parsed.hidden == true
end

function M.cancel()
  if inflight then
    pcall(function() inflight.cancel() end)
    inflight = nil
  end
end

local function indexAgeSeconds()
  local attrs = hs.fs.attributes(indexPath(), "modification")
  if type(attrs) ~= "number" then return nil end
  return os.time() - attrs
end

-- Build the index. Everything with a dot segment anywhere in its path, which is precisely the
-- complement of what Spotlight holds, expressed as one full path pattern so the walker does
-- the whole job in a single pass with no piping.
local function rebuild(done)
  if building then
    if done then pendingAfterBuild[#pendingAfterBuild + 1] = done end
    return
  end
  building = true

  local dir = indexPath():match("^(.*)/[^/]+$")
  pcall(function() hs.fs.mkdir(dir) end)

  local home = os.getenv("HOME") or ""
  local args = { "--hidden", "--full-path", "/\\." }
  for _, name in ipairs(cfg.prune or {}) do
    args[#args + 1] = "--exclude"
    args[#args + 1] = name
  end
  for _, name in ipairs(cfg.pruneLocal or {}) do
    args[#args + 1] = "--exclude"
    args[#args + 1] = name
  end
  args[#args + 1] = home

  -- Written to a temporary file and moved into place, so a filter running against the old
  -- index never reads a half written one.
  local tmp = indexPath() .. ".tmp"
  util.run(cfg.fdPath, args, 60, function(out, err)
    building = false
    if out then
      local f = io.open(tmp, "w")
      if f then
        f:write(out)
        f:close()
        os.rename(tmp, indexPath())
      end
    else
      util.log.i("hidden index build failed, " .. tostring(err))
    end
    local waiting = pendingAfterBuild
    pendingAfterBuild = {}
    if done then done() end
    for _, fn in ipairs(waiting) do fn() end
  end)
end

--- hidden.rebuild() - force an index build, for a caller wanting it warmed.
function M.rebuild()
  rebuild(nil)
end

--- hidden.warm() - make sure an index exists and is reasonably fresh, and put it in the page
--- cache while it is at it. Called when the picker opens, so the first hidden query pays no
--- cold read. Measured, a cold read of the index costs 240 milliseconds against 6 warm.
function M.warm()
  local age = indexAgeSeconds()
  if not age or age > cfg.maxAgeSeconds then
    rebuild(nil)
    return
  end
  -- Touch it so the pages are resident, cheaply and off the main thread.
  util.run("/bin/dd", { "if=" .. indexPath(), "of=/dev/null", "bs=1m" }, 5, function() end)
end

-- Filter the index and turn the surviving lines into rows.
local function filter(parsed, ctx, cb)
  local cap = ctx.cap or 200
  local path = indexPath()

  -- fzf matches a subsequence, so the words are joined with spaces which is its own AND
  -- syntax for separate terms, meaning every term must match somewhere in the line.
  local needle = table.concat(parsed.words, " ")
  -- -i forces case insensitivity, since the matcher is smart case by default and one capital
  -- letter would otherwise make the whole query case sensitive. Same reasoning as the walker.
  local cmd = string.format("%s -i --filter=%s < %s | head -n %d",
    util.shellQuote(cfg.fzfPath),
    util.shellQuote(needle),
    util.shellQuote(path),
    cap)

  M.cancel()
  inflight = util.run("/bin/sh", { "-c", cmd }, ctx.timeoutSeconds, function(out, err)
    inflight = nil
    if not out then
      -- fzf exits non zero when nothing matched, which is not a failure worth reporting.
      cb({}, nil)
      return
    end
    local exts = nil
    if parsed.exts and #parsed.exts > 0 then
      exts = {}
      for _, e in ipairs(parsed.exts) do exts[e] = true end
    end
    local rows = {}
    for line in util.lines(out) do
      local isDir = line:sub(-1) == "/"
      local p = isDir and line:sub(1, -2) or line
      local keep = true
      if exts then
        keep = exts[util.ext(p)] == true
      end
      if keep then
        rows[#rows + 1] = util.row(p, { isDir = isDir, source = M.name })
      end
    end
    cb(rows, nil)
  end)
end

--- hidden.search(parsed, ctx, cb)
--- With nothing typed there is nothing to filter, since the index holds a quarter of a
--- million paths and no useful order, so an empty hidden query returns nothing rather than an
--- arbitrary slice.
function M.search(parsed, ctx, cb)
  if #parsed.words == 0 then
    cb({}, "type something to search hidden files")
    return
  end
  local age = indexAgeSeconds()
  if not age then
    -- No index at all, so the first hidden search waits for one to be built.
    rebuild(function() filter(parsed, ctx, cb) end)
    return
  end
  -- Stale is answered from what exists while a fresh index is built behind it, so a search
  -- never waits on a rebuild it did not have to.
  if age > cfg.maxAgeSeconds then rebuild(nil) end
  filter(parsed, ctx, cb)
end

return M
