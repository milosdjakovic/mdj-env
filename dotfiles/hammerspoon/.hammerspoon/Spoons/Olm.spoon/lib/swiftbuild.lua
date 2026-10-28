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
--- finds a half written file.

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
--- compiler path or nil. done(ok, pathOrReason, hash) is called once, at once when the output
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
