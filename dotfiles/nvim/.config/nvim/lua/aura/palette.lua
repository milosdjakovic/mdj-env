-- The Aura palette, in the shape its Neovim package reads, plus the two chrome greys the
-- package has no slot for.
--
-- That package defines 357 highlight groups across three files, and every one of them
-- resolves to one of ten slots. So a variant is ten values rather than 357 overrides, which
-- is why the light half below is small. The slot names are semantic rather than literal,
-- white is the foreground and black is the background, so they invert without renaming.
--
-- Aura publishes exactly one grey. The palette in packages/color-palettes names three
-- neutrals, --white #edecee, --gray #6d6d6d and --black #15141b, and it calls the grey
-- --muted-color. Its job is comments, and 3.54 to 1 against the background is deliberately
-- low, because a comment is meant to recede behind the code. That is the value this file's
-- gray slot carries, and the nine groups reading it are all comment shaped, Comment,
-- SpecialComment, TSComment, doc tags, markdown rules and blockquotes, Folded and FoldColumn.
--
-- It carried #949494 until the palette was read properly. That value came from 9424044,
-- long before Aura, and it appears in neither the published palette nor any file Aura ships.
--
-- overlay is not a package slot and nothing upstream reads it. It exists because chrome is a
-- different job from comments and the palette names no colour for it, while Aura's own VS
-- Code theme does. #adacae is what that theme puts on statusBar.foreground, sideBarTitle and
-- sideBarSectionHeader, and it is the same value herdr's overlay0 carries, which is what
-- makes the sidebar, the lualine bar and the Claude statusline agree rather than merely look
-- similar. Aura has a fourth neutral for secondary body text, #cdccce, and it is left out
-- here because nothing in this config has that job yet.
--
-- light is derived, because Aura publishes no light edition. Every value is the one already
-- committed in the Ghostty aura-light theme or, for the two chrome greys, in herdr's light
-- half, so no layer invents a number of its own.
--
-- purple_faded is stored without its alpha byte on purpose. The package truncates hex to
-- seven characters, so Aura's own #3d375e7f becomes #3d375e before it is ever used, and
-- writing the short form here keeps this file honest about what actually gets painted.
--
-- surface is not read by the package at all. It is ours, for the lualine theme, which
-- upstream does not ship.
local M = {
  dark = {
    purple = "#a277ff",
    green = "#61ffca",
    orange = "#ffca85",
    red = "#ff6767",
    pink = "#f694ff",
    white = "#edecee",
    gray = "#6d6d6d",
    black = "#15141b",
    purple_faded = "#3d375e",
    blue = "#82e2ff",
    surface = "#1c1b22",
    overlay = "#adacae",
  },
  light = {
    purple = "#7e54d1",
    green = "#00805f",
    orange = "#6b4400",
    red = "#bf3239",
    pink = "#872f90",
    white = "#474556",
    gray = "#7c7b85",
    black = "#f8f7fb",
    purple_faded = "#dfdaf2",
    blue = "#005669",
    surface = "#e8e7ed",
    overlay = "#727276",
  },
}

-- One place answers which half is live, so the colorscheme, the statusline and anything
-- added later cannot disagree about it.
function M.current()
  return M[vim.o.background == "light" and "light" or "dark"]
end

return M
