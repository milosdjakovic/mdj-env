-- Clipboard history, the behaviour no declaration implies.
--
-- Everything structural about this plugin is already checked without a word being written
-- here. That it registers, that it is active, that it owns a key, that its picker opens and
-- closes, that its two commands carry rows, all of that is derived from the registry block in
-- its manifest. Restating any of it would be the same duplication the manifest layer exists to
-- remove, and the copy here would be the one that goes stale.
--
-- What is left is the only thing this tool actually promises. Something copied turns up in the
-- history, at the top, and it is still there after the picker is opened and closed again.

return {
  feature = "Clipboard history",

  scenarios = {
    {
      scenario = "something copied reaches the top of the history",
      given = function(w)
        w._mark = "olm suite " .. w.stamp
        w.pasteboard(w._mark)
      end,
      when = function(w)
        -- The watcher polls rather than being told, so this waits a beat longer than the
        -- shared settle. Asking immediately would be asking before the poll that notices.
        w.settle()
        w.settle()
      end,
      expect = function(w)
        local rows = w.rows("clipboard", "")
        if type(rows) ~= "table" then
          return false, "the clipboard answered no rows at all for an empty query"
        end
        if #rows == 0 then
          return false, "the history is empty, so nothing was recorded"
        end
        local top = rows[1]
        local text = tostring(top.text or top.title or "")
        if not text:find(w._mark, 1, true) then
          return false, "the newest row reads '" .. text .. "' rather than what was just copied"
        end
        return true
      end,
    },

    {
      scenario = "the history survives the picker being opened and closed",
      when = function(w)
        w.open("clipboard")
        w.settle()
        w.close("clipboard")
      end,
      expect = function(w)
        local rows = w.rows("clipboard", "")
        if type(rows) ~= "table" or #rows == 0 then
          return false, "the history came back empty after one open and close"
        end
        return true
      end,
    },

    {
      scenario = "a copied image is kept as an image rather than as its file name",
      manual = "copy a screenshot, open the history, and check the row shows a preview",
    },
  },
}
