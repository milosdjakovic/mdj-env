--- The grid surface type, the webview host for the cheat sheet overlays.
---
--- Built on the shell engine like the searchable list, but display only. It draws
--- no rows of its own, it hosts a block of already positioned HTML the caller
--- builds (CheatSheet.spoon lays elements out with absolute coordinates), inside
--- the same frosted panel the list uses, themed from the same palette, so the
--- overlays and the pickers share one background and one look.
---
--- The shell is passive here, so the overlay never takes key focus and floats over
--- an open picker without stealing its search field, which is exactly what the
--- Hyper context peek sheet needs while the clipboard is open. The caller sizes
--- the panel, since it owns the layout math, and this type only wraps that block
--- in the themed panel and places it centered on screen.

local Grid = {}
Grid.__index = Grid

--------------------------------------------------------------------------------
-- Page template. BODY is inserted after token substitution, so its own text is
-- never rescanned for tokens. Colours come from the active theme side, matching
-- the list, so one palette drives both.
--------------------------------------------------------------------------------
local TEMPLATE = [==[
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  html,body { background:transparent; height:100%; overflow:hidden; }
  body { font-family:-apple-system,system-ui,sans-serif; -webkit-user-select:none; user-select:none; }
  .panel {
    position:relative;
    background:rgba({{BG}}, {{OPACITY}});
    -webkit-backdrop-filter:blur(30px) saturate(160%);
    backdrop-filter:blur(30px) saturate(160%);
    border:1px solid rgba({{BORDER}});
    border-radius:{{RADIUS}}px;
    overflow:hidden;
    color:{{FG}};
    font-size:{{FONTSIZE}}px;
  }
  .sec { position:absolute; left:0; top:0; right:0; bottom:0; }
  .badge {
    position:absolute; display:flex; align-items:center; justify-content:center;
    background:rgba({{BADGE}}); border-radius:{{BADGERADIUS}}px; color:{{FG}};
  }
  .sep { position:absolute; display:flex; align-items:center; justify-content:center; color:{{FG}}; }
  .label { position:absolute; display:flex; align-items:center; color:{{FG}}; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .title { position:absolute; display:flex; align-items:center; color:{{TITLE}}; letter-spacing:.04em; }
  .ico { position:absolute; object-fit:contain; }
  /* An offscreen focusable input. Keeping a real text field focused is what holds
     the frosted backdrop, which WebKit drops the moment focus leaves a text field,
     the same trick the Panel uses. Only matters when the overlay is activating; a
     passive peek never becomes key, so the field never takes focus, and the peek
     floats over an already frosted picker instead. */
  .sink { position:absolute; top:0; left:0; width:1px; height:1px; opacity:0; border:0; padding:0; background:transparent; }
</style>
<div class="panel" style="width:{{W}}px;height:{{H}}px;">{{BODY}}<input id="sink" class="sink" aria-hidden="true"></div>
<script>
(function(){ var s = document.getElementById('sink'); if (s) s.focus(); })();
</script>
]==]

--------------------------------------------------------------------------------
-- Colour helpers, the same two the list uses. Kept local here rather than shared,
-- since they are two lines and a shared util would be ceremony for that.
--------------------------------------------------------------------------------

local function hexRGB(hex)
  hex = tostring(hex):gsub("#", "")
  return string.format("%d, %d, %d",
    tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
end

local function whiteToCss(c)
  local w = math.floor(((c and c.white) or 0.9) * 255 + 0.5)
  return string.format("rgb(%d,%d,%d)", w, w, w)
end

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

--- Grid:render(spec) - show the overlay. spec.body is the positioned HTML block,
--- spec.w and spec.h its pixel size, spec.fontSize and spec.badgeRadius the
--- caller's content styling. The panel is placed centered on the main screen.
function Grid:render(spec)
  spec = spec or {}
  -- A standalone cheat sheet activates and focuses its sink so the backdrop holds.
  -- A peek over an open picker stays passive so it never steals the picker's focus,
  -- trading its own backdrop, which barely shows over the picker anyway.
  self.shell:setPassive(spec.passive and true or false)
  self.shell:selectTheme()
  local side = self.shell:activeSide()
  local dark = side.bgDark
  local pv = side.preview or {}
  local w, h = spec.w or 480, spec.h or 300
  local map = {
    BG = hexRGB(pv.bg or "#1e1e22"),
    OPACITY = "0.72",
    FG = pv.fg or whiteToCss(side.titleColor),
    TITLE = pv.meta or whiteToCss(side.subColor),
    BORDER = dark and "255,255,255,0.09" or "0,0,0,0.09",
    BADGE = dark and "255,255,255,0.12" or "0,0,0,0.08",
    RADIUS = "14",
    FONTSIZE = tostring(spec.fontSize or 16),
    BADGERADIUS = tostring(spec.badgeRadius or 6),
    W = tostring(w),
    H = tostring(h),
    BODY = spec.body or "",
  }
  local page = (TEMPLATE:gsub("{{(%w+)}}", map))
  self.shell:html(page)
  local f = hs.screen.mainScreen():frame()
  local floor = math.floor
  self.shell:show({
    x = f.x + floor((f.w - w) / 2),
    y = f.y + floor((f.h - h) / 2),
    w = w,
    h = h,
  })
end

function Grid:hide() self.shell:hide() end
function Grid:isShowing() return self.shell:isShowing() end
function Grid:activeSide() return self.shell:activeSide() end

--------------------------------------------------------------------------------
-- Factory
--------------------------------------------------------------------------------

local function new(config, deps)
  config = config or {}
  deps = deps or {}
  local self = setmetatable({}, Grid)
  -- clickAway off, the overlay is dismissed by releasing the held key, not by a
  -- click. Activation is decided per render via setPassive, so it is not fixed here.
  self.shell = deps.shell.new({
    name = config.name or "surfacegrid",
    theme = config.theme,
    clickAway = false,
  })
  return self
end

return { new = new }
