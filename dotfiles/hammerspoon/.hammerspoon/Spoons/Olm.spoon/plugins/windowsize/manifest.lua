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
  needs = {
    -- The resize itself, which is window geometry and belongs to the plugin that already
    -- owns every other move and size on this machine. This plugin asks it what a request
    -- would actually do, so the row can say up front that a size the display cannot hold is
    -- about to be trimmed, and the resize that follows is the same plugin's own action
    -- reached through the launcher's window dispatch rather than through anything here.
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
    },
  },

  -- What the launcher may reach for a typed size. queryRows rather than rows, because rows
  -- and select together mean a browsable list a typed alias can hand the launcher, and this
  -- computes at most one row from what was typed and claims nothing else. The member is
  -- spelled rows because the launcher's own door asks a source for a member literally by
  -- that name, so this is the one field here whose spelling is not free.
  provides = {
    queryRows = "rows",
  },

  defaults = {
    glyph = "📐",
    category = "Window size",

    -- The one short line the launcher's empty field can wear, which is the only way a person
    -- finds out that typing a size answers at all. Checked against this plugin's own grammar
    -- before it shipped, so the field never invites a person to type something the parser
    -- refuses, and short enough for the field, which holds about twenty eight characters.
    example = { "Try 1920x1080" },

    -- The smallest edge worth offering a row for. A window narrower or shorter than this
    -- shows nothing readable, so a slip like 19x1080 answers no row rather than shrinking a
    -- window down to a sliver, and a person who genuinely wants a smaller one lowers this.
    -- The window is recoverable either way, since typing a larger size is this same row, but
    -- a typo that quietly acts is worse than a typo that quietly does not.
    smallestEdge = 200,
  },
}
