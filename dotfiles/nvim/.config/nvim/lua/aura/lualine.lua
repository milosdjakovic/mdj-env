-- A lualine theme built from the Aura palette.
--
-- Aura ships no lualine theme, so this fills a real gap rather than overriding anything.
-- It is a function of the palette rather than a table of literals, which is the whole point,
-- the same definition serves both appearances and a palette change reaches it for free.
--
-- The mode block carries the background colour as its text, which is the same trick Aura's
-- own badge uses. On the light half that is #f8f7fb on #7e54d1, 6.08 to 1.
return function(p)
  local mode = function(bg) return { bg = bg, fg = p.black, gui = "bold" } end
  local b = { bg = p.purple_faded, fg = p.white }
  local c = { bg = p.surface, fg = p.gray }
  return {
    normal = { a = mode(p.purple), b = b, c = c },
    insert = { a = mode(p.green), b = b, c = c },
    visual = { a = mode(p.orange), b = b, c = c },
    replace = { a = mode(p.red), b = b, c = c },
    command = { a = mode(p.purple), b = b, c = c },
    inactive = { a = c, b = c, c = c },
  }
end
