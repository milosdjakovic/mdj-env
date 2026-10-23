-- How apps toggle, read by the app toggler through its entry in config/plugins.lua.
--
-- A style is a behaviour described once, and every app that names it follows when it changes.
-- `hides` turns focus or cycle into show and hide, a second press on an app already in front
-- hiding it. `placement` centers and sizes the window once a press showed, launched or focused it,
-- on the display it is already on. The app toggler's README has every field.
--
-- An app listed in `apps` takes its style on its own action, apptoggler.<name> with the name from
-- config/apps.lua, so a key in config/keymap.lua names the app and never the style. An entry may
-- override a field of its style, a placement naming only a width keeps the style's height and
-- padding, and may add a `description`, the label Olm shows for the app's action. An app not
-- listed keeps the plain focus or cycle.

return {
  styles = {
    -- Pops in centered at a fixed size and hides again on a second press, the terminal summon
    -- the retired TerminalHandler spoon used to be.
    popup = { hides = true,
      placement = { width = 2400, height = 1350, padding = { x = 40, y = 20 } } },
  },

  apps = {
    { app = "Ghostty", style = "popup" },
  },
}
