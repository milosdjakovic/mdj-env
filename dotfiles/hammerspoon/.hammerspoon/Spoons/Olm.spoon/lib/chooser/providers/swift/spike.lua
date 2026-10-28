--- The spike's Lua side, which is not the provider yet. It builds the native library through
--- lib/swiftbuild.lua, loads it, and drives it over a fixed list, so the four questions the spike
--- exists for can be answered before the twenty five contract methods are written. Does the
--- library load, does the panel draw glass, does it take the keyboard over another app, and does
--- the round trip from a keystroke to Lua and back to the rows feel instant.
---
--- M.load(opts, done) builds and loads, then calls done(native) or done(nil, reason).
--- opts.swiftc is the resolved compiler and opts.dir the cache directory.
--- M.demo(native, opts) shows the panel over opts.rows, filtering by substring, and calls
--- opts.onQuery(text, count), opts.onChoose(text) and opts.onDismiss() so a probe can record
--- what happened.

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local swiftbuild = dofile(here .. "../../../swiftbuild.lua")

local M = {}

local NATIVE = here .. "native/"
local FRAMEWORKS = hs.processInfo.bundlePath .. "/Contents/Frameworks"

function M.load(opts, done)
  swiftbuild.ensure({
    sources = { NATIVE .. "Panel.swift", NATIVE .. "Entry.swift" },
    inputs = { NATIVE .. "bridge.h" },
    flags = {
      "-emit-library", "-O",
      "-module-name", "OlmSwiftChooser_{hash}",
      "-import-objc-header", NATIVE .. "bridge.h",
      "-F", FRAMEWORKS,
      "-framework", "LuaSkin",
    },
    dir = opts.dir,
    name = "swiftchooser",
    swiftc = opts.swiftc,
  }, function(ok, result)
    if not ok then done(nil, result) return end
    local open, err = package.loadlib(result, "luaopen_olm_swiftchooser")
    if not open then done(nil, "loadlib failed, " .. tostring(err)) return end
    local okOpen, native = pcall(open)
    if not okOpen then done(nil, "luaopen failed, " .. tostring(native)) return end
    done(native, result)
  end)
end

local function filtered(rows, query)
  if query == "" then return rows end
  local needle = query:lower()
  local out = {}
  for _, row in ipairs(rows) do
    if row:lower():find(needle, 1, true) then out[#out + 1] = row end
  end
  return out
end

function M.demo(native, opts)
  local visible = opts.rows
  native.setCallback(function(event, payload)
    if event == "query" then
      visible = filtered(opts.rows, payload)
      native.setRows(visible)
      if opts.onQuery then opts.onQuery(payload, #visible) end
    elseif event == "choose" then
      native.hide()
      if opts.onChoose then opts.onChoose(visible[payload]) end
    elseif event == "dismiss" then
      if opts.onDismiss then opts.onDismiss() end
    end
  end)
  native.setPlaceholder(opts.placeholder or "Search")
  native.setQuery("")
  native.setRows(visible)
  native.show(opts.activate == true)
end

return M
