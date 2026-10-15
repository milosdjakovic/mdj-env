-- Audio, what it declares about itself.
--
-- Native Lua over hs.audiodevice, so it names no external tool. One behaviour, so no engine
-- and no contract, the whole plugin is init.lua.
return {
  -- The row icons, named by the rows and drawn by Olm.
  icons = {
    current = { emoji = "✅" },
    output = { emoji = "🔊" },
    input = { emoji = "🎙️" },
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
    description = "Audio devices",
    glyph = "🎧",
    aliases = { "au", "audio" },
    example = "Try audio to switch output",
  },

  surface = {
    context = "audio",
    primary = { action = "insertSelected", description = "Use" },
  },

  -- onPresent reads the devices once per opening, since rows runs on every keystroke and
  -- should only read what is already held. intercept switches a device and answers stay, so
  -- the mark moves to the chosen row and the list stays put for an input to be picked too.
  presentation = {
    rows = { member = "rows", call = "dot" },
    select = { member = "select", call = "dot" },
    placeholder = { member = "placeholder", call = "dot" },
    onPresent = { member = "onPresent", call = "dot" },
    intercept = { member = "intercept", call = "dot" },
  },

  -- The scope has its own rows member because a scope has no onPresent, so it reads the
  -- devices itself when what it holds has gone stale.
  registry = {
    row = { category = "System", detail = "switch the sound output or the microphone",
      glyph = "🎧", keywords = "audio sound output input microphone mic speaker headphones device" },
    open = { member = "show", call = "dot" },
    hosted = true,
    scope = {
      rows = { member = "scopeRows", call = "dot" },
      run = { member = "select", call = "dot" },
    },
  },
}
