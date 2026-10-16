-- Unit case for the theme reader and store under Olm.spoon/lib/ui, stage three of
-- docs/DESIGN-UI-KIT.md. The runner reaches this file with a dofile call carrying an
-- absolute path, so this file locates itself through debug.getinfo and derives every module
-- path from there. Both modules are plain Lua, so nothing here touches a disk or hs.settings,
-- the file reader, the directory lister and the settings are all stand ins.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local uiDir = caseDir .. "/../../Spoons/Olm.spoon/lib/ui/"

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    print("FAIL " .. description .. (detail and (", " .. detail) or ""))
  end
end

local function fresh(name)
  local chunk, err = loadfile(uiDir .. name)
  if not chunk then error("could not load lib/ui/" .. name .. ", " .. tostring(err)) end
  return chunk()
end

--------------------------------------------------------------------------------
-- toml
--------------------------------------------------------------------------------

local toml = fresh("toml.lua")

do
  local parsed = toml.parse([[
# a comment, then a blank line

top = "before any section"

[dark]
text = "#ebebeb"   # a trailing comment
border="#59575c"
  # an indented comment
[light]
text = "#262626"
]], "theme.toml")
  check("toml reads a key before any section into the unnamed one", parsed[""].top == "before any section")
  check("toml reads sections and keys", parsed.dark.text == "#ebebeb" and parsed.dark.border == "#59575c"
    and parsed.light.text == "#262626")
  check("toml keeps a hash inside a quoted string", toml.parse('[a]\nk = "#fff"\n').a.k == "#fff")
end

do
  local ok, err = pcall(toml.parse, '[dark]\ntext = "#ebebeb"\nsubtext = 0.5\n', "bad.toml")
  check("toml refuses a line outside the subset", not ok)
  check("toml names the file and the line number", type(err) == "string" and err:find("bad.toml, line 3", 1, true) ~= nil, tostring(err))
  local ok2, err2 = pcall(toml.parse, '[dark]\nk = "a"\nk = "b"\n', "twice.toml")
  check("toml refuses a key set twice", not ok2 and tostring(err2):find("twice.toml, line 3", 1, true) ~= nil)
  local ok3 = pcall(toml.parse, '[dark]\n[dark]\n', "x")
  check("toml refuses a section declared twice", not ok3)
  local ok4 = pcall(toml.parse, 'k = "a" extra\n', "x")
  check("toml refuses text after the string", not ok4)
end

do
  local ok, err = pcall(toml.read, "missing.toml", function() return nil end)
  check("toml read names a file that is not there", not ok and tostring(err):find("missing.toml", 1, true) ~= nil)
  check("toml read parses what the reader answers",
    toml.read("a.toml", function() return '[s]\nk = "v"\n' end).s.k == "v")
end

--------------------------------------------------------------------------------
-- themes
--------------------------------------------------------------------------------

local themes = fresh("themes.lua")

-- theme-exempt, fixture colours for a unit case, not a tool's look
local DEFAULT_FILE = [[
[dark]
foreground = "#111111"
subtext = "#222222"
background = "#333333"
border = "#444444"
highlight = "#555555"
primary = "#666666"
secondary = "#777777"
tertiary = "#888888"

[light]
foreground = "#aaaaaa"
subtext = "#bbbbbb"
background = "#cccccc"
border = "#dddddd"
highlight = "#eeeeee"
primary = "#101010"
secondary = "#202020"
tertiary = "#303030"
]]

local function store(files, stored, extra)
  local warnings = {}
  local set = {}
  local opts = {
    dir = "themes",
    list = function() local names = {}; for name in pairs(files) do names[#names + 1] = name end; return names end,
    read = function(path) return files[path:match("([^/]+)$")] end,
    store = { get = function() return stored end, set = function(k, v) set[k] = v end },
    log = { w = function(message) warnings[#warnings + 1] = message end },
  }
  for k, v in pairs(extra or {}) do opts[k] = v end
  return themes.new(opts), warnings, set
end

do
  local s = store({ ["zeta.toml"] = DEFAULT_FILE, ["default.toml"] = DEFAULT_FILE,
                    ["alpha.toml"] = DEFAULT_FILE, ["notes.txt"] = "ignored" })
  local names = s.names()
  check("names are sorted and only the toml files", #names == 3 and names[1] == "alpha"
    and names[2] == "default" and names[3] == "zeta")
  check("the current theme is default when nothing is stored", s.current() == "default")
  check("colors answers the current theme's halves", s.colors().dark.foreground == "#111111"
    and s.colors().light.foreground == "#aaaaaa")
  check("every one of the eight roles is answered", s.colors().dark.primary == "#666666"
    and s.colors().light.tertiary == "#303030")
end

do
  local changes, specs = {}, {}
  local ui = { configure = function(c) specs[#specs + 1] = c.spec end }
  local s, _, set = store({ ["default.toml"] = DEFAULT_FILE, ["bright.toml"] = DEFAULT_FILE },
    nil, { ui = ui, specFor = function(colors) return { foreground = colors.dark.foreground } end,
           onChange = function(name) changes[#changes + 1] = name end })
  check("set answers true for a loaded theme", s.set("bright") == true)
  check("set persists through the injected settings", set.olmTheme == "bright")
  check("set makes the theme current", s.current() == "bright")
  check("set hands the kit the new spec", #specs == 1 and specs[1].foreground == "#111111")
  check("set calls onChange with the name", #changes == 1 and changes[1] == "bright")
  check("set refuses a name with no file", s.set("nothing") == false and s.current() == "bright"
    and set.olmTheme == "bright")
end

do
  local s, warnings = store({ ["default.toml"] = DEFAULT_FILE, ["quiet.toml"] = DEFAULT_FILE }, "gone")
  check("an unknown persisted name falls back to default", s.current() == "default")
  check("an unknown persisted name warns once", #warnings == 1 and warnings[1]:find("gone", 1, true) ~= nil)
  s.colors(); s.colors()
  check("asking again does not warn again", #warnings == 1)
end

do
  local s = store({ ["default.toml"] = DEFAULT_FILE, ["quiet.toml"] = DEFAULT_FILE }, "quiet")
  check("a persisted name with a file is the current theme", s.current() == "quiet")
end

do
  local darkOnly = [[
[dark]
foreground = "#010101"
subtext = "#020202"
background = "#030303"
border = "#040404"
highlight = "#050505"
primary = "#060606"
secondary = "#070707"
tertiary = "#080808"
]]
  local s, warnings = store({ ["default.toml"] = DEFAULT_FILE, ["dim.toml"] = darkOnly }, "dim")
  local c = s.colors()
  check("a missing light half is the theme's dark half", c.light.foreground == "#010101" and c.light.tertiary == "#080808")
  check("a missing light half is not a warning", #warnings == 0)
end

do
  local missingKey = [[
[dark]
foreground = "#010101"
background = "#030303"
border = "#040404"
highlight = "#050505"
primary = "#060606"
secondary = "#070707"
tertiary = "#080808"

[light]
foreground = "#0a0a0a"
subtext = "#0b0b0b"
background = "#0c0c0c"
border = "#0d0d0d"
highlight = "#0e0e0e"
primary = "#0f0f0f"
secondary = "#101011"
tertiary = "#121212"
]]
  local s, warnings = store({ ["default.toml"] = DEFAULT_FILE, ["gap.toml"] = missingKey }, "gap")
  local c = s.colors()
  check("a missing key takes the default theme's value for that half", c.dark.subtext == "#222222"
    and c.light.subtext == "#0b0b0b")
  check("a missing key warns once naming the theme and the key", #warnings == 1
    and warnings[1]:find("gap", 1, true) ~= nil and warnings[1]:find("subtext", 1, true) ~= nil, tostring(warnings[1]))
  s.colors()
  check("a missing key does not warn again", #warnings == 1)
end

do
  local s, warnings = store({ ["default.toml"] = DEFAULT_FILE,
    ["broken.toml"] = '[dark]\ntext = 3\n' })
  check("a theme file with a refused line is left out", #s.names() == 1 and s.names()[1] == "default")
  check("a refused line warns with the file and line", #warnings == 1
    and warnings[1]:find("broken.toml, line 2", 1, true) ~= nil, tostring(warnings[1]))
end

do
  local withAlpha = DEFAULT_FILE:gsub('tertiary = "#888888"', 'tertiary = "#88888880"', 1)
  local s = store({ ["default.toml"] = withAlpha })
  check("an eight digit colour is kept", s.colors().dark.tertiary == "#88888880")
  local extra = DEFAULT_FILE:gsub('%[light%]', 'meta = "#12345678"\n\n[light]', 1)
  local old = store({ ["default.toml"] = extra })
  check("a key beyond the eight is dropped rather than carried", old.colors().dark.meta == nil)
end

--------------------------------------------------------------------------------
-- the style takes a hex with alpha
--------------------------------------------------------------------------------

do
  local style = fresh("style.lua").new({ appearance = function() return "Dark" end })
  style.configure({ colors = { dark = { foreground = "#ff000080", background = "#000000" } } })
  local c = style.tokens().colors
  check("style reads an eight digit hex as a colour with alpha",
    c.foreground.red == 1 and math.abs(c.foreground.alpha - 128 / 255) < 1e-6)
  check("style still reads a six digit hex as opaque", c.background.alpha == 1)
end
