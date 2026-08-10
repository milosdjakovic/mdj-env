-- Unit case for Olm.spoon/lib/storage.lua, the path mechanism every later
-- plugin will ask its own directory from. The runner reaches this file with
-- a dofile call carrying an absolute path, so this file in turn locates
-- itself the same way, through debug.getinfo, and derives the module path
-- from there. No absolute path is ever written down here, and the module
-- under test is only loaded, never edited.
--
-- Each check prints one line, PASS or FAIL followed by a plain description,
-- and the runner counts and reports from those lines alone. There is no
-- shared assertion library between this file and the runner, since one case
-- file does not yet earn one, the same choice cases/match.lua already made.
--
-- This case never creates a directory and never calls ensure, since path
-- building is pure string work and the point of testing it this way is that
-- it needs no filesystem at all. Each block below loads its own fresh copy
-- of the module with loadfile, so one block's call to configure can never
-- leak into another's expectations.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/lib/storage.lua"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    if detail then
      print("FAIL " .. description .. ", " .. detail)
    else
      print("FAIL " .. description)
    end
  end
end

local home = os.getenv("HOME")

-- Expansion and the too early builder, on a freshly loaded module that has
-- never been configured.
do
  local moduleChunk, loadErr = loadfile(modulePath)
  if not moduleChunk then
    print("FAIL load Olm.spoon/lib/storage.lua, " .. tostring(loadErr))
    return
  end
  local M = moduleChunk()

  check(
    "expandHome turns a leading tilde into the HOME environment variable",
    M.expandHome("~/Olm") == home .. "/Olm"
  )

  check(
    "expandHome leaves an already absolute path untouched",
    M.expandHome("/Users/someone/Olm") == "/Users/someone/Olm"
  )

  local calledOk, err = pcall(function() return M.cacheDir("clipboard") end)
  check(
    "a builder called before configure raises a readable error",
    calledOk == false and type(err) == "string" and #err > 0,
    "pcall returned ok=" .. tostring(calledOk) .. " err=" .. tostring(err)
  )
end

-- Joining, on a fresh module configured with the settings values exactly as
-- written in config/settings.lua.
do
  local M = loadfile(modulePath)()
  M.configure({ cacheRoot = "~/.cache/hammerspoon", olmRoot = "~/Olm" })

  check(
    "cacheDir joins the expanded cache root and the name with one slash",
    M.cacheDir("clipboard") == home .. "/.cache/hammerspoon/clipboard"
  )

  check(
    "dataDir joins the expanded olm root and the name with one slash",
    M.dataDir("clipboard") == home .. "/Olm/clipboard"
  )
end

-- A root written with a trailing slash, on another fresh module, still
-- produces a single slash join rather than a double one.
do
  local M = loadfile(modulePath)()
  M.configure({ cacheRoot = "~/.cache/hammerspoon/", olmRoot = "~/Olm/" })

  check(
    "a cache root written with a trailing slash still joins with a single slash",
    M.cacheDir("clipboard") == home .. "/.cache/hammerspoon/clipboard"
  )

  check(
    "an olm root written with a trailing slash still joins with a single slash",
    M.dataDir("clipboard") == home .. "/Olm/clipboard"
  )
end
