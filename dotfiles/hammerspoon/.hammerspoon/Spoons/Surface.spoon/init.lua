--- === Surface ===
---
--- One themed webview foundation for every picker surface, the replacement for
--- the native hs.chooser. This spoon is the composition root, it loads the shell
--- engine, the searchable list type, and the disk backed icon cache, names them,
--- and hands back a factory for list instances plus the cache for the root to
--- warm.
---
--- The shell owns the invariant webview scaffolding, geometry, focus, the frosted
--- backdrop, click away dismissal, the previous window restore, and the message
--- bridge. The list type owns the searchable list page and its protocol. The icon
--- cache persists encoded PNGs so the app icons are not re-encoded on every reload.
--- Adding another surface type, a split for the clipboard or a grid for the cheat
--- sheet, is a new sibling file plus one factory line here, with no change to the
--- shell.
---
--- Usage from the composition root:
---   spoon.Surface:init()
---   spoon.Surface:configure({ iconCacheDir = "~/.cache/hs-icons" })
---   local picker = spoon.Surface:newList({ theme = ..., rows = ..., onSelect = ... })
--- newList takes the same config the old Chooser atom did (theme, rows, onSelect,
--- onHighlight, onClose, onInput, fieldMode, placeholder, layout), plus optional
--- typePrefixes for a leading type token and iconKey per row for the disk cache.

local obj = {}
obj.__index = obj
obj.name = "Surface"
obj.version = "1.0"
obj.author = "mdj-env"

-- Load siblings by absolute path, the Capture idiom, since a spoon dir is not on
-- package.path.
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local function load(name)
  local chunk, err = loadfile(spoonPath .. name)
  if not chunk then
    error("Surface: failed to load " .. name .. ": " .. tostring(err))
  end
  return chunk()
end

local shell = load("shell.lua")
local list = load("list.lua")
local grid = load("grid.lua")

--- obj.iconcache - the disk backed icon cache module. The root configures its
--- directory and drives reconcile and warm for the app icons; list instances read
--- it to resolve an iconKey row to a data URI.
obj.iconcache = load("iconcache.lua")

--- Surface:init() - nothing to build yet; the cache directory is set in configure.
function obj:init()
  return self
end

--- Surface:configure(opts) - opts.iconCacheDir sets and creates the icon cache
--- folder. A leading ~ is expanded, since a spoon config often writes paths that
--- way. Safe to call before any list is built.
function obj:configure(opts)
  opts = opts or {}
  if opts.iconCacheDir then
    local dir = opts.iconCacheDir:gsub("^~", os.getenv("HOME"))
    obj.iconcache.configure({ dir = dir })
  end
  return self
end

--- Surface:newList(config) -> list instance. Injects the shell factory and the
--- icon cache so the list stays ignorant of how either is built.
function obj:newList(config)
  return list.new(config, { shell = shell, iconcache = obj.iconcache })
end

--- Surface:newGrid(config) -> grid instance. A passive, display only overlay host
--- for the cheat sheets, sharing the shell so it wears the same frosted panel and
--- theme as the lists. Injects only the shell, since a grid resolves no icons of
--- its own, the caller hands it fully positioned HTML.
function obj:newGrid(config)
  return grid.new(config, { shell = shell })
end

return obj
