--- === TmuxSessions.contract ===
---
--- What a terminal backend must answer. Two identity fields, name and bundleID, plus four
--- methods, the same shape BrowserTabs already keeps between its engine and its browsers,
--- so a provider never learns why it is asked, only what to do.
---
--- Three of those four are decided entirely by the bundle id, so no backend writes them.
--- providers/bundle.lua supplies them and every provider file is built through it, leaving
--- each one holding only its identity and its own openAttach. This file stays the thing both
--- sides point at, since a backend built some other way satisfies it just the same.
---
---   available()          -> boolean, is this terminal actually installed on this machine.
---   running()             -> boolean, is it running right now. Answered through
---                            hs.application.applicationsForBundleID rather than
---                            hs.application.get, a measured difference rather than a taste,
---                            see this plugin's CLAUDE.md for what get costs when the answer
---                            is no.
---   activate()            -> bring its frontmost window forward, launching it first when
---                            it was not running. No return value.
---   openAttach(target)    -> ok, err. Open a NEW window that runs
---                            `tmux attach-session -t target`, for the moment nothing
---                            anywhere already has a tmux client attached.

local M = {}

M.requiredFields = { "name", "bundleID" }
M.requiredMethods = { "available", "running", "activate", "openAttach" }

--- contract.validate(provider) -> ok, missing
--- Return true when the provider is a table carrying every required field and method, or
--- false and the name of the first gap. Never throws, so the engine owns the failure
--- policy, dropping a non conforming provider and logging why.
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
