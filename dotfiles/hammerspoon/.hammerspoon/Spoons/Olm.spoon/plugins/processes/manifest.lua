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

      -- Three root computed words, the trickle migration onto the shared stage. stagePresent
      -- is what a fresh present asks for, both from the confirmation's own reopen and from
      -- registry.open's kept fallback. redrawPresented is the async seam a completed scan and
      -- a live sample both ask to be redrawn through, once this presentation, and no other, is
      -- what the stage is actually showing. stageHide is this plugin's own addition to the
      -- published set, for the one action that wants the shared window gone at once rather
      -- than waiting on a dismissal, a forced stop giving instant feedback rather than leaving
      -- a stale row on screen. All three degrade to an inert press or a silently skipped
      -- redraw when absent, never a crash, so all three are optional.
      stagePresent = { source = "root", policy = "optional",
        breaks = "a fresh open, and the confirmation screen's own reopen after a stop needing " ..
                 "confirmation, both reach nothing, since neither has any other way to ask the " ..
                 "shared stage to show this presentation" },
      redrawPresented = { source = "root", policy = "optional",
        breaks = "a scan that lands after the keystroke that asked for it, and the live sampler's " ..
                 "own tick, both stop reaching the screen, so the list and the pane freeze at " ..
                 "whatever they last showed until the picker is closed and reopened" },
      stageHide = { source = "root", policy = "optional",
        breaks = "a forced stop no longer closes the window at once, leaving a stale row on " ..
                 "screen until the next sample or rescan catches up with what actually happened" },
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
    -- matcher over fuzzy. Migrated onto the shared stage, contract v2, this word now
    -- travels through presentation.matcher below instead, host/stage/init.lua writing
    -- it onto the live instance before every show and swap, but it stays declared here
    -- too, unread by the stage, since surface is where a person reading this file
    -- expects to find what a query means for this tool.
    matcher = "words",
    -- The detail pane beside the list is the live sampler's home, the port, the
    -- project, and the process tree that makes pressing stop safe, so it earns the
    -- reserved room.
    pane = true,
  },

  -- The presentation contract, contract v2, docs/BRIEF-CONTRACT-V2.md. rows and select are
  -- this plugin's own chooser.rows and chooser.select, plain closures assigned inside the
  -- chooser submodule exactly the way its show, refresh, and every other public member
  -- already are, so every field below says call = dot, stated outright, never the bare
  -- string shorthand this contract allows everywhere else a member is not a presentation's
  -- own. placeholder resolves once, at register, to whatever chooser.placeholder currently
  -- answers, which by then already reflects whatever this plugin's own configure passed.
  --
  -- enter is contract v2's own second addition and the reason this plugin needed it at all.
  -- M.show used to scan before ever building the picker, "the picker is shown only once the
  -- rows are in hand", and present used to call onPresent then show synchronously with
  -- nothing able to delay the second half, so a presentation with no enter would have shown
  -- an empty "Nothing running" row on every fresh open, the exact flash this plugin's own
  -- design record already rejected. chooser.enter receives proceed and calls it once the scan
  -- lands, or at once when a confirmation is already built and needs no scan at all.
  --
  -- onHighlight, onPositioned, and onClose carry the detail pane, its dock, and its teardown,
  -- the identical shape filesearch and clipboard's own onPositioned already keep, minus the
  -- anchor arithmetic and the cfg.onPositioned call the stage now owns for every presenting
  -- plugin, host/stage's own paneAnchor replacing the local copy this file used to carry.
  --
  -- No back and no intercept. This tool has one level, a flat list with an occasional two row
  -- confirmation that is a fresh present of its own rather than an inner level Backspace steps
  -- out of, so it declares neither hook.
  presentation = {
    rows = { member = "chooser.rows", call = "dot" },
    select = { member = "chooser.select", call = "dot" },
    placeholder = { member = "chooser.placeholder", call = "dot" },
    enter = { member = "chooser.enter", call = "dot" },
    onHighlight = { member = "chooser.onHighlight", call = "dot" },
    onPositioned = { member = "chooser.onPositioned", call = "dot" },
    onClose = { member = "chooser.onClose", call = "dot" },
    -- true inherits the chooser's own width, the atom's own companionWidth semantics carried
    -- one layer up, matching what this plugin's own retired layout block asked for whenever
    -- the detail pane was enabled, preview.isEnabled() and (cfg.previewWidth or true) or 0,
    -- cfg.previewWidth never set by anything today.
    paneWidth = true,
    matcher = "words",
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
  -- never a colon method, so open says so. show still stays, and still matters even though
  -- this tool proposes no key of its own, contract v2's own precedent, VPN's manifest, since
  -- a launcher row choosing this tool now pushes the registry's own presentation straight
  -- from root/compose.lua's rowIntercept and never calls open at all, leaving this as the
  -- fallback an unmigrated path would still reach if presentationFor ever answered nil for a
  -- name it used to answer for.
  --
  -- surface = "chooser" stays declared, a narrower exception to PLUGIN-CONTRACT.md's own "a
  -- presenting plugin declares no registry.surface" rule that this plugin is the first to
  -- need. isShowing, selectNext, selectPrev, insertSelected, and hide are gone from the
  -- chooser submodule, deleted along with the Chooser.new block that gave them something to
  -- answer for, and host/stage's own surfaceFor(identity) answers all five now. But refresh,
  -- sortByLoad, and stopForced, the three extra verbs surface.extra above binds keys to, live
  -- on nowhere else, and root/compose.lua's own surfaceAdapterFor falls through to whatever
  -- this field names once the stage's own five have been asked and answered nothing, exactly
  -- the same walk it already used before this plugin presented at all. Leaving this field out
  -- would not merely be dead weight, it would silently drop three bound keys with nothing in
  -- the console naming why.
  registry = {
    row = { category = "System", detail = "stops a dev server, container, or watcher",
      glyph = "🔌", keywords = "processes port node docker" },
    open = { member = "chooser.show", call = "dot" },
    surface = "chooser",
  },
}
