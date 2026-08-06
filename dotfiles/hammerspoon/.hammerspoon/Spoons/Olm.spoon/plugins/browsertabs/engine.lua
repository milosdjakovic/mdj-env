--- === BrowserTabs.engine ===
---
--- The mechanism. It fans a tab listing out across the browsers, merges the answers into one
--- flat list, and turns a chosen tab back into a focused window. It talks only through the
--- provider contract and names no browser, so adding one never touches this file.
---
--- It also decides nothing about policy. Which browsers are switched on is an injected
--- predicate, so the engine never learns what enabled means or where that choice is stored,
--- and the ordering of the merged list is the caller's, not the engine's.
---
--- Three things a browser must never suffer. It is not scripted when it is not installed. It
--- is not scripted when it is not running, so being asked for its tabs can never launch it,
--- which is why the liveness check sits at dispatch rather than being resolved once at load.
--- And it is not scripted when it is switched off, so a browser you would rather Hammerspoon
--- left alone costs no Apple Events at all and never raises a permission prompt.
---
--- The fan out is concurrent. Each provider runs its own osascript off the main thread, so
--- the whole listing costs about as long as the slowest single browser rather than the sum of
--- them all. A provider that fails does not fail the listing, its error is collected under
--- its bundle id and the browsers that did answer still show.

local M = {}

local log = hs.logger.new("BrowserTabs", "info")

local apps = (function()
  local p = debug.getinfo(1, "S").source:sub(2):match("(.*/)") .. "apps.lua"
  local chunk, err = loadfile(p)
  if not chunk then error("BrowserTabs.engine: failed to load apps.lua: " .. tostring(err)) end
  return chunk()
end)()

local providers = {}   -- injected, the full validated set in root order
local isEnabled = nil  -- injected policy, function(provider) -> boolean

--- M.configure(opts) - inject the providers and the enabled predicate. opts.providers is the
--- ordered list the composition root assembled, opts.enabled is the policy deciding which of
--- them may be scripted. With no predicate every provider counts as enabled, so the engine
--- still works standalone.
function M.configure(opts)
  opts = opts or {}
  providers = opts.providers or {}
  isEnabled = opts.enabled
  return M
end

--- M.providers() - the injected set, in root order. The settings surface lists these.
function M.providers()
  return providers
end

--- M.provider(bundleID) - the provider with that bundle id, or nil. Used to resolve a tab
--- back to the browser it came from.
function M.provider(bundleID)
  for _, p in ipairs(providers) do
    if p.bundleID == bundleID then return p end
  end
  return nil
end

--- M.enabled(provider) - whether policy allows this provider to be scripted. Kept here as
--- the single reading of the injected predicate, so the queryable test and the settings
--- surface can never disagree about what enabled means.
function M.enabled(provider)
  if not isEnabled then return true end
  return isEnabled(provider) == true
end

--- M.queryable() - the providers that will actually be asked, switched on and installed and
--- running. The settings surface reads the same three tests through M.status.
function M.queryable()
  local out = {}
  for _, p in ipairs(providers) do
    if M.enabled(p) and p.available() and p.running() then
      out[#out + 1] = p
    end
  end
  return out
end

--- M.status() - one row per provider describing what is true of it right now, the synchronous
--- facts only. The Apple Events permission is asynchronous and lives elsewhere, so the
--- settings surface merges that in rather than this blocking on it.
function M.status()
  local out = {}
  for _, p in ipairs(providers) do
    out[#out + 1] = {
      provider = p,
      name = p.name,
      bundleID = p.bundleID,
      enabled = M.enabled(p),
      installed = p.available(),
      running = p.running(),
    }
  end
  return out
end

--- M.listTabs(cb) - fan out across every queryable provider and call cb(tabs, errors) once
--- they have all answered. Each returned tab is stamped with the browser it came from, so a
--- consumer can group, label, and resolve it without holding on to the provider. errors maps a
--- bundle id to the reason that browser did not answer, so a caller can explain a refused
--- permission rather than silently showing a short list. With nothing queryable it calls back
--- at once with two empty tables rather than leaving the caller waiting.
function M.listTabs(cb)
  local live = M.queryable()
  if #live == 0 then
    cb({}, {})
    return
  end

  local pending = #live
  local out, errors = {}, {}

  for _, p in ipairs(live) do
    p.listTabs(function(tabs, err)
      if err then
        errors[p.bundleID] = err
        log.w(p.name .. " did not answer, " .. tostring(err))
      else
        for _, t in ipairs(tabs or {}) do
          t.browser = p.name
          t.bundleID = p.bundleID
          out[#out + 1] = t
        end
      end
      pending = pending - 1
      if pending == 0 then cb(out, errors) end
    end)
  end
end

-- Bring the tab's own window forward, rather than the application it belongs to. Raising an
-- application asks macOS to restore whichever window that application last had focused, which is
-- very often not the one the tab lives in, so the browser arrives showing something else. Measured
-- against a second window three times out of three, and focusing the window directly won three
-- times out of three in the same conditions.
--
-- Tying the browser's window to the accessibility window is the whole difficulty here. A browser
-- numbers its windows in its own dictionary and the window server numbers them in another, and the
-- two only sometimes agree. Safari's window ids are the window server's own, so they match exactly,
-- while Chrome's are a private counter that matches nothing. So the id is tried and never assumed,
-- and the search runs over this application's own windows, which is what keeps a number meant for
-- one namespace from ever matching a window in the other.
--
-- What is left when the ids do not agree is the title, and there are two of those to try because
-- each covers the other's one measured failure. The window's own name, which the provider reads
-- straight after the tab switch, is the fresher of the two and is exact on Safari, where the window
-- is named after the tab group as well as the page and so never equals the tab's title. But Chrome
-- elides a long window name in the middle with an ellipsis, and an elided name appears in no
-- accessibility title at all. The tab's title survives that, being the page's own title in full,
-- and pays for it by going stale when a page retitles itself after the list was read, which was
-- measured happening to an ordinary shopping page mid run. So the name is tried and then the title.
--
-- Containment rather than equality or a prefix, since the two browsers decorate the accessibility
-- title at opposite ends, Chrome appending its own name and profile and Safari prefixing the tab
-- group. A prefix test was the first attempt and it failed every time on Safari. Anything other
-- than exactly one match, including two windows genuinely showing the same page, falls back to
-- raising the application, which is the old behaviour and is right more often than it is wrong.
local function focusTabWindow(app, windowID, windowName, tabTitle)
  local windows = app:allWindows()

  local wid = tostring(windowID or "")
  for _, w in ipairs(windows) do
    if tostring(w:id()) == wid then
      w:focus()
      return nil
    end
  end

  local tried = 0
  for _, want in ipairs({ tostring(windowName or ""), tostring(tabTitle or "") }) do
    if want ~= "" then
      tried = tried + 1
      local matches = {}
      for _, w in ipairs(windows) do
        if tostring(w:title()):find(want, 1, true) then matches[#matches + 1] = w end
      end
      if #matches == 1 then
        matches[1]:focus()
        return nil
      end
    end
  end

  app:activate()
  if tried == 0 then return "no id, no name and no title to match on" end
  return "no single window matched the name or the title"
end

--- M.activate(tab, cb) - bring a tab to the front. The provider selects it and restores its window
--- if it was minimized, then that window is brought forward here, because finding and focusing a
--- window is the same for every browser and a provider would only be repeating it. The optional cb
--- receives (ok, err).
---
--- The raise waits for the provider to answer rather than going out first, which looks like an
--- avoidable delay and is not. A surface that opens over another app hands focus back to that
--- app when it hides, so a raise sent while the list was still on screen is undone a moment
--- later by that restore, measured as landing on the browser and then losing the front again.
--- Sent after the answer it lands once the list has already gone. Why a window that is
--- minimized has to be restored at all, and what still cannot be relied on, are in the
--- CLAUDE.md beside this file.
function M.activate(tab, cb)
  cb = cb or function() end
  if not tab or not tab.bundleID then
    cb(false, "the tab names no browser")
    return
  end
  local p = M.provider(tab.bundleID)
  if not p then
    cb(false, "no provider for " .. tostring(tab.bundleID))
    return
  end
  p.activate(tab, function(ok, err, info)
    if ok then
      local app = apps.forBundleID(tab.bundleID)
      if app then
        local fellBack = focusTabWindow(app, tab.windowID, info and info.name, tab.title)
        if fellBack then
          log.d("raised " .. p.name .. " itself rather than the tab's window, " .. fellBack)
        end
      else
        log.w("could not find " .. p.name .. " to bring forward")
      end
    else
      log.w("could not open the tab in " .. p.name .. ", " .. tostring(err))
    end
    cb(ok, err)
  end)
end

return M
