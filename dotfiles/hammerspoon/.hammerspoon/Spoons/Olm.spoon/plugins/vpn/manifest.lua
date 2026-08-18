-- Vpn, what it declares about itself.
--
-- A native chooser over one backend, Mullvad, plus the shared lift to front ordering
-- service borrowed from lib so the location list opens already sorted by what was
-- used last. When Mullvad is absent the chooser still opens, to one row naming the
-- missing tool, so this plugin is safe to wire on any machine.
return {
  needs = {
    -- Remembering the last used city, so the list opens already ordered by that. This
    -- said optional once, which promised the panel would still open and still connect
    -- with the resting order lost. The plugin's own configure does not honour that
    -- promise, it hard errors when opts.recency is nil, by its own comment's account
    -- deliberately, "rejected loudly rather than quietly ordering nothing." The code and
    -- its own stated intent agree with each other and disagree with this manifest, so the
    -- manifest is the one that was wrong. Required.
    lib = {
      recency = { from = "recency", policy = "required" },
    },
    tools = {
      { name = "mullvad", kind = "path", policy = "optional", unit = "mullvad",
        reason = "the relay CLI behind every VPN control and location",
        origin = { cask = "mullvad-vpn" } },
    },
  },

  -- configure alone leaves this plugin with no engine and no chooser. start resolves the
  -- tool's availability, wires the engine when it is present, and builds the one native
  -- chooser either way, so it is a real step beyond configure rather than an empty
  -- lifecycle method.
  wiring = {
    { method = "start" },
  },

  -- Scoped by the launcher, typing the alias and a space lists the same controls and
  -- locations the picker does and choosing one does the same thing.
  provides = {
    rows = "rows",
    select = "select",
  },

  defaults = {
    leader = "app",
    key = "P",
    description = "VPN",
    glyph = "🌐",
    aliases = { "v", "vpn" },
  },

  -- One flat list, the controls on top and every city below, so it takes the shared
  -- navigation with nothing beyond the primary key.
  surface = {
    context = "vpn",
    primary = { action = "insertSelected", description = "Confirm" },
  },

  -- show, and every scope action below, are plain dot called functions on this plugin's own
  -- root, never colon methods, so every one of them says call = dot rather than taking the
  -- default. scopeRows is the one member this plugin's own module did not use to expose. It
  -- joins M.prepare and M.rows exactly the way M.show already does either side of revealing
  -- its own chooser, and it takes a second argument, redraw, since a scope has no chooser of
  -- its own to refresh once the fetch answers. Olm hands that callback over so this plugin
  -- still never learns a launcher exists, closing the one real cross plugin coupling the
  -- retired root's own registration carried, spoon.Vpn's scope calling spoon.Launcher:refresh()
  -- directly.
  registry = {
    row = { category = "Network" },
    open = { member = "show", call = "dot" },
    surface = true,
    hosted = true,
    shortcut = "leader",
    scope = {
      rows = { member = "scopeRows", call = "dot" },
      run = { member = "select", call = "dot" },
    },
  },
}
