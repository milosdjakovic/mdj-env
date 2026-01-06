AppToggler = require("spoons.appToggler")
keyBindings = require("spoons.keyBindings")
WindowManagementBindings = require('spoons.windowManagementBindings')
StageManager = require('spoons.stageManager')
Workspaces = require("spoons.workspaces")
TerminalHandler = require('spoons.terminalHandler')

AppToggler.initialize({
    toggles = keyBindings.appToggles,
})
WindowManagementBindings.initialize()
StageManager.initialize({
    keyBinding = keyBindings.stageManager,
})
Workspaces.initialize()
TerminalHandler.initialize()

-- hs.loadSpoon("Hammerflow")
-- spoon.Hammerflow.loadFirstValidTomlFile({
--     "home.toml",
--     "work.toml",
--     "Spoons/Hammerflow.spoon/sample.toml"
-- })
-- -- optionally respect auto_reload setting in the toml config.
-- if spoon.Hammerflow.auto_reload then
--     hs.loadSpoon("ReloadConfiguration")
--     -- set any paths for auto reload
--     -- spoon.ReloadConfiguration.watch_paths = {hs.configDir, "~/path/to/my/configs/"}
--     spoon.ReloadConfiguration:start()
-- end

-- Reload Hammerspoon configuration automatically
hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", hs.reload):start()
-- hs.alert.show("Hammerspoon config loaded")
require("hs.ipc")
