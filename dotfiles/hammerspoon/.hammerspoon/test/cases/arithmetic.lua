-- Unit case for Olm.spoon/plugins/arithmetic/init.lua, the query row source that
-- evaluates a typed expression. The runner reaches this file with a dofile call
-- carrying an absolute path, so this file in turn locates itself the same way,
-- through debug.getinfo, and derives the module path from there. No absolute path is
-- ever written down here, and the module under test is only loaded, never edited.
--
-- Each check prints one line, PASS or FAIL followed by a plain description, and the
-- runner counts and reports from those lines alone, the same convention cases/match.lua
-- and cases/recency.lua already follow.
--
-- evaluate needs no per instance state, so the loaded module is used directly rather
-- than through configure and an instance of its own.

local source = debug.getinfo(1, "S").source
local herePath = source:match("^@(.*)$") or source
local caseDir = herePath:match("^(.*)/[^/]+$")
local modulePath = caseDir .. "/../../Spoons/Olm.spoon/plugins/arithmetic/init.lua"

local moduleChunk, loadErr = loadfile(modulePath)
if not moduleChunk then
  print("FAIL load Olm.spoon/plugins/arithmetic/init.lua, " .. tostring(loadErr))
  return
end
local Arithmetic = moduleChunk()

local function check(description, ok, detail)
  if ok then
    print("PASS " .. description)
  else
    if detail then
      print("FAIL " .. description .. ", " .. detail)
    else
      print("FAIL " .. description)
    end
  end
end

local function near(a, b)
  return a ~= nil and math.abs(a - b) < 1e-9
end

-- The baseline, unaffected by the percent rewrite.

do
  local value = Arithmetic:evaluate("2+2")
  check("a plain sum still answers", near(value, 4), tostring(value))
end

-- The unit reading, a number followed by an operator, a closing parenthesis, or the
-- end of the string, rewrites to a division by one hundred.

do
  local value = Arithmetic:evaluate("2+2%")
  check("2+2% reads the percent as a unit and answers 2.02", near(value, 2.02), tostring(value))
end

do
  local value = Arithmetic:evaluate("200*10%")
  check("200*10% answers 20", near(value, 20), tostring(value))
end

do
  local value = Arithmetic:evaluate("50%*80")
  check("50%*80 answers 40", near(value, 40), tostring(value))
end

do
  local value = Arithmetic:evaluate("2%+5%")
  check("two percent terms in one query both rewrite, 2%+5% answers 0.07", near(value, 0.07), tostring(value))
end

do
  local value = Arithmetic:evaluate("10%^2")
  check("10%^2 rewrites to (10/100)^2 and answers 0.01", near(value, 0.01), tostring(value))
end

-- The modulo reading survives, a percent followed by a digit or a decimal point is
-- left untouched.

do
  local value = Arithmetic:evaluate("7%3")
  check("7%3 still answers 1 as modulo", near(value, 1), tostring(value))
end

-- The cases that still produce no row.

do
  local value = Arithmetic:evaluate("%")
  check("a lone percent produces no row", value == nil, tostring(value))
end

do
  local value = Arithmetic:evaluate("(2+2)%")
  check("a percent right after a closing parenthesis is out of scope and produces no row", value == nil, tostring(value))
end

do
  local value = Arithmetic:evaluate("2+%")
  check("a malformed expression still produces no row", value == nil, tostring(value))
end
