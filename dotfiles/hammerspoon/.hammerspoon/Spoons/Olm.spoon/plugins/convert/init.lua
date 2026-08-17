--- === Convert ===
---
--- Converts units and currencies from a typed query and offers the answer as a row. Like
--- Arithmetic it is a query row source, not a picker, so it owns no chooser, no key, and
--- no window, and it returns rows as plain data for whatever surface composes it.
---
--- It is a separate spoon from Arithmetic on purpose. Conversion needs a calculator tool
--- from outside Hammerspoon and unit and currency knowledge nothing here has, so it can
--- legitimately be absent, and it declares that tool as required. When the tool is
--- missing the composition root leaves this spoon out of the launcher's sources entirely,
--- so no row, no partial answer, and no explanation clutters the list, while arithmetic
--- keeps working untouched. The console says once what was left out and why. Splitting
--- the two is what makes that possible, one spoon carrying both would have to disable
--- half of itself at runtime.
---
--- Why an explicit target is required. The tool runs as a separate process, which costs
--- tens of milliseconds, so it must never run while someone is searching for an app. A
--- query is treated as a conversion only when it carries a number and names a target
--- after `to`, as in ten kilometres to miles. That is a deliberate narrowing rather than
--- a limit of the tool, and it means an ordinary search never spawns anything.
---
--- Why the answer arrives late, and how that is handled. A process cannot answer inside
--- the synchronous call that builds rows, so a new query returns a pending row, the run
--- is debounced so a burst of keystrokes launches one process rather than one per
--- character, and the result is cached and announced through an injected callback the
--- presenter uses to redraw. Each run carries a generation number, so an answer to a
--- query the user has already moved past is discarded instead of replacing a newer one.
---
--- This is the olm side copy of Convert, phase six of the olm build plan, and the
--- original this was copied from lived at Spoons/Convert.spoon.

local obj = {}
obj.__index = obj

obj.name = "Convert"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

local log = hs.logger.new("Convert", "info")

-- The name this tool is declared under in the dependencies file beside this init.lua.
-- The root looks the path up by it, so the declaration and this spoon agree on one
-- spelling and a rename fails visibly rather than silently.
obj.tool = "qalc"

-- Injected via configure
obj._path = nil        -- resolved absolute path of the calculator tool
obj._glyph = nil
obj._category = nil
obj._onResult = nil    -- called when a late answer lands, so the presenter can redraw
obj._debounce = nil    -- seconds to wait for typing to stop before running

-- Owned state
obj._cache = nil       -- query -> { value = string } or { miss = true }
obj._pending = nil     -- query currently being run, so a burst does not queue twice
obj._generation = nil  -- run counter, so a stale answer is dropped
obj._timer = nil       -- the debounce timer, held so it lives long enough to fire

-- The cache is per session and small on purpose. Conversions are typed in bursts and
-- currency rates move, so there is nothing worth keeping across a reload, and a cap keeps
-- a long session from growing it without bound.
local CACHE_MAX = 200

-- The flags every run carries, and why each one is here.
--
-- Terse output keeps stdout to the answer alone. Limiting implicit multiplication is what
-- turns an unknown word into a failure instead of an answer, because without it the tool
-- reads `bogus` as a product of the single letter units b, o, g, u and s and returns a
-- number for a query nobody meant. Never updating exchange rates keeps a keystroke off the
-- network, since the tool's default is to ask, and either a prompt or a download inside a
-- background task is a hang waiting to happen. Currency therefore uses the rate file
-- already on disk, and refreshing it is a deliberate `qalc -e` in a terminal.
local FLAGS = { "-t", "-set", "limimpl on", "-set", "upxrates 0" }

-- The tool's own conversion operators. The word `in` is deliberately absent even though it
-- reads naturally, because the tool parses `in` as inches, so `5 ft in cm` answers with a
-- volume rather than failing and nothing here can tell the two readings apart. The tool
-- documents `to` and the arrow, and those are what this accepts.
local OPERATORS = { " to ", "->" }

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

--- Convert:init()
--- Method
--- Initialize. No side effects, per the lifecycle contract.
function obj:init()
  self._cache = {}
  self._generation = 0
  return self
end

--- Convert:configure(opts)
--- Method
--- opts.deps     the dependency scope this plugin earned by declaring a tool at all, asked
---               here for the calculator's resolved absolute path. This spoon probes for
---               nothing and names no way to install anything.
---
---               It reads the same door every other plugin with a tool reads, and it used
---               to read a bare opts.path instead. Nothing ever supplied that, because a
---               bare path was something the retired root handed over by hand and the
---               entitlement replaced. The plugin wired, registered and answered rows on
---               every keystroke, and every one of those rows was empty, since the very
---               first line of rows returns nothing without a path. A plugin reading a
---               field nobody sends fails exactly this quietly, which is why there is one
---               door rather than one per plugin.
--- opts.glyph    the character shown as the row icon, rendered by the presenter.
--- opts.category the word leading the row subtitle, so the visible wording stays config.
--- opts.redraw   called with no arguments when a late answer lands, so the presenter can
---               redraw its list. Omit it and a result simply appears the next time rows
---               are asked for. Named redraw because it is the root's own one word for this,
---               shared with every plugin that answers later than the keystroke did, and a
---               root value is delivered by field name so the name has to be the shared one.
--- opts.debounce seconds of quiet before a run starts, defaulting to a quarter second.
function obj:configure(opts)
  opts = opts or {}
  self._path = opts.deps and opts.deps.path(self.tool) or nil
  self._glyph = opts.glyph or "📐"
  self._category = opts.category or "Convert"
  self._onResult = opts.redraw
  self._debounce = opts.debounce or 0.25
  return self
end

-- Split a query at its last conversion operator. The last one is the operator because the
-- tool takes the target at the end of the expression, and an earlier one may belong to the
-- expression itself, as the inches in `10 in to cm` would if `in` were accepted. Matched on
-- a lowered copy so the word is case insensitive, and on byte positions in the original so
-- the slices keep their case. Returns the expression and the target, both trimmed, or nil
-- when there is no operator with content on both sides.
local function splitTarget(q)
  local low = q:lower()
  local at, stop
  for _, op in ipairs(OPERATORS) do
    local from = 1
    while true do
      local s, e = low:find(op, from, true)
      if not s then break end
      if not at or s > at then at, stop = s, e end
      from = s + 1
    end
  end
  if not at then return nil end
  local expression = trim(q:sub(1, at - 1))
  local target = trim(q:sub(stop + 1))
  if expression == "" or target == "" then return nil end
  return expression, target
end

-- The gate. A query must carry a digit and name a target, so a number alone, a word alone,
-- and an app name never reach the tool.
local function conversionParts(q)
  if not q:match("%d") then return nil end
  return splitTarget(q)
end

-- Whether an answer is one clean value. A mixed unit answer arrives as a sum of units, and
-- the retry below can come back as an unevaluated expression, which always shows
-- parentheses.
local function isSingleValue(text)
  return not text:find(" + ", 1, true) and not text:find("(", 1, true)
end

-- Run one expression, off the main thread, and hand the answer to done, or nil when the
-- tool failed or said nothing. A non zero exit, empty output, or output the tool marks as an
-- error all count as no answer. A generation older than the current one is dropped without
-- calling done, which is what stops an answer to an abandoned query from replacing a newer
-- one and leaves the pending slot to whichever run owns it now.
--
-- The unicode minus the tool prints is replaced with a plain hyphen, because this answer
-- exists to be copied and a minus sign no parser accepts is a trap in a spreadsheet or a
-- source file. Nothing else in the answer is touched.
function obj:_exec(expression, generation, done)
  local args = {}
  for i, flag in ipairs(FLAGS) do args[i] = flag end
  args[#args + 1] = expression
  local task = hs.task.new(self._path, function(code, out, err)
    if generation ~= self._generation then return end
    local text = trim((out or ""):gsub("\226\136\146", "-"))
    if code ~= 0 or text == "" or text:lower():find("error", 1, true) then
      if code ~= 0 and (err or "") ~= "" then
        log.d("conversion failed for '" .. expression .. "', " .. tostring(err))
      end
      return done(nil)
    end
    done(text)
  end, args)
  if not task then return done(nil) end
  task:start()
end

-- Record an answer, release the pending slot, and let the presenter know. A query with no
-- answer is cached as a miss, so a typo is not retried on every keystroke.
function obj:_finish(query, text)
  self._pending = nil
  self._cache[query] = text and { value = text } or { miss = true }
  if self._onResult then self._onResult() end
end

-- Ask once, and ask a second time with mixed units disabled when the answer came back as a
-- sum of units.
--
-- Mixed units are the tool's default for customary lengths and for time, so `10 km to
-- miles` answers with miles plus yards plus inches, which reads well and copies badly. The
-- only lever the tool offers is a minus in front of the target and it has no setting for it,
-- so the target has to be rewritten. That happens only after seeing a sum rather than on
-- every run, because a target can also be a presentation command like hex or base instead
-- of a unit, and a minus in front of one of those yields an unevaluated expression. Waiting
-- for the sum means the vocabulary of those commands never has to be known here, the second
-- answer is used only when it is one clean value, and the common query costs one process.
function obj:_run(query, expression, target, generation)
  self:_exec(expression .. " to " .. target, generation, function(text)
    if text and not isSingleValue(text) and not target:match("^[%+%-]") then
      self:_exec(expression .. " to -" .. target, generation, function(retry)
        self:_finish(query, (retry and isSingleValue(retry)) and retry or text)
      end)
      return
    end
    self:_finish(query, text)
  end)
end

--- Convert:rows(query) -> list
--- Method
--- The query row source contract, the same one Arithmetic implements. Returns an empty
--- list for anything that is not a conversion request, a pending row while the tool runs,
--- and the answer once it lands. A query already known to have no answer returns nothing,
--- so a typo does not leave a stale row sitting in the list.
---
--- Rows are plain data carrying a glyph rather than an image and a serializable descriptor
--- rather than a function, matching every other launcher row. filterText is the raw query
--- so a presenter that ranks with a matcher keeps this row at the top rather than scoring
--- the answer against the question.
function obj:rows(query)
  if not self._path then return {} end
  local q = trim(query or "")
  local expression, target = conversionParts(q)
  if not expression then return {} end

  local hit = self._cache[q]
  if hit then
    if hit.miss then return {} end
    return {
      {
        title = hit.value,
        subTitle = self._category .. " · " .. q .. " · copy the result",
        glyph = self._glyph,
        filterText = query,
        item = { kind = "calc", value = hit.value },
      },
    }
  end

  -- Not answered yet. Debounce a run and show a quiet placeholder meanwhile, so the row
  -- does not appear out of nowhere and the list does not jump as the answer replaces it.
  if self._pending ~= q then
    self._pending = q
    self._generation = self._generation + 1
    local generation = self._generation
    -- Trim before inserting rather than after, so the table never exceeds the cap.
    local count = 0
    for _ in pairs(self._cache) do count = count + 1 end
    if count >= CACHE_MAX then self._cache = {} end
    -- The timer is held in a field rather than dropped on the floor, and that is load
    -- bearing. A Hammerspoon timer is userdata whose finalizer stops it, so a pending
    -- timer nothing refers to can be collected before it ever fires. The presenter
    -- rebuilds its whole row list on every keystroke, which is enough allocation to bring
    -- a collection down inside this quarter second, and the symptom is a placeholder that
    -- sits there forever because the pending slot below is only released by an answer.
    -- Stopping the previous one first also means one timer is outstanding at a time.
    if self._timer then self._timer:stop() end
    self._timer = hs.timer.doAfter(self._debounce, function()
      self._timer = nil
      if generation ~= self._generation then return end
      self:_run(q, expression, target, generation)
    end)
  end
  return {
    {
      title = "Converting",
      subTitle = self._category .. " · " .. q,
      glyph = self._glyph,
      filterText = query,
      enabled = false,
      item = { kind = "calc", value = nil },
    },
  }
end

return obj
