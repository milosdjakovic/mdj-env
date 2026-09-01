--- === Olm ===
---
--- The reusable core, phase one of the build plan, with the tool registry from phase
--- seven added beside the libs that arrived before it. Init here stays deliberately
--- bare, a name, a version, an api version a plugin declares itself against, and the
--- loaded modules under Olm.lib. The registry is state and the composition root builds
--- its own instance from the factory this spoon loads, so nothing here names a tool or
--- holds an activation list of its own.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Olm"
obj.version = "0.1"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- The api version a plugin will one day declare itself against, a single
-- integer starting at one, bumped only on a breaking change to what this
-- spoon exposes, settled in phase zero of the build plan.
obj.apiVersion = 1

-- Loaded relative to this file's own location rather than from a hardcoded
-- path, the same pattern ClipboardHistory.spoon already uses for every file
-- it loads, since a spoon directory is never on package.path.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("Olm failed to load " .. name .. ", " .. tostring(err))
  end
  return chunk()
end

--- Olm.lib
--- The shared mechanisms every later plugin reaches through this table.
--- Storage is the path builder that turns the two roots in
--- config/settings.lua into a finished directory for a tool, see
--- lib/storage.lua for its api. Recency is the lift to front ordering
--- service, a factory handing out an independent instance per caller, see
--- lib/recency.lua for its api. Paste is the insertion engine, one shared
--- instance rather than a factory since the machine has one pasteboard, see
--- lib/paste.lua for its api and for the boundary it draws.
---
--- The six below arrived in phase five, copies of the six atom spoons the design
--- names as core, each a faithful copy of the spoon it came from so the composition
--- root can hand it straight to that spoon's global and leave every existing call
--- site alone. Chooser is the picker facade, a directory rather than a file because
--- it loads a matcher and a backend of its own. Panel is the shared canvas surface,
--- cheatsheet the overlay renderer that draws through it, chordkey the hold and tap
--- engine under every leader, hyperkey the leader modal every context binds into,
--- and deps the declaration reader. Each is loaded here and named nowhere else in
--- this file, so the root decides what becomes of it.
---
--- Registry arrived in phase seven, another factory like recency, handing the root an
--- independent instance to register every tool against. See lib/registry.lua for its
--- api.
---
--- Glyphicon arrived in phase eight's third packet, lifted out of Launcher's own private
--- drawing once ActionPanel became a second caller of it, another factory in the same
--- style as recency and registry. See lib/glyphicon.lua for its api.
---
--- These are THE instances, not a second set alongside the running ones. The composition
--- root reads this table and configures what it finds here rather than loading its own,
--- because loadfile answers a fresh module on every call, so the two files each loading
--- lib/chordkey.lua gave the config two unrelated engines. Only the root's copy was ever
--- configured, and the copy published here sat with no tap and no keys, which reads
--- exactly like a leader that failed to wire and was diagnosed as one. Nothing in either
--- file could have said which copy anybody was holding, so the answer is that there is
--- only ever one.
obj.lib = {
  storage = load("lib/storage.lua"),
  recency = load("lib/recency.lua"),
  paste = load("lib/paste.lua"),
  chooser = load("lib/chooser/init.lua"),
  panel = load("lib/panel.lua"),
  cheatsheet = load("lib/cheatsheet.lua"),
  chordkey = load("lib/chordkey.lua"),
  hyperkey = load("lib/hyperkey.lua"),
  deps = load("lib/deps.lua"),
  -- The tool registry, phase seven of the build plan. A factory in the same style as
  -- recency, so the root builds its own instance with M.new rather than reaching for a
  -- shared one, and every function it hands back is dot called, since it holds no
  -- metatable and no self. See lib/registry.lua for the descriptor shape, the four
  -- refusals, and what active and inactive mean today.
  registry = load("lib/registry.lua"),
  -- The glyph to icon drawer, phase eight's third packet. A factory in the same style as
  -- recency and registry, one instance per caller, each owning its own drawing cache. See
  -- lib/glyphicon.lua for the one function it answers and for the numbers it draws with.
  glyphicon = load("lib/glyphicon.lua"),
}

--- Olm:start(cfg)
--- The one door into the composition root. Loaded the same way every atom in Olm.lib
--- already is, relative to this file rather than by name, so this spoon still assumes
--- nothing about where it sits on disk. Runs the root exactly once, because the root
--- takes the shared chooser atom and the leader engines through their own init and
--- configure, and neither is written to survive going through that twice.
---
--- Answers self. A separate handle table was tried first, three plain function values
--- closing over self so a caller could still write olm:report(), olm:module(name) and
--- olm:screen(). That shape carries its own trap. A plain function value called with a
--- colon receives the table it was found on as its own first argument, which is exactly
--- right for module and screen, both already written to take self first, and exactly
--- wrong for report, which takes nothing, so handle:report() would have silently hand
--- the handle itself in as an unused argument, harmless only because report happens to
--- ignore every argument it receives. Getting a fourth method onto that handle right
--- would mean remembering the same trick a fourth time. self has none of that problem.
--- Every method below is a real colon method already, module and screen included, so
--- returning self makes olm:report(), olm:module(name) and olm:screen() correct because
--- they are ordinary method calls, not because three closures were each written
--- carefully enough to fake one. The narrower handle would have hidden Olm.lib,
--- apiVersion and the rest from a caller, which reads as tidier until you notice Lua
--- grants no real enforcement of that hiding anyway, spoon.Olm.lib.paste is one field
--- access away from any caller holding spoon.Olm at all, so the handle was only ever
--- documentation of an intended contract, never a boundary, and self documents the exact
--- same intended contract, report, module and screen, without a bug the documentation
--- introduced trying to look narrower than Lua lets it be.
function obj:start(cfg)
  if self._started then
    error("Olm:start already ran once, and it must run exactly once")
  end
  self._started = true

  local compose = load("root/compose.lua")

  -- Stored on the spoon rather than kept only in this closure, because obj:report,
  -- obj:module and obj:screen are reached long after start returns, on the caller's own
  -- schedule rather than this one. TerminalHandler used to be that caller, kept outside
  -- Olm's own management by the user's own decision on 2026-08-07, and reaching obj:module
  -- for a plugin it did not manage. It is gone now, absorbed into AppToggler, see
  -- obj:module's own note.
  --
  -- report, modules and screen, read off this below by the three methods beneath it, are
  -- the seam between this file and root/compose.lua, since compose.lua is the one file
  -- allowed to name every atom and this file must not. report is wire.lua's own report
  -- function passed through untouched, modules is loader.lua's table of loaded modules
  -- keyed by plugin identity, and screen is the overlay display resolver's own screen
  -- function, handed back rather than called here, since it must answer fresh every time
  -- a caller asks rather than once at start time.
  self._composed = compose.run(self, cfg or {})

  return self
end

--- Olm:report()
--- Answers the finished wiring report as one string, a line per stage naming how many
--- steps it ran, then a line per problem, or "no problems" when nothing went wrong.
--- wire.lua's own report function, read off the composed record and called here rather
--- than at compose time, though every call answers the same text once start has
--- returned, since the record it reads is already final by then. The plain text a
--- reload's own console line, or the user's own file, prints to say the run was clean
--- without opening a log.
function obj:report()
  local composed = self._composed
  local answer = composed and composed.report
  return answer and answer()
end

--- Olm:module(name)
--- Answers the loaded module for a plugin identity, or nil before start has run or
--- after a name nothing wired. The escape hatch a caller outside Olm's own wiring reaches
--- a plugin it does not manage itself through, since compose.lua already resolved identity
--- to module once and a second resolution anywhere else would only repeat that work.
---
--- This is an escape hatch with no caller left in this config, the same standing obj:screen
--- carries and for the same reason. TerminalHandler was the one caller, and it is gone now,
--- its own placement behaviour absorbed into AppToggler as a field any toggle may declare
--- rather than a plugin it does not manage. The method stays for the next tool this config
--- ever again keeps outside Olm's own management, should one exist, and is deliberately not
--- a claim that something uses it today.
function obj:module(name)
  local composed = self._composed
  return composed and composed.modules and composed.modules[name]
end

--- Olm:screen()
--- Answers the actual hs.screen the shared overlay display resolver currently names,
--- resolved fresh on every call rather than a screen picked once at start time and
--- handed back stale, since the resolver watches for display changes and invalidates
--- its own cache, and a value taken early would not see a display attached or removed
--- afterwards. composed.screen itself is the resolver's own resolving function, kept
--- unpicked all the way from root/compose.lua for exactly that reason, and this method
--- is the one place that finally calls it, at the moment a caller actually asks.
---
--- This is an escape hatch with no caller left in this config. TerminalHandler was the
--- one, and it stopped asking on 2026-09-01, because the policy this answers resolves to
--- the cursor's screen and a terminal window that changes display on every summon is
--- worse than one that stays put. The method stays because it is the public way any
--- future surface outside Olm's own wiring reads the same display policy every managed
--- surface reads, which is the whole reason a policy is shared rather than copied. It is
--- deliberately not a claim that something uses it today.
function obj:screen()
  local composed = self._composed
  local resolve = composed and composed.screen
  return resolve and resolve()
end

return obj
