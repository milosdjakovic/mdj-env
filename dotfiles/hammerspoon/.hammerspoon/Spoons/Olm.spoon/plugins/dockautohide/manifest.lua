-- DockAutoHide, what it declares about itself.
--
-- A thin front end onto three macOS binaries with no partial service to offer if
-- any is gone, so all three are required rather than optional, matching the needs
-- table below exactly. It carries no surface, unlike most of this set,
-- since it is a two row page hosted inside the launcher rather than a native chooser
-- with its own hyperContext.
return {
  -- The registry and the launcher both know this plugin as dockAutoHide, camelCase, not as
  -- the lowercase directory. config/settings.lua's activation roster and config/keys.lua's
  -- alias entry both spell it this way.
  name = "dockAutoHide",

  needs = {
    tools = {
      { name = "defaults", kind = "system", locator = "/usr/bin/defaults", policy = "required",
        reason = "reading and writing the Dock's auto hide preference and its show delay",
        origin = { macos = "ships with the system" } },
      { name = "osascript", kind = "system", locator = "/usr/bin/osascript", policy = "required",
        reason = "telling the running Dock to notice a hiding change immediately",
        origin = { macos = "ships with the system" } },
      { name = "killall", kind = "system", locator = "/usr/bin/killall", policy = "required",
        reason = "restarting the Dock so it notices a show delay change",
        origin = { macos = "ships with the system" } },
    },
  },

  -- Scoped by the launcher, the alias lists the same two rows the hosted page shows
  -- and choosing one flips that setting in place rather than closing the list.
  provides = {
    rows = "rows",
    select = "select",
  },

  -- A launcher row named Dock that is a doorway onto a page of two, opened from the
  -- launcher only, so it proposes no key at all.
  defaults = {
    description = "Dock",
    launcherRow = true,
    aliases = { "d", "dock" },
  },

  -- toggle, rows and act are all colon methods, obj:toggle(), obj:rows() and obj:act(kind),
  -- so every one of them takes the default call. No surface, matching the comment above,
  -- since this tool is entirely a hosted page rather than a native chooser of its own. run
  -- and act point at the same method, matching the retired root's own registration exactly,
  -- since choosing a row and clicking one whose row the accessibility tree could not resolve
  -- in time both mean the same thing here, flip the setting in place.
  registry = {
    row = { category = "System", detail = "hides or reveals the Dock", glyph = "🗄️",
      keywords = "dock hide hiding autohide show" },
    open = "toggle",
    hosted = true,
    scope = {
      rows = "rows",
      run = "act",
      act = "act",
    },
  },
}
