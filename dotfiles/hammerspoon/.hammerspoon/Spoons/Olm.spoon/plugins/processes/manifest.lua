-- Processes, what it declares about itself.
--
-- Three sources share the same handful of macOS binaries, each declaring the tools
-- beside the file that actually runs them rather than once for the whole plugin, so
-- the same name appears more than once below with a different reason each time.
-- None of the sources ever go missing on a real machine, every tool here ships with
-- macOS itself, so optional documents the contract rather than guarding against a
-- practical absence, matching the reasoning ports.dependencies itself gives.
return {
  needs = {
    tools = {
      { name = "ps", kind = "system", locator = "/bin/ps", policy = "optional",
        reason = "samples cpu and memory for the rows the picker is showing",
        origin = { macos = "ships with the system" } },
      { name = "lsof", kind = "system", locator = "/usr/sbin/lsof", policy = "optional",
        reason = "finds which process holds a listening port",
        origin = { macos = "ships with the system" } },
      { name = "ps", kind = "system", locator = "/bin/ps", policy = "optional",
        reason = "reads the command, start time, and working directory of a holder",
        origin = { macos = "ships with the system" } },
      { name = "kill", kind = "system", locator = "/bin/kill", policy = "optional",
        reason = "stops a holder, gracefully first and forcefully on request",
        origin = { macos = "ships with the system" } },
      { name = "ps", kind = "system", locator = "/bin/ps", policy = "optional",
        reason = "finds candidate runtime processes and reads their working directory",
        origin = { macos = "ships with the system" } },
      { name = "lsof", kind = "system", locator = "/usr/sbin/lsof", policy = "optional",
        reason = "checks whether a candidate holds a socket, the evidence that separates a dev server from a stray process",
        origin = { macos = "ships with the system" } },
      { name = "kill", kind = "system", locator = "/bin/kill", policy = "optional",
        reason = "stops a runtime process, gracefully first and forcefully on request",
        origin = { macos = "ships with the system" } },
      { name = "docker", kind = "path", policy = "optional",
        reason = "lists running containers and stops one by name",
        origin = { cask = "docker-desktop" } },
    },

    data = {
      -- Everything in config/processes.lua, the runtime allowlist, the commands to ignore, the
      -- directory names that mark a dev tree and the ones too vague to name a project, the grace
      -- period before a stop turns forceful, and the sampling weights.
      --
      -- It was declared NOWHERE, which is why nothing supplied it and nothing said so. A need
      -- that is not declared cannot be reported missing, cannot be reported degraded, and cannot
      -- be reported at all, so this was the one gap in the whole set that no amount of reading
      -- the plan could have found. Declaring it is most of the fix.
      --
      -- Optional, since every consumer treats an absent slice as nothing configured, so the tool
      -- still opens and still lists. What it loses is the ability to recognise anything.
      policy = { source = "user", policy = "optional",
                 breaks = "no process name counts as a dev runtime and no directory counts as a "
                   .. "dev tree, so the list falls back to port holders alone and a running "
                   .. "server with no listening socket is never found" },
    },
  },

  -- No provides. This tool has no alias in config/keys.lua, so it is reached only by
  -- opening the picker itself, never by a typed scope.

  -- Opened from the launcher only, so it proposes no key at all. Named Local Servers
  -- on its launcher row rather than Processes, since the list is port holders,
  -- containers, and portless watchers and never the whole process table, but the
  -- plugin keeps its own internal name here.
  defaults = {
    description = "Local Servers",
    launcherRow = true,
  },

  -- A flat list with three actions of its own beyond the shared navigation, a force
  -- stop with no grace period, a rescan in place, and a sort by live load.
  surface = {
    context = "processes",
    primary = { action = "insertSelected", description = "Stop" },
    extra = {
      { key = "s", action = "sortByLoad",  description = "Sort by load", glyph = "🔥" },
      { key = "f", action = "stopForced",  description = "Force stop",  glyph = "⛔" },
      { key = "r", action = "refreshList", description = "Rescan",      glyph = "🔄" },
    },
    -- A query here is a real remembered fragment, a port number or a project name,
    -- rather than an abbreviation of a short label, so this plugin wants the words
    -- matcher over fuzzy. Unlike file search and the clipboard, this one reaches
    -- its own Chooser instance directly, so the value injected here is exactly the
    -- one the atom ranks with.
    matcher = "words",
    -- The detail pane beside the list is the live sampler's home, the port, the
    -- project, and the process tree that makes pressing stop safe, so it earns the
    -- reserved room.
    pane = true,
  },

  -- This plugin's own configure already wires the api and the metrics slice onto
  -- the chooser submodule, so calling configure(opts) on the plugin root is not the
  -- whole story but needs no extra step here. What configure alone never reaches is
  -- the view wave, the factory, the theme, the placeholder and the panel triple,
  -- which land on the chooser submodule as a second call, plus the submodule's own
  -- start before a picker exists to show at all.
  wiring = {
    { target = "chooser", method = "configure" },
    { target = "chooser", method = "start" },
  },

  -- show lives on the chooser submodule as a plain dot called function, function M.show(),
  -- never a colon method, so open says so, and the chooser is the surface too.
  registry = {
    row = { category = "System", detail = "stops a dev server, container, or watcher",
      glyph = "🔌", keywords = "processes port node docker" },
    open = { member = "chooser.show", call = "dot" },
    surface = "chooser",
  },
}
