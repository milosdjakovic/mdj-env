--- === BrowserTabs.jxa ===
---
--- The shared osascript runner every provider talks to a browser through. It is spoon
--- level mechanism rather than a backend, so it sits here beside the engine and not in
--- providers/, which stays one file per browser. It exists because all three providers
--- need the same plumbing, an off main thread osascript, a JSON parse, and one reading of
--- the failure, and the rule when two adapters need the same behavior is to share it
--- rather than duplicate it.
---
--- Why JavaScript for Automation and not AppleScript. A tab list is fetched by asking for
--- every title in one call and every URL in one call, which is one Apple Event per
--- property per window. The obvious per tab loop costs one event per property per tab and
--- is more than twenty times slower on a browser holding a hundred tabs, slow enough to
--- be unusable. JXA expresses the bulk form directly, returns JSON, and addresses an app
--- by bundle id, so no provider needs a separate scripting name.
---
--- Why hs.task and never hs.osascript. Even the bulk form takes a tenth of a second, most
--- of it the interpreter launch, and hs.osascript blocks the main thread for all of it.
--- Through hs.task the providers run concurrently and the whole fan out costs about as
--- long as the slowest single browser.

local M = {}

--- The one failure worth naming. macOS refuses an Apple Event to an app the calling
--- application has no Automation permission for, reporting errAEEventNotPermitted. The
--- callers turn this into an explanatory row and a request action rather than a bare
--- error, so it is a value and not just a message.
M.notPermitted = "notPermitted"

local OSASCRIPT = "/usr/bin/osascript"

-- Every task in flight, held here on purpose. An hs.task kept only in a local dies when that
-- local goes out of scope, because nothing else references it and Lua collects it before the
-- process finishes, so the callback never runs and the caller waits forever. Holding it until
-- its callback has fired is what keeps a listing from vanishing. Keyed by the task itself so
-- concurrent runs cannot displace one another.
local inFlight = {}

-- Read a failure. A refused Apple Event is reported as -1743, with wording that has
-- changed across macOS releases, so the numeric code is the reliable test and the wording
-- is only a fallback.
local function readError(stderr)
  local why = stderr or ""
  if why:find("-1743", 1, true) or why:lower():find("not authori", 1, true)
    or why:lower():find("not permitted", 1, true) then
    return M.notPermitted
  end
  why = why:gsub("^%s+", ""):gsub("%s+$", "")
  if why == "" then return "the browser did not answer" end
  return why
end

--- M.run(source, args, cb) - run a JXA source string with the given string arguments and
--- call cb(value, err) on the main thread. The source is expected to define run(argv) and
--- return a JSON string, which is decoded before the callback, so a provider deals in Lua
--- tables and never in text. A non zero exit, an unparseable body, or a spawn failure all
--- arrive as err with value nil, so a caller has one thing to check.
function M.run(source, args, cb)
  local argv = { "-l", "JavaScript", "-e", source }
  for _, a in ipairs(args or {}) do argv[#argv + 1] = a end

  local task
  task = hs.task.new(OSASCRIPT, function(code, stdout, stderr)
    inFlight[task] = nil
    if code ~= 0 then
      cb(nil, readError(stderr))
      return
    end
    local body = (stdout or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if body == "" then
      cb(nil, "the browser returned nothing")
      return
    end
    local ok, data = pcall(hs.json.decode, body)
    if not ok or type(data) ~= "table" then
      cb(nil, "the browser returned an unreadable answer")
      return
    end
    cb(data, nil)
  end, argv)

  if not task then
    cb(nil, "could not run osascript")
    return
  end
  inFlight[task] = true
  task:start()
end

return M
