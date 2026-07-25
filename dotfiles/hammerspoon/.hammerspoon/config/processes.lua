-- Development process discovery policy.
--
-- Pure data, read by Processes.spoon through the composition root in init.lua. The
-- spoon holds only the mechanism and never names a runtime, a daemon, or a
-- directory, so changing what counts as a development process is an edit here and
-- nothing else.

return {
  -- The runtimes a listening socket must belong to before it is treated as a
  -- development server. Matched against the kernel process name rather than argv,
  -- because a node server routinely rewrites its own argv, so the next dev server
  -- reports itself as "next-server" while the kernel still knows it as "node".
  --
  -- This is an allowlist rather than a denylist on purpose. The set of system
  -- daemons that happen to hold a socket is unbounded and grows with every macOS
  -- release, while the set of runtimes you actually develop in is small and
  -- changes rarely, so an allowlist stays quiet by default and a denylist would
  -- need endless maintenance to stay quiet at all.
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

  -- Listener commands that are never a development server, even when they match a
  -- runtime above or sit under a dev root. com.docker.backend is here because the
  -- docker source claims those ports and republishes them as named containers, so
  -- the raw proxy must never surface on its own, not even when the daemon is
  -- unreachable and the claim never arrives.
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

  -- Directories under home whose subtree counts as development work. A listener
  -- whose working directory falls inside one of these is treated as a development
  -- server even when its runtime is not listed above, which catches an unfamiliar
  -- toolchain running inside a project you own. Stored relative to home so this
  -- config carries no absolute path and moves between machines unchanged.
  devRoots = {
    "Development",
    "Projects",
    "src",
  },

  -- Working directory names too generic to identify a project on their own. When a
  -- server's directory ends in one of these the label walks up one level and joins
  -- both, so a webpack server in canvas/home-app/static reads as "home-app / static"
  -- rather than the useless "static".
  genericDirs = {
    "static", "src", "dist", "build", "public", "app", "apps",
    "server", "backend", "frontend", "api", "web", "client", "www",
    "packages", "site", "docs",
  },

  -- Stopping policy. graceSeconds is how long a process group is given to exit on
  -- its own after the first signal before the stop escalates to an unconditional
  -- kill. confirmAbove is the group size past which a stop asks first, so taking
  -- down a five process next dev tree is one keypress while something unexpectedly
  -- large is not.
  stop = {
    graceSeconds = 3,
    confirmAbove = 8,
  },

  -- How long any single scan shellout may run before it is abandoned. The docker
  -- CLI is the reason this exists, it answers in well under a tenth of a second
  -- with the daemon up but hangs indefinitely while the daemon is starting, and a
  -- scan that never returns would leave the picker empty with no explanation.
  scanTimeoutSeconds = 5,

  -- Live sampling, which happens only while the picker is on screen and stops with
  -- it. So intervalSeconds is a redraw cadence rather than a background poll, and
  -- none of this costs anything with the picker closed.
  --
  -- The two weights decide the single number the load ordering sorts on. They can
  -- only mean anything because each side is normalised to its own unit first, one
  -- fully saturated core counts as 1.0 and memReferenceMb of resident memory counts
  -- as 1.0. Without that step the weights would be comparing a percentage against a
  -- byte count and memory would win every time. Putting cpuWeight above memWeight
  -- means a small busy process outranks a large idle one, which is the one you
  -- opened the picker to find.
  metrics = {
    intervalSeconds = 1.5,
    historySamples = 60,
    cpuWeight = 0.7,
    memWeight = 0.3,
    memReferenceMb = 1024,
  },
}
