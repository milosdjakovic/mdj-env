-- Display profiles
--
-- The profiles themselves are this machine's, not this file's. An arrangement of monitors belongs
-- to one desk and the built in panel has a different id on every Mac, so each machine keeps its own
-- list in machines/<LocalHostName>/hammerspoon-displays.lua at the repository root, and a machine
-- with none takes machines/default/hammerspoon-displays.lua, which is empty. setup copies the one
-- that applies beside this config and config/machine.lua reads it. The default file's header has
-- the shape, how to capture a profile, and how matching works.
--
-- DisplayProfiles takes the list as it is, since it is already this machine's slice, and applies
-- whichever profile fits the displays attached. Only what every machine shares stays here.

return {
  -- Seconds to wait for displays to settle after a change before applying. A
  -- dock waking several monitors fires many events in a burst, so we coalesce
  -- them and act once things are stable.
  settleDelay = 1.5,

  profiles = require("config.machine").profiles,
}
