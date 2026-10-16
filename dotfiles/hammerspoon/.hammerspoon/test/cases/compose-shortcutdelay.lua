-- Unit case for the one wire that carries the hint bar's idle delay from the root to the panel.
-- root/compose.lua hands its policy to lib/hints.lua under a name, and lib/hints.lua reads the
-- delay from it. test/cases/surfaces.lua checks the hints half, and this checks the whole path
-- by running the composition root itself, through the dry gate's own stubbed run,
-- Olm.spoon/test/drygate-composerun.lua, which records every panel the root builds. A rename
-- that reaches only one of the two files leaves every hint bar's panel with no delay, which
-- draws it the instant a list opens, and fails here.
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
local spoonDir = configDir .. "/Spoons/Olm.spoon/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local sandbox = os.tmpname()
os.remove(sandbox)
local command = string.format("lua %q %q %q %q 2>&1", spoonDir .. "test/drygate-composerun.lua",
  spoonDir, configDir, sandbox)
local output
if hs and hs.execute then
  output = hs.execute(command, true) or ""
else
  local pipe = io.popen(command)
  output = pipe:read("a")
  pipe:close()
end

-- A hint bar's panel is the one the root builds below a list, eight points off it, with a
-- content strategy that can say what it shows.
local panels, delays = 0, {}
for line in output:gmatch("[^\n]+") do
  -- The placement is read as the snapshot prints it, a word after placement, never written
  -- here as a value handed to anything.
  if line:match("^atom lib%.panel%.new%(") and line:match('placement=(%b"")') == '"below"'
    and line:find("gap=8", 1, true) and line:find("state=fn", 1, true) then
    panels = panels + 1
    local delay = line:match("delay=([%d%.]+)")
    if delay then delays[#delays + 1] = tonumber(delay) end
  end
end

check("the root ran to the end under the stub", not output:find("\nraised ", 1, true) and panels > 0,
  "panels " .. panels)
check("every hint bar panel the root builds carries a delay", panels > 0 and #delays == panels,
  string.format("%d of %d", #delays, panels))
local same = #delays > 0
for _, d in ipairs(delays) do same = same and d == delays[1] and d > 0 end
check("every hint bar panel carries the same delay, above zero", same)

-- When the person sets a delay it is that one, otherwise the root's own shipped value.
local ok, settings = pcall(dofile, configDir .. "/config/settings.lua")
local wanted = ok and type(settings) == "table" and type(settings.shortcutsPanel) == "table"
  and settings.shortcutsPanel.delayMs
if wanted then
  check("the delay is the one the person's settings name", delays[1] == wanted,
    tostring(delays[1]) .. " against " .. tostring(wanted))
end
