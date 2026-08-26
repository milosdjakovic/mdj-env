-- Apple's own Terminal.app, scripted through its own long standing dictionary. "do script"
-- with no target window opens a fresh one, which is exactly what an attach wants.
--
-- Everything a bundle id alone decides comes from providers/bundle.lua, as with every backend
-- here, so this file is the identity and the one command only Terminal understands.

return function(bundle)
  local BUNDLE_ID = "com.apple.Terminal"

  return bundle.provider({
    name = "Terminal",
    bundleID = BUNDLE_ID,
    openAttach = function(target)
      hs.application.launchOrFocusByBundleID(BUNDLE_ID)
      local cmd = "tmux attach-session -t " .. bundle.asQuote(target)
      -- Addressed by bundle id rather than by name, the same reasoning as Ghostty's provider.
      local script = 'tell application id ' .. bundle.asQuote(BUNDLE_ID)
        .. ' to do script ' .. bundle.asQuote(cmd)
      local ok, _, err = hs.osascript.applescript(script)
      if not ok then return false, tostring(err) end
      return true
    end,
  })
end
