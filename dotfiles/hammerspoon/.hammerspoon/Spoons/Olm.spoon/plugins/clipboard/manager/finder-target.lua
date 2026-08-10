--- The one file in this feature that knows Finder or AppleScript exist. Everything else
--- in this folder talks about paths and folders and never about which application is
--- asking for them, and that separation is the whole reason this file is as small as it
--- is, one method answering one question.
---
--- folder() answers where a paste would land right now, so a caller deciding whether to
--- stage a file never has to guess at a frontmost window or a selection itself. Finder
--- exposes this directly as its own insertion location, which agrees with where a paste
--- actually lands whether a subfolder is open, a subfolder is selected inside a window, or
--- the Desktop is the active target, so asking Finder is simpler and more honest than
--- reconstructing the same answer from window state in here.
---
--- It answers nil rather than a folder whenever the question does not apply, Finder is not
--- the frontmost application, or whenever the script itself comes back empty or fails for
--- any reason at all, a window with nothing open included. Nil is answered on purpose
--- rather than let anything raise, since the one caller of this module treats nil as leave
--- the paths alone, which is exactly today's paste and exactly Finder's own prompt, so a
--- question this file cannot answer must never turn into an error somewhere else.
---
--- The one real cost here is worth recording rather than hiding. Asking Finder is a
--- synchronous AppleScript round trip on the main thread, measured at about thirty
--- milliseconds on a warm call and about seventy on the first one, which is invisible
--- against a paste and is only ever paid on a file paste, since the only caller is the one
--- place that already decides which file paths to write. Nothing is paid at all when
--- Finder is not frontmost, since the bundle id is checked first and that path costs
--- nothing. The honest part is that a Finder which is itself blocked, waiting on a slow
--- network volume for instance, would block this call and so would block Hammerspoon for
--- as long as it takes, and there is no timeout available for a synchronous AppleScript
--- call. The choice made here is to accept that rather than to restructure the whole paste
--- path around an asynchronous answer.

local M = {}

--- M.folder() -> string or nil
--- The absolute path of the folder a paste would land in right now, with any trailing
--- slash removed, or nil when Finder is not frontmost or the folder cannot be read.
function M.folder()
  local front = hs.application.frontmostApplication()
  if not front or front:bundleID() ~= "com.apple.finder" then
    return nil
  end
  local ok, result = hs.osascript.applescript(
    'tell application "Finder" to POSIX path of (insertion location as alias)'
  )
  if not ok or type(result) ~= "string" or result == "" then
    return nil
  end
  return (result:gsub("/+$", ""))
end

return M
