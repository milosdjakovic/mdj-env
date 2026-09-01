--- LinkRouter destination provider contract.
---
--- The interface every provider must satisfy. This is the one named place that declares what
--- a destination provider is, so an author adding support for another browser family reads
--- this file and nothing else to know the shape. It is a runtime checklist, not a base class,
--- Lua has no interfaces, so a provider conforms by carrying these methods rather than by
--- inheriting anything, and the engine calls validate at load and drops whatever does not.
---
--- A provider is a plain table with an optional `name` and these methods.
---   claims(self, bundleID) -> boolean
---       Does this provider own this application. The engine asks each provider in order and
---       the first to claim it decides how that application expands and how it opens, so a
---       provider that answers true for everything must be last. Answering this from what is
---       actually on disk rather than from a list of known bundle ids is what lets a browser
---       nobody has heard of work on the day it is installed.
---   destinations(self, bundleID, appName) -> list of entries
---       Expand one application into the rows a person can choose between. An application
---       with no separable profiles answers one entry. A Chromium application answers one per
---       profile. Never answers nil, an empty list is the honest answer for an application
---       that claims to have profiles and turns out to have none readable.
---   open(self, entry, url, deps) -> boolean
---       Send the url to that entry. `deps` is the per consumer dependency adapter, so a
---       provider needing an external binary asks it by the name this spoon declared rather
---       than probing for it, and a provider needing nothing outside Hammerspoon ignores the
---       argument. Answers false when it could not, so the caller can say so rather than
---       leaving a person looking at a link that silently went nowhere.
---
--- An entry is a plain table the engine and the rows both read.
---   id       stable string identifying this destination across reloads, what the favourite
---            and the ordering are both stored against.
---   bundle   the application's bundle id.
---   profile  the profile directory name, or nil for an application with no profiles.
---   private  true when choosing this entry means a private or incognito window. A provider
---            emits these as ordinary entries beside the normal ones rather than answering a
---            capability question, so a private window is a thing you turn on and order like
---            any other destination instead of a key you have to remember.
---   label    what a person reads, the application name alone, or with the profile's own name
---            after it, and the words for a private window when it is one.
---
--- An entry is NEVER put into a chooser row. A row carries the entry's id and nothing else,
--- because a row is serialised to native objects by the chooser and an entry holds a reference
--- to its provider, whose methods are functions that cannot be converted. Handing one to the
--- widget makes the whole list fail to parse and the chooser renders completely empty, with the
--- reason visible only in the console. Resolve an id back to an entry when acting on it.

local M = {}

M.requiredMethods = { "claims", "destinations", "open" }

--- M.entryId(bundle, profile) -> string
--- The one place an entry's identity is spelled, so the store, the ordering, and every
--- provider agree on it by calling this rather than by each formatting it the same way and
--- drifting later. A profile free entry is its bundle id unchanged, which is deliberate, it
--- keeps a preference stored before profiles existed still matching the same destination.
function M.entryId(bundle, profile, private)
  local id = bundle
  if profile ~= nil and profile ~= "" then id = id .. "::" .. profile end
  if private then id = id .. "::private" end
  return id
end

--- M.validate(provider) -> ok, missing
--- True when the provider is a table carrying every required method, or false and the name of
--- the first gap. Never throws, the engine drops a non conforming provider and logs.
function M.validate(provider)
  if type(provider) ~= "table" then return false, "not a table" end
  for _, method in ipairs(M.requiredMethods) do
    if type(provider[method]) ~= "function" then return false, method end
  end
  return true
end

return M
