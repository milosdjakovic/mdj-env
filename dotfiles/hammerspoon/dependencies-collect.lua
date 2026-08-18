-- Read every plugin manifest and emit this module's upward facing declaration lines.
--
-- Run by dependencies-collect, which finds the manifests and hands them over as arguments.
-- Finding files is what a shell is good at and reading Lua is what Lua is good at, so the
-- split falls there rather than in a hand written parser for a real language, which works
-- until the day a manifest formats an entry differently and then drops a tool in silence.
--
-- A manifest is pure data by contract, so loading one runs nothing that could touch the
-- machine, and a manifest that is not pure data fails here loudly instead of being half
-- read. Every field is checked on the way past, because a bad line poisons the layer above
-- and a generator is the cheapest place to catch it.
--
-- Eight fields per line, name, kind, locator, policy, consumer, reason, origin, and origin
-- detail. The consumer is stamped from where the declaration sits rather than written by
-- hand, so a file cannot mislabel itself and a rename cannot leave a stale owner behind. A
-- tool entry may name the unit inside the plugin that wanted it, and the stamp then reads
-- plugin slash unit, which is how a missing tool names the provider that wanted it rather
-- than the whole plugin.
--
-- The last two fields are empty for a tool that states no origin. Where a tool comes from is
-- stated exactly once in this repository, either beside the thing that needs it or in the map
-- one layer up, and the reconciler above proves it is once rather than twice or never.

local KINDS = {
  path = true,     -- a command on PATH
  system = true,   -- a fixed absolute path
  app = true,      -- a macOS bundle id
  manual = true,   -- a marker path proving a hand installed thing arrived
  package = true,  -- ships files rather than a command, so the package manager is asked
}

-- The origins the map one layer up understands. Checked here because an origin key nobody
-- recognises would otherwise pass through as an empty column and read as a tool that simply
-- states no origin, which is the one thing this field exists to distinguish.
local ORIGINS = {
  brew = true, cask = true, tap = true, ["xcode-clt"] = true, macos = true, manual = true,
}

local failures = {}
local function fail(where, message)
  failures[#failures + 1] = where .. ", " .. message
end

-- Which plugin a manifest belongs to, read off its path. The directory rather than the name
-- the plugin declares for itself, deliberately. This column tells a person where to go and
-- edit the declaration, and that is the directory. The identity a plugin declares is the
-- runtime's business and appears nowhere in this file.
local function consumerOf(path)
  return path:match("([^/]+)/manifest%.lua$") or path
end

local lines = {}
for _, path in ipairs(arg) do
  local chunk, loadErr = loadfile(path)
  if not chunk then
    fail(path, "would not load, " .. tostring(loadErr))
  else
    local okCall, manifest = pcall(chunk)
    if not okCall then
      fail(path, "raised while loading, " .. tostring(manifest))
    elseif type(manifest) ~= "table" then
      fail(path, "returned " .. type(manifest) .. " rather than a table")
    else
      local consumer = consumerOf(path)
      for index, tool in ipairs(((manifest.needs or {}).tools or {})) do
        local where = consumer .. " tool " .. index
        if type(tool) ~= "table" then
          fail(where, "is a " .. type(tool) .. " rather than a table")
        else
          local name = tool.name
          local kind = tool.kind
          local locator = tool.locator or tool.name
          local policy = tool.policy
          local reason = tool.reason

          if type(name) ~= "string" or name == "" then
            fail(where, "has no name")
            name = nil
          end
          -- These two are checked before anything concatenates them, rather than after, because
          -- concatenating a table is a raw Lua error that takes the whole run down with a
          -- traceback instead of one reported line. A generator that crashes tells you less than
          -- one that names the field, which is the entire reason these checks exist.
          if type(locator) ~= "string" or locator == "" then
            fail(where .. " (" .. tostring(name) .. ")", "has a locator that is a "
              .. type(locator) .. " rather than a string")
            locator = nil
          end
          if tool.unit ~= nil and type(tool.unit) ~= "string" then
            fail(where .. " (" .. tostring(name) .. ")", "names a unit that is a "
              .. type(tool.unit) .. " rather than a string")
          end
          local owner = (type(tool.unit) == "string") and (consumer .. "/" .. tool.unit)
            or consumer
          if not KINDS[kind] then
            fail(where .. " (" .. tostring(name) .. ")", "has kind " .. tostring(kind)
              .. ", which is not one of path, system, app, manual, or package")
          end
          if policy ~= "required" and policy ~= "optional" then
            fail(where .. " (" .. tostring(name) .. ")", "has policy " .. tostring(policy)
              .. ", which is neither required nor optional")
          end
          if type(reason) ~= "string" or reason == "" then
            fail(where .. " (" .. tostring(name) .. ")", "states no reason, so a missing "
              .. "tool could not say what it costs")
          end
          -- An absolute locator is what proves presence for these two kinds, and a bare
          -- command name there resolves against nothing and reports the tool absent on every
          -- machine. Silent, and fatal for a required one.
          if locator and (kind == "system" or kind == "manual") and locator:sub(1, 1) ~= "/"
            and locator:sub(1, 1) ~= "~" then
            fail(where .. " (" .. tostring(name) .. ")", "is kind " .. kind
              .. " but its locator " .. locator .. " is not an absolute path")
          end

          local origin, detail = "", ""
          if tool.origin ~= nil then
            if type(tool.origin) ~= "table" then
              fail(where .. " (" .. tostring(name) .. ")", "has an origin that is a "
                .. type(tool.origin) .. " rather than a table")
            else
              local count = 0
              for key, value in pairs(tool.origin) do
                count = count + 1
                if not ORIGINS[key] then
                  fail(where .. " (" .. tostring(name) .. ")", "states origin " .. tostring(key)
                    .. ", which is not one the map above understands")
                elseif type(value) ~= "string" or value == "" then
                  fail(where .. " (" .. tostring(name) .. ")", "states origin " .. key
                    .. " with no detail")
                else
                  origin, detail = key, value
                end
              end
              if count > 1 then
                fail(where .. " (" .. tostring(name) .. ")", "states " .. count
                  .. " origins, and a tool comes from one place")
              end
            end
          end

          for field, value in pairs({ name = name, locator = locator, reason = reason,
                                      detail = detail }) do
            if type(value) == "string" and value:find("|", 1, true) then
              fail(where .. " (" .. tostring(name) .. ")", "has a pipe in its " .. field
                .. ", which is the field separator of the file this becomes")
            end
          end

          -- A line is written only when the two fields that cannot be stood in for are real
          -- strings. Every other field renders through tostring, so a bad one still produces a
          -- readable line beside the reported problem, which is more useful than nothing while
          -- somebody is fixing it.
          if name and locator then
            -- Trailing separators are trimmed rather than padded out, so a line for a tool
            -- that states no origin ends at its reason instead of carrying two empty columns
            -- a reader has to count past.
            local line = table.concat({
              name, tostring(kind), locator, tostring(policy), owner, tostring(reason),
              origin, detail,
            }, " | ")
            lines[#lines + 1] = (line:gsub("[%s|]+$", ""))
          end
        end
      end
    end
  end
end

if #failures > 0 then
  io.stderr:write("dependencies-collect: " .. #failures .. " manifest problem(s)\n")
  for _, message in ipairs(failures) do
    io.stderr:write("  " .. message .. "\n")
  end
  os.exit(1)
end

io.write(table.concat(lines, "\n"))
if #lines > 0 then io.write("\n") end
