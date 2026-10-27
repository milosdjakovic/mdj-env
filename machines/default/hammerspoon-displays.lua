-- The display profiles a machine takes when it has no machines/<name>/hammerspoon-displays.lua,
-- which is none, since an arrangement of monitors belongs to one desk and one machine.
--
-- src/setup-hammerspoon-apps.sh copies the file that applies to ~/.hammerspoon/machine-displays.lua,
-- where config/machine.lua reads it and config/displays.lua hands it to DisplayProfiles, which
-- applies whichever profile fits the displays attached. `--capture` gives a machine its own file.
--
-- profiles is a list of { name, command }, the first match winning. A profile matches when it
-- names as many screens as are attached and every id it names is attached. Arrange the displays
-- in System Settings, run `displayplacer list`, and paste the full `displayplacer ...` line it
-- prints last as command. An external monitor's serial id, `Serial screen id: sXXXX`, is the same
-- on every Mac, so prefer it over the persistent id for an external. The built in panel's id
-- differs per Mac, which is why profiles are per machine. The name is only a label, leading with
-- the place and naming the monitors reads best in the log line printed on apply.

return {
  profiles = {},
}
