-- Processes, what it declares about itself.
--
-- Three sources share the same handful of macOS binaries, each declaring the tools
-- beside the file that actually runs them rather than once for the whole plugin, so
-- the same name appears more than once below with a different reason each time.
-- None of the sources ever go missing on a real machine, every tool here ships with
-- macOS itself, so optional documents the contract rather than guarding against a
-- practical absence, matching the reasoning the ports entries below already give.
return {
  needs = {
    tools = {
      { name = "ps", kind = "system", locator = "/bin/ps", policy = "optional", unit = "metrics",
        reason = "samples cpu and memory for the rows the picker is showing",
        origin = { macos = "ships with the system" } },
      { name = "lsof", kind = "system", locator = "/usr/sbin/lsof", policy = "optional", unit = "ports",
        reason = "finds which process holds a listening port",
        origin = { macos = "ships with the system" } },
      { name = "ps", kind = "system", locator = "/bin/ps", policy = "optional", unit = "ports",
        reason = "reads the command, start time, and working directory of a holder",
        origin = { macos = "ships with the system" } },
      { name = "kill", kind = "system", locator = "/bin/kill", policy = "optional", unit = "ports",
        reason = "stops a holder, gracefully first and forcefully on request",
        origin = { macos = "ships with the system" } },
      { name = "ps", kind = "system", locator = "/bin/ps", policy = "optional", unit = "runtimes",
        reason = "finds candidate runtime processes and reads their working directory",
        origin = { macos = "ships with the system" } },
      { name = "lsof", kind = "system", locator = "/usr/sbin/lsof", policy = "optional", unit = "runtimes",
        reason = "checks whether a candidate holds a socket, the evidence that separates a dev server from a stray process",
        origin = { macos = "ships with the system" } },
      { name = "kill", kind = "system", locator = "/bin/kill", policy = "optional", unit = "runtimes",
        reason = "stops a runtime process, gracefully first and forcefully on request",
        origin = { macos = "ships with the system" } },
      { name = "docker", kind = "path", policy = "optional", unit = "docker",
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
      --
      -- Most of it ships now, because most of it is not personal at all. node is node on every
      -- machine and so is every other runtime name, a directory called dist tells you nothing
      -- about a project anywhere, and a system daemon is never a dev server on anyone's Mac. What
      -- genuinely cannot ship is where a person keeps their own work, since nobody else knows
      -- what that folder is called.
      --
      -- Three slices are deliberately absent, and for the opposite reason to devRoots. The
      -- sampling weights, the stop timings and the scan timeout are already defaulted inside the
      -- plugin, metrics.lua against its own DEFAULTS table and both sources against their own
      -- initial values, so shipping them here would put one number in two files and let the two
      -- drift. One fact, one home.
      policy = { source = "user", policy = "optional",
                 default = {
                   -- What counts as a dev runtime. Binary names, so they travel exactly.
                   runtimes = {
                     "node", "deno", "bun",
                     "python", "python2", "python3", "pypy",
                     "ruby", "puma", "unicorn",
                     "java", "kotlin", "scala",
                     "php", "php-fpm",
                     "perl", "beam.smp", "erl",
                     "dotnet", "mono",
                     "caddy", "hugo", "esbuild", "vite", "webpack",
                     "gunicorn", "uvicorn", "daphne", "hypercorn", "flask", "rails",
                     "air", "gin", "reflex",
                   },
                   -- Never a dev server. An entry costs nothing on a machine that does not run
                   -- the thing it names, and hides nothing anybody wants, since none of these
                   -- IS a dev server anywhere. That is why third party names sit here quite
                   -- happily while a project folder name could never sit above.
                   ignoreCommands = {
                     "com.docker.backend",
                     "com.docke",
                     "rapportd",
                     "ControlCenter",
                     "ControlCe",
                     "Google Drive",
                     "Raycast",
                     "Code Helper",
                     "Code\\x20H",
                     "identityservicesd",
                     "sharingd",
                     "AirPlayXPCHelper",
                   },
                   -- Too vague to name a project, so a server found in one is labelled by
                   -- something further up instead. Generic by definition, hence shippable.
                   genericDirs = {
                     "static", "src", "dist", "build", "public", "app", "apps",
                     "server", "backend", "frontend", "api", "web", "client", "www",
                     "packages", "site", "docs",
                   },
                 },
                 breaks = "the directories this person keeps their own work in are unknown, so a "
                   .. "runtime found outside a recognised tree is labelled by whatever directory "
                   .. "it happens to sit in rather than by the project it belongs to" },
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
