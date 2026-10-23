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
local configDir = caseDir .. "/../.."

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

-- The run is handed the config directory as the shell resolves it, with no dot segments, since
-- the stub lists the plugin trees by that spelling and a path through this case's own directory
-- finds no plugin and no host, so nothing it checks below would be built.
local sandbox = os.tmpname()
os.remove(sandbox)
local command = string.format("cd %q && lua Spoons/Olm.spoon/test/drygate-composerun.lua \"$(pwd)/Spoons/Olm.spoon/\" \"$(pwd)\" %q 2>&1",
  configDir, sandbox)
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
