-- The launcher catalog probe, every row the running launcher's own catalog holds.
--
-- This reads LIVE state and nothing else. It posts no key, opens no list and reloads nothing.
-- It asks the running launcher to build its catalog afresh, which touches none of the caches an
-- open uses, and writes the answer to a file rather than returning it over the port, which loses
-- or truncates large replies. Run it through test/views.sh, which sets the output path in the
-- global OLM_VIEW_OUT and bounds the call. See launcher-project.lua for the line format.
--
--   hs -q -c 'OLM_VIEW_OUT = "/some/path"; return dofile("/path/to/launcher-probe.lua")'

local OUT = OLM_VIEW_OUT
assert(type(OUT) == "string" and OUT ~= "", "set OLM_VIEW_OUT to the output path before dofile")

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local project = assert(loadfile(here .. "launcher-project.lua"))()

local composed = assert(spoon.Olm and spoon.Olm._composed, "the live Olm has no composed plan")
local identity = (composed.plan and composed.plan.identity) or {}
local launcher = assert(composed.modules[identity.launcher or "launcher"], "the live Olm has no launcher")

local lines = project.lines(launcher)
local f = assert(io.open(OUT, "w"))
f:write(table.concat(lines, "\n"), "\n")
f:close()
return "wrote " .. #lines .. " lines"
