local StageManager = {}

function StageManager.getStatus()
  local output, status = hs.execute("defaults read com.apple.WindowManager GloballyEnabled")
  local active = (output:gsub("%s+", "") == "1")

  return active
end

StageManager.active = StageManager.getStatus()
StageManager.onToggleCallback = nil

function StageManager.toggle()
  StageManager.active = StageManager.getStatus()

  if StageManager.onToggleCallback then
    StageManager.onToggleCallback(StageManager.active)
  end
end

function StageManager.initialize(options)
  options = options or {}
  local keyBinding = options.keyBinding
  StageManager.onToggleCallback = options.onToggle

  if keyBinding then
    hs.hotkey.bind(keyBinding.modifiers, keyBinding.key, StageManager.toggle)
  end
end

return StageManager
