-- Aura, following the terminal's appearance.
--
-- This is a colorscheme in its own right rather than a wrapper, and it exists because the
-- upstream package cannot switch. Its setupTheme writes vim.o.background = "dark"
-- unconditionally on every call, and nothing anywhere in it ever reads that option, so no
-- variant it ships can answer a light terminal.
--
-- The seam it does offer is core.createTheme(palette), which takes the palette table as an
-- argument. The palette module is a singleton, so filling its ten fields and calling
-- createTheme directly applies a theme without going near setupTheme or its hardcoded line.
--
-- Neovim supplies the rest. It sets 'background' from the terminal when it can detect it,
-- and reloads the colorscheme whenever 'background' changes as long as g:colors_name is
-- set. So this file is re-sourced on an appearance switch, reads the option again, and
-- repaints. No autocmd and no watcher, the same shape as Ghostty and herdr.
--
-- The overrides at the end used to live in a ColorScheme autocmd, which had to be
-- registered in the plugin's init rather than its config to beat LazyVim to the first
-- paint. Doing the work here instead removes that race rather than winning it.

local ok, core = pcall(require, "aura-theme.common.core")
if not ok then
  vim.notify("aura, the aura-theme package is not on the runtimepath", vim.log.levels.ERROR)
  return
end

local p = require("aura.palette").current()

local palette = require("aura-theme.common.palette")
for slot, value in pairs(p) do
  palette[slot] = value
end

vim.o.termguicolors = true

core.createTheme(palette)

-- After createTheme, never before. It runs "hi clear", which unsets g:colors_name, and that
-- variable is precisely what makes Neovim reload this file when 'background' changes. Set it
-- first and the theme paints correctly once and then never switches again.
vim.g.colors_name = "aura"

-- The package maps :terminal slots 4 and 6 both to blue and never uses pink, so a terminal
-- inside Neovim disagrees with the one around it. These four restore the hue ordered layout
-- the Ghostty themes use, each accent once at the slot nearest its hue.
vim.g.terminal_color_4, vim.g.terminal_color_12 = p.purple, p.purple
vim.g.terminal_color_5, vim.g.terminal_color_13 = p.pink, p.pink
vim.g.terminal_color_6, vim.g.terminal_color_14 = p.blue, p.blue

-- Aura draws nine groups with gui = "inverse", which swaps fg and bg at render time. For
-- Visual that makes Normal.fg the rendered background, so a selection is a near solid bar of
-- foreground colour, and Substitute sets bg = white directly for the same effect. Both feel
-- wrong against the rest of the theme, so they become solid backgrounds with readable text.
-- These now read from the palette, so they follow the appearance like everything else.
local hl = function(group, spec) vim.api.nvim_set_hl(0, group, spec) end

hl("Visual", { bg = p.purple_faded, fg = p.white })
hl("VisualNOS", { bg = p.purple_faded, fg = p.white })
hl("Search", { bg = p.purple_faded, fg = p.orange })
hl("IncSearch", { bg = p.orange, fg = p.black })
hl("Substitute", { bg = p.purple_faded, fg = p.red })
hl("TabLineSel", { bg = p.purple_faded, fg = p.green, bold = true })
hl("DiffAdd", { bg = p.purple_faded, fg = p.green })
hl("DiffChange", { bg = p.purple_faded, fg = p.blue })
hl("DiffDelete", { bg = p.purple_faded, fg = p.red })
hl("DiffText", { bg = p.purple_faded, fg = p.orange })

-- mini.icons colours every filetype separately, which turns the file tree into a rainbow.
-- These are LazyVim's groups, not Aura's, so this is an addition rather than a correction.
for _, name in ipairs({
  "MiniIconsAzure", "MiniIconsBlue", "MiniIconsCyan", "MiniIconsGreen", "MiniIconsGrey",
  "MiniIconsOrange", "MiniIconsPurple", "MiniIconsRed", "MiniIconsYellow",
}) do
  hl(name, { fg = p.gray })
end
