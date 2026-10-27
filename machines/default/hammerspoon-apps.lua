-- The Hyper app keys a machine takes when it has no machines/<name>/hammerspoon-apps.lua.
--
-- Only apps every machine has, the ones macOS ships and the ones the Brewfile installs, so a key
-- here never points at an app a machine lacks. A machine that wants more gets a file of its own,
-- which replaces this one whole rather than adding to it, so it repeats these lines and adds its
-- own. src/setup-hammerspoon-apps.sh --capture writes that file from whatever this machine has
-- now, and src/setup-hammerspoon-apps.sh copies the right one to ~/.hammerspoon/machine-apps.lua,
-- where config/machine.lua reads it.
--
-- keys maps a chord to an action, as in config/keymap.lua, an app being apptoggler.<Name> for a
-- name in config/apps.lua. apps lays a bundle id over that catalog for an app whose id differs
-- per install, which is every Chrome web app.

return {
  keys = {
    -- Shipped with macOS
    ["hyper+B"] = "apptoggler.Books",
    ["hyper+F"] = "apptoggler.Finder",
    ["hyper+M"] = "apptoggler.Mail",
    ["hyper+S"] = "apptoggler.Safari",
    ["hyper+N"] = "apptoggler.Notes",
    ["hyper+I"] = "apptoggler.iPhoneMirroring",
    ["hyper+R"] = "apptoggler.Preview",
    ["hyper+T"] = "apptoggler.Stickies",
    ["hyper+\\"] = "apptoggler.ActivityMonitor",
    -- System Settings, opened straight to the General pane, a hide when it is already in front.
    ["hyper+,"] = "systemsettings.General",

    -- Installed by the Brewfile. Docker only where the docker piece is on, and the Hyper sheet
    -- leaves an app off where it is not installed.
    -- The terminal, popping in and out through its popup style in config/toggles.lua.
    ["hyper+`"] = "apptoggler.Ghostty",
    ["hyper+O"] = "apptoggler.Obsidian",
    ["hyper+D"] = "apptoggler.Docker",
  },

  apps = {},
}
