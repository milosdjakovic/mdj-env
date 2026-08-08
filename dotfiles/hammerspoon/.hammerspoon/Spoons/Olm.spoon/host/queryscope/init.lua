--- === QueryScope ===
---
--- Scopes a query driven list down to one tool, chosen by a word the user types. Typing an
--- alias and a space hands the whole list over, so `k 2h` is the keep awake picker reached
--- from inside the launcher, and deleting the space hands the list straight back.
---
--- The scope is derived from the query on every keystroke and nothing is remembered, which
--- is the decision the rest of the design rests on. There is no mode to enter and none to
--- leave, so stepping back out is ordinary text editing rather than a second mechanism, and
--- the field and the behaviour can never disagree about which scope is live.
---
--- It is a query row source like any other, answering rows(query), with one extra answer. A
--- second return value says this source claims the query, so the presenter shows these rows
--- alone. That one bit is the entire seam, which is why the presenter learns nothing about
--- aliases, about the grammar, or about which tools can be scoped.
---
--- It names no scope. The composition root supplies them, each a small adapter over a tool
--- that already answers a rows and a select, so a tool never learns it can be scoped and
--- adding a scope is one entry in that root and no change here.
---
--- This is the olm side copy of QueryScope, made in the host into olm pass on 2026-08-07, and
--- the original this was copied from lived at Spoons/QueryScope.spoon.

local obj = {}
obj.__index = obj

obj.name = "QueryScope"
obj.version = "1.0"
obj.author = "Milos Djakovic"
obj.license = "MIT"

-- Injected via configure
obj._matcher = nil    -- shared filter strategy, applied for a scope that wants one
obj._scopes = nil     -- the admitted scopes, in the order they were given
obj._byAlias = nil    -- lowercased alias to scope
obj._byName = nil     -- scope name to scope, so a chosen row finds its way home

-- The separator between the alias and the rest of the query. A single space, and
-- deliberately not configurable. It is this spoon's own grammar rather than a binding, and
-- it is the one character whose removal must mean leave the scope, so making it a choice
-- would only create a way for two consumers to disagree about what leaving looks like.
--
-- Two forms of one decision. The pattern accepts any run of whitespace, since a query
-- arrives from a person typing and being strict there would only reject something that
-- plainly meant to enter a scope. SEPARATOR is the canonical text, which is what a caller
-- asking for the query that enters a scope is handed, so nobody outside this file ever
-- concatenates a space and decides for itself what entering looks like.
local SEPARATOR = " "
local SEPARATOR_PATTERN = "^(%S+)%s+(.*)$"

--- QueryScope:init()
--- Method
--- Initialize. Nothing is built until the scopes arrive.
function obj:init()
  self._scopes = {}
  self._byAlias = {}
  self._byName = {}
  return self
end

-- Whether a scope answers the whole contract, with the reason named in the console when it
-- does not. A scope is repository data rather than user input, so a malformed one is a
-- defect worth stating loudly, and dropping it alone keeps the rest of them working.
local function admissible(s)
  local function reject(why)
    hs.printf("QueryScope: ignoring a scope, %s", why)
    return false
  end
  if type(s) ~= "table" then return reject("it is not a table") end
  local label = tostring(s.name or "with no name")
  if type(s.name) ~= "string" or s.name == "" then return reject("it has no name") end
  if type(s.title) ~= "string" or s.title == "" then return reject(label .. " has no title") end
  if type(s.rows) ~= "function" then return reject(label .. " has no rows function") end
  if type(s.run) ~= "function" then return reject(label .. " has no run function") end
  -- Optional, so absence is fine and a wrong type is not. A scope that meant to offer a peek and
  -- handed over something uncallable would otherwise fail at the keystroke rather than at load.
  if s.peek ~= nil and type(s.peek) ~= "function" then
    return reject(label .. " has a peek that is not a function")
  end
  if s.redirect ~= nil and type(s.redirect) ~= "function" then
    return reject(label .. " has a redirect that is not a function")
  end
  if type(s.aliases) ~= "table" or #s.aliases == 0 then return reject(label .. " has no aliases") end
  return true
end

--- QueryScope:configure(opts)
--- Method
--- opts.scopes  the ordered scope list, each a table answering name, title, aliases, rows,
---              and run, plus an optional glyph, matcher, peek, and redirect.
--- opts.matcher the shared filter strategy a scope inherits, the same one the presenter
---              uses, so a list shaped scope filters exactly like every other list. A scope
---              setting matcher false owns its own filtering, which is right when its field
---              is a value being typed rather than a filter over rows.
---
--- Registration is order sensitive on purpose. The first scope to claim an alias keeps it
--- and a later claim is refused by name, so a collision is visible and resolves the same way
--- on every machine rather than depending on table order.
function obj:configure(opts)
  opts = opts or {}
  self._matcher = opts.matcher
  self._scopes = {}
  self._byAlias = {}
  self._byName = {}
  for _, s in ipairs(opts.scopes or {}) do
    if admissible(s) then
      if self._byName[s.name] then
        hs.printf("QueryScope: ignoring a second scope named %s", s.name)
      else
        self._byName[s.name] = s
        self._scopes[#self._scopes + 1] = s
        for _, a in ipairs(s.aliases) do
          local alias = tostring(a):lower()
          if alias:match("%s") or alias == "" then
            hs.printf("QueryScope: %s cannot use the alias %q, an alias is one word", s.name, tostring(a))
          elseif self._byAlias[alias] then
            hs.printf("QueryScope: %s cannot use the alias %q, %s already has it",
              s.name, alias, self._byAlias[alias].name)
          else
            self._byAlias[alias] = s
          end
        end
      end
    end
  end
  return self
end

--- QueryScope:aliasesOf(name) -> list
--- Method
--- The aliases a named scope actually holds, which is not always the aliases it asked for,
--- since a collision or a malformed one is refused above. Exposed so a surface that states
--- the aliases states the live ones rather than the requested ones.
function obj:aliasesOf(name)
  local out = {}
  local scope = self._byName[name]
  if not scope then return out end
  for _, a in ipairs(scope.aliases) do
    local alias = tostring(a):lower()
    if self._byAlias[alias] == scope then out[#out + 1] = alias end
  end
  return out
end

--- QueryScope:catalog() -> list
--- Method
--- Every scope that can actually be entered right now, each as a plain table of name, title,
--- glyph, and live aliases, in registration order. A scope whose aliases were all refused is
--- left out, since nothing could reach it and a row for it would do nothing.
---
--- It exists so a surface can list the aliases without asking any tool anything and without
--- reading the config the root built the scopes from, which is the only way such a list can
--- state what resolves rather than what was requested. It hands back data and no wording, so
--- how a list of aliases is phrased stays with whoever shows it.
function obj:catalog()
  local out = {}
  for _, s in ipairs(self._scopes) do
    local aliases = self:aliasesOf(s.name)
    if #aliases > 0 then
      out[#out + 1] = { name = s.name, title = s.title, glyph = s.glyph, aliases = aliases }
    end
  end
  return out
end

--- QueryScope:queryFor(name) -> string or nil
--- Method
--- The query text that enters a named scope, so `browserTabs` answers `"t "`. Nil when the
--- scope is unknown or holds no live alias, which a caller reads as nothing to do rather
--- than seeding a query that would claim nothing.
---
--- The first alias is the one used, and first means the order the aliases were written in,
--- filtered to those that survived. So the short one written first is the canonical one, and
--- that judgement lives here rather than at each caller. The separator comes along, since it
--- is this spoon's grammar and a caller appending its own space would be a second opinion
--- about what entering a scope looks like.
function obj:queryFor(name)
  local aliases = self:aliasesOf(name)
  if #aliases == 0 then return nil end
  return aliases[1] .. SEPARATOR
end

--- QueryScope:resolve(query) -> scope, rest
--- Method
--- The whole grammar, exposed on its own so it can be checked from the console. The first
--- word plus a space names a scope and everything after the space is that scope's own query,
--- which may be empty. Returns nil when the first word claims nothing, which is the usual
--- case and the reason an ordinary search is unaffected.
function obj:resolve(query)
  local token, rest = tostring(query or ""):match(SEPARATOR_PATTERN)
  if not token then return nil end
  local scope = self._byAlias[token:lower()]
  if not scope then return nil end
  return scope, rest
end

-- Rank a scope's rows against its own query, using the scope's matcher or the shared one.
-- Skipped for a scope that opted out and for an empty query, where the scope's natural order
-- is what it means. This mirrors the presenter's own filtering step rather than inventing a
-- second policy, so a list shaped scope needs no filter loop of its own.
function obj:_filter(scope, rest, rows)
  local matcher = scope.matcher
  if matcher == nil then matcher = self._matcher end
  if type(matcher) ~= "function" or rest == "" then return rows end
  local ranked = {}
  for i = 1, #rows do
    local r = rows[i]
    local hay = r.filterText or ((r.title or "") .. " " .. (r.subTitle or ""))
    local score = matcher(rest, hay)
    if score ~= nil then
      ranked[#ranked + 1] = { row = r, score = score, idx = i }
    end
  end
  table.sort(ranked, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.idx < b.idx
  end)
  local out = {}
  for i = 1, #ranked do out[i] = ranked[i].row end
  return out
end

-- Wrap a scope's rows for the presenter. Two things happen here and both matter.
--
-- The row's own item is nested under a descriptor naming its scope, so a chosen row routes back
-- to the scope that made it. It stays plain data, because a presenter hands every row to a
-- native chooser that serialises it and would drop a function.
--
-- filterText becomes the raw query, including the alias. Filtering already happened above,
-- against the scope's own query, so this is what stops the presenter's matcher scoring these
-- rows a second time against a string that carries a word they were never meant to contain.
-- Every row then scores alike and the order decided above survives, the same trick a
-- computed row already uses.
function obj:_present(scope, query, rows)
  local out = {}
  for i = 1, #rows do
    local r = rows[i]
    out[i] = {
      title = r.title,
      subTitle = r.subTitle,
      image = r.image,
      glyph = r.glyph or scope.glyph,
      enabled = r.enabled,
      filterText = query,
      item = { kind = "scope", scope = scope.name, payload = r.item },
    }
  end
  return out
end

--- QueryScope:rows(query) -> rows, exclusive
--- Method
--- The query row source contract plus the one extra answer. When the first word claims no
--- scope this returns nothing and claims nothing, so the presenter's own list is untouched.
--- When it claims one, the rows are that scope's alone and exclusive is true.
---
--- A claimed query is claimed even when it matches nothing, otherwise a scope with no hit
--- would silently fall back to the full list and the same keystroke would mean two different
--- things. An empty result is shown as one disabled row instead, so the list explains itself
--- rather than coming up blank.
---
--- A scope is trusted for its own rows and not for the presenter's stability, so one that
--- raises becomes a disabled row naming the failure rather than an empty list or an error out
--- of a keystroke.
function obj:rows(query)
  local scope, rest = self:resolve(query)
  if not scope then return {}, false end

  local ok, rows = pcall(scope.rows, rest)
  if not ok then
    hs.printf("QueryScope: the %s scope failed, %s", scope.name, tostring(rows))
    return { {
      title = scope.title .. " is not answering",
      subTitle = "the reason is in the Hammerspoon console",
      glyph = scope.glyph,
      enabled = false,
      filterText = query,
      item = { kind = "scope", scope = scope.name },
    } }, true
  end

  local kept = self:_filter(scope, rest, rows or {})
  if #kept == 0 then
    return { {
      title = "No match",
      subTitle = scope.title .. " has nothing matching " .. rest,
      glyph = scope.glyph,
      enabled = false,
      filterText = query,
      item = { kind = "scope", scope = scope.name },
    } }, true
  end
  return self:_present(scope, query, kept), true
end

-- The scope a row descriptor came from, or nil with the reason stated. A row with no payload is
-- one of the disabled rows above, which cannot be acted on, so it is a no op rather than a case
-- any scope has to handle.
function obj:_scopeOf(item)
  if type(item) ~= "table" or not item.payload then return nil end
  local scope = self._byName[item.scope]
  if not scope then
    hs.printf("QueryScope: a row named the unknown scope %s", tostring(item.scope))
    return nil
  end
  return scope
end

--- QueryScope:run(item)
--- Method
--- Route a chosen row back to the scope that made it, handing over the descriptor the scope's
--- own rows put there.
function obj:run(item)
  local scope = self:_scopeOf(item)
  if not scope then return end
  local ok, err = pcall(scope.run, item.payload)
  if not ok then
    hs.printf("QueryScope: the %s scope failed to run a row, %s", scope.name, tostring(err))
  end
end

--- QueryScope:peek(item)
--- Method
--- Show more about a row without choosing it, routed home exactly as running one is.
---
--- THE SECOND VERB EXISTS BECAUSE CHOOSING IS NOT THE ONLY THING A LIST IS FOR, and a scope was
--- previously able to say only what a row is and what happens when you take it. A file row wants
--- one more question answered before you commit, which is what am I actually looking at, and the
--- tool behind the scope already answers it. Without a route the alias reaches a diminished copy
--- of the tool, which is the thing the scope rules here are written to prevent.
---
--- It is optional, so a scope with nothing to show simply does not offer it and every surface
--- above can ask whether there is anything to show rather than assuming.
function obj:peek(item)
  local scope = self:_scopeOf(item)
  if not scope or type(scope.peek) ~= "function" then return end
  local ok, err = pcall(scope.peek, item.payload)
  if not ok then
    hs.printf("QueryScope: the %s scope failed to peek a row, %s", scope.name, tostring(err))
  end
end

--- QueryScope:redirectFor(item) -> query or nil
--- Method
--- The query this row means instead of the action taking it would run, or nil when taking it
--- means what it says. Routed home exactly as running and peeking are.
---
--- THE THIRD VERB EXISTS BECAUSE SOME ROWS ARE SIGNPOSTS RATHER THAN DESTINATIONS. A row in the
--- alias directory does not do anything, it tells you the word for something else, and the useful
--- outcome is that word in the field with the list still open. Expressed as a run, the only thing
--- such a row could do was close the list and reopen it with the word typed, which works and looks
--- broken. Asking first is what lets the same row be answered without the list ever going away.
---
--- Optional like peek, so a scope with no signpost rows says nothing and every surface above asks
--- rather than assumes. An empty or non string answer is read as no redirect, so a scope that
--- cannot name the query right now falls back to being taken normally rather than doing nothing.
function obj:redirectFor(item)
  local scope = self:_scopeOf(item)
  if not scope or type(scope.redirect) ~= "function" then return nil end
  local ok, query = pcall(scope.redirect, item.payload)
  if not ok then
    hs.printf("QueryScope: the %s scope failed to answer a redirect, %s", scope.name, tostring(query))
    return nil
  end
  if type(query) ~= "string" or query == "" then return nil end
  return query
end

--- QueryScope:canPeek(item) -> bool
--- Method
--- Whether this row has anything to peek at. Asked by a surface deciding whether a key means
--- anything right now, so a binding that would do nothing can be gated and left out of the
--- shortcut hints rather than listed and inert.
function obj:canPeek(item)
  local scope = self:_scopeOf(item)
  return scope ~= nil and type(scope.peek) == "function"
end

return obj
