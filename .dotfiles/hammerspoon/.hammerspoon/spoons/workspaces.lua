local Workspaces = {}

-- Import all the workspace modules
Workspaces.Dev = require("spoons.workspaces.dev")
-- Add more workspaces as needed
-- Workspaces.AnotherWorkspace = require("workspaces.another_workspace")

function Workspaces.initialize()
  -- Initialize each workspace's keybindings
  Workspaces.Dev.initialize()
  -- Add more initializations as needed
  -- Workspaces.AnotherWorkspace.initialize()
end

return Workspaces
