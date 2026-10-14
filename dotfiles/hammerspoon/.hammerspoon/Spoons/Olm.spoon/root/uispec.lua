-- The UI kit's style spec, built from policy. One function, spec(policy), answering the table
-- lib/ui/style.lua takes at configure time. It lives beside the composition root because
-- only the root knows the shape of the settings blocks it reads, surface, chooserTheme and
-- cheatSheet, and it is its own file rather than a local inside root/compose.lua because a
-- second reader needs the very same answer, the stage two parity probes under test/, which
-- build every surface through the kit with the spec a running config would get.
--
-- Only what policy owns is named here, each half's colours, the two radii settings carries,
-- and the cheat sheet's type when settings sets it. Every other token, and the four colours
-- derived from these, are lib/ui/style.lua's own. A half with no light block of its own takes
-- the dark one, the same fallback every reader of these settings already applies.

local M = {}

local function sideOf(t, half) return (t and (t[half] or t.dark)) or {} end

local function colorsFor(policy, half)
  local theme = sideOf(policy.chooserTheme, half)
  local surface = sideOf(policy.surface, half)
  local preview = theme.preview or {}
  return {
    foreground = theme.titleColor,
    subtext = theme.subColor,
    background = surface.bg,
    border = surface.border,
    overlay = preview.meta,
    path = preview.path,
    note = preview.note,
    accent = preview.fg,
  }
end

-- The cheat sheet's two text variants, following the rule lib/cheatsheet.lua's configure
-- applied before stage two. A font size sets both, and the title's line box follows it at
-- one and a quarter, rounded, unless a line height is set too. A line height alone sets only
-- the title's box. The glyph, label and separator box was always the size plus four. Nothing
-- set means the shipped variants stand.
local function cheatText(cheatSheet)
  local text = {}
  if cheatSheet.fontSize ~= nil then
    local size = cheatSheet.fontSize
    text.cheat = { size = size, lineHeight = size + 4 }
    text.cheatTitle = { size = size,
      lineHeight = cheatSheet.lineHeight or math.floor(size * 1.25 + 0.5) }
  elseif cheatSheet.lineHeight ~= nil then
    text.cheatTitle = { lineHeight = cheatSheet.lineHeight }
  end
  return text
end

--- M.spec(policy) -> the style spec for lib/ui/style.lua.
function M.spec(policy)
  policy = policy or {}
  local cheatSheet = policy.cheatSheet or {}
  return {
    colors = { dark = colorsFor(policy, "dark"), light = colorsFor(policy, "light") },
    text = cheatText(cheatSheet),
    radius = {
      surface = (policy.surface or {}).cornerRadius,
      -- One radius shared on purpose by the cheat sheet badges and the hint bar badges,
      -- matching the settings comment.
      badge = cheatSheet.badgeRadius,
    },
  }
end

return M
