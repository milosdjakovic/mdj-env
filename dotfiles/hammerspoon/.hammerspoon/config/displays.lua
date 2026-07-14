-- Display profiles
--
-- Pure data. One saved displayplacer arrangement per situation, grouped by
-- machine. The composition root in init.lua resolves this machine's name and
-- hands the matching list to DisplayProfiles, which watches for screen changes
-- and applies whichever profile fits the displays currently attached. Nothing
-- here knows about the watcher or the matching, it is just the policy.
--
-- Keyed by LocalHostName, which you read with `scutil --get LocalHostName`. Each
-- machine gets its own list because the built in laptop panel has a different id
-- on every Mac, so a profile that names it can only ever be this machine's.
--
-- Capturing a profile. Arrange your displays the way you want in System Settings,
-- run `displayplacer list` in a terminal, and copy the full `displayplacer ...`
-- line it prints at the bottom. Paste it as `command` below and give it a `name`.
-- That is the whole capture step.
--
-- Portable ids. The printed command uses per machine persistent ids. External
-- monitors also expose a serial id, printed as `Serial screen id: sXXXX`, which
-- stays the same monitor to monitor even on another Mac. The two profiles below
-- were rewritten to use serial ids, so the same physical monitors following you
-- to another machine keep working once that machine has its own entry. Using
-- persistent ids straight from the printed line works too, it is simply not
-- portable.
--
-- Matching. A profile is chosen when the number of screens it lists equals the
-- number attached and every id it names is one of the attached ids. So the three
-- screen desk profile and the one screen laptop profile never collide, the count
-- alone separates them. The first matching profile in the list wins. Two setups
-- with the same screen count still never collide, because their externals carry
-- different serial ids, which is what lets one place hold several setups.
--
-- Naming. Names are labels only, the ids do the matching, so a name never has to
-- be unique or encode anything. The scheme here is a plain descriptive phrase
-- that leads with the place and names the monitors, like "vicert office, built in
-- and two Dell P2318HC", so the log line that prints on apply reads for itself.
-- The built in panel alone is location neutral, so it is just laptop only.
--
-- Tweaking. Edit any value in a command, resolution, refresh, scaling, origin, or
-- degree, and save. Hammerspoon reloads on save and reapplies the matching
-- profile, so the change takes effect at once.

return {
  -- Seconds to wait for displays to settle after a change before applying. A
  -- dock waking several monitors fires many events in a burst, so we coalesce
  -- them and act once things are stable.
  settleDelay = 1.5,

  profiles = {
    ["Miloss-MacBook-Pro-Vicert"] = {
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
  },
}
