-- Unit case for the clipboard capture readers, plugins/clipboard/manager/readers.lua, walked
-- the way the monitor walks them, the first reader that matches owning the copy. It pins the
-- Universal Clipboard case, a copy from another device that arrives as a file url this
-- process cannot open beside the image's real bytes, which must be recorded as an image
-- named after the file, while a readable Finder copy stays a file. The pasteboard is a stand
-- in, so the live hs is never touched. The runner reaches this file with a dofile call
-- carrying an absolute path, so it locates itself through debug.getinfo and loads by path.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local manager = caseDir .. "/../../Spoons/Olm.spoon/plugins/clipboard/manager/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  elseif detail then
    print("FAIL " .. description .. ", " .. tostring(detail))
  else
    print("FAIL " .. description)
  end
end

-- What the pasteboard holds for one copy, set per scenario.
local board = {}
local fakeHs = {
  pasteboard = {
    readURL = function() return board.urls end,
    readImage = function() return board.image end,
  },
}
local env = setmetatable({ hs = fakeHs }, { __index = _G })

local util = assert(loadfile(manager .. "util.lua"))()
local readers = assert(loadfile(manager .. "readers.lua", "t", env))()
local chain = readers.build(util)

-- The monitor's walk, the first match owns the copy whatever its read answers.
local function capture(set, avail)
  local ctx = { set = set, avail = avail }
  for _, reader in ipairs(chain) do
    if reader.matches(ctx) then return reader.read(ctx) end
  end
  return nil
end

local image = { size = function() return { w = 805, h = 383 } end }

-- A file this process can open, standing in for a Finder copy.
local real = os.tmpname()
local f = assert(io.open(real, "wb")); f:write("x"); f:close()

-- The spool path from a synced copy, which here simply does not exist, so it cannot be opened.
local spool = "/nonexistent/shared-pasteboard/items/ABC/Screenshot 2026-10-27 at 13-21-07.png"

board = { urls = { { filePath = spool } }, image = image }
local e = capture({ ["public.file-url"] = true, ["public.png"] = true }, { URL = true, image = true })
check("an unopenable file url beside an image is recorded as an image", e and e.kind == "image",
  e and e.kind)
check("that image keeps the file's name as its title",
  e and e.title == "Screenshot 2026-10-27 at 13-21-07.png", e and e.title)
check("that image carries the pasteboard's bytes", e and e._img == image)

board = { urls = { { filePath = real } }, image = image }
e = capture({ ["public.file-url"] = true, ["public.tiff"] = true }, { URL = true, image = true })
check("a readable file url stays a file even with a thumbnail image", e and e.kind == "file",
  e and e.kind)
check("the file entry lists the readable path", e and e._paths and e._paths[1] == real)

board = { urls = { { filePath = spool } }, image = nil }
e = capture({ ["public.file-url"] = true }, { URL = true })
check("an unopenable file url with no image is still a file", e and e.kind == "file", e and e.kind)

board = { urls = nil, image = image }
e = capture({ ["public.png"] = true }, { image = true })
check("a plain image copy keeps its dimension title", e and e.title == "Image 805x383", e and e.title)

os.remove(real)
