--- === Capture ===
---
--- Trigger screen capture and recording on a hotkey, backed by an ordered chain
--- of providers so the underlying screenshot tool can be replaced, or fallen back
--- on, without touching the bindings. The spoon speaks a small, app-agnostic
--- action vocabulary (captureArea, captureAreaClipboard, recordArea); which tool
--- runs each action is decided by the provider chain.
---
--- This file is the composition root, and only this. It loads the three pieces
--- and wires them together, then returns the assembled spoon:
---   engine.lua      the Context, owns the chain and the dispatch (the behavior)
---   contract.lua    the interface every provider must implement
---   providers/*.lua the concrete backends, one self-contained file each
---
--- The split keeps each piece ignorant of the others. The engine never names a
--- provider, the providers never know about the chain or each other, and the
--- contract knows nothing about any of them. So this is the ONE file that names
--- concrete providers, which is why the default chain order lives here.
---
--- Adding a backend is a new file in providers/ plus one line below. Loaded by
--- absolute path off this file's own location (loadfile, not require, since a
--- spoon dir is not on package.path).

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("Capture: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

local obj = load("engine.lua")

-- Inject the contract the engine validates the chain against.
obj._contract = load("contract.lua")

-- Register the concrete providers and set the default chain order. macshot is
-- preferred, native is the always-available tail. The top-level init.lua may
-- still pass its own ordered list to configure; this is the fallback order used
-- when it does not.
obj.providers = {
  macshot = load("providers/macshot.lua"),
  native = load("providers/native.lua"),
}
obj._defaultProviders = { obj.providers.macshot, obj.providers.native }

return obj
