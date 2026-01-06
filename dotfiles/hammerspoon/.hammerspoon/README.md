# Hammerspoon Configuration

## Directory Structure

```
.hammerspoon/
├── init.lua                      # Main orchestrator (loads and wires everything)
├── config/                       # Configuration (pure data, edit these)
│   ├── apps.lua                  # App bundle ID registry
│   ├── keys.lua                  # All keybinding definitions
│   ├── settings.lua              # Global settings (margins, timing, etc.)
│   └── workspaces/               # Workspace definitions
│       ├── dev.lua               # Dev workspace
│       └── vicert.lua            # Vicert workspace
└── Spoons/                       # Hammerspoon Spoons (reusable logic)
    ├── AppToggler.spoon/         # Smart app toggle with hide-others
    ├── WindowManager.spoon/      # Window sizing and positioning
    ├── StageManager.spoon/       # macOS Stage Manager integration
    ├── WorkspaceEngine.spoon/    # Generic workspace orchestration
    ├── TerminalHandler.spoon/    # Terminal-specific handling
    └── DockMenuToggle.spoon/     # Dock/menu bar auto-hide toggle
```

## Adding New Apps

Edit `config/apps.lua`:
```lua
NewApp = "com.example.newapp",
```

Edit `config/keys.lua`:
```lua
{ app = "NewApp", modifiers = HYPER, key = "W" },
```

## Adding New Workspaces

Create `config/workspaces/myworkspace.lua`:
```lua
return {
  name = "myworkspace",
  hotkey = { modifiers = { "shift", "alt" }, key = "M" },
  apps = { "App1", "App2", "App3" },
  secondaryDisplayApps = { "App3" },
  primaryDisplayApps = {},
  strategies = {
    primary = {
      App1 = { action = "percentage", width = 90, height = 90 },
      App2 = { action = "fullHeightReasonableWidth" },
      App3 = { action = "resizeDefault" },
    },
    secondary = { ... },
  },
}
```

Add to `init.lua`:
```lua
local myWorkspace = require("config.workspaces.myworkspace")
-- ...
spoon.WorkspaceEngine:registerWorkspace(myWorkspace)
```

## Strategy Actions

- `percentage` - Resize to percentage of screen (requires `width`, `height`)
- `fullHeightReasonableWidth` - Full height, capped width
- `resizeDefault` - Default size (1800x1200)
- `none` - Just launch, don't resize

## Useful Commands

Open Hammerspoon Console:
```bash
open -a Hammerspoon
```

Get app bundle identifier:
```bash
osascript -e 'id of app "APP_NAME"'
```
