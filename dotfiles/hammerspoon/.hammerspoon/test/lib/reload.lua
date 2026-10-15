-- Schedules a reload on a fresh run loop tick and answers at once, since a reload called
-- inside the ipc request tears down the port answering it. The handle is kept in a global so
-- the timer cannot be collected before it fires.
_G.__unitsReloadTimer = hs.timer.doAfter(0.2, hs.reload)
return "scheduled"
