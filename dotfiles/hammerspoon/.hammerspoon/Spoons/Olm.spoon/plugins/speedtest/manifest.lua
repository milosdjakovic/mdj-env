-- Speedtest, what it declares about itself.
--
-- One measurement tool, networkQuality, which ships with macOS, and a history file so a
-- reading can be read against this network's own past rather than against a number from a
-- review. The tool is optional, so the list still opens on a machine without it and says
-- what is missing instead of failing to wire.
--
-- There is no chord of its own here. A speedtest is something a person reaches for when
-- the network feels wrong, which is a few times a month, so the launcher row and the alias
-- are the whole of how it opens.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Speedtest",
    description = "Measure this connection and compare it with its own past readings.",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  -- The row icons, named by the rows and drawn by Olm.
  icons = {
    run = { emoji = "📶", sf = "speedometer" },
    stop = { emoji = "🚫", sf = "nosign" },
    result = { emoji = "📈", sf = "chart.line.uptrend.xyaxis" },
    settings = { emoji = "⚙️", sf = "gearshape" },
    networks = { emoji = "🌐", sf = "globe" },
    back = { emoji = "⬅️", sf = "chevron.left" },
    empty = { emoji = "📊", sf = "chart.bar" },
    problem = { emoji = "⚠️", sf = "exclamationmark.triangle" },
    name = { emoji = "✏️", sf = "pencil" },
    clear = { emoji = "🗑️", sf = "trash" },
    speedtest = { emoji = "📶", sf = "speedometer" },
  },

  needs = {
    lib = {
      -- A run cannot be recreated once its moment has passed, so the history is durable
      -- data under the olm root rather than a cache, and required because a plugin whose
      -- whole value is the comparison has nothing to compare against without it.
      storage = { from = "storage", policy = "required" },
      -- No ui. The kit every piece of text in the pane is drawn through arrives with the
      -- docked pane, which hands it to the describer on every paint.
    },

    tools = {
      { name = "networkQuality", kind = "system", locator = "/usr/bin/networkQuality",
        policy = "optional", unit = "runner",
        reason = "measures capacity and responsiveness under load, the whole of what this tool reports",
        origin = { macos = "ships with the system" } },
      -- The one reason there is a live graph. networkQuality decides whether to report
      -- progress by asking whether its output is a terminal, and a task gives it a pipe, so
      -- without this it says nothing at all until it finishes. script exists to run a program
      -- with a terminal attached, which is all it is used for here. Optional, since a run
      -- without it still lands and still keeps everything, it simply cannot be watched.
      { name = "script", kind = "system", locator = "/usr/bin/script", policy = "optional",
        unit = "runner",
        reason = "gives networkQuality a terminal so it reports figures while a run is still in progress",
        origin = { macos = "ships with the system" } },
    },

    -- Five root computed words, every one of them already spoken by other plugins rather
    -- than minted here. All five degrade to a key that quietly does nothing, never a
    -- crash, so all five are optional.
    data = {
      stagePresent = { source = "root", policy = "optional",
        breaks = "the launcher row and this plugin's own open reach nothing, since neither has any other way to ask the shared stage to show this presentation" },
      redrawPresented = { source = "root", policy = "optional",
        breaks = "a run in flight stops ticking on screen and a finished run does not appear until the field is touched, since a background answer has no other way to reach the list" },
      stagePop = { source = "root", policy = "optional",
        breaks = "the Back row on every inner page does nothing, leaving Backspace as the only way out of a level" },
      stagePush = { source = "root", policy = "optional",
        breaks = "Name this network in the action panel opens nothing, since a verb has no other way to open a level" },
      stageSelectedItem = { source = "root", policy = "optional",
        breaks = "the docked pane cannot read the highlighted row when the list is rebuilt under it, so it keeps showing the run that was highlighted before the rebuild" },
    },
  },

  -- Scoped by the launcher, typing the alias and a space lists the same rows the
  -- presentation does and choosing one does the same thing.
  provides = {
    rows = "chooser.rows",
    select = "chooser.select",
  },

  defaults = {
    description = "Speedtest",
    icon = "speedtest",
    -- st is the short form a person types, speed is the whole word anybody would try
    -- first. Neither collides with a claimed alias, s belongs to system settings.
    aliases = { "st", "speed" },
    example = "Try st to measure this network",
  },

  -- A flat list whose settings are verbs of the action panel alone, docs/PLAN-ACTION-PANEL.md.
  -- What a run does is a pick of one of a few through choices, naming the network opens its
  -- own field through stagePush, and the two clears ask first through the panel's own confirm,
  -- each listed only when there is something to clear. None names a key, since a setting is
  -- changed a few times a year. Every method they name is a colon method on the chooser
  -- submodule, which registry.surface below names.
  surface = {
    context = "speedtest",
    primary = { action = "insertSelected", description = "Confirm" },
    extra = {
      { action = "setDirection", description = "Direction", icon = "settings", section = "Run",
        choices = "directionChoices" },
      { action = "setMeasurement", description = "Measurement", icon = "settings", section = "Run",
        choices = "measurementChoices" },
      { action = "setRuntime", description = "Maximum runtime", icon = "settings", section = "Run",
        choices = "runtimeChoices" },
      { action = "setProtocol", description = "Protocol", icon = "settings", section = "Run",
        choices = "protocolChoices" },
      { action = "setRelay", description = "iCloud Private Relay", icon = "settings", section = "Run",
        choices = "relayChoices" },
      { action = "setCap", description = "Keep per network", icon = "settings", section = "History",
        choices = "capChoices" },
      { action = "nameNetwork", description = "Name this network", icon = "name", section = "History" },
      { action = "clearNetwork", description = "Clear this network", icon = "clear", section = "History",
        applies = "hasRuns", confirm = "Forget every run on this network" },
      { action = "clearEverything", description = "Clear every network", icon = "clear", section = "History",
        applies = "hasHistory", confirm = "Forget every run on every network" },
    },
    -- The detail pane beside the list is where every figure the tool returns actually
    -- lands, since a row holds three numbers and a run answers twenty.
    pane = true,
  },

  -- Every member is a plain dot called function on the chooser submodule, so every one of
  -- them states call explicitly rather than taking a default that would not raise.
  presentation = {
    rows = { member = "chooser.rows", call = "dot" },
    select = { member = "chooser.select", call = "dot" },
    placeholder = { member = "chooser.placeholder", call = "dot" },
    intercept = { member = "chooser.intercept", call = "dot" },
    onPresent = { member = "chooser.onPresent", call = "dot" },
    onHighlight = { member = "chooser.onHighlight", call = "dot" },
    onPositioned = { member = "chooser.onPositioned", call = "dot" },
    onClose = { member = "chooser.onClose", call = "dot" },
    -- A trackpad scroll over the docked pane, which the pane needs because a finished run says
    -- more than one pane holds. It arrives with no binding of its own, the chooser atom
    -- watching for a scroll over the companion rect, so it costs no key anywhere.
    onScroll = { member = "chooser.onScroll", call = "dot" },
    -- A member spec rather than a static true, so a root that injected no pane surface
    -- opens this list exactly as it would without one rather than reserving a rect with
    -- nothing able to draw in it.
    paneWidth = { member = "chooser.paneWidth", call = "dot" },
  },

  registry = {
    row = { category = "Network", detail = "measure this connection and compare it with its own past",
      keywords = "internet speed, bandwidth, latency, ping, network quality, rpm" },
    open = { member = "chooser.show", call = "dot" },
    -- The submodule the action panel's verbs are answered by.
    surface = "chooser",
    hosted = true,
    -- The scope is deliberately not the whole tool. A scope shows its rows inside the
    -- launcher's own list, which reserves no companion pane and cannot be pushed into, so
    -- neither the pane nor the settings can exist here. What it carries is the two
    -- things worth reaching by a typed word, starting a measurement and reading what this
    -- network has done before, plus one row that opens the tool proper for everything else.
    --
    -- act rather than run is what keeps the list open. A scope declaring act has every one of
    -- its rows routed through it, run never being reached, so this one function answers for
    -- the whole scope and run below names it too rather than a second behaviour that would
    -- only ever disagree with it.
    scope = {
      rows = { member = "chooser.scopeRows", call = "dot" },
      run = { member = "chooser.scopeAct", call = "dot" },
      act = { member = "chooser.scopeAct", call = "dot" },
    },
  },
}
