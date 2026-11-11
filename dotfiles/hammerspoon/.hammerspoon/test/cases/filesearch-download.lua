-- Unit case for Download in file search, step 1.4i of docs/PLAN-STANDALONE.md,
-- docs/DESIGN-APP-DOWNLOAD.md. The verb is declared once, in the manifest Olm.app reads its row and
-- its key from, and the Lua list never offers it, since its preview reads the file and so
-- downloads it. The chooser loads by path into an environment of its own over a stand in hs.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local fs = caseDir .. "/../../Spoons/Olm.spoon/plugins/filesearch/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  elseif detail then
    print("FAIL " .. description .. ", " .. tostring(detail))
  else
    print("FAIL " .. description)
  end
end

local noop = function() end
local stub = setmetatable({}, { __index = function() return noop end, __call = noop })
local fakeHs = setmetatable({
  logger = { new = function() return stub end },
}, { __index = function() return stub end })
local env = setmetatable({ hs = fakeHs }, { __index = _G })
env.loadfile = function(path, mode, e) return loadfile(path, mode or "t", e or env) end

local manifest = assert(loadfile(fs .. "manifest.lua", "t", {}))()
local row
for _, r in ipairs(manifest.surface.extra or {}) do
  if r.action == "download" then row = r end
end
check("Download is declared on G, listed only over a placeholder",
  row ~= nil and row.key == "g" and row.applies == "isPlaceholder" and row.description == "Download")
check("with an icon the manifest names", row and manifest.icons[row.icon] ~= nil)

local ok, chooser = pcall(function() return assert(env.loadfile(fs .. "chooser.lua"))() end)
check("the chooser loads", ok, chooser)
if ok then
  check("the Lua list answers no placeholder", chooser:isPlaceholder({ path = "/a.pdf" }) == false)
  check("and its verb does nothing", type(chooser.download) == "function" and chooser.download() == nil)
end
