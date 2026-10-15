-- Volume, what it declares about itself.
--
-- Native Lua over hs.audiodevice, so it names no external tool. One behaviour, so no engine
-- and no contract, the whole plugin is init.lua.
return {
  -- The row icons, named by the rows and drawn by Olm.
  icons = {
    muted = { emoji = "🔇" },
    quiet = { emoji = "🔈" },
    loud = { emoji = "🔊" },
    warn = { emoji = "⚠️" },
  },

  needs = {
    data = {
      stagePresent = { source = "root", policy = "optional",
        breaks = "the launcher row reaches nothing, since it has no other way to ask the shared stage to show this presentation" },
    },
  },

  -- What puts this tool in the launcher's scope set, so its alias and a space lists these rows.
  provides = {
    rows = "rows",
    select = "select",
  },

  defaults = {
    description = "Volume",
    glyph = "🔊",
    aliases = { "vol" },
    example = "Try vol 40 to set the volume",
  },

  -- One morphing row, so the context binds only the commit and the close.
  surface = {
    context = "volume",
    primary = { action = "insertSelected", description = "Confirm" },
    nav = false,
  },

  -- rowCount is one, since this tool only ever shows its one morphing row and the default
  -- chooser sizes a one row window to exactly that row.
  --
  -- matcher is a real false in both places. The field is a value being typed, so rows parses
  -- it on every keystroke and answers the row that value means, and a fuzzy pass over that
  -- row would drop it whenever the typed number did not match its own wording.
  presentation = {
    rows = { member = "rows", call = "dot" },
    select = { member = "select", call = "dot" },
    placeholder = { member = "placeholder", call = "dot" },
    rowCount = 1,
    matcher = false,
  },

  registry = {
    row = { category = "System", detail = "see the volume, set it from 0 to 100, mute or unmute",
      glyph = "🔊", keywords = "volume sound audio mute unmute speaker loud quiet" },
    open = { member = "show", call = "dot" },
    hosted = true,
    scope = {
      matcher = false,
      rows = { member = "rows", call = "dot" },
      run = { member = "select", call = "dot" },
    },
  },
}
