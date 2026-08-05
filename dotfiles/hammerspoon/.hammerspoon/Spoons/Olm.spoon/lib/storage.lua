-- Storage roots, the path mechanism every plugin will one day ask its
-- directory from. It owns tilde expansion and the join from a root to a
-- tool's own directory, so a plugin names itself once and never assembles a
-- path by hand. configure receives the two roots exactly as written in
-- config/settings.lua, cacheRoot and olmRoot, expands each once, and after
-- that cacheDir(name) and dataDir(name) each return the finished absolute
-- path of that tool's directory under the matching root, with no trailing
-- slash and no double slash regardless of how the root was written. A
-- builder called before configure fails loudly with a readable error rather
-- than answering nil or a partial path.
--
-- Every function above is pure string work with no disk access, which is
-- what lets the unit case cover path building without touching the
-- filesystem. ensure is the one exception, the only function in this file
-- that touches disk, and no consumer calls it yet.

local M = {}

-- The expanded roots, filled in once by configure and read by every builder
-- after that. Left nil until configure runs, so a builder called too early
-- has something clear to check against rather than a table of blanks.
local expanded = nil

--- M.expandHome(path)
--- Turns a leading tilde into the value of the HOME environment variable and
--- leaves any other path untouched. A tilde only counts at the very start of
--- the string, since a tilde appearing later is just a character in a name.
function M.expandHome(path)
  if path:sub(1, 1) == "~" then
    local home = os.getenv("HOME") or ""
    return home .. path:sub(2)
  end
  return path
end

-- Strips every trailing slash from an expanded root, so joining it with a
-- name never produces a double slash regardless of how the root was written
-- in settings.
local function stripTrailingSlashes(path)
  local stripped = path
  while #stripped > 1 and stripped:sub(-1) == "/" do
    stripped = stripped:sub(1, -2)
  end
  return stripped
end

--- M.configure(roots)
--- Receives the two roots as written in settings, cacheRoot and olmRoot,
--- expands each once, and remembers the result for every later builder
--- call. The live config calls this exactly once, from the composition
--- root, right after loading this spoon.
function M.configure(roots)
  expanded = {
    cacheRoot = stripTrailingSlashes(M.expandHome(roots.cacheRoot)),
    olmRoot = stripTrailingSlashes(M.expandHome(roots.olmRoot)),
  }
end

-- Answers the expanded value of the named root, or fails loudly naming the
-- builder that was asked too early, since a silent nil here would only
-- surface as a mysterious failure many calls away from the module that
-- forgot to configure.
local function rootFor(builderName, key)
  if not expanded then
    error("storage configure must run before " .. builderName .. ", no roots are configured yet")
  end
  return expanded[key]
end

--- M.cacheDir(name)
--- The finished absolute path of name's directory under the cache root,
--- regenerable data that is safe to delete and only costs a rebuild.
function M.cacheDir(name)
  return rootFor("cacheDir", "cacheRoot") .. "/" .. name
end

--- M.dataDir(name)
--- The finished absolute path of name's directory under the olm root,
--- durable data a person may back up or turn into a git repository.
function M.dataDir(name)
  return rootFor("dataDir", "olmRoot") .. "/" .. name
end

--- M.ensure(path)
--- Creates the directory if missing and returns the path unchanged, so a
--- consumer can ask for its directory and have it exist in one call. It
--- walks every segment from the root down, since a fresh machine may be
--- missing the olm root itself and not only the tool directory beneath it,
--- and it is the only function in this file that touches the disk.
function M.ensure(path)
  local built = ""
  for segment in path:gmatch("[^/]+") do
    built = built .. "/" .. segment
    if not hs.fs.attributes(built) then
      hs.fs.mkdir(built)
    end
  end
  return path
end

return M
