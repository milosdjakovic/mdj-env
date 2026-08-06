--- File search source contract.
---
--- What every search source must satisfy. This is the one named place that declares
--- what a source is, so adding a backend means reading this file and nothing else. It
--- is a runtime checklist rather than a base class, since a Lua contract is structural,
--- so a source conforms by carrying these methods and the engine validates and drops
--- whatever does not.
---
--- The methods are DOT called, the module style the other spoons here already use for
--- backends, because a source holds only its own injected policy and is never
--- instantiated.
---
---   available() -> boolean[, reason]
---       Is this backend usable right now. Checked live rather than once at load, since
---       a tool can be removed while Hammerspoon runs. Return false and a short reason,
---       which the engine logs so a source stepping aside always says why.
---
---   supports(parsed) -> boolean
---       Can this source answer THIS query. The engine asks each source in the order the
---       composition root registered them and the first that says yes owns the query, so
---       ordering is how conflicts are settled and no source needs to know the others
---       exist. A source answers on the shape of the parse, never on the text.
---
---   search(parsed, ctx, cb) -> handle or nil
---       Produce rows. ASYNCHRONOUS, it must call cb(rows[, reason]) exactly once with a
---       list, or cb({}, reason) on failure, and must never block the main thread. Every
---       shellout goes through hs.task, never hs.execute or io.popen, because the picker
---       redraws from the main thread and a blocking search would freeze every hotkey in
---       the config, not just this one.
---
---       Returns a handle carrying one method, cancel(), which abandons THIS search and
---       nothing else. Cancelling is silent, the callback simply never arrives, since an
---       abandoned search must not paint rows the caller has already moved past.
---
---       Per call rather than per source, because a source answers more than one caller at
---       a time and cannot tell them apart. The engine runs a typed search and a background
---       recent files fetch concurrently, and while cancelling was a module level method
---       here, starting either one silently killed the other. The recent list then never
---       arrived and never retried, and the picker opened on a loading row with nothing
---       under it. So a source keeps no in flight slot of its own and the caller holds one
---       handle per concurrent search it started.
---
---       Holding the handle is also what keeps the search alive, since it closes over the
---       task or the query object, and an unreferenced one is collected mid flight with its
---       callback silently never arriving. So the handle goes in a field, the same rule this
---       config states for timers.
---
---       Returning nil is allowed and means this search cannot be abandoned, which is
---       honest for one that has not started yet, such as a first query waiting on an index
---       build. The caller falls back to its own generation guard and drops the late answer
---       instead.
---
---       ctx carries what the engine resolved so the source does not repeat the work:
---         scopePath        the scope token resolved to a real directory, or nil
---         cap              how many rows to return at most
---         timeoutSeconds   abandon after this
---         limits           the pure limits table from config, for a source needing more
---
--- An optional configure(opts) is called by the composition root and never by the
--- engine, so the root stays the one place that knows each source's config shape.
---
--- A ROW is plain serializable data with no functions on it, because hs.chooser
--- serialises each row and silently drops a function. The fields:
---   path      absolute path, the identity of the row
---   lower     the same path case folded, which is what the local narrow matches against.
---             Derived rather than declared, so a source builds it by going through util.row
---             and never sets it itself. It exists because the shared words matcher folds
---             only the query, so a verbatim haystack makes an uppercase query match nothing
---   name      basename, what the row shows as its title
---   dir       parent directory, what the row shows as its subtitle
---   isDir     true for a directory, which is what makes a row browsable
---   ext       lowercased extension with no dot, or "" when there is none
---   size      bytes, or nil when the source did not cheaply know it
---   modified  epoch seconds, or nil for the same reason
---   source    name of the source that produced it, for logging and for the preview
---
--- Size and modified are optional ON PURPOSE. Spotlight returns both as attributes for
--- free, so its rows carry them, while a directory walk would have to stat every path to
--- fill them in and that cost buys nothing for a row nobody looked at. So a source fills
--- in what it already knows and never stats to satisfy this shape.

local M = {}

M.requiredMethods = { "available", "supports", "search" }

--- contract.validate(source) -> ok, missing
--- True when the source carries every required method, or false and the name of the
--- first gap. Never throws, the engine drops a non conforming source and logs it.
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
