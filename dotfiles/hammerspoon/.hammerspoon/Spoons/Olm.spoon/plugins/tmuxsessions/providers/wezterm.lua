-- WezTerm carries no AppleScript dictionary either, so a fresh attach goes through its own
-- `start -- command` form instead, reached the same way Alacritty is, through `open -na`
-- and --args, -n forcing a new instance for the same reason.
--
-- Not installed on the machine this was written on, so unlike Ghostty and Terminal.app
-- this is unverified against a live run, only against WezTerm's documented CLI. available()
-- answers false without it, and the Settings row shows it disabled.
--
-- The resolved path to open is a local of this factory rather than a file global, the same as
-- Alacritty's, so it belongs to the backend this call built.

return function(bundle)
  local BUNDLE_ID = "com.github.wez.wezterm"
  local openPath = nil -- resolved absolute path to /usr/bin/open, injected via configure

  return bundle.provider({
    name = "WezTerm",
    bundleID = BUNDLE_ID,
    configure = function(opts)
      openPath = (opts and opts.open) or openPath
    end,
    openAttach = function(target)
      if not openPath then return false, "open is not resolved" end
      local cmd = bundle.shq(openPath)
        .. " -na WezTerm --args start -- tmux attach-session -t " .. bundle.shq(target)
      local output, ok = hs.execute(cmd)
      if not ok then return false, tostring(output) end
      return true
    end,
  })
end
