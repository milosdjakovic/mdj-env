--- === BrowserTabs.apps ===
---
--- Finding a running application from its bundle id. One tiny module rather than a line repeated
--- in four places, because the obvious call is not reliable and the workaround has to be somewhere
--- nobody can forget it.
---
--- `hs.application.applicationsForBundleID` returns an empty list for an application that is
--- plainly running. Measured, not guessed. At the moment it failed, the same application was found
--- by name, was present in `hs.application.runningApplications` under exactly that bundle id, and
--- twenty further calls in the same instant all succeeded, as did a retry half a second later. So
--- it is the first call after something disturbs it that answers wrongly, and the caller that
--- happens to make that call gets nothing. It showed up here under rapid application switching,
--- which is precisely the situation this spoon runs in.
---
--- What that costs is worth spelling out, because both readings are silent. A provider asking
--- whether its browser is running is told no, so the browser is dropped from the listing and its
--- tabs simply are not there. The engine asking for the application to raise is told nothing is
--- there, so it raises nothing and the chosen tab is selected in a window that never comes
--- forward. Neither reports an error, and both look like the tool randomly not working.
---
--- The answer is to ask a second way rather than to retry on a timer, since the running list was
--- already correct at the instant the first call was wrong. Nothing here waits.

local M = {}

--- M.forBundleID(bundleID) - the running application with that bundle id, or nil when it really
--- is not running.
function M.forBundleID(bundleID)
  local direct = hs.application.applicationsForBundleID(bundleID)[1]
  if direct then return direct end
  for _, app in ipairs(hs.application.runningApplications()) do
    if app:bundleID() == bundleID then return app end
  end
  return nil
end

--- M.isRunning(bundleID) - whether it is running, by the same reliable reading, so a listing and
--- a raise can never disagree about it.
function M.isRunning(bundleID)
  return M.forBundleID(bundleID) ~= nil
end

return M
