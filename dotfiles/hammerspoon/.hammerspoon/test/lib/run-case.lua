-- Runs one case and writes what it printed to a results file, so the runner never depends on
-- the hs client mirroring the console back to it. That mirroring is what made a killed client
-- dangerous. Hammerspoon kept the dead client registered, every later console line was sent to
-- it and refused as already recursing, each refusal was itself a console line, and the flood
-- wedged the ipc channel for every call after it. With results in a file the runner calls hs
-- with -q, nothing is mirrored, and a call that hangs can be killed and leave nothing behind.
--
-- Called as dofile(thisFile)(casePath, resultsPath). print is replaced only while the case
-- runs and is put back whether the case finishes or raises. A case that raises gets one
-- ERROR line in the results, which the runner reports as a case that did not run cleanly.

return function(casePath, resultsPath)
  local out = assert(io.open(resultsPath, "w"))
  local originalPrint = print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    out:write(table.concat(parts, "\t"), "\n")
    out:flush()
  end
  local ok, err = xpcall(dofile, debug.traceback, casePath)
  print = originalPrint
  if not ok then
    out:write("ERROR ", (tostring(err):gsub("\n", " ")), "\n")
  end
  out:close()
  return "done"
end
