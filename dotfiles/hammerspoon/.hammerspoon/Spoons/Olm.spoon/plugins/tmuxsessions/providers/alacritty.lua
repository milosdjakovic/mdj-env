-- Alacritty carries no AppleScript dictionary, so a fresh attach goes through its own -e
-- flag instead, which runs a program in place of the shell and must be the last thing on
-- its argv since it swallows everything after it. `open -na` is the one door from
-- Hammerspoon to a bundle's own argv without shelling to the binary directly, -n forcing a
-- new instance so a window that is already open and ignoring --args is not what answers.
--
-- Not installed on the machine this was written on, so unlike Ghostty and Terminal.app
-- this is unverified against a live run, only against Alacritty's documented -e flag.
-- available() answers false without it, and the Settings row shows it disabled.
--
-- The one backend state in this plugin, the resolved path to open, is a local of this factory
-- rather than a file global, so it belongs to the backend this call built and not to the file.

return function(bundle)
  local BUNDLE_ID = "org.alacritty"
  local openPath = nil -- resolved absolute path to /usr/bin/open, injected via configure

  return bundle.provider({
    name = "Alacritty",
    bundleID = BUNDLE_ID,
    configure = function(opts)
      openPath = (opts and opts.open) or openPath
    end,
    openAttach = function(target)
      if not openPath then return false, "open is not resolved" end
      local cmd = bundle.shq(openPath)
        .. " -na Alacritty --args -e tmux attach-session -t " .. bundle.shq(target)
      local output, ok = hs.execute(cmd)
      if not ok then return false, tostring(output) end
      return true
    end,
  })
end
