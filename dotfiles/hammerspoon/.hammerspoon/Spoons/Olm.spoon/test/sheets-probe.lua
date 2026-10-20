-- The cheat sheet probe, the content model each leader's sheet would draw.
--
-- This reads LIVE state and nothing else. It posts no key, shows no sheet and reloads nothing.
-- It reads the one sheet host's own records, asks each plugin supplied section once the way a
-- show would, and writes the answer to a file rather than returning it over the port. Run it
-- through test/views.sh, which sets the output path in OLM_VIEW_OUT and bounds the call. See
-- sheets-project.lua for the line format.

local OUT = OLM_VIEW_OUT
assert(type(OUT) == "string" and OUT ~= "", "set OLM_VIEW_OUT to the output path before dofile")

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local project = assert(loadfile(here .. "sheets-project.lua"))()

local olm = spoon.Olm
local composed = assert(olm and olm._composed, "the live Olm has no composed plan")
local identity = (composed.plan and composed.plan.identity) or {}
local sheet = composed.modules[identity.leadersheet or "leadersheet"]

local lines = project.lines(sheet)
local f = assert(io.open(OUT, "w"))
f:write(table.concat(lines, "\n"), "\n")
f:close()

return "wrote " .. #lines .. " lines"
