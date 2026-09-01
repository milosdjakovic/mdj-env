--- LinkRouter engine.
---
--- Owns the destination list, which destinations are shown, what order they sit in, and the
--- routing rules. It holds no policy about which browsers exist and names none, it asks an
--- ordered chain of providers, first claim wins, and the composition root decides that order
--- and puts the provider claiming everything last.
---
--- Discovery starts from LaunchServices rather than from anything written down here, so a
--- browser installed later appears on its own, and the only entry ever removed is this
--- application itself, which is structural rather than a judgement. Hammerspoon holds the
--- system handler, so offering it as a destination would hand every link straight back forever.
---
--- Shown and ordered are ONE stored fact, a list of entry ids, rather than a set of flags plus
--- a separate arrangement. That collapse is what removes every keyboard shortcut this plugin
--- used to need. Choosing a destination on the configuration page appends it to the list, which
--- is both what makes it appear and what decides its place, so picking Safari then Chrome
--- (Milos) then Chrome (Vicert) produces exactly that order with three ordinary selections and
--- no key to remember. Choosing one already on the list takes it off.
---
--- Never configured is stored as nil and is distinct from configured to be empty. Nil means
--- show every ordinary destination in discovery order, so a fresh machine has a working router
--- rather than an empty one. The moment anything is chosen the stored list governs completely.
--- Private windows are deliberately outside that default, since offering everybody a private
--- window for every profile they own would double the list for something most people want once
--- or never.

local M = {}

local log = hs.logger.new("LinkRouter", "info")

local SHOWN_KEY = "olm.linkRouter.shown"
local RULES_KEY = "olm.linkRouter.rules"
local SCHEME = "https"

-- Injected by the composition root.
local providers = {}
local contract = nil
local deps = nil

-- The ordered list of entry ids to show, or nil when this has never been configured.
local shown = nil
-- The routing rules, in the order they are asked. A list rather than a map because first match
-- wins and a map has no order to be first in.
local rules = {}

--------------------------------------------------------------------------------
-- Discovery
--------------------------------------------------------------------------------

--- selfBundle() -> string
--- Read inside a function rather than into a file level local, deliberately. The dry gate loads
--- this module under a permissive stub where hs.processInfo autostubs to a table, and a bundle
--- id concatenated at file scope raises there and reports the plugin unknown instead of
--- checking it. Compared rather than concatenated, the gate sees the real contract.
local function selfBundle()
  local info = hs.processInfo
  local id = info and info.bundleID
  return type(id) == "string" and id or ""
end

local function providerFor(bundleID)
  for _, p in ipairs(providers) do
    local ok, claimed = pcall(p.claims, p, bundleID)
    if ok and claimed then return p end
    if not ok then
      log.w("provider '" .. tostring(p.name) .. "' raised while claiming " .. tostring(bundleID))
    end
  end
  return nil
end

--- M.all() -> list of entries, in discovery order
--- Every application LaunchServices reports for the scheme, expanded through whichever provider
--- claims it. A provider that raises costs its own application rather than the whole list,
--- since one browser with an unreadable profile file must not empty the router.
---
--- Entries carry a live provider reference, so an entry must never reach a chooser row.
function M.all()
  local me = selfBundle()
  local out = {}
  for _, bundle in ipairs(hs.urlevent.getAllHandlersForScheme(SCHEME) or {}) do
    if bundle ~= me then
      local name = hs.application.nameForBundleID(bundle) or bundle
      local p = providerFor(bundle)
      if p then
        local ok, entries = pcall(p.destinations, p, bundle, name)
        if ok and type(entries) == "table" then
          for _, e in ipairs(entries) do
            e.provider = p
            out[#out + 1] = e
          end
        else
          log.w("provider '" .. tostring(p.name) .. "' could not expand " .. name)
        end
      end
    end
  end
  return out
end

function M.entryById(id)
  for _, e in ipairs(M.all()) do
    if e.id == id then return e end
  end
  return nil
end

--------------------------------------------------------------------------------
-- Shown and ordered, one fact
--------------------------------------------------------------------------------

--- M.shownIds() -> list of entry ids
--- The stored arrangement, or the built in default when nothing has ever been chosen. The
--- default is every ordinary destination in discovery order, private windows excluded, so a
--- fresh machine opens a useful router without anybody configuring anything first.
function M.shownIds()
  if shown then return shown end
  local out = {}
  for _, e in ipairs(M.all()) do
    if not e.private then out[#out + 1] = e.id end
  end
  return out
end

--- M.position(id) -> number or nil
--- Where this destination sits in the router, which is the number the configuration page shows
--- beside it, or nil when it is not shown at all.
function M.position(id)
  for i, stored in ipairs(M.shownIds()) do
    if stored == id then return i end
  end
  return nil
end

--- M.toggleShown(id)
--- The one action the configuration page has. Appending rather than inserting is what makes the
--- order fall out of the choosing, so a person builds the list they want by picking in the
--- order they want it. Materialises the effective list first, since before anything is chosen
--- the stored value is nil and there would otherwise be nothing to append to.
function M.toggleShown(id)
  local current = M.shownIds()
  local kept, found = {}, false
  for _, stored in ipairs(current) do
    if stored == id then
      found = true
    else
      kept[#kept + 1] = stored
    end
  end
  if not found then kept[#kept + 1] = id end
  shown = kept
  hs.settings.set(SHOWN_KEY, shown)
end

--- M.shown() -> list of entries, in the order they are offered
--- What a clicked link is actually offered. An id naming a destination this machine no longer
--- has is skipped rather than breaking the list, so uninstalling a browser degrades quietly.
function M.shown()
  local byId = {}
  for _, e in ipairs(M.all()) do byId[e.id] = e end
  local out = {}
  for _, id in ipairs(M.shownIds()) do
    if byId[id] then out[#out + 1] = byId[id] end
  end
  return out
end

--- M.hidden() -> list of entries
--- Everything this machine can reach that is NOT in the main list, in discovery order. These
--- are not disabled, they are one level further away, reached through the router's own More
--- row, so turning a destination off shortens the list a link lands on without ever putting
--- that destination out of reach.
function M.hidden()
  local out = {}
  for _, e in ipairs(M.all()) do
    if not M.position(e.id) then out[#out + 1] = e end
  end
  return out
end

--- M.clearShown()
--- Empty the main list so it can be rebuilt by choosing in the order wanted, which is how a
--- person reorders, since appending is the only way an entry joins it.
---
--- Written as an explicitly empty list rather than as nil, deliberately, and the difference is
--- the whole point of the row. Nil means never configured and brings the built in default back,
--- every ordinary destination in discovery order, which is the opposite of starting over. An
--- empty list is a configured choice and leaves nothing in the main list, which is what a person
--- about to pick three destinations in a particular order actually wants. Nothing is lost by it,
--- since everything not in the main list is still one level down under More.
function M.clearShown()
  shown = {}
  hs.settings.set(SHOWN_KEY, shown)
end

--------------------------------------------------------------------------------
-- Rules
--------------------------------------------------------------------------------

--- hostMatches(host, pattern) -> boolean
--- A rule naming a domain covers the domain and everything under it, so github.com matches
--- gist.github.com. Compared as a suffix on a dot boundary rather than a plain suffix,
--- deliberately, since a plain one would let a rule for example.com capture notexample.com,
--- which is a different site owned by somebody else.
local function hostMatches(host, pattern)
  if not (host and pattern) then return false end
  host, pattern = host:lower(), pattern:lower()
  if host == pattern then return true end
  return host:sub(-(#pattern + 1)) == "." .. pattern
end

function M.rules()
  local out = {}
  for i, r in ipairs(rules) do out[i] = r end
  return out
end

--- M.addRule(kind, value, entryId)
--- Prepend, since a rule made now is the most specific thing known and a narrower rule added
--- later should beat a broad one made before it. Any existing rule for the same kind and value
--- is dropped first, so making a rule twice replaces rather than shadows.
function M.addRule(kind, value, entryId)
  if not (kind and value and entryId) then return false end
  local kept = {}
  for _, r in ipairs(rules) do
    if not (r.kind == kind and r.value == value) then kept[#kept + 1] = r end
  end
  table.insert(kept, 1, { kind = kind, value = value, entry = entryId })
  rules = kept
  hs.settings.set(RULES_KEY, rules)
  return true
end

function M.removeRule(index)
  if not (index and rules[index]) then return false end
  table.remove(rules, index)
  hs.settings.set(RULES_KEY, rules)
  return true
end

--- M.hostOf(url) -> string or nil
--- The host alone, credentials and port removed, which is what a rule is written against.
function M.hostOf(url)
  if not url then return nil end
  local host = url:match("^%a[%w+.-]*://([^/?#]+)")
  if not host then return nil end
  return host:match("([^@]+)$"):match("^([^:]+)")
end

--- M.routeFor(url, senderBundle) -> entry or nil
--- The chain a clicked link walks before anything is shown. Each rule is asked in order and the
--- first that matches AND still resolves to a live destination answers. A rule pointing at a
--- browser since uninstalled declines rather than winning and opening nothing, so the chooser
--- appears exactly as it would have without the rule. Nil is the ordinary case, ask the person.
function M.routeFor(url, senderBundle)
  if not url then return nil end
  local host = M.hostOf(url)
  for _, r in ipairs(rules) do
    local hit = false
    if r.kind == "host" then
      hit = hostMatches(host, r.value)
    elseif r.kind == "app" then
      hit = senderBundle ~= nil and senderBundle == r.value
    end
    if hit then
      local entry = M.entryById(r.entry)
      if entry then return entry end
      log.w("a rule for " .. tostring(r.value) .. " points at a destination this machine no "
        .. "longer has, so it was skipped")
    end
  end
  return nil
end

--------------------------------------------------------------------------------
-- Acting
--------------------------------------------------------------------------------

--- M.open(entry, url) -> boolean
--- Hand the link to the provider that produced this entry, the one that knows how to reach it,
--- including whether this entry means a private window.
function M.open(entry, url)
  if not (entry and entry.provider and url) then return false end
  local ok, sent = pcall(entry.provider.open, entry.provider, entry, url, deps)
  if not ok then
    log.w("provider '" .. tostring(entry.provider.name) .. "' raised opening " .. tostring(entry.label))
    return false
  end
  return sent and true or false
end

--- M.refresh()
--- Tell every provider holding a cache to drop it, called when a list is about to be shown, so
--- a profile added or renamed in a browser appears without a Hammerspoon reload.
function M.refresh()
  for _, p in ipairs(providers) do
    if type(p.forget) == "function" then pcall(p.forget) end
  end
end

function M.holdsHandler()
  return hs.urlevent.getDefaultHandler(SCHEME) == selfBundle()
end

--- M.claimHandler(want) -> boolean
--- Take the system handler, or hand it to the first shown destination. macOS puts up its own
--- confirmation panel on both, which is why neither happens without a person choosing the row.
function M.claimHandler(want)
  if want == "claim" then
    hs.urlevent.setDefaultHandler("http", selfBundle())
    return true
  end
  local first = M.shown()[1]
  if not first then
    log.w("asked to hand the link handler back with no destination shown to hand it to")
    return false
  end
  hs.urlevent.setDefaultHandler("http", first.bundle)
  return true
end

--- M.configure(opts)
--- opts.providers  the ordered provider chain, the one claiming everything last.
--- opts.contract   the shared entry identity and validation helpers.
--- opts.deps       the per consumer dependency adapter a provider needing a binary asks.
function M.configure(opts)
  opts = opts or {}
  contract = opts.contract
  deps = opts.deps
  providers = {}
  for _, p in ipairs(opts.providers or {}) do
    local ok, missing = contract.validate(p)
    if ok then
      p.contract = contract
      providers[#providers + 1] = p
    else
      log.w("dropped a destination provider, it is missing " .. tostring(missing))
    end
  end
  local storedShown = hs.settings.get(SHOWN_KEY)
  shown = type(storedShown) == "table" and storedShown or nil
  local storedRules = hs.settings.get(RULES_KEY)
  rules = type(storedRules) == "table" and storedRules or {}
  return M
end

return M
