--- The browser provider contract. The engine calls only these methods and names no
--- browser, so adding one is a new file in providers plus one line in the composition
--- root. In a dynamic language a contract is a documented set of required methods plus a
--- validation step, not a compiled interface, so validate checks the shape once at load.
--- It returns (ok, missing) rather than throwing, a soft shape the caller acts on, which
--- here means a bad provider is dropped with a log rather than killing the whole tool.
---
--- This doc comment is the provider spec. It lives here, beside the validation, rather
--- than in the spoon's CLAUDE.md, because a method list copied into prose is a second
--- source of truth that drifts the moment the contract changes.
---
--- The metadata a provider must carry.
---   name        the human browser name, shown on rows and in the settings list.
---   bundleID    the app's bundle identifier. It is the provider's identity here, the
---               key the enabled set and the recency store are written under, and the
---               value every JXA call addresses the app by.
---
--- The methods a provider must implement.
---   available()        returns whether the browser is installed. Read live, since a
---                      browser can be installed while Hammerspoon runs. Fast, so
---                      synchronous.
---   running()          returns whether the browser is running right now. Fast, so
---                      synchronous. The engine checks this at dispatch and skips a
---                      browser that is closed, so a closed browser is never scripted
---                      and never launched by being asked.
---   listTabs(cb)       fetch every open tab and call cb(list, err) on the main thread.
---                      Each entry is { title, url, windowID, windowIndex, tabIndex,
---                      active, group }. active marks the selected tab of its window,
---                      and may be false on every row when the browser does not report
---                      one. group is an optional label the browser gives the tab, nil
---                      when it has no such notion. err is nil on success, the string
---                      "notPermitted" when macOS refused the Apple Event, or another
---                      message.
---   activeTab(cb)      the selected tab of the frontmost window as { title, url }, or
---                      nil when the browser does not report one. Called by the recency
---                      observer on every browser focus and tab switch, so it must stay
---                      cheap, one Apple Event rather than a full listing. A provider
---                      whose browser cannot answer implements it and calls cb(nil),
---                      which costs that browser live recency and nothing else.
---   activate(tab, cb)  bring that tab to the front, selecting it in its window and
---                      raising the window, then cb(ok, err). Raising the application
---                      itself is the caller's job, so this stays about the tab.

local M = {}

M.requiredFields = { "name", "bundleID" }
M.requiredMethods = { "available", "running", "listTabs", "activeTab", "activate" }

--- contract.validate(provider) -> ok, missing
--- Return true when the provider is a table carrying every required field and method, or
--- false and the name of the first gap. Never throws, so the caller owns the failure
--- policy.
function M.validate(provider)
  if type(provider) ~= "table" then return false, "not a table" end
  for _, field in ipairs(M.requiredFields) do
    if type(provider[field]) ~= "string" or provider[field] == "" then
      return false, field
    end
  end
  for _, name in ipairs(M.requiredMethods) do
    if type(provider[name]) ~= "function" then
      return false, name .. "()"
    end
  end
  return true
end

return M
