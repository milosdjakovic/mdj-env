--- Processes source contract.
---
--- The interface every discovery source must satisfy. This is the one named place
--- that declares what a source is, so a new backend author reads this file and
--- nothing else to know the shape. It is a runtime checklist, not a base class, Lua
--- has no interfaces, so a source conforms by carrying these methods rather than by
--- inheriting anything. The engine calls validate() at load and drops whatever does
--- not conform.
---
--- A source is a plain table with an optional `name` and these methods. They are
--- DOT called, not colon called, the module style Vpn and the clipboard submodules
--- already use. The lifecycle contract allows either, and a source holds only its
--- own injected policy with no instances of it, so the plainer form fits.
---   available() -> boolean[, reason]
---       Is this backend usable right now. Checked LIVE on every scan and every
---       stop, since a daemon can quit long after Hammerspoon loaded. Return false
---       plus a short reason string, which the engine logs so you can see why the
---       source stepped aside.
---   scan(cb)
---       Discover rows. ASYNCHRONOUS, it must call cb(rows[, reason]) exactly once
---       with a list, or cb({}, reason) on failure, and must never block the main
---       thread. Every shellout goes through hs.task, never hs.execute, because the
---       picker is redrawn from the main thread and a blocking scan would stutter it.
---   stop(row, opts, cb)
---       Terminate what the row names. opts.force asks for the unconditional kill
---       with no grace period. opts.confirmed acknowledges a target the source
---       already refused once as too large. Calls cb(ok, message) once, where
---       message is short human readable text the caller may surface.
---
---       A source that considers a stop too large to take silently returns
---       cb(false, reason) rather than acting, and only proceeds when called again
---       with opts.confirmed. The threshold lives in the source, where the live
---       data is, while the decision to ask lives in the UI, where the user is.
---
--- An optional `configure(opts)` is called by the composition root, never by the
--- engine, so the root stays the one place that knows each source's config shape
--- and the engine never forwards opaque policy it cannot read.
---
--- A row is plain serializable data with no functions on it, the Command as data
--- rule every list tool here follows, because hs.chooser serialises each row and
--- silently drops a function. The fields.
---   source     name of the source that produced it, used to route the stop back
---   key        stable identity across scans, used to hold metric history
---   title      display label, or nil to let the engine derive one from cwd
---   runtime    what it runs on, "node", "docker", "python"
---   pid, pgid  the process and its group, absent on a container row
---   ports      list of port numbers it listens on, possibly empty
---   cwd        working directory, absent on a container row
---   command    the command line, elided by the source if very long
---   status     short human readable state, "up 19h"
---   startedAt  epoch seconds, used for the recency sort, 0 when unknown
---   tier       display tier, lower sorts first, so local processes sit above
---              containers regardless of the claim priority below
---   tree       list of { pid, ppid, label } a stop would take, may be empty
---
--- Claim priority is separate from display tier and comes from the registration
--- order in the composition root. A row is dropped when every port it holds is
--- already claimed by an earlier source, which is how eleven docker proxy
--- listeners collapse into named containers without the engine knowing the word
--- docker.

local M = {}

M.requiredMethods = { "available", "scan", "stop" }

--- contract.validate(source) -> ok, missing
--- Return true when the source is a table carrying every required method, or false
--- and the name of the first gap, or "not a table". Never throws, the engine drops
--- a non conforming source and logs.
function M.validate(source)
  if type(source) ~= "table" then return false, "not a table" end
  for _, method in ipairs(M.requiredMethods) do
    if type(source[method]) ~= "function" then
      return false, method
    end
  end
  return true
end

return M
