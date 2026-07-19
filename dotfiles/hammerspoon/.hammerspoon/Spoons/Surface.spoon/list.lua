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
  iconSize = 34,  -- leading row icon box, points
  numSize = 16,   -- the Cmd digit badge font size, points
  previewWidth = 0, -- 0 leaves the list single column; a positive width adds a
                    -- preview pane on the right, the clipboard split, inside the
                    -- same window. The consumer fills it through setPreview.
  footerH = 36,   -- the one row estimate for the shortcut hint bar, points; the
                  -- page measures the real height (it wraps) and the window grows
                  -- to fit. Only reserved when the consumer supplies footer hints.
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
  /* The body is the list beside its optional preview; the footer sits below both,
     spanning the full width, so the shortcut hints read as one bar under the whole
     surface rather than under just the list column. */
  .body { display:flex; flex-direction:row; flex:1 1 auto; min-height:0; }
  .listcol { display:flex; flex-direction:column; flex:1 1 auto; min-width:0; }
  /* Transparent so the panel's one frosted backdrop shows through here too, rather
     than painting a solid block beside the translucent list. The list and its
     preview then read as the same surface. */
  .preview {
    flex:0 0 {{PREVIEWW}}px;
    overflow:auto;
    border-left:1px solid rgba({{BORDER}});
    background:transparent;
    color:{{FG}};
  }
  .panel.nosplit .preview { display:none; }
  #preview .wrap { padding:16px; box-sizing:border-box; }
  #preview .meta { color:{{META}}; font-size:11px; margin-bottom:10px; text-transform:uppercase; letter-spacing:.04em; }
  #preview .path { color:{{PVPATH}}; font-size:11px; margin-bottom:6px; word-break:break-all; }
  #preview .note { color:{{PVNOTE}}; }
  #preview pre { white-space:pre-wrap; word-break:break-word; margin:0; color:{{FG}}; font:14px/1.5 -apple-system,BlinkMacSystemFont,Menlo,monospace; }
  #preview img { max-width:100%; height:auto; border-radius:8px; margin-top:8px; }
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
  .row .icon { position:relative; flex:0 0 {{ICONSIZE}}px; width:{{ICONSIZE}}px; height:{{ICONSIZE}}px; margin-right:12px; }
  .row .icon img { width:100%; height:100%; object-fit:contain; }
  /* Order badge for a collected row: a pill centered over the icon, drawn in the
     same translucent material as the panel (same colour, opacity, and blur) so it
     reads as the frosted surface laid over the icon. Absolute so it never affects
     the row's width, which is what kept the title from shifting. */
  .row .icon .badge {
    position:absolute; top:50%; left:50%; transform:translate(-50%, -50%);
    min-width:18px; height:18px; padding:0 4px; box-sizing:border-box;
    border-radius:9px; background:rgba({{BG}}, {{OPACITY}}); color:{{FG}};
    -webkit-backdrop-filter:blur(30px) saturate(160%);
    backdrop-filter:blur(30px) saturate(160%);
    font-size:11px; font-weight:700; line-height:18px; text-align:center;
  }
  .row .text { flex:1 1 auto; min-width:0; }
  .row .title { font-size:{{TITLESIZE}}px; color:{{FG}}; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .row.disabled .title { opacity:0.4; }
  .row .sub { font-size:{{SUBSIZE}}px; color:{{META}}; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; margin-top:1px; }
  .row .num { flex:0 0 auto; margin-left:10px; font-size:{{NUMSIZE}}px; font-weight:400; color:{{META}}; }
  .empty { padding:18px 14px; font-size:13px; color:{{META}}; }
  /* The shortcut hint bar. Chips of a key badge (or two) and a label, laid out
     left to right and wrapping onto more rows when the surface is too narrow to
     hold them in one, so a narrow picker never clips them. The bar grows with the
     rows it needs; the page measures its height and the Lua side grows the window
     to fit (see the footerHeight message). Absent when the consumer supplies no
     hints, via the nofooter class. */
  .footer {
    flex:0 0 auto;
    display:flex; flex-wrap:wrap; align-items:center;
    gap:8px 16px;
    padding:9px 14px;
    border-top:1px solid rgba({{BORDER}});
  }
  .panel.nofooter .footer { display:none; }
  .fhint { display:inline-flex; align-items:center; gap:6px; white-space:nowrap; }
  .fhint .kbd {
    display:inline-flex; align-items:center; justify-content:center;
    padding:2px 6px; border-radius:5px;
    background:rgba({{BADGE}}); color:{{FG}};
    font-size:11px; line-height:1;
  }
  .fhint .flabel { color:{{META}}; font-size:12px; }
</style>
<div class="panel {{SPLITCLASS}} {{FOOTERCLASS}}">
  <div class="body">
    <div class="listcol">
      <div class="search"><input id="q" type="text" placeholder="{{PLACEHOLDER}}" autocomplete="off" spellcheck="false"></div>
      <div class="scroll" id="scroll"><div class="spacer" id="spacer"></div></div>
    </div>
    <div class="preview" id="preview"><div class="wrap" id="pvwrap"></div></div>
  </div>
  <div class="footer" id="footer">{{FOOTER}}</div>
</div>
<script>
window.onerror = function(msg, src, line){ window.__err = msg + ' @' + line; return false; };
(function(){
  var ROWH = {{ROWH}};
  var BUFFER = 6;                 // rows rendered above and below the viewport
  var data = [];                  // full dataset, each {i,title,sub,key,enabled,search,kind,badge}
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
  var pvwrap = document.getElementById('pvwrap');

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
    el.innerHTML = '<span class="icon"><img><span class="badge"></span></span><span class="text"><div class="title"></div><div class="sub"></div></span><span class="num"></span>';
    el.addEventListener('mousedown', function(ev){ if (ev.button === 2) return; ev.preventDefault(); if (el._pos != null){ sel = el._pos; activate(); } });
    el.addEventListener('contextmenu', function(ev){ ev.preventDefault(); if (el._pos != null){ sel = el._pos; render(); emitHighlight(); var d = data[view[sel]]; post({ action:"rightclick", index: d ? d.i : -1 }); } });
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
      var img = icoWrap.querySelector('img');
      if (d.key && icons[d.key]) { img.src = icons[d.key]; img.style.display = ''; }
      else { img.removeAttribute('src'); img.style.display = 'none'; if (d.key) needKeys.push(d.key); }
      var badge = icoWrap.querySelector('.badge');
      if (d.badge != null && d.badge !== '') { badge.textContent = d.badge; badge.style.display = ''; }
      else { badge.style.display = 'none'; }
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

  // Keep the search field focused for as long as the window is key, so the frosted
  // backdrop, which WebKit renders only for the key window with a focused text field,
  // never drops on its own. If the field blurs while the document still has focus,
  // something inside the page pulled it (a click on the scroll gutter, the footer, or
  // the preview), so take it back. If the document has lost focus the window is no
  // longer key, the user moved to another app, so leave it be and let the click
  // watcher dismiss the surface. The window focus handler covers the case where the
  // window loses then regains key while still open, which is the drop the user could
  // not otherwise catch.
  q.addEventListener('blur', function(){ setTimeout(function(){ if (document.hasFocus()) q.focus(); }, 0); });
  window.addEventListener('focus', function(){ q.focus(); });

  // Lua entry points.
  // keepSel holds the highlight where it is, for a refresh that redraws rows in
  // place (the clipboard append badge). Without it a refresh jumps to the top.
  window.__setRows = function(rows, keepSel){
    data = rows || [];
    if (!keepSel){ sel = 0; scroll.scrollTop = 0; }
    filter();
    if (keepSel){ ensureVisible(); render(); }
  };
  window.__setIcons = function(map){
    for (var key in map){ icons[key] = map[key]; delete pending[key]; }
    render();
  };
  // Fill the preview pane of a split surface. Inner html only; the page owns the
  // pane's chrome and theme, so the consumer sends just the body fragment.
  window.__setPreview = function(html){ if (pvwrap) pvwrap.innerHTML = html || ''; };
  // Scroll the preview pane by a pixel delta, so a long clipboard entry that
  // overflows the pane can be read without the mouse. The pane (#preview) is the
  // scroll container; #pvwrap is only its content. A no op when there is no pane.
  var pv = document.getElementById('preview');
  window.__scrollPreview = function(dy){ if (pv) pv.scrollTop += dy; };
  // Replace the footer chips live, for a consumer whose shortcut labels change with
  // state (the clipboard's Delete becoming "Delete marked"). Re-report the height,
  // since a longer label can wrap the bar onto another row and the window regrows.
  window.__setFooter = function(html){ var f = document.getElementById('footer'); if (f){ f.innerHTML = html || ''; reportFooter(); } };
  window.__move = function(d){ move(d); };
  window.__activate = function(){ activate(); };
  window.__focus = function(){ q.focus(); };

  // The footer chips wrap to as many rows as the width needs, so the bar's height
  // is not known until the page has laid out at the real window width. Report it,
  // on load and on any resize, so the Lua side can grow the window to fit the
  // wrapped rows instead of clipping them. A hidden footer (nofooter) has no
  // offset parent, so it reports zero and the Lua side leaves the height alone.
  function reportFooter(){
    var f = document.getElementById('footer');
    post({ action:"footerHeight", h: (f && f.offsetParent !== null) ? f.offsetHeight : 0 });
  }
  window.addEventListener('resize', reportFooter);

  q.focus();
  // Report the footer height first, then ready. The Lua side processes messages in
  // order, so it learns the real footer height before the ready handler computes the
  // reveal frame, and the window opens already sized to the footer's wrapped rows
  // rather than revealing at the estimate and then resizing while visible.
  reportFooter();
  // Tell the Lua side the page is parsed and the entry points exist, so it can
  // reveal the window and push the dataset. Carries the generation so a stale ready
  // from a page already replaced by a newer show is ignored. This replaces guessing
  // a delay after html() and reveals only once the new content has painted, so the
  // previous open's still-painted DOM never flashes.
  post({ action:"ready", gen:{{GEN}} });
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

-- Escape text bound for the footer html, since a key label could carry a glyph or
-- a character the browser would read as markup.
local function esc(s)
  return (tostring(s or "")
    :gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
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
  -- A consumer-provided (stable) key memoizes the encoded uri by the key itself, so
  -- an icon survives its hs.image being rebuilt (a churned app-bundle image, a
  -- regenerated clipboard thumbnail) without re-encoding on the main thread or
  -- growing a per-image memo without bound. Synthetic per-index keys are not stable
  -- across opens, so they fall back to memoizing by image identity.
  if key and self.iconStable[key] then
    local hit = self.uriByKey[key]
    if hit == nil then
      hit = (image and image:encodeAsURLString()) or false
      self.uriByKey[key] = hit
    end
    return hit or nil
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
    elseif key then
      if it.image then self.iconByKey[key] = it.image end
      -- A consumer key is stable across opens, so its encoded uri is memoized by
      -- the key in _iconURI rather than by the (rebuildable) image object.
      self.iconStable[key] = true
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
      -- Optional short text drawn as an overlay badge on the row icon. Generic:
      -- the atom only renders it, the consumer decides what it means (the
      -- clipboard puts the append-batch position here).
      badge = it.badge,
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
    -- The page parsed and painted; reveal it now, then push the rows and focus. The
    -- reveal is gated on this handshake rather than fired at show() so the previous
    -- open's still-painted DOM never flashes. _reveal carries the row push and focus,
    -- shared with the fallback path, and ignores a stale generation.
    self:_reveal(body.gen)
  elseif a == "highlight" then
    self.highlightIndex = body.index
    if self.config.onHighlight then
      self.config.onHighlight(body.index and body.index >= 1 and self.items[body.index] or nil)
    end
  elseif a == "select" then
    self:_complete(body.index)
  elseif a == "input" then
    self:_completeInput(body.text)
  elseif a == "rightclick" then
    local item = body.index and body.index >= 1 and self.items[body.index] or nil
    if item and self.config.onRightClick then
      self.config.onRightClick(item, body.index)
    end
  elseif a == "icons" then
    self:_answerIcons(body.keys)
  elseif a == "footerHeight" then
    self:_applyFooterHeight(body.h)
  elseif a == "close" then
    self:hide()
  end
end

-- The page reported the footer's rendered height, which depends on how many rows
-- the chips wrapped into at the current width. Grow or shrink the window to fit it
-- exactly, keeping it centered. Guarded so a measurement equal to the reserved
-- height does nothing, which also stops the resize event the growth itself fires
-- from looping. The measured height is kept across opens as the next estimate, so
-- only the first open of a narrow picker grows visibly.
function List:_applyFooterHeight(h)
  if not self:_footer() or not h or h <= 0 or h == self._footerH then return end
  self._footerH = h
  if self:isShowing() then self.shell:setFrame(self:_frame()) end
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

-- Preview pane width for this instance, capped like the list itself, or 0 when
-- the surface is a single column list.
function List:_previewW()
  local L = self.layout
  local pw = L.previewWidth or 0
  return pw > 0 and math.min(pw, L.paneMaxW) or 0
end

-- The footer hints for this instance, or nil when the consumer supplied none.
function List:_footer()
  local f = self.config.footer
  return (f and #f > 0) and f or nil
end

-- Build the footer bar's inner html from the hints, each a chip of one or two key
-- badges and a label. Reuses the same badge strings the cheat sheet builds, so the
-- footer and the overlays never drift.
function List:_footerHtml()
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

function List:_frame()
  local L = self.layout
  local f = hs.screen.mainScreen():frame()
  local listW = math.min(math.floor(f.w * L.widthPct / 100), L.paneMaxW)
  local w = listW + self:_previewW() -- the +1px divider is absorbed by the border
  local h = L.headerH + L.visibleRows * L.rowH + 2 -- +2 for the header border
  -- Reserve the footer's height: the measured value once the page has reported it,
  -- else the one row estimate. The page corrects it after layout (footerHeight).
  if self:_footer() then h = h + (self._footerH or L.footerH) end
  return self.shell:placeCentered(w, h, L.topFrac, L.minVPad)
end

function List:_buildPage()
  local side = self.shell:activeSide()
  local dark = side.bgDark
  local pv = side.preview or {}
  local L = self.layout
  local pvW = self:_previewW()
  local map = {
    BRIDGE = self.shell.bridge,
    GEN = tostring(self._gen or 0),
    BG = hexRGB(pv.bg or "#1e1e22"),
    OPACITY = "0.72",
    FG = pv.fg or whiteToCss(side.titleColor),
    META = pv.meta or whiteToCss(side.subColor),
    BORDER = dark and "255,255,255,0.09" or "0,0,0,0.09",
    ACTIVE = dark and "255,255,255,0.10" or "0,0,0,0.06",
    BADGE = dark and "255,255,255,0.12" or "0,0,0,0.08",
    RADIUS = "14",
    HEADERH = tostring(L.headerH),
    FOOTER = self:_footerHtml(),
    FOOTERCLASS = self:_footer() and "" or "nofooter",
    ROWH = tostring(L.rowH),
    TITLESIZE = tostring(L.titleSize),
    SUBSIZE = tostring(L.subSize),
    ICONSIZE = tostring(L.iconSize),
    NUMSIZE = tostring(L.numSize),
    PLACEHOLDER = (self.config.placeholder or ""):gsub('"', "'"),
    FIELDMODE = self.fieldMode,
    PREFIXES = json(self.config.typePrefixes or EMPTY),
    -- Split preview tokens. Width 0 with the nosplit class keeps the pane hidden,
    -- so a plain list and the clipboard split share one page.
    PREVIEWW = tostring(pvW),
    SPLITCLASS = pvW > 0 and "split" or "nosplit",
    PVPATH = pv.path or pv.meta or "#7a7a7a",
    PVNOTE = pv.note or "#c8a86a",
  }
  return (TEMPLATE:gsub("{{(%w+)}}", map))
end

--- List:show() - reselect the theme, rebuild the page, and load it, but hold the
--- reveal until the page reports it has parsed (see _reveal), so the previous open's
--- still-painted DOM never flashes while the new page loads. The webview is reused
--- warm across opens, which is exactly why an immediate reveal showed the stale
--- content, the flicker this mirrors Grid to fix. A generation counter tags this
--- open so a stale ready or fallback from a page already replaced is ignored, and a
--- fallback timer reveals anyway should a hidden webview ever delay the handshake.
function List:show()
  self.shell:selectTheme()
  self._gen = (self._gen or 0) + 1
  self.dataset = self:_buildDataset("")
  self._pending = { gen = self._gen, frame = self:_frame() }
  -- Size the still hidden webview to the final width before loading the page, so the
  -- footer measures its real wrap at the true width instead of at whatever width the
  -- warm webview was left at, which reported a taller footer and forced a visible
  -- resize once the reveal placed it at the correct width.
  self.shell:setFrame(self._pending.frame)
  self.shell:html(self:_buildPage())
  if self._fallback then self._fallback:stop() end
  local gen = self._gen
  self._fallback = hs.timer.doAfter(0.2, function() self:_reveal(gen) end)
end

--- List:_reveal(gen) - show the pending frame, then push the dataset and focus the
--- field, but only for the current generation, so a stale ready or fallback from an
--- open already replaced by a newer one is ignored and each generation reveals once.
--- Revealing first makes the window key so the guarded shell:eval that pushes the
--- rows and focuses lands, and the dataset is rebuilt from the supplier here rather
--- than replayed from the show-time snapshot, so rows that arrived between show and
--- ready (an async location list) are included instead of lost to the handshake race.
function List:_reveal(gen)
  local pending = self._pending
  if not pending or gen ~= pending.gen or self._revealedGen == gen then return end
  self._revealedGen = gen
  if self._fallback then self._fallback:stop(); self._fallback = nil end
  -- Recompute the frame here rather than reuse the show-time snapshot, so it picks up
  -- the footer height the page reported before ready. The window then opens at its
  -- final height with no resize once visible.
  self.shell:show(self:_frame())
  self.dataset = self:_buildDataset(self.lastQuery or "")
  self.shell:eval("window.__setRows(" .. json(self.dataset) .. ")")
  self.shell:focusWindow()
  self.shell:eval("window.__focus()")
end

--------------------------------------------------------------------------------
-- Public contract, matching the old Chooser atom
--------------------------------------------------------------------------------

-- Cancel any pending reveal before hiding, so a dismiss inside the 0.2s fallback
-- window (open then escape or click away before the page reports ready) cannot let
-- a late fallback re-reveal the hidden window. Clearing _pending also makes a stale
-- ready that arrives after the hide a no op.
function List:_cancelReveal()
  if self._fallback then self._fallback:stop(); self._fallback = nil end
  self._pending = nil
end

function List:hide() self:_cancelReveal(); self.shell:hide() end
function List:close() self:_cancelReveal(); self.shell:hide() end
function List:isShowing() return self.shell:isShowing() end

function List:refresh()
  if not self:isShowing() then return end
  -- Keep self.dataset in sync so a refresh landing before the page reports ready
  -- is not lost, the ready handler rebuilds from the same supplier. keepSel true,
  -- so a redraw after a batch toggle or a delete holds the highlight in place
  -- rather than jumping to the top, matching the native atom.
  self.dataset = self:_buildDataset(self.lastQuery or "")
  self.shell:eval("window.__setRows(" .. json(self.dataset) .. ", true)")
end

--- List:hasPreview() - true when this surface reserves a split preview pane, so a
--- consumer can push preview html here instead of docking a separate window. The
--- native atom lacks this method, which is how the clipboard tells the backends
--- apart.
function List:hasPreview()
  return self:_previewW() > 0
end

--- List:setFooter(hints) - replace the footer hints live, for a consumer whose
--- shortcuts change with state (the clipboard's Delete label once a batch is marked).
--- Updates the stored config so the next open renders the new hints too, and redraws
--- the bar now when showing. Same-shape updates only; a footer that already exists
--- stays visible, this does not toggle the nofooter class.
function List:setFooter(hints)
  self.config.footer = hints
  if self:isShowing() then
    local payload = json({ h = self:_footerHtml() })
    self.shell:eval("window.__setFooter((" .. payload .. ").h)")
  end
end

--- List:setPreview(html) - fill the split preview pane with an html fragment. The
--- page wraps it in the themed pane chrome, so the consumer sends only the body.
function List:setPreview(html)
  -- hs.json.encode takes a table, not a bare string, so wrap the fragment, encode,
  -- and read the field back in JS. This escapes the html safely for the eval.
  local payload = json({ h = html or "" })
  self.shell:eval("window.__setPreview((" .. payload .. ").h)")
end

function List:selectNext() self.shell:eval("window.__move(1)") end
function List:selectPrev() self.shell:eval("window.__move(-1)") end
function List:insertSelected() self.shell:eval("window.__activate()") end

--- List:scrollPreview(dy) - scroll the split preview pane by dy pixels, positive
--- down and negative up, for a consumer whose preview overflows (the clipboard). A
--- no op on a surface with no preview pane, where the page's __scrollPreview finds
--- no element and does nothing.
function List:scrollPreview(dy) self.shell:eval("window.__scrollPreview(" .. tostring(dy) .. ")") end

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
    uriByKey = {},
    iconStable = {},
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
