-- The Aura palette, in the shape its Neovim package reads.
--
-- That package defines 357 highlight groups across three files, and every one of them
-- resolves to one of ten slots. So a variant is ten values rather than 357 overrides, which
-- is why the light half below is small. The slot names are semantic rather than literal,
-- white is the foreground and black is the background, so they invert without renaming.
--
-- Two values are ours rather than Aura's.
--
-- dark.gray is #949494 where Aura says #6d6d6d, the repo wide decision from 9424044 that
-- Ghostty and kitty also carry. Setting it here replaces five separate highlight overrides
-- the old config carried, since thirteen groups read this slot.
--
-- light is derived, because Aura publishes no light edition. Every value is the one already
-- committed in the Ghostty aura-light theme, so Neovim and the terminal agree. The #949494
-- bump deliberately does not carry over. It existed to rescue #6d6d6d from 3.0 to 1 on a
-- dark page, and the light comment grey already measures 3.92, in line with Catppuccin
-- Latte at 4.1.
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
    gray = "#949494",
    black = "#15141b",
    purple_faded = "#3d375e",
    blue = "#82e2ff",
    surface = "#1c1b22",
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
  },
}

-- One place answers which half is live, so the colorscheme, the statusline and anything
-- added later cannot disagree about it.
function M.current()
  return M[vim.o.background == "light" and "light" or "dark"]
end

return M
