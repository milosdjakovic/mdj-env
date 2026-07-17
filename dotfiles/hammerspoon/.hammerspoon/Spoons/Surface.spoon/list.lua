--- The searchable list surface type, the webview replacement for hs.chooser.
---
--- Built on the shell engine. This file owns the list page, its HTML, CSS, and
--- JS, the message protocol with that page, and the Lua side that feeds rows,
--- resolves row icons to data URIs lazily, and turns a chosen row back into the
--- consumer's callback. It keeps the same public contract the old Chooser atom
--- exposed, show, hide, isShowing, refresh, selectNext, selectPrev,
--- insertSelected, query, selectedItem, setFieldMode, setPlaceholder,
--- activeTheme, so a consumer is near drop in.
---
--- Filtering is client side by default, so typing is instant with no per
--- keystroke round trip. The supplier is called once per open (and on refresh)
--- for the full set, each row carrying a precomputed search string, so the page
--- can match substrings and an optional leading type token without reimplementing
--- any policy. Rendering is virtualized, only the rows in view plus a small
--- buffer exist in the DOM, which bounds both the DOM size and how many icons are
--- encoded at once, so a thousand row clipboard and the whole app list cost the
--- same as a short list.
---
--- Icons are resolved lazily. A row carries either an iconKey, a stable key into
--- the disk backed cache (bundle ids for apps), or an image, an hs.image the atom
--- encodes once and memoizes by identity (flags, thumbnails). The page asks for
--- the icons of the rows it is about to draw, the Lua side answers with data
--- URIs, and the page caches them, so encoding tracks the visible window.

local List = {}
List.__index = List

local DEFAULT_LAYOUT = {
  widthPct = 32,
  paneMaxW = 480,
  rowH = 44,
  headerH = 52,   -- search field row height
  visibleRows = 10,
  topFrac = 0.06,
  minVPad = 60,
  titleSize = 15,
  subSize = 12,
}

-- Type prefix map for the clipboard style "img ..." tokens. Injected per consumer
-- via config.typePrefixes; empty means the leading token is never special.
local EMPTY = {}

--------------------------------------------------------------------------------
-- Page template. Tokens in {{ }} are filled once at build. Colours come from the
-- active theme side. The list is a fixed height scroll region; a spacer sized to
-- the full filtered count gives a real scrollbar, and only the rows in the
-- viewport window are absolutely positioned inside it. A hidden but focusable
-- text field is the search box, which also holds the frosted backdrop the way
-- Panel's sink does. The document keydown drives navigation so arrows, Enter,
-- Escape, and Cmd plus a digit work while the field has focus.
--------------------------------------------------------------------------------
local TEMPLATE = [==[
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  html,body { background:transparent; overflow:hidden; height:100%; }
  body { font-family:-apple-system,system-ui,sans-serif; -webkit-user-select:none; user-select:none; }
  .panel {
    display:flex; flex-direction:column;
    height:100vh;
    background:rgba({{BG}}, {{OPACITY}});
    -webkit-backdrop-filter:blur(30px) saturate(160%);
    backdrop-filter:blur(30px) saturate(160%);
    border:1px solid rgba({{BORDER}});
    border-radius:{{RADIUS}}px;
    overflow:hidden;
    color:{{FG}};
  }
  .search {
    flex:0 0 {{HEADERH}}px;
    display:flex; align-items:center;
    padding:0 14px;
    border-bottom:1px solid rgba({{BORDER}});
  }
  .search input {
    width:100%; background:transparent; border:0; outline:none;
    font-size:16px; color:{{FG}}; caret-color:{{FG}};
    -webkit-user-select:text; user-select:text;
  }
  .search input::placeholder { color:{{META}}; }
  .scroll { flex:1 1 auto; position:relative; overflow-y:auto; overflow-x:hidden; }
  .spacer { position:relative; width:100%; }
  .row {
    position:absolute; left:0; right:0;
    display:flex; align-items:center;
    height:{{ROWH}}px; padding:0 12px;
  }
  .row.active { background:rgba({{ACTIVE}}); }
  .row .icon { flex:0 0 22px; width:22px; height:22px; margin-right:10px; }
  .row .icon img { width:100%; height:100%; object-fit:contain; }
  .row .text { flex:1 1 auto; min-width:0; }
  .row .title { font-size:{{TITLESIZE}}px; color:{{FG}}; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .row.disabled .title { opacity:0.4; }
  .row .sub { font-size:{{SUBSIZE}}px; color:{{META}}; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; margin-top:1px; }
  .row .num { flex:0 0 auto; margin-left:8px; font-size:11px; color:{{META}}; opacity:0.7; }
  .empty { padding:18px 14px; font-size:13px; color:{{META}}; }
</style>
<div class="panel">
  <div class="search"><input id="q" type="text" placeholder="{{PLACEHOLDER}}" autocomplete="off" spellcheck="false"></div>
  <div class="scroll" id="scroll"><div class="spacer" id="spacer"></div></div>
</div>
<script>
window.onerror = function(msg, src, line){ window.__err = msg + ' @' + line; return false; };
(function(){
  var ROWH = {{ROWH}};
  var BUFFER = 6;                 // rows rendered above and below the viewport
  var data = [];                  // full dataset, each {i,title,sub,key,enabled,search,kind}
  var view = [];                  // indices into data that pass the current filter
  var sel = 0;                    // position within view
  var icons = {};                 // key -> data URI, filled by the Lua side
  var pending = {};               // keys already requested, to avoid re-asking
  var fieldMode = "{{FIELDMODE}}";
  var prefixes = {{PREFIXES}};    // {token: kind} for the leading type filter
  var pool = [];                  // reused row elements (virtualization)
  var q = document.getElementById('q');
  var scroll = document.getElementById('scroll');
  var spacer = document.getElementById('spacer');

  function post(p){ try { window.webkit.messageHandlers.{{BRIDGE}}.postMessage(p); } catch(e){} }

  // Parse an optional leading type token, "img foo" -> {kind:'image', rest:'foo'}.
  function parse(text){
    var m = text.match(/^(\w+)[:\s]\s*(.*)$/);
    if (m && prefixes[m[1].toLowerCase()]) return { kind: prefixes[m[1].toLowerCase()], rest: m[2] };
    return { kind: null, rest: text };
  }

  function filter(){
    var p = parse(q.value || "");
    var needle = p.rest.trim().toLowerCase();
    view = [];
    for (var k=0;k<data.length;k++){
      var d = data[k];
      if (p.kind && d.kind !== p.kind) continue;
      if (needle === "" || d.search.indexOf(needle) !== -1) view.push(k);
    }
    if (sel >= view.length) sel = Math.max(0, view.length - 1);
    spacer.style.height = (view.length * ROWH) + "px";
    render();
    emitHighlight();
  }

  function requestIcons(keys){
    var want = [];
    for (var i=0;i<keys.length;i++){
      var key = keys[i];
      if (key && icons[key] === undefined && !pending[key]) { pending[key] = true; want.push(key); }
    }
    if (want.length) post({ action:"icons", keys: want });
  }

  function rowEl(n){
    if (pool[n]) return pool[n];
    var el = document.createElement('div');
    el.className = 'row';
    el.innerHTML = '<span class="icon"></span><span class="text"><div class="title"></div><div class="sub"></div></span><span class="num"></span>';
    el.addEventListener('mousedown', function(ev){ ev.preventDefault(); if (el._pos != null){ sel = el._pos; activate(); } });
    scroll.appendChild(el);
    pool[n] = el;
    return el;
  }

  function render(){
    var top = scroll.scrollTop;
    var first = Math.max(0, Math.floor(top / ROWH) - BUFFER);
    var visible = Math.ceil(scroll.clientHeight / ROWH) + BUFFER * 2;
    var last = Math.min(view.length - 1, first + visible);
    var needKeys = [];
    var n = 0;
    for (var pos=first; pos<=last; pos++){
      var d = data[view[pos]];
      var el = rowEl(n++);
      el.style.display = 'flex';
      el.style.top = (pos * ROWH) + 'px';
      el._pos = pos;
      el.className = 'row' + (pos === sel ? ' active' : '') + (d.enabled === false ? ' disabled' : '');
      el.querySelector('.title').textContent = d.title || '';
      el.querySelector('.sub').textContent = d.sub || '';
      el.querySelector('.num').textContent = pos < 9 ? ('⌘' + (pos + 1)) : '';
      var icoWrap = el.querySelector('.icon');
      if (d.key && icons[d.key]) icoWrap.innerHTML = '<img src="' + icons[d.key] + '">';
      else { icoWrap.innerHTML = ''; if (d.key) needKeys.push(d.key); }
    }
    for (; n<pool.length; n++){ if (pool[n]) pool[n].style.display = 'none'; }
    if (!view.length){ /* empty handled by leaving rows hidden */ }
    if (needKeys.length) requestIcons(needKeys);
  }

  function ensureVisible(){
    var y = sel * ROWH;
    var top = scroll.scrollTop, h = scroll.clientHeight;
    if (y < top) scroll.scrollTop = y;
    else if (y + ROWH > top + h) scroll.scrollTop = y + ROWH - h;
  }

  function move(delta){
    if (!view.length) return;
    sel = Math.max(0, Math.min(view.length - 1, sel + delta));
    ensureVisible(); render(); emitHighlight();
  }

  function emitHighlight(){
    var d = view.length ? data[view[sel]] : null;
    post({ action:"highlight", index: d ? d.i : -1 });
  }

  function activate(){
    if (fieldMode === "input" || (fieldMode === "hybrid" && (q.value||"") !== "")){
      post({ action:"input", text: q.value || "" }); return;
    }
    var d = view.length ? data[view[sel]] : null;
    post({ action:"select", index: d ? d.i : -1 });
  }

  scroll.addEventListener('scroll', function(){ render(); });

  document.addEventListener('keydown', function(ev){
    if (ev.key === 'ArrowDown'){ ev.preventDefault(); move(1); }
    else if (ev.key === 'ArrowUp'){ ev.preventDefault(); move(-1); }
    else if (ev.key === 'Enter'){ ev.preventDefault(); activate(); }
    else if (ev.key === 'Escape'){ ev.preventDefault(); post({ action:"close" }); }
    else if (ev.metaKey && ev.key >= '1' && ev.key <= '9'){
      ev.preventDefault();
      var want = parseInt(ev.key, 10) - 1;
      if (want < view.length){ sel = want; ensureVisible(); render(); emitHighlight(); activate(); }
    }
  });
  q.addEventListener('input', function(){ if (fieldMode !== "off") filter(); });

  // Lua entry points.
  window.__setRows = function(rows){
    data = rows || []; sel = 0; scroll.scrollTop = 0; filter();
  };
  window.__setIcons = function(map){
    for (var key in map){ icons[key] = map[key]; delete pending[key]; }
    render();
  };
  window.__move = function(d){ move(d); };
  window.__activate = function(){ activate(); };
  window.__focus = function(){ q.focus(); };

  q.focus();
  // Tell the Lua side the page is parsed and the entry points exist, so it can
  // push the dataset. This replaces guessing a delay after html().
  post({ action:"ready" });
})();
</script>
]==]

--------------------------------------------------------------------------------
-- Colour helpers
--------------------------------------------------------------------------------

local function hexRGB(hex)
  hex = tostring(hex):gsub("#", "")
  return string.format("%d, %d, %d",
    tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
end

-- A styledtext white value maps to a CSS rgb grey. The chooser theme states row
-- colours as styledtext white values, so reuse them for the webview.
local function whiteToCss(c)
  local w = math.floor(((c and c.white) or 0.9) * 255 + 0.5)
  return string.format("rgb(%d,%d,%d)", w, w, w)
end

-- Serialize a Lua value to a compact JSON literal for embedding in the page.
local function json(v)
  return hs.json.encode(v)
end

--------------------------------------------------------------------------------
-- Icon resolution. iconKey hits the disk cache; an hs.image is encoded once and
-- memoized by identity so flags and thumbnails are not re-encoded each open.
--------------------------------------------------------------------------------

function List:_iconURI(key, image)
  if key and self.iconcache then
    local uri = self.iconcache.dataURI(key)
    if uri then return uri end
  end
  if image then
    local hit = self.imgMemo[image]
    if hit == nil then
      hit = image:encodeAsURLString() or false
      self.imgMemo[image] = hit
    end
    return hit or nil
  end
  return nil
end

--------------------------------------------------------------------------------
-- Build the page dataset from the supplier. Each row gets a stable index, a
-- precomputed lowercase search string, an icon key, and the opaque item kept on
-- the Lua side. The image itself is not sent, only a key the page asks back for.
--------------------------------------------------------------------------------

function List:_buildDataset(query)
  local items = self.config.rows and self.config.rows(query) or {}
  local out = {}
  self.items = {}
  self.iconByKey = {} -- key -> {image} so an icon request can resolve to a URI
  for i = 1, #items do
    local it = items[i]
    local key = it.iconKey
    -- An hs.image with no explicit key gets a synthetic one so the page can ask
    -- for it and the Lua side can find the image to encode.
    if not key and it.image then
      key = "img#" .. i
      self.iconByKey[key] = it.image
    elseif key and it.image then
      self.iconByKey[key] = it.image
    end
    local search = (it.search or ((it.title or "") .. " " .. (it.subTitle or ""))):lower()
    out[i] = {
      i = i,
      title = it.title or "",
      sub = it.subTitle or "",
      key = key,
      enabled = it.enabled ~= false,
      search = search,
      kind = it.kind,
    }
    self.items[i] = it.item
    self.itemEnabled = self.itemEnabled or {}
    self.itemEnabled[i] = it.enabled ~= false
  end
  return out
end

--------------------------------------------------------------------------------
-- Message handling from the page
--------------------------------------------------------------------------------

function List:_onMessage(body)
  local a = body.action
  if a == "ready" then
    -- The page is parsed; push the dataset built at show. Focus the field too,
    -- since the reload may have dropped it.
    if self.dataset then
      self.shell:eval("window.__setRows(" .. json(self.dataset) .. ")")
    end
    self.shell:eval("window.__focus()")
  elseif a == "highlight" then
    self.highlightIndex = body.index
    if self.config.onHighlight then
      self.config.onHighlight(body.index and body.index >= 1 and self.items[body.index] or nil)
    end
  elseif a == "select" then
    self:_complete(body.index)
  elseif a == "input" then
    self:_completeInput(body.text)
  elseif a == "icons" then
    self:_answerIcons(body.keys)
  elseif a == "close" then
    self:hide()
  end
end

function List:_answerIcons(keys)
  if not keys then return end
  local map = {}
  for _, key in ipairs(keys) do
    local uri = self:_iconURI(key, self.iconByKey[key])
    if uri then map[key] = uri end
  end
  if next(map) then
    self.shell:eval("window.__setIcons(" .. json(map) .. ")")
  end
end

-- A row was chosen. Restore focus first by hiding, then fire onSelect deferred so
-- the action, a paste in the clipboard's case, lands in the window that was
-- frontmost before the surface opened. onSelect runs only for an enabled row.
function List:_complete(index)
  local item = index and index >= 1 and self.items[index] or nil
  local enabled = index and index >= 1 and (self.itemEnabled and self.itemEnabled[index] ~= false)
  self:hide()
  if item and enabled and self.config.onSelect then
    hs.timer.doAfter(0.05, function() self.config.onSelect(item) end)
  end
end

function List:_completeInput(text)
  self:hide()
  if self.config.onInput then
    hs.timer.doAfter(0.05, function() self.config.onInput(text) end)
  end
end

--------------------------------------------------------------------------------
-- Geometry and show
--------------------------------------------------------------------------------

function List:_frame()
  local L = self.layout
  local f = hs.screen.mainScreen():frame()
  local w = math.min(math.floor(f.w * L.widthPct / 100), L.paneMaxW)
  local h = L.headerH + L.visibleRows * L.rowH + 2 -- +2 for the header border
  return self.shell:placeCentered(w, h, L.topFrac, L.minVPad)
end

function List:_buildPage()
  local side = self.shell:activeSide()
  local dark = side.bgDark
  local pv = side.preview or {}
  local L = self.layout
  local map = {
    BRIDGE = self.shell.bridge,
    BG = hexRGB(pv.bg or "#1e1e22"),
    OPACITY = "0.72",
    FG = pv.fg or whiteToCss(side.titleColor),
    META = pv.meta or whiteToCss(side.subColor),
    BORDER = dark and "255,255,255,0.09" or "0,0,0,0.09",
    ACTIVE = dark and "255,255,255,0.10" or "0,0,0,0.06",
    RADIUS = "14",
    HEADERH = tostring(L.headerH),
    ROWH = tostring(L.rowH),
    TITLESIZE = tostring(L.titleSize),
    SUBSIZE = tostring(L.subSize),
    PLACEHOLDER = (self.config.placeholder or ""):gsub('"', "'"),
    FIELDMODE = self.fieldMode,
    PREFIXES = json(self.config.typePrefixes or EMPTY),
  }
  return (TEMPLATE:gsub("{{(%w+)}}", map))
end

--- List:show() - reselect the theme, rebuild the page and dataset, place, reveal.
--- The dataset is stored and pushed when the page reports ready (see _onMessage),
--- so nothing races a fixed delay after html().
function List:show()
  self.shell:selectTheme()
  self.dataset = self:_buildDataset("")
  self.shell:html(self:_buildPage())
  self.shell:show(self:_frame())
end

--------------------------------------------------------------------------------
-- Public contract, matching the old Chooser atom
--------------------------------------------------------------------------------

function List:hide() self.shell:hide() end
function List:close() self.shell:hide() end
function List:isShowing() return self.shell:isShowing() end

function List:refresh()
  if not self:isShowing() then return end
  local ds = self:_buildDataset(self.lastQuery or "")
  self.shell:eval("window.__setRows(" .. json(ds) .. ")")
end

function List:selectNext() self.shell:eval("window.__move(1)") end
function List:selectPrev() self.shell:eval("window.__move(-1)") end
function List:insertSelected() self.shell:eval("window.__activate()") end

function List:selectedItem()
  local i = self.highlightIndex
  return (i and i >= 1) and self.items[i] or nil
end

function List:setFieldMode(mode) self.fieldMode = mode or "filter" end
function List:setPlaceholder(text) self.config.placeholder = text or "" end
function List:activeTheme() return self.shell:activeSide() end
function List:query() return self.lastQuery or "" end

--------------------------------------------------------------------------------
-- Factory
--------------------------------------------------------------------------------

local function new(config, deps)
  config = config or {}
  deps = deps or {}
  local layout = {}
  for k, v in pairs(DEFAULT_LAYOUT) do layout[k] = v end
  for k, v in pairs(config.layout or {}) do layout[k] = v end

  local self = setmetatable({
    config = config,
    layout = layout,
    fieldMode = config.fieldMode or "filter",
    iconcache = deps.iconcache,
    imgMemo = {},
    items = {},
    highlightIndex = nil,
    lastQuery = "",
  }, List)

  self.shell = deps.shell.new({
    name = config.name or "surfacelist",
    theme = config.theme,
    onMessage = function(body) self:_onMessage(body) end,
    onClose = function() if config.onClose then config.onClose() end end,
  })

  return self
end

return { new = new }
