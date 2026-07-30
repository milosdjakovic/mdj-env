--- Walk source, the one that answers anything with a directory scope.
---
--- Once a directory is named, walking it beats querying an index and needs no index at all.
--- Measured on one machine, walking Downloads with 797 entries took 13 milliseconds, and a
--- project tree holding 196 thousand entries took 353. The same tool over a whole home took
--- 11.9 seconds, which is exactly why this source refuses anything unscoped and Spotlight
--- owns that half.
---
--- It also sees what Spotlight cannot. A scoped search here finds dotfiles with no index and
--- no cache, because it is looking at the filesystem rather than at a metadata store, which
--- makes a scoped hidden search both the cheapest and the most complete case in the spoon.
---
--- TWO MODES, and the split is not arbitrary. With no text this is a BROWSE, so it lists one
--- level sorted newest first, because that is what a file manager shows and because one level
--- can be listed and ordered by the system with no recursion and no stat calls. Type anything
--- and it becomes a recursive search. So `downloads/` shows you Downloads and `downloads/hs`
--- searches beneath it.
---
--- The browse uses /bin/ls rather than the walker, and by absolute path deliberately. ls does
--- the mtime ordering itself in C, which is the whole reason to use it, since the walker
--- cannot sort and ordering by date any other way means stat'ing every entry. The absolute
--- path matters because ls is commonly shadowed by a fancier replacement in a user's shell,
--- and this must run the real one.

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local util = loadfile(spoonPath .. "../util.lua")()

local M = {}
M.name = "walk"
M.tool = "fd"

local cfg = {
  path = nil,
  prune = {},
}

local inflight = nil

--- walk.configure(opts)
--- opts.path   resolved location of the walker, injected by the composition root, which is
---             the only way this file learns where the tool lives
--- opts.prune  directory names never worth descending into
function M.configure(opts)
  opts = opts or {}
  cfg.path = opts.path
  cfg.prune = opts.prune or {}
  return M
end

function M.available()
  if not cfg.path then return false, "fd not resolved" end
  return true
end

--- Claims every query carrying a scope, hidden or not, which is why the composition root
--- registers it first.
function M.supports(parsed)
  return parsed.scope ~= nil
end

function M.cancel()
  if inflight then
    pcall(function() inflight.cancel() end)
    inflight = nil
  end
end

-- One level, newest first. ls marks directories with a trailing slash under -p, lists
-- dotfiles under -A without the two dot entries, and sorts by modification time under -t.
local function browse(parsed, ctx, cb)
  local dir = ctx.scopePath
  local args = { "-1", "-A", "-p", "-t", dir }
  M.cancel()
  inflight = util.run("/bin/ls", args, ctx.timeoutSeconds, function(out, err)
    inflight = nil
    if not out then
      cb({}, err or "listing failed")
      return
    end
    local rows = {}
    local cap = ctx.cap or 200
    for line in util.lines(out) do
      local isDir = line:sub(-1) == "/"
      local name = isDir and line:sub(1, -2) or line
      if name ~= "" then
        local path = dir:gsub("/+$", "") .. "/" .. name
        rows[#rows + 1] = util.row(path, { isDir = isDir, source = M.name })
        if #rows >= cap then break end
      end
    end
    -- A directory that listed cleanly and holds nothing is a fact only this source knows, and
    -- saying so here is what stops the picker reporting an empty folder as no matches found, which
    -- is a different thing and reads as a failed search. Spelled out rather than folded into an
    -- and or expression, since `cond and value or nil` is the shape that has already caused two
    -- bugs in this spoon.
    local reason = nil
    if #rows == 0 then reason = "empty folder" end
    cb(rows, reason)
  end)
end

-- Recursive search beneath the scope.
--
-- The walker takes one pattern, so the FIRST word is handed to it as a fixed string and any
-- remaining words are applied here to what came back. That keeps the expensive part, visiting
-- the tree, filtering in C on the most selective thing available, while the cheap part runs
-- over a bounded list. Extensions go to the tool as well, since it filters those natively.
local function search(parsed, ctx, cb)
  local dir = ctx.scopePath
  local cap = ctx.cap or 200
  local args = {}

  if parsed.hidden then args[#args + 1] = "--hidden" end
  -- The bang sigil means walk what gitignore and the prune list would drop.
  if parsed.ignored then
    args[#args + 1] = "--no-ignore"
  else
    for _, name in ipairs(cfg.prune or {}) do
      args[#args + 1] = "--exclude"
      args[#args + 1] = name
    end
  end

  for _, e in ipairs(parsed.exts or {}) do
    args[#args + 1] = "--extension"
    args[#args + 1] = e
  end

  -- Follow symlinks, which is not optional in this environment. Every config directory here is
  -- stow managed, so ~/.hammerspoon and each spoon beneath it is a symlink into the repository,
  -- and without this a scoped search there returns nothing at all while looking perfectly
  -- healthy. The walker detects its own loops, so the usual objection does not apply.
  args[#args + 1] = "--follow"

  args[#args + 1] = "--max-results"
  args[#args + 1] = tostring(cap)
  -- Case insensitive explicitly, because the walker is smart case by default, so a single
  -- capital letter anywhere in the query silently turns the whole search case sensitive. That
  -- is a sensible default for a shell and the wrong one for a picker, where the same typed text
  -- must mean the same thing however it was capitalised.
  args[#args + 1] = "--ignore-case"
  args[#args + 1] = "--fixed-strings"
  args[#args + 1] = parsed.words[1] or ""
  args[#args + 1] = dir

  M.cancel()
  inflight = util.run(cfg.path, args, ctx.timeoutSeconds, function(out, err)
    inflight = nil
    if not out then
      cb({}, err or "walk failed")
      return
    end
    local rows = {}
    local extra = {}
    for i = 2, #parsed.words do extra[#extra + 1] = parsed.words[i]:lower() end
    for line in util.lines(out) do
      local keep = true
      if #extra > 0 then
        local hay = line:lower()
        for _, w in ipairs(extra) do
          if not hay:find(w, 1, true) then keep = false break end
        end
      end
      if keep then
        local isDir = line:sub(-1) == "/"
        local path = isDir and line:sub(1, -2) or line
        rows[#rows + 1] = util.row(path, { isDir = isDir, source = M.name })
      end
    end
    cb(rows, nil)
  end)
end

--- walk.search(parsed, ctx, cb)
function M.search(parsed, ctx, cb)
  if not ctx.scopePath then
    cb({}, "no directory")
    return
  end
  if parsed.text == "" then
    browse(parsed, ctx, cb)
  else
    search(parsed, ctx, cb)
  end
end

return M
