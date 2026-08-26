-- Ghostty carries a real AppleScript dictionary (sdef /Applications/Ghostty.app), one of
-- only three backends here that do, so opening an attach is one scripting command rather
-- than a CLI flag guess. "new window with configuration {command:...}" takes the place of
-- the configured shell for exactly that one window, which is what makes a fresh attach a
-- single call with nothing to clean up after.
--
-- Everything a bundle id alone decides, whether this is installed, whether it is running and
-- how it is raised, comes from providers/bundle.lua rather than being written out here again.

return function(bundle)
  local BUNDLE_ID = "com.mitchellh.ghostty"

  return bundle.provider({
    name = "Ghostty",
    bundleID = BUNDLE_ID,
    openAttach = function(target)
      hs.application.launchOrFocusByBundleID(BUNDLE_ID)
      local cmd = "tmux attach-session -t " .. bundle.asQuote(target)
      -- Addressed by bundle id rather than by name, since "id" is the one identifier that
      -- cannot drift with a display name change across a version.
      local script = 'tell application id ' .. bundle.asQuote(BUNDLE_ID)
        .. ' to new window with configuration {command:' .. bundle.asQuote(cmd) .. '}'
      local ok, _, err = hs.osascript.applescript(script)
      if not ok then return false, tostring(err) end
      return true
    end,
  })
end
