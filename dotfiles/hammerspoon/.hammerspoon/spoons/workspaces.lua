local Workspaces = {}

-- Import all the workspace modules
Workspaces.Dev = require("spoons.workspaces.dev")
Workspaces.Vicert = require("spoons.workspaces.vicert")

function Workspaces.initialize()
  -- Initialize each workspace's keybindings
  Workspaces.Dev.initialize()
  Workspaces.Vicert.initialize()
end

return Workspaces
