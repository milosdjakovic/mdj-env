-- This machine's display profiles, moved unchanged out of config/displays.lua on 2026-10-27,
-- where they sat under this machine's name. The shape and how to capture a profile are in
-- machines/default/hammerspoon-displays.lua.

return {
  profiles = {
  -- vicert-1. Vicert office, built in panel plus a matched pair of Dell
  -- P2318HC externals. Built in is the main display at the bottom center,
  -- with the two Dells up and to each side, the left one (serial s826946124)
  -- at origin (-1146,-1080) and the right one (serial s826888524) at
  -- (774,-1080). Home uses different monitors, so its serial ids differ and
  -- it will not match this even if it also has three screens.
  {
    name = "vicert office, built in and two Dell P2318HC",
    command = 'displayplacer '
      .. '"id:s4251086178 res:1512x982 hz:120 color_depth:8 enabled:true scaling:on origin:(0,0) degree:0" '
      .. '"id:s826946124 res:1920x1080 hz:60 color_depth:8 enabled:true scaling:off origin:(-1146,-1080) degree:0" '
      .. '"id:s826888524 res:1920x1080 hz:60 color_depth:8 enabled:true scaling:off origin:(774,-1080) degree:0"',
  },

  -- Vicert office with one external. Default guess only, built in as main at
  -- (0,0) with one Dell centered just above it. It names Dell s826946124, so
  -- it matches only that single monitor; if you dock the other Dell instead,
  -- capture that as its own entry. When you next run a one external setup on
  -- site, confirm it with `spoon.DisplayProfiles:capture(true)` and paste the
  -- real arrangement over this.
  {
    name = "vicert office, built in and one Dell P2318HC",
    command = 'displayplacer '
      .. '"id:s4251086178 res:1512x982 hz:120 color_depth:8 enabled:true scaling:on origin:(0,0) degree:0" '
      .. '"id:s826946124 res:1920x1080 hz:60 color_depth:8 enabled:true scaling:off origin:(-204,-1080) degree:0"',
  },

  -- home-office. Built in panel plus one 34 inch ultrawide external (serial
  -- s810891350) at 3440x1440 75hz, sitting up and to the left of the built in
  -- at origin (-991,-1440), with the built in as main at (0,0). Written with
  -- the external's serial id so the same monitor matches on another Mac once
  -- that machine has its own entry. Two screens, but no collision with the
  -- one external vicert profile, that names a different Dell serial.
  {
    name = "home-office",
    command = 'displayplacer '
      .. '"id:s4251086178 res:1512x982 hz:120 color_depth:8 enabled:true scaling:on origin:(0,0) degree:0" '
      .. '"id:s810891350 res:3440x1440 hz:75 color_depth:8 enabled:true scaling:off origin:(-991,-1440) degree:0"',
  },

  -- laptop. The built in panel by itself. Location neutral, it matches
  -- whenever no externals are attached, since it names only this machine's
  -- panel and one screen.
  {
    name = "laptop only, built in panel",
    command = 'displayplacer '
      .. '"id:s4251086178 res:1512x982 hz:120 color_depth:8 enabled:true scaling:on origin:(0,0) degree:0"',
  },
  },
}
