-- Input Sources, what it declares about itself.
--
-- Native Lua over hs.keycodes, so it names no external tool. One behaviour, so no engine and
-- no contract, the whole plugin is init.lua.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Input Sources",
    description = "Switch between the keyboard layouts and input methods enabled on this Mac.",
    author = "Milos Djakovic",
    version = "0.3",
    license = "MIT",
  },

  -- The row icons, named by the rows and drawn by Olm. The green circle marks the source in
  -- use, the marker every list here uses for the live choice.
  icons = {
    inputsources = { emoji = "⌨️", sf = "keyboard" },
    current = { emoji = "🟢", sf = "circle.fill" },
    layout = { emoji = "🔤", sf = "character.textbox" },
    method = { emoji = "💬", sf = "character.bubble" },
  },

  needs = {
    data = {
      stagePresent = { source = "root", policy = "optional",
        breaks = "the launcher row reaches nothing, since it has no other way to ask the shared stage to show this list" },
      notify = { source = "root", policy = "optional",
        breaks = "the Previous Input Source action switches in silence, so the only sign of which layout is now active is the menu bar" },
    },
    lib = {
      -- The order the list leads with, most recently used first, kept across reloads, so the
      -- cycle key's first press lands on the layout used before this one.
      recency = { from = "recency", policy = "optional" },
    },
  },

  -- What puts this tool in the launcher's scope set, so its alias and a space lists these rows.
  -- actions is the one thing it can run without a list, the step back to the layout used before,
  -- which earns its launcher row.
  provides = {
    rows = "rows",
    select = "select",
    actions = "actions",
  },

  defaults = {
    description = "Input sources",
    icon = "inputsources",
    aliases = { "kb", "input" },
    example = "Try input to pick a keyboard layout",
    -- A tap of fn cycles the list, the Globe key macOS posts for it, bound with no leader since
    -- no app reads it. With this plugin switched off nothing binds it and macOS answers the tap
    -- with whatever its own Globe key setting says.
    bindings = {
      { action = "cycle", key = "globe", leader = false, description = "Cycle input sources" },
    },
  },

  surface = {
    context = "inputsources",
    primary = { action = "insertSelected", description = "Use" },
  },

  -- onPresent reads the sources once per opening, since rows runs on every keystroke.
  presentation = {
    rows = { member = "rows", call = "dot" },
    select = { member = "select", call = "dot" },
    placeholder = { member = "placeholder", call = "dot" },
    onPresent = { member = "onPresent", call = "dot" },
    rowCount = { member = "rowCount", call = "dot" },
  },

  registry = {
    row = { category = "Keyboard", detail = "switch the keyboard layout or input method",
      keywords = "keyboard layout, language, ime, japanese, chinese, pinyin, korean, abc, serbian, cyrillic, latin" },
    open = { member = "show", call = "dot" },
    hosted = true,
    scope = {
      rows = { member = "scopeRows", call = "dot" },
      run = { member = "select", call = "dot" },
    },
  },
}
