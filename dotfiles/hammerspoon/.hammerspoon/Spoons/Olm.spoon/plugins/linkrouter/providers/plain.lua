--- Plain destination provider.
---
--- One application, one destination, opened by bundle id. This is the terminal link in the
--- provider chain and it claims everything, so it must always be registered last, which the
--- plugin's own composition root is what guarantees.
---
--- Everything that is not a browser family with separable profiles ends up here, Safari and
--- Arc among them today. Safari is worth naming as a deliberate absence rather than an
--- oversight. Safari has had profiles since macOS Sonoma, and there is no supported way to ask
--- it to open a url in a particular one, no launch argument and no scripting door, so a Safari
--- profile cannot be offered as a destination however it is discovered. Arc is the same story
--- for a different reason, its spaces are not profiles and it exposes no argument for them
--- either.
---
--- No private window entry is emitted here for the same reason. macOS offers no way to ask
--- Safari or Arc for one from outside, so offering the row would be offering something that
--- cannot work.

local M = { name = "plain" }

--- M:claims(bundleID) -> true
--- Claims everything. The chain is ordered, so this only ever sees what no earlier provider
--- wanted.
function M:claims()
  return true
end

function M:destinations(bundleID, appName)
  local contract = self.contract
  return {
    {
      id = contract.entryId(bundleID, nil, false),
      bundle = bundleID,
      profile = nil,
      private = false,
      label = appName,
    },
  }
end

--- M:open(entry, url) -> boolean
--- The ordinary door, which launches the application if it is not running and hands it the
--- url. No external binary is involved, so the dependency adapter is ignored.
function M:open(entry, url)
  return hs.urlevent.openURLWithBundle(url, entry.bundle) and true or false
end

return M
