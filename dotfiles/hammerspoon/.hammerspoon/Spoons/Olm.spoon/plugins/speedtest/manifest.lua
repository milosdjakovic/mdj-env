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
  needs = {
    lib = {
      -- A run cannot be recreated once its moment has passed, so the history is durable
      -- data under the olm root rather than a cache, and required because a plugin whose
      -- whole value is the comparison has nothing to compare against without it.
      storage = { from = "storage", policy = "required" },
      -- The shared glyph drawer, so a row's icon is sized and framed exactly like every
      -- other row's in this configuration rather than being drawn a second way here.
      -- Optional, a list with no icons still reads.
      glyphIcon = { from = "glyphicon", policy = "optional" },
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

    -- Four root computed words, every one of them already spoken by other plugins rather
    -- than minted here. All four degrade to a key that quietly does nothing, never a
    -- crash, so all four are optional.
    data = {
      stagePresent = { source = "root", policy = "optional",
        breaks = "the launcher row and this plugin's own open reach nothing, since neither has any other way to ask the shared stage to show this presentation" },
      redrawPresented = { source = "root", policy = "optional",
        breaks = "a run in flight stops ticking on screen and a finished run does not appear until the field is touched, since a background answer has no other way to reach the list" },
      stagePop = { source = "root", policy = "optional",
        breaks = "the Back row on every inner page does nothing, leaving Backspace as the only way out of a level" },
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
    glyph = "📶",
    -- st is the short form a person types, speed is the whole word anybody would try
    -- first. Neither collides with a claimed alias, s belongs to system settings.
    aliases = { "st", "speed" },
    example = "Try st to measure this network",
  },

  -- A flat list with one extra verb of its own, a run started without leaving the row the
  -- person is on. Everything else is the shared navigation.
  surface = {
    context = "speedtest",
    primary = { action = "insertSelected", description = "Confirm" },
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
      glyph = "📶", keywords = "speedtest speed network bandwidth latency rpm" },
    open = { member = "chooser.show", call = "dot" },
    hosted = true,
    -- The scope is deliberately not the whole tool. A scope shows its rows inside the
    -- launcher's own list, which reserves no companion pane and cannot be pushed into, so
    -- neither the pane nor the settings level can exist here. What it carries is the two
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
