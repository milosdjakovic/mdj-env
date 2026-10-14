-- The UI kit's style spec, built from policy and the current theme. One function,
-- spec(policy, colors), answering the table lib/ui/style.lua takes at configure time. It
-- lives beside the composition root because only the root knows the shape of the settings
-- blocks it reads, surface and cheatSheet, and the shape of the readers outside the kit that
-- still take a theme, and it is its own file rather than a local inside root/compose.lua
-- because a second reader needs the very same answer, the parity probes under test/, which
-- build every surface through the kit with the spec a running config would get.
--
-- The colours are no longer policy's. They come from the current theme, the colours table
-- lib/ui/themes.lua answers, a half each of the keys a theme file holds, and each key maps
-- onto one of the kit's colour roles below. Only what policy owns is read from policy, the
-- two radii settings carries. Every other
-- token, and the colours a theme leaves out, are lib/ui/style.lua's own. A half with no
-- light colours of its own takes the dark one, the same fallback every reader applies.
--
-- chooserView and surfaceView are the other two things this file knows. The native provider
-- and the plugin panes still read a table shaped like the old chooserTheme setting, and the
-- panel still reads one shaped like the surface setting, so the root keeps one table of each
-- and these two fill it in place from the colours of the live theme. Stage four of the kit
-- retires both views once those readers draw through the kit, and these two go with them.

local M = {}

-- A theme key and the kit colour role it answers. The kit calls the ink foreground and the
-- preview metadata overlay, a theme file uses the plainer words.
local ROLE_OF = {
  text = "foreground",
  subtext = "subtext",
  background = "background",
  border = "border",
  accent = "accent",
  meta = "overlay",
  path = "path",
  note = "note",
  highlight = "highlight",
  selection = "selection",
}

local function colorsFor(colors, half)
  local theme = (colors and (colors[half] or colors.dark)) or {}
  local out = {}
  for key, role in pairs(ROLE_OF) do out[role] = theme[key] end
  return out
end

--- M.spec(policy, colors, typography) -> the style spec for lib/ui/style.lua. colors is the
--- table lib/ui/themes.lua answers for the current theme, a half each of theme keys.
--- typography is what style.loadTypography answered, the valid fonts and sizes of the type
--- roles from config/typography.toml, handed on untouched since the style owns the fallback.
function M.spec(policy, colors, typography)
  policy = policy or {}
  local cheatSheet = policy.cheatSheet or {}
  return {
    colors = { dark = colorsFor(colors, "dark"), light = colorsFor(colors, "light") },
    typography = typography,
    radius = {
      surface = (policy.surface or {}).cornerRadius,
      -- One radius shared on purpose by the cheat sheet badges and the hint bar badges,
      -- matching the settings comment.
      badge = cheatSheet.badgeRadius,
    },
  }
end

-- A "#rrggbb" or "#rrggbbaa" string as an hs colour table, nil for anything else.
local function hexColor(hex)
  local r, g, b, a = tostring(hex):match("^#(%x%x)(%x%x)(%x%x)(%x?%x?)$")
  if not r or (a ~= "" and #a ~= 2) then return nil end
  return { red = tonumber(r, 16) / 255, green = tonumber(g, 16) / 255,
           blue = tonumber(b, 16) / 255, alpha = a ~= "" and tonumber(a, 16) / 255 or 1.0 }
end

-- Empties a table without replacing it, since the readers that hold it hold the reference.
local function clear(t)
  for k in pairs(t) do t[k] = nil end
end

--- M.chooserView(into, colors) -> into
--- Rewrites into, in place, as a table shaped like the old chooserTheme setting from the
--- colours of a theme, so the readers outside the kit that took that setting follow a switch
--- without a reload. bgDark is the half itself, the row text colours are hs colour tables,
--- and the preview four are the CSS hex strings the preview webviews take, alpha digits cut
--- off since CSS here has never been handed any.
function M.chooserView(into, colors)
  clear(into)
  for _, half in ipairs({ "dark", "light" }) do
    local theme = (colors and (colors[half] or colors.dark)) or {}
    local function six(hex) return hex and hex:sub(1, 7) end
    into[half] = {
      bgDark = half == "dark",
      titleColor = hexColor(theme.text),
      subColor = hexColor(theme.subtext),
      preview = { fg = six(theme.accent), meta = six(theme.meta), path = six(theme.path),
                  note = six(theme.note) },
    }
  end
  return into
end

--- M.surfaceView(into, colors) -> into
--- Fills the dark and light background and border of into, in place, from the colours of a
--- theme. The corner radius and the border width are settings' and are left alone, which is
--- why this fills rather than clears.
function M.surfaceView(into, colors)
  for _, half in ipairs({ "dark", "light" }) do
    local theme = (colors and (colors[half] or colors.dark)) or {}
    into[half] = { bg = theme.background, border = theme.border }
  end
  return into
end

return M
