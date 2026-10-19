-- WindowSize, what it declares about itself.
--
-- A launcher query row source rather than a picker of its own, so it owns no chooser, no
-- key, and no alias, exactly as arithmetic does. It is found only by typing a size, which is
-- why the placeholder hint below is the whole of its discoverability.
--
-- NO name FIELD ON PURPOSE. A camelCased identity would read better than the directory, and
-- it cannot be declared here yet. The launcher's query source set is answered from the
-- manifest scan, so it holds DIRECTORY names, while the composition root then indexes the
-- module table with them and that table is keyed by IDENTITY. The two agree for every source
-- that has ever joined this set, since each one's directory and identity are the same word,
-- and a plugin declaring a different identity would be dropped from the set in silence with
-- its rows never asked for. The directory is one word here regardless, so nothing is lost by
-- staying inside what the wiring can actually carry.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Window Size",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  -- The icons this plugin names, in the emoji set and the SF Symbol set. The one named for the
  -- plugin is its identity icon, which the launcher row and the scoped list both wear.
  icons = {
    windowsize = { emoji = "📐", sf = "ruler" },
  },

  needs = {
    -- The resize itself, which is window geometry and belongs to the plugin that already
    -- owns every other move and size on this machine. This plugin asks it what a request
    -- would actually do, so the row can say up front that a size the display cannot hold is
    -- about to be trimmed, and the resize that follows is the same plugin's own exact size
    -- action, which launcherRun below reaches through the second sibling, the window manager's
    -- action descriptors, calling the exact size action's run with the size. That used to be the
    -- launcher's window dispatch holding the window manager's action map, and phase three of
    -- the core split moved the call here so the launcher names no plugin.
    --
    -- Required, since a source that cannot describe what a row would do has no honest row to
    -- offer and is better absent than offering one that lies.
    --
    -- ordering false, since the member is called when a person types rather than while
    -- anything is being wired, so needing it says nothing about who goes first and an edge
    -- here would only constrain the plan for no reason.
    siblings = {
      plan = { plugin = "windowmanager", member = "exactSizePlan", call = "method",
        policy = "required", ordering = false },
      windowActions = { plugin = "windowmanager", member = "actions", call = "method",
        policy = "required", ordering = false },
    },

    -- Which application the launcher opened over, the same root word menu search and text
    -- case declare. The launcher gives focus back to that app before it runs a window row, so
    -- it is the app whose window this row resizes, and the title names it. Asking macOS here
    -- would answer the launcher's own list, which holds focus while anybody is typing.
    -- Optional, since the row works the same without it and only its wording loses the name.
    data = {
      coveredApp = { source = "root", policy = "optional",
        breaks = "the row reads Resize window rather than naming the application it resizes" },
    },
  },

  -- What the launcher may reach for a typed size. queryRows rather than rows, because rows
  -- and select together mean a browsable list a typed alias can hand the launcher, and this
  -- computes at most one row from what was typed and claims nothing else. The member is
  -- spelled rows because the launcher's own door asks a source for a member literally by
  -- that name, so this is the one field here whose spelling is not free.
  --
  -- launcherRun is how a chosen row comes back. The launcher routes a row by the owner the root
  -- stamps on it, so this plugin runs its own row rather than the launcher knowing which
  -- plugin a window row belongs to. It provides no launcherRows, since its one row is computed
  -- from what was typed and reaches the launcher as a query row instead.
  provides = {
    queryRows = "rows",
    launcherRun = "launcherRun",
  },

  defaults = {
    icon = "windowsize",

    -- The one short line the launcher's empty field can wear, which is the only way a person
    -- finds out that typing a size answers at all. Checked against this plugin's own grammar
    -- before it shipped, so the field never invites a person to type something the parser
    -- refuses, and short enough for the field, which holds about twenty eight characters.
    example = { "Try 1920x1080" },

    -- The smallest edge a row will size a window to. A window narrower or shorter than this
    -- shows nothing readable, so a slip like 19x1080 raises that edge to this floor rather
    -- than shrinking a window down to a sliver, and a person who genuinely wants a smaller
    -- one lowers this. A size under the floor used to offer no row at all, on the reasoning
    -- that a typo which quietly acts is worse than one that quietly does not. It no longer
    -- acts quietly, since the subtitle names the size that will land and says size limit
    -- before Return, while a row that silently vanished told a person nothing about why,
    -- decisions/olm-launcher-ranking.md has the reversal.
    smallestEdge = 200,
  },
}
