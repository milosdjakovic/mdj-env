-- Unit case for the one wire that carries the action bar from the root to the chooser. The root
-- builds a footer collaborator over lib/hints.lua's footerModel and hands it to the stage, the
-- stage hands it to its one instance, and the default provider sizes a footer row from the kit's
-- tokens only when it has one, docs/PLAN-ACTION-BAR.md. A rename that reaches only one of those
-- files leaves every list with no bar and fails here. It runs the composition root itself,
-- through the dry gate's own stubbed run, Olm.spoon/test/drygate-composerun.lua, which records
-- every call into a host or a shared atom and a walk of what the root recorded.
--
-- It replaced the case for the hint bar's idle delay, which carried the docked hint panel's
-- policy the same way, and it also proves that panel is gone, so no second bar is drawn.
--
-- The run is a separate plain lua process, so it touches neither the live config nor the
-- running Hammerspoon. Inside Hammerspoon the command goes through hs.execute with the user's
-- shell, which is where lua is found, and under a plain interpreter through io.popen.
--
-- Each check prints one line, PASS or FAIL followed by a plain description.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")

-- A path with its dot segments resolved in Lua, the config directory two levels above this case.
-- The run must be handed it with no dot segments, since the stub lists the plugin trees by that
-- spelling and a path through this case's own directory finds no plugin and no host.
local function resolved(path)
  -- A relative path, a plain lua run from inside the checkout, is taken from the working directory.
  if path:sub(1, 1) ~= "/" then path = (os.getenv("PWD") or ".") .. "/" .. path end
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then table.remove(parts)
    elseif part ~= "." then parts[#parts + 1] = part end
  end
  return "/" .. table.concat(parts, "/")
end
local configDir = resolved(caseDir .. "/../..")
local spoonDir = configDir .. "/Spoons/Olm.spoon/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

-- Every path is resolved here and single quoted, with nothing for a shell to expand. Inside
-- Hammerspoon hs.execute wraps the whole command in double quotes for the user's login shell, so
-- a double quote in it ends that quoting and a command substitution is expanded by the outer
-- shell, in Hammerspoon's own directory, before any cd in the command has run. The first version
-- built the paths with cd and $(pwd) and so handed the stub a spoon that was not there inside
-- Hammerspoon, while it passed under plain lua.
local sandbox = os.tmpname()
os.remove(sandbox)
local function quoted(path) return "'" .. path .. "'" end
local command = "lua " .. quoted(spoonDir .. "test/drygate-composerun.lua") .. " " .. quoted(spoonDir)
  .. " " .. quoted(configDir) .. " " .. quoted(sandbox) .. " 2>&1"
local output
if hs and hs.execute then
  output = hs.execute(command, true) or ""
else
  local pipe = io.popen(command)
  output = pipe:read("a")
  pipe:close()
end

local stageFooter, instanceFooter, footerH, hintPanels = false, false, nil, 0
for line in output:gmatch("[^\n]+") do
  if line:match("^atom host%.stage%.configure%(") and line:find("footer=fn", 1, true) then
    stageFooter = true
  end
  if line:match("stage%._instance%.config%.footer = fn$") then instanceFooter = true end
  local h = line:match("stage%._instance%.layout%.footerH = ([%d%.]+)$")
  if h then footerH = tonumber(h) end
  -- The docked hint panel was a panel the root built below a list with a content strategy that
  -- could say what it showed. The placement is read as the snapshot prints it, a word after
  -- placement, never written here as a value handed to anything.
  if line:match("^atom lib%.panel%.new%(") and line:match('placement=(%b"")') == '"below"'
    and line:find("state=fn", 1, true) then
    hintPanels = hintPanels + 1
  end
end

check("the root ran to the end under the stub", not output:find("\nraised ", 1, true))
check("the root hands the stage a footer collaborator", stageFooter)
check("the stage hands it to its one chooser instance", instanceFooter)
check("the default provider sizes a footer row from the kit's tokens", footerH ~= nil and footerH > 0,
  "footerH " .. tostring(footerH))
check("no docked hint panel is built under any list, so nothing draws a second bar", hintPanels == 0,
  hintPanels .. " panel(s)")
