--- === Panel ===
---
--- A themed, keyboard driven webview list panel, the reusable mechanism behind the
--- keep awake tool and any similar short fixed list. It owns only the window, the
--- HTML and CSS, the up and down navigation and focus, the frosted backdrop, the
--- geometry, the click away dismissal, and the previous window restore. It knows
--- nothing about keep awake, VPN, or any tool. Each consumer injects its own rows,
--- the meaning of a selection, and a status supplier.
---
--- This is a FACTORY, not a singleton spoon. Call spoon.Panel.new(config) to get an
--- independent instance, so two tools never share one panel. The composition root
--- creates the instance, injects the theme and callbacks, and binds a Hyper context
--- to the navigation methods selectNext, selectPrev, and close.
---
--- Why a webview and not the Chooser atom. The chooser is a filterable list whose
--- rows are always numbered, right for a long searchable list like the clipboard but
--- wrong for a short fixed list of actions. A webview gives a small styled panel with
--- real form fields, so a row can carry a constrained inline entry, and it may take
--- keyboard focus, which a tool that pastes nothing back can do like a normal window.
---
--- Config, all optional unless noted.
---   name     the message bridge name, unique per tool so two panels never collide,
---            for example caffeinate or vpn. Defaults to panel.
---   theme    palette source with dark and light sides, each carrying bgDark and a
---            preview color set. Injected from config.
---   width    the panel width in points. Defaults to 380.
---   options  REQUIRED rows, each { id, label, entry }, where entry is nil for a plain
---            row, or duration or clock for a row that carries a small inline hours and
---            minutes field the panel builds and clamps. It may be a plain list, or a
---            function returning one, evaluated on each show so the rows can track live
---            state the way the status supplier does.
---   status   function returning the status line text shown at the top.
---   onApply  function(selection) called when a row is applied, returning nil on
---            success so the panel closes, or an error string so it stays open and
---            shows it. selection is { id, h, m }, with h and m present only for an
---            entry row.
---   onClose  called once when the panel closes.
---   footer   optional list of shortcut hints, each { badges = {...}, label = ... },
---            drawn as a wrapping chip bar under the rows so the panel shows its Hyper
---            shortcuts. Same shape the searchable list takes, stamped by withFooter in
---            the composition root. Omitted means no footer bar.

local obj = {}
obj.__index = obj
obj.name = "Panel"
obj.version = "1.0"
obj.author = "mdj-env"

local View = {}
View.__index = View

local DEFAULT_WIDTH = 380
local TOP_FRAC = 0.28

local FALLBACK = {
  bgDark = true,
  preview = { bg = "#1e1e22", fg = "#dcdcdc", meta = "#8a8a8a", path = "#7a7a7a", note = "#c8a86a" },
}

local function hexRGB(hex)
  hex = tostring(hex):gsub("#", "")
  return string.format("%d, %d, %d",
    tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
end

-- The page. Tokens in {{ }} are filled per show. The rows are a navigable list, the
-- active row carries a translucent highlight, and an entry row holds two constrained
-- number fields. The document level keydown listener drives navigation, so up and
-- down move the highlight even while a field is focused, and it focuses the active
-- row's field on every move. The BRIDGE token is the message handler name, so two
-- panels post to their own channels and never cross.
local TEMPLATE = [[
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { background: transparent; overflow: hidden; }
  body { font-family: -apple-system, system-ui, sans-serif; -webkit-user-select: none; user-select: none; }
  .panel {
    display: flex; flex-direction: column;
    background: rgba({{BG}}, 0.72);
    -webkit-backdrop-filter: blur(30px) saturate(160%);
    backdrop-filter: blur(30px) saturate(160%);
    border: 1px solid rgba({{BORDER}});
    border-radius: 14px;
    color: {{FG}};
    outline: none;
    overflow: hidden;
  }
  .content { padding: 14px; }
  .opts { display: flex; flex-direction: column; }
  .row {
    display: flex; align-items: center;
    padding: 9px 11px; border-radius: 8px;
    min-height: 38px;
  }
  .row.active { background: rgba({{ACTIVE}}); }
  .row .label { flex: 1; font-size: 14px; color: {{FG}}; }
  .entry { display: flex; align-items: center; gap: 5px; font-size: 14px; color: {{FG}}; }
  .entry input {
    width: 36px; text-align: center;
    background: rgba({{FIELDFILL}});
    border: 1px solid rgba({{FIELDBORDER}});
    border-radius: 6px; padding: 3px 0;
    font-size: 14px; color: {{FG}}; caret-color: {{FG}};
    outline: none;
    -webkit-user-select: text; user-select: text;
  }
  .entry input::placeholder { color: {{META}}; }
  .entry .u { color: {{META}}; }
  .status { margin-bottom: 12px; padding: 0 11px; font-size: 12px; color: {{FG}}; opacity: 0.7; }
  .status.error { color: #e0705a; opacity: 1; }
  /* The shortcut hint bar under the rows, the same chips the searchable list draws,
     so the fixed panels show their Hyper shortcuts too. Chips wrap onto more rows
     when the panel is too narrow, and the panel measure (see _fit) grows the window
     to fit. Hidden via the nofooter class when the consumer supplies no hints. */
  .footer {
    flex: 0 0 auto;
    display: flex; flex-wrap: wrap; align-items: center;
    gap: 8px 16px;
    padding: 9px 14px;
    border-top: 1px solid rgba({{BORDER}});
  }
  .panel.nofooter .footer { display: none; }
  .fhint { display: inline-flex; align-items: center; gap: 6px; white-space: nowrap; }
  .fhint .kbd {
    display: inline-flex; align-items: center; justify-content: center;
    padding: 2px 6px; border-radius: 5px;
    background: rgba({{BADGE}}); color: {{FG}};
    font-size: 11px; line-height: 1;
  }
  .fhint .flabel { color: {{META}}; font-size: 12px; }
  /* An offscreen but focusable input. Keeping a real text field focused on plain
     rows is what holds the frosted backdrop, which WebKit drops when focus is on a
     non text element. It absorbs stray keys harmlessly and is never read. */
  .sink { position: absolute; top: 0; left: 0; width: 1px; height: 1px; opacity: 0; border: 0; padding: 0; }
</style>
<div class="panel {{FOOTERCLASS}}">
  <div class="content">
    <div id="status" class="status">{{STATUS}}</div>
    <div class="opts" id="opts">{{ROWS}}</div>
    <input id="sink" class="sink" aria-hidden="true">
  </div>
  <div class="footer">{{FOOTER}}</div>
</div>
<script>
  var rows = Array.prototype.slice.call(document.querySelectorAll('.row'));
  var status = document.getElementById('status');
  var sink = document.getElementById('sink');
  var idx = 0;

  function post(p) { try { window.webkit.messageHandlers.{{BRIDGE}}.postMessage(p); } catch (e) {} }

  function focusActive() {
    var a = rows[idx];
    var hh = a.querySelector('.hh');
    // A field row focuses its hours. A plain row focuses the hidden sink input, so a
    // real text field always holds focus and the frosted backdrop never drops.
    if (hh) { hh.focus(); hh.select(); }
    else { sink.focus(); }
  }
  window.focusActive = focusActive;

  function highlight(i) {
    idx = Math.max(0, Math.min(rows.length - 1, i));
    for (var j = 0; j < rows.length; j++) { rows[j].classList.toggle('active', j === idx); }
    focusActive();
  }

  function apply() {
    var a = rows[idx];
    var msg = { action: 'apply', id: a.getAttribute('data-id') };
    if (a.getAttribute('data-entry')) {
      var hh = a.querySelector('.hh').value, mm = a.querySelector('.mm').value;
      msg.h = hh === '' ? 0 : parseInt(hh, 10);
      msg.m = mm === '' ? 0 : parseInt(mm, 10);
    }
    post(msg);
  }

  document.addEventListener('keydown', function (ev) {
    if (ev.key === 'ArrowDown') { ev.preventDefault(); highlight(idx + 1); }
    else if (ev.key === 'ArrowUp') { ev.preventDefault(); highlight(idx - 1); }
    else if (ev.key === 'Enter') { ev.preventDefault(); apply(); }
    else if (ev.key === 'Escape') { ev.preventDefault(); post({ action: 'close' }); }
  });

  function clampIn(inp) {
    var max = parseInt(inp.getAttribute('data-max'), 10);
    var v = inp.value.replace(/[^0-9]/g, '');
    if (v.length > 2) v = v.slice(0, 2);
    if (v !== '' && parseInt(v, 10) > max) v = String(max);
    inp.value = v;
  }
  Array.prototype.slice.call(document.querySelectorAll('.hh, .mm')).forEach(function (inp) {
    inp.addEventListener('input', function () {
      clampIn(inp);
      if (inp.classList.contains('hh') && inp.value.length === 2) {
        var mm = inp.parentNode.querySelector('.mm');
        if (mm) { mm.focus(); mm.select(); }
      }
    });
    inp.addEventListener('focus', function () { setTimeout(function () { inp.select(); }, 0); });
  });

  rows.forEach(function (r, i) {
    r.addEventListener('mousedown', function (ev) {
      idx = i;
      for (var j = 0; j < rows.length; j++) { rows[j].classList.toggle('active', j === idx); }
      if (!r.getAttribute('data-entry')) { ev.preventDefault(); apply(); }
    });
  });

  window.moveHighlight = function (d) { highlight(idx + d); };
  window.showError = function (t) { status.textContent = t; status.classList.add('error'); focusActive(); };
  window.setStatus = function (t) { status.textContent = t; status.classList.remove('error'); };
  window.addEventListener('DOMContentLoaded', function () { highlight(idx); });
  setTimeout(function () { highlight(idx); }, 20);
</script>
]]

--------------------------------------------------------------------------------
-- Theme, reselected on each show so the view tracks the live light and dark switch.
--------------------------------------------------------------------------------

function View:_selectTheme()
  local p = self.config.theme or {}
  local dark = hs.host.interfaceStyle() == "Dark"
  self.side = (dark and p.dark) or p.light or p.dark or FALLBACK
end

-- Build one row's HTML. A plain row is a label. An entry row adds two constrained
-- number fields, hours and minutes, whose data-max clamps them in the page. The
-- duration kind reads N hours and minutes, the clock kind reads a 24 hour time.
local function rowHtml(i, o)
  local entry = ""
  if o.entry == "duration" then
    entry = "<span class='entry'>"
      .. "<input class='hh' maxlength='2' data-max='99' inputmode='numeric' placeholder='00'>"
      .. "<span class='u'>h</span>"
      .. "<input class='mm' maxlength='2' data-max='59' inputmode='numeric' placeholder='00'>"
      .. "<span class='u'>m</span></span>"
  elseif o.entry == "clock" then
    entry = "<span class='entry'>"
      .. "<input class='hh' maxlength='2' data-max='23' inputmode='numeric' placeholder='00'>"
      .. "<span class='u'>:</span>"
      .. "<input class='mm' maxlength='2' data-max='59' inputmode='numeric' placeholder='00'></span>"
  end
  return string.format(
    "<div class='row' data-idx='%d' data-id='%s' data-entry='%s'><span class='label'>%s</span>%s</div>",
    i - 1, o.id, o.entry or "", o.label, entry)
end

-- Resolve the rows, allowing a supplier so a consumer can vary them by live state.
-- Called on each show, so the list is always current.
function View:_options()
  local o = self.config.options
  if type(o) == "function" then o = o() end
  return o or {}
end

-- Escape text bound for the footer html, since a key label could carry a glyph or a
-- character the browser would read as markup.
local function esc(s)
  return (tostring(s or "")
    :gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

-- The footer hints for this instance, or nil when the consumer supplied none. Same
-- shape and builder the searchable list uses, so the fixed panels and the lists draw
-- an identical shortcut bar from the same footerFor hints.
function View:_footer()
  local f = self.config.footer
  return (f and #f > 0) and f or nil
end

function View:_footerHtml()
  local hints = self:_footer()
  if not hints then return "" end
  local parts = {}
  for _, h in ipairs(hints) do
    local badges = {}
    for _, b in ipairs(h.badges or {}) do
      badges[#badges + 1] = '<span class="kbd">' .. esc(b) .. "</span>"
    end
    parts[#parts + 1] = '<span class="fhint">' .. table.concat(badges) ..
      '<span class="flabel">' .. esc(h.label or "") .. "</span></span>"
  end
  return table.concat(parts)
end

function View:_buildHtml()
  local pv = self.side.preview or FALLBACK.preview
  local dark = self.side.bgDark
  local rows = {}
  for i, o in ipairs(self:_options()) do
    rows[#rows + 1] = rowHtml(i, o)
  end
  local map = {
    BRIDGE = self.bridge,
    BG = hexRGB(pv.bg),
    FG = pv.fg,
    META = pv.meta,
    BORDER = dark and "255, 255, 255, 0.09" or "0, 0, 0, 0.09",
    ACTIVE = dark and "255, 255, 255, 0.10" or "0, 0, 0, 0.06",
    BADGE = dark and "255, 255, 255, 0.12" or "0, 0, 0, 0.08",
    FIELDFILL = dark and "255, 255, 255, 0.06" or "0, 0, 0, 0.04",
    FIELDBORDER = dark and "255, 255, 255, 0.13" or "0, 0, 0, 0.13",
    ROWS = table.concat(rows),
    FOOTER = self:_footerHtml(),
    FOOTERCLASS = self:_footer() and "" or "nofooter",
    STATUS = (self.config.status and self.config.status()) or "",
  }
  return (TEMPLATE:gsub("{{(%w+)}}", map))
end

--------------------------------------------------------------------------------
-- Geometry
--------------------------------------------------------------------------------

function View:_estHeight()
  local n = #(self:_options())
  -- Seed a one row footer estimate so the panel does not jump before _fit measures
  -- the real height, which includes any wrapped footer rows.
  local footer = self:_footer() and 34 or 0
  return 28 + n * 38 + 12 + 18 + 8 + footer
end

function View:_place(h)
  local sf = hs.screen.mainScreen():frame()
  self.frame = {
    x = sf.x + math.floor((sf.w - self.width) / 2),
    y = sf.y + math.floor(sf.h * TOP_FRAC),
    w = self.width,
    h = h,
  }
  self.wv:frame(self.frame)
end

function View:_fit()
  self.wv:evaluateJavaScript("document.querySelector('.panel').offsetHeight", function(res)
    local h = tonumber(res)
    if h and self.active then self:_place(h) end
  end)
end

--------------------------------------------------------------------------------
-- Click away dismissal
--------------------------------------------------------------------------------

function View:_startMouse()
  self.mouse = hs.eventtap.new(
    { hs.eventtap.event.types.leftMouseDown, hs.eventtap.event.types.rightMouseDown },
    function(e)
      if not self.active then return false end
      local p, fr = e:location(), self.frame
      local inside = fr and p.x >= fr.x and p.x <= fr.x + fr.w and p.y >= fr.y and p.y <= fr.y + fr.h
      if not inside then self:close() end
      return false
    end)
  self.mouse:start()
end

--------------------------------------------------------------------------------
-- Apply and lifecycle
--------------------------------------------------------------------------------

-- The page applied a row. Hand it to the policy, which returns nil on success
-- (close) or an error string (stay open and show it). Error strings are simple
-- ASCII, so %q is a safe JS string literal.
function View:_apply(sel)
  local err = self.config.onApply and self.config.onApply(sel)
  if err then
    self.wv:evaluateJavaScript(string.format("window.showError(%q)", err))
  else
    self:close()
  end
end

--- View:show() - reselect the theme, rebuild the page, place, reveal, and focus.
function View:show()
  if not self.wv then return end
  self:_selectTheme()
  -- Remember the window in front so close can hand focus back to it. Captured only
  -- on a fresh open, before this view takes focus, so a re-show does not record the
  -- webview itself.
  if not self.active then self.prevWindow = hs.window.focusedWindow() end
  self.active = true
  self:_place(self:_estHeight())
  self.wv:html(self:_buildHtml())
  self.wv:show()
  self.wv:bringToFront(true)
  hs.timer.doAfter(0.06, function()
    if not self.active then return end
    local win = self.wv:hswindow()
    if win then win:focus() end
    self.wv:evaluateJavaScript("window.focusActive && window.focusActive()")
    self:_fit()
  end)
  self:_startMouse()
end

--- View:selectNext() / View:selectPrev() - move the highlight down or up, so the
--- composition root can drive it from Hyper+j and Hyper+k the way it drives the
--- clipboard. The page keeps the index and focuses the landed row's field.
function View:selectNext()
  if self.active and self.wv then self.wv:evaluateJavaScript("window.moveHighlight && window.moveHighlight(1)") end
end

function View:selectPrev()
  if self.active and self.wv then self.wv:evaluateJavaScript("window.moveHighlight && window.moveHighlight(-1)") end
end

--- View:refresh() - update the status line while open (a live state changed).
function View:refresh()
  if self.active and self.wv then
    local s = (self.config.status and self.config.status()) or ""
    self.wv:evaluateJavaScript(string.format("window.setStatus(%q)", s))
  end
end

--- View:close() - hide (the webview is kept warm) and fire onClose once.
function View:close()
  if not self.active then return end
  self.active = false
  if self.mouse then self.mouse:stop(); self.mouse = nil end
  if self.wv then self.wv:hide() end
  -- Hand focus back to the window that had it, so the app is not just frontmost with
  -- no key window. On a click away dismissal the click itself lands afterward and
  -- wins, which is the intended target.
  if self.prevWindow then self.prevWindow:focus(); self.prevWindow = nil end
  if self.config.onClose then self.config.onClose() end
end

function View:isShowing()
  return self.active == true
end

--------------------------------------------------------------------------------
-- Factory
--------------------------------------------------------------------------------

--- spoon.Panel.new(config) -> panel instance. See the header for the config fields.
function obj.new(config)
  config = config or {}
  local self = setmetatable({
    config = config,
    bridge = config.name or "panel",
    width = config.width or DEFAULT_WIDTH,
    active = false,
  }, View)
  self:_selectTheme()

  local ucc = hs.webview.usercontent.new(self.bridge)
  ucc:setCallback(function(msg)
    local body = (msg and msg.body) or {}
    if body.action == "apply" then
      self:_apply(body)
    elseif body.action == "close" then
      self:close()
    end
  end)

  local wv = hs.webview.new({ x = 0, y = 0, w = self.width, h = 200 }, {}, ucc)
  wv:windowStyle(hs.webview.windowMasks.borderless)
  wv:level(hs.canvas.windowLevels.modalPanel)
  wv:transparent(true)
  wv:allowTextEntry(true)
  wv:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  self.wv = wv
  self.ucc = ucc
  return self
end

return obj
