--- === SwiftBuild ===
---
--- Compiles Swift sources into one cached output and says when it is ready. It answers one
--- question, whether the output for these exact inputs exists, and builds it in the background
--- when it does not. It knows nothing about what the output is for, so a library Hammerspoon
--- loads and a helper program it runs are the same call with different flags.
---
--- WHY THE OUTPUT IS NAMED BY A HASH AND NOT COMPARED BY DATE. A library loaded into
--- Hammerspoon can never be unloaded, since an image that defines Objective C or Swift classes
--- stays mapped until the process exits. A rebuild written over the same path would therefore
--- never be seen, the next load finds the old image by its path and hands it back. So the name
--- of the output carries a hash of every input, the sources, any extra input such as a bridging
--- header, the flags, and the running Hammerspoon's version, since a library links against
--- Hammerspoon's own LuaSkin. A changed input is a new path, a new path is a fresh load, and an
--- unchanged one is found on disk with no compile at all. The caller folds the same hash into
--- the Swift module name, so the classes of a rebuilt image never collide with the old one.
---
--- Builds go to a temporary name and are renamed into place only on success, so a load never
--- finds a half written file. After a success the older outputs of the same name are removed,
--- keeping the newest few, so the cache does not grow by one library per edit, and a main
--- checkout and a worktree on different sources keep one each rather than rebuilding each other.
---
--- M.toolchain answers whether a compiler inside the command line tools has what
--- src/install-xcode-clt.sh calls present, clang beside it and an SDK for the running macOS,
--- without running anything, since running a compiler that is missing its tools raises Apple's
--- install dialog. decisions/developer-toolchain.md has why that is the definition.

local M = {}

-- Every running build, held so the task is not collected before its callback fires.
local inFlight = {}

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("a")
  f:close()
  return data
end

-- Creates a directory and every missing parent, since hs.fs.mkdir makes only one level.
local function mkdirs(path)
  local built = ""
  for part in path:gmatch("[^/]+") do
    built = built .. "/" .. part
    if not hs.fs.attributes(built) then hs.fs.mkdir(built) end
  end
end

-- How many outputs of one name a successful build leaves in the directory, the new one included,
-- when the spec does not say.
local KEEP = 3

--- M.toolchain(swiftc, major) -> sdk path or nil, reason
--- swiftc is a compiler's path inside a command line tools directory, usr/bin/swiftc under it,
--- and major the running macOS's major version. Answers the newest SDK for that version under the
--- directory's SDKs when clang is beside the compiler, and nil and a reason otherwise. Looks at
--- the disk only.
function M.toolchain(swiftc, major)
  local root = type(swiftc) == "string" and swiftc:match("^(.*)/usr/bin/swiftc$")
  if not root then return nil, "no compiler inside the command line tools" end
  if not hs.fs.attributes(root .. "/usr/bin/clang") then
    return nil, "the command line tools have no clang"
  end
  local names = {}
  local ok, iterator, handle = pcall(hs.fs.dir, root .. "/SDKs")
  if ok and iterator then
    local prefix = "MacOSX" .. tostring(major)
    for name in iterator, handle do
      if name:sub(1, #prefix) == prefix and name:match("^MacOSX[%d%.]*%.sdk$") then
        names[#names + 1] = name
      end
    end
  end
  if #names == 0 then return nil, "the command line tools have no macOS " .. tostring(major) .. " SDK" end
  table.sort(names)
  return root .. "/SDKs/" .. names[#names]
end

-- Removes every output of name in dir past the newest keep by modification time, never the one
-- just built. A file that cannot be removed is left, since a stale library costs only space.
local function prune(dir, name, keep, current)
  local pattern = "^" .. name:gsub("%p", "%%%0") .. "%-%x+%.so$"
  local found = {}
  local ok, iterator, handle = pcall(hs.fs.dir, dir)
  if not ok or not iterator then return end
  for file in iterator, handle do
    if file:match(pattern) then
      local path = dir .. "/" .. file
      found[#found + 1] = { path = path, at = hs.fs.attributes(path, "modification") or 0 }
    end
  end
  table.sort(found, function(a, b)
    if a.path == current then return true end
    if b.path == current then return false end
    return a.at > b.at
  end)
  for i = keep + 1, #found do os.remove(found[i].path) end
end

--- M.hash(spec) -> string or nil, reason
--- The first sixteen hex digits of a SHA256 over every input that decides what the compiler
--- produces. Answers nil and a reason when a source cannot be read.
function M.hash(spec)
  local parts = { hs.processInfo.version, table.concat(spec.flags or {}, "\0") }
  local files = {}
  for _, path in ipairs(spec.sources) do files[#files + 1] = path end
  for _, path in ipairs(spec.inputs or {}) do files[#files + 1] = path end
  for _, path in ipairs(files) do
    local data = readFile(path)
    if not data then return nil, "cannot read " .. path end
    parts[#parts + 1] = data
  end
  return hs.hash.SHA256(table.concat(parts, "\0")):sub(1, 16)
end

--- M.ensure(spec, done)
--- spec.sources, the Swift files. spec.inputs, other files whose change must force a rebuild.
--- spec.flags, compiler flags before the sources, where the token {hash} is replaced by the hash.
--- spec.dir, the cache directory. spec.name, the output's stem. spec.swiftc, the resolved
--- compiler path or nil. spec.keep, how many outputs of the name a successful build leaves,
--- three when absent. done(ok, pathOrReason, hash) is called once, at once when the output
--- is already there and from the task's callback otherwise. Never throws.
function M.ensure(spec, done)
  local hash, reason = M.hash(spec)
  if not hash then done(false, reason) return end
  local output = spec.dir .. "/" .. spec.name .. "-" .. hash .. ".so"
  if hs.fs.attributes(output) then done(true, output, hash) return end
  if not spec.swiftc then done(false, "no swiftc, the command line tools are not installed") return end

  mkdirs(spec.dir)
  local temp = output .. ".building"
  local args = {}
  for _, flag in ipairs(spec.flags or {}) do args[#args + 1] = (flag:gsub("{hash}", hash)) end
  for _, path in ipairs(spec.sources) do args[#args + 1] = path end
  args[#args + 1] = "-o"
  args[#args + 1] = temp

  local task
  task = hs.task.new(spec.swiftc, function(code, _, err)
    inFlight[task] = nil
    if code == 0 and os.rename(temp, output) then
      prune(spec.dir, spec.name, spec.keep or KEEP, output)
      done(true, output, hash)
    else
      os.remove(temp)
      done(false, "swiftc exited " .. tostring(code) .. ", " .. tostring(err))
    end
  end, args)
  if not task then done(false, "could not create the build task") return end
  inFlight[task] = true
  task:start()
end

return M
