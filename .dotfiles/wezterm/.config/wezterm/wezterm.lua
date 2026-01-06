local wezterm = require("wezterm")

local config = wezterm.config_builder()

config.color_scheme = 'Aura (Gogh)'

config.font = wezterm.font("Hack Nerd Font")
config.font_size = 18

config.harfbuzz_features = { 'calt=1', 'clig=1', 'liga=1' }

config.adjust_window_size_when_changing_font_size = false

config.enable_tab_bar = false
config.window_decorations = "RESIZE"

config.disable_default_key_bindings = true
config.window_close_confirmation = 'NeverPrompt'

config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

config.keys = {
  { key = 'w',          mods = 'CMD', action = wezterm.action.CloseCurrentTab { confirm = false } }, -- Close tab
  { key = 'q',          mods = 'CMD', action = wezterm.action.QuitApplication },                     -- Quit
  { key = 'n',          mods = 'CMD', action = wezterm.action.SpawnWindow },                         -- Spawn new window
  { key = 'c',          mods = 'CMD', action = wezterm.action.CopyTo 'Clipboard' },                  -- Copy to clipboard
  { key = 'v',          mods = 'CMD', action = wezterm.action.PasteFrom 'Clipboard' },               -- Paste from clipboard
  { key = 'LeftArrow',  mods = 'OPT', action = wezterm.action.SendString '\x1b[1;5D' },              -- Move word left
  { key = 'RightArrow', mods = 'OPT', action = wezterm.action.SendString '\x1b[1;5C' },              -- Move word right
  { key = 'LeftArrow',  mods = 'CMD', action = wezterm.action.SendString '\x1bOH' },                 -- Move to start of line
  { key = 'RightArrow', mods = 'CMD', action = wezterm.action.SendString '\x1bOF' },                 -- Move to end of line
  { key = 'Backspace',  mods = 'CMD', action = wezterm.action.SendString '\x15' },                   -- Delete line
  { key = 'Backspace',  mods = 'OPT', action = wezterm.action.SendString '\x17' },                   -- Delete word
  { key = '=',          mods = 'CMD', action = wezterm.action.IncreaseFontSize },                    -- Increase font size
  { key = '-',          mods = 'CMD', action = wezterm.action.DecreaseFontSize },                    -- Decrease font size
  { key = '0',          mods = 'CMD', action = wezterm.action.ResetFontSize },                       -- Reset font size
}

return config
