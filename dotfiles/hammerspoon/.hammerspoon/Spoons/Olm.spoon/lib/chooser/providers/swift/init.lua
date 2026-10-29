--- === Swift picker provider ===
---
--- The swift provider, the chooser engine composed with a native view. Read
--- docs/CONTRACT-PICKER.md first, and its section on the engine and the view. The engine is the
--- default provider's own, lib/chooser/engine/init.lua, so every picker rule is shared and none
--- is copied. view.lua beside this file is the view, a Humble Object over a Swift library whose
--- sources are in native/, which draws a nonactivating panel on a glass surface with a native
--- field, list and action bar. pane.lua beside it is the docked pane's native drawing backend,
--- the pane's region on the chooser panel's own glass, which the root hands every docked pane
--- while this provider serves. decisions/olm-swift-chooser.md has why it exists and what was measured and turned
--- down.
---
--- THE LIBRARY. lib/swiftbuild.lua compiles native/ into the cache directory configure is handed,
--- named by a hash of every input and loaded with package.loadlib into Hammerspoon's own process.
--- A loaded image is never unloaded, so the Swift module name carries the same hash and a rebuilt
--- image never collides with the old one. The compiler is the swiftc inside the command line
--- tools, swiftc-clt in root/manifest.lua, resolved through the dependency door and handed in, so
--- this file names no path to it. Before anything is built, lib/swiftbuild.lua's toolchain proves
--- the tools are present the way src/install-xcode-clt.sh defines it, clang beside the compiler
--- and an SDK for the running macOS, looking at the disk only, and the SDK it finds is handed to
--- the compiler. Without them the default chooser serves and one line says why, and nothing is
--- run, since running a compiler whose tools are missing raises Apple's install dialog.
---
--- WHEN IT SERVES. The one shared picker is built once at startup, and a build takes a second or
--- more, so the choice is made at configure time and never changes during a session. A library
--- already on disk for the current inputs is loaded there and then, and every new builds through
--- it. When there is none, the build starts in the background, every new is answered by the
--- injected fallback provider, the default one, for the rest of the session, and one line says
--- the swift provider takes over from the next reload. A failed build or a failed load serves the
--- fallback too, and logs the compiler's or the loader's error.
---
--- NO FOCUS HOLD. The canvas surface never takes key, so the default provider is handed a focus
--- hold that shows a hidden hs.chooser to take focus from a password field. This panel takes key
--- itself, and that hold would take key away from it, so this provider is handed none and its copy
--- of the engine never asks for one. The engine is loaded here as a module of its own, so the
--- default provider's copy keeps its hold for the fallback.
---
--- M.configure(opts) takes opts.ui, the UI kit, opts.icon, the icon resolver, opts.fallback, the
--- configured provider to serve when the library is not loaded, opts.yields and opts.listKeys,
--- the same predicates the default provider is handed, and opts.swiftc, the resolved compiler,
--- opts.dir, the cache directory, and opts.log, a logger with i and e. A dir starts the load.
---
--- M.paneBackend() answers the docked pane's native drawing backend, pane.lua beside this file,
--- as the factory lib/dockedpane.lua and lib/panel.lua take, while the library is loaded, and nil otherwise, so
--- the composition root hands panes the canvas backend whenever this provider is not serving.
---
--- M.uses(keyCode, mods) answers what the serving field already does with a chord, the native
--- field's keys in fieldkeys.lua when the library is loaded and the fallback's own answer when it
--- is not, so the root checks a person's list keys against the field that is really there.

local herePath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(relPath)
  local chunk, err = loadfile(herePath .. relPath)
  if not chunk then
    error("Swift provider: failed to load " .. relPath .. ", " .. tostring(err))
  end
  return chunk()
end

local Engine = load("../../engine/init.lua")
local SwiftView = load("view.lua")
local SwiftPane = load("pane.lua")
local fieldKeys = load("fieldkeys.lua")
local swiftbuild = load("../../../swiftbuild.lua")

-- The Swift sources and the bridging header, in the order the compiler is handed them.
local NATIVE_DIR = herePath .. "native/"
local SOURCES = { "Lua.swift", "Model.swift", "Surface.swift", "List.swift", "Bar.swift", "Popover.swift", "Panel.swift",
  "Pane.swift", "Entry.swift" }
local HEADER = "bridge.h"

-- The library's stem in the cache directory and the symbol package.loadlib opens it by.
local NAME = "swiftchooser"
local OPEN_SYMBOL = "luaopen_olm_swiftchooser"

-- The provider served while the library is not loaded, and the loaded library once it is.
local FALLBACK = nil
local NATIVE = nil

-- The logger configure was handed, for the pane backend's one line per element it cannot draw.
local LOG = nil

local M = {}

--- M.spec(opts) -> the lib/swiftbuild.lua spec for opts.dir, opts.swiftc, opts.sdk, the SDK
--- the toolchain check found, and opts.frameworks, the directory holding Hammerspoon's LuaSkin
--- framework. The flags are the whole compile, so the shell build that checks the sources and
--- this provider's own build are the same command.
function M.spec(opts)
  local sources = {}
  for i, name in ipairs(SOURCES) do sources[i] = NATIVE_DIR .. name end
  return {
    sources = sources,
    inputs = { NATIVE_DIR .. HEADER },
    flags = {
      "-emit-library", "-O",
      "-sdk", opts.sdk,
      "-module-name", "OlmSwiftChooser_{hash}",
      "-import-objc-header", NATIVE_DIR .. HEADER,
      "-F", opts.frameworks,
      "-framework", "LuaSkin",
    },
    dir = opts.dir,
    name = NAME,
    swiftc = opts.swiftc,
  }
end

-- Opens a built library and answers its table, or nil and why.
local function open(path)
  local opener, err = package.loadlib(path, OPEN_SYMBOL)
  if not opener then return nil, "loadlib failed, " .. tostring(err) end
  local ok, native = pcall(opener)
  if not ok then return nil, "luaopen failed, " .. tostring(native) end
  return native
end

-- Loads the library for the current inputs when it is on disk, or starts its build. Answered
-- synchronously by swiftbuild when the output exists, so the load happens inside configure.
local function prepare(opts)
  local log = opts.log
  local major = (hs.host.operatingSystemVersion() or {}).major
  local sdk, missing = swiftbuild.toolchain(opts.swiftc, major)
  if not sdk then
    if log then log.i("swift chooser, " .. missing .. ", so the default chooser serves") end
    return
  end
  local inConfigure, answered = true, false
  swiftbuild.ensure(M.spec({ dir = opts.dir, swiftc = opts.swiftc, sdk = sdk,
    frameworks = hs.processInfo.bundlePath .. "/Contents/Frameworks" }), function(ok, result)
    answered = true
    if not ok then
      if log then log.e("swift chooser, the build failed, the default chooser serves, " .. tostring(result)) end
      return
    end
    if not inConfigure then
      if log then log.i("swift chooser, the library is built and takes over from the next reload") end
      return
    end
    local native, why = open(result)
    if not native then
      if log then log.e("swift chooser, the library did not load, the default chooser serves, " .. why) end
      return
    end
    NATIVE = native
    SwiftView.attach(native)
  end)
  inConfigure = false
  if not answered and log then
    log.i("swift chooser, building the library, the default chooser serves until the next reload")
  end
end

function M.configure(opts)
  opts = opts or {}
  if opts.fallback ~= nil then FALLBACK = opts.fallback end
  if opts.log ~= nil then LOG = opts.log end
  Engine.configure({ ui = opts.ui, yields = opts.yields, listKeys = opts.listKeys })
  SwiftView.configure({ ui = opts.ui, icon = opts.icon })
  if opts.dir ~= nil and not NATIVE then prepare(opts) end
  return M
end

function M.uses(keyCode, mods)
  if NATIVE then return Engine.uses(keyCode, mods, fieldKeys.resolve) end
  if FALLBACK and FALLBACK.uses then return FALLBACK.uses(keyCode, mods) end
  return nil
end

--- M.iconsChanged() repaints the icons of every list this provider has on screen, called by the
--- root when an icon source has finished pictures in the background. A list served by the
--- fallback is the fallback provider's own, which the root asks too.
function M.iconsChanged()
  SwiftView.iconsChanged()
end

--- M.serving() -> "swift" when the native library is loaded and every new builds through it,
--- "fallback" otherwise, for a probe or a test to read.
function M.serving()
  return NATIVE and "swift" or "fallback"
end

function M.paneBackend()
  if not NATIVE then return nil end
  return SwiftPane.factory(NATIVE, LOG)
end

--- M.paneDebug(id) -> the native library's read only account of a docked pane, where it is
--- hosted, its frames and what it last drew, or of every pane keyed by id when id is nil. Nil
--- while the library is not loaded. For a live look through hs, see paneDebug in
--- native/Entry.swift for the fields.
function M.paneDebug(id)
  if not NATIVE then return nil end
  return NATIVE.paneDebug(id)
end

--- M.new(config) answers an instance satisfying lib/chooser/contract.lua, the engine over the
--- native view when the library is loaded, and the fallback provider's own instance otherwise.
function M.new(config)
  if NATIVE then
    return Engine.new(config, function(engine) return SwiftView.new(engine, NATIVE) end)
  end
  if not FALLBACK then
    error("Swift provider: M.configure must be called with opts.fallback before M.new, since "
      .. "the native library is not loaded and there is nothing else to build with")
  end
  return FALLBACK.new(config)
end

return M
