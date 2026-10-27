-- Olm Placement, what it declares about itself.
--
-- A friendly front end onto lib/overlaydisplay.lua's own two modes. It owns no data of its own,
-- it only reads and writes the live choice through the root words below.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Olm Placement",
    description = "Choose which display Olm opens on, under the cursor or with the active window.",
    author = "Milos Djakovic",
    version = "0.2",
    license = "MIT",
  },

  -- Green marks whichever option is current and red marks the other one.
  icons = {
    placement = { emoji = "🪟", sf = "macwindow.and.cursorarrow" },
    selected = { emoji = "🟢", sf = "circle.fill" },
    notSelected = { emoji = "🔴", sf = "circle" },
  },

  needs = {
    data = {
      -- The reader, a function of no arguments answering the resolver's own effective mode as a
      -- string, and the writer, a function of one mode string persisted through the resolver's
      -- own write path. Both required, since a list whose whole reason is showing and changing
      -- this choice has nothing honest left to do without either.
      overlayPlacementMode = { source = "root", policy = "required",
        breaks = "the Olm Placement list cannot say which choice is live, since the resolver's "
          .. "own mode has no other door out" },
      setOverlayPlacementMode = { source = "root", policy = "required",
        breaks = "choosing an option in the Olm Placement list changes nothing, since the "
          .. "resolver's own persisted choice has no other way in from this plugin" },
      stagePresent = { source = "root", policy = "optional",
        breaks = "the Olm Placement launcher row opens nothing, since M.show has no other way "
          .. "to reach the shared stage" },
    },
  },

  -- Opened from the launcher only, so it proposes no key.
  defaults = {
    description = "Olm Placement",
  },

  surface = {
    context = "olmplacement",
    primary = { action = "insertSelected", description = "Choose" },
  },

  presentation = {
    rows = { member = "rows", call = "dot" },
    select = { member = "select", call = "dot" },
    placeholder = { member = "placeholder", call = "dot" },
    intercept = { member = "intercept", call = "dot" },
  },

  registry = {
    row = { category = "Olm", icon = "placement",
      detail = "which display the launcher appears on",
      keywords = "position, cursor, display, screen, monitor" },
    open = { member = "show", call = "dot" },
  },
}
