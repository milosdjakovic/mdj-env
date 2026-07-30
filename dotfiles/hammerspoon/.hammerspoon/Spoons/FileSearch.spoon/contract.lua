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
---   search(parsed, ctx, cb)
---       Produce rows. ASYNCHRONOUS, it must call cb(rows[, reason]) exactly once with a
---       list, or cb({}, reason) on failure, and must never block the main thread. Every
---       shellout goes through hs.task, never hs.execute or io.popen, because the picker
---       redraws from the main thread and a blocking search would freeze every hotkey in
---       the config, not just this one.
---
---       ctx carries what the engine resolved so the source does not repeat the work:
---         scopePath        the scope token resolved to a real directory, or nil
---         cap              how many rows to return at most
---         timeoutSeconds   abandon after this
---         limits           the pure limits table from config, for a source needing more
---
---   cancel()
---       Optional. Abandon whatever is in flight. The engine calls it before dispatching
---       a newer query. A source with nothing cancellable may omit it, and one that
---       shells out should terminate its task here, since a stale answer arriving late is
---       the classic way a picker paints the wrong list.
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
