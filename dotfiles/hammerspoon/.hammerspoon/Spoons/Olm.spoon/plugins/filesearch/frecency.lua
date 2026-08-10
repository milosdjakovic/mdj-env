--- What you actually use, as opposed to what got written.
---
--- Every other ordering in this spoon is a file date or a text score, so the list you land on
--- before typing anything is really answering which files changed rather than which files you
--- reach for. Those are different questions. A generated manifest, a build output and a spec
--- someone else wrote all sit at the top of a date ordered list, and none of them is a file you
--- chose. This is the missing signal, and it is the only one that can only come from watching
--- you.
---
--- macOS looks like it should already answer this. It holds kMDItemLastUsedDate, its own record
--- of when a file was last opened by any application, which would be strictly better than
--- anything we can record because it sees every app rather than only this picker. It is not
--- usable. Measured over the same scopes and the same seven day window, it returned 16 files
--- against 342 for the modification date, so it is far too sparse to rank anything and the store
--- has to be ours.
---
--- ONE NUMBER PER PATH, not a history. Each use decays what was there and adds one, so a file
--- used ten times last year sinks below one used twice this week with no list of timestamps to
--- keep and nothing to trim. That is the whole mechanism. The half life is the only knob that
--- changes its character, and it is pure data in config.
---
--- Every action counts the same, opening, revealing, copying the path, and walking into a
--- directory. Weighting them differently would be a claim about intent that cannot be backed,
--- and copying a path is often the strongest possible signal that a file matters. One weight also
--- means a fifth action later needs no retuning.
---
--- THE STORE IS DELIBERATELY OUTSIDE THE CONFIG TREE. It is written on every action, and
--- ~/.hammerspoon is watched for changes, so a store living in there would reload the whole
--- config every time you opened a file. hs.settings writes to the user defaults instead, which
--- is also the right home for this on its own merits, since it is per machine behaviour rather
--- than configuration worth carrying to another machine the way the display profiles are. That
--- is the one coupling in this file, and the key name is injected so it is at least named
--- upward rather than chosen here.
---
--- Dead paths are pruned lazily at read time and only among the handful about to be shown, so a
--- deleted file cannot sit at the top forever and there is no background job and no cost for the
--- long tail nobody is looking at.

local M = {}

local cfg = {
  key = "fileSearchFrecency",
  halfLifeDays = 14,
  maxEntries = 500,
}

-- Loaded once and kept, since this is read on every open and written on every action.
local store = nil

--- frecency.configure(opts)
--- opts.key           the hs.settings key holding the store, named by the composition root
--- opts.halfLifeDays  how long a use takes to count half as much
--- opts.maxEntries    how many paths to remember before the weakest are forgotten
function M.configure(opts)
  opts = opts or {}
  if opts.key then cfg.key = opts.key end
  if opts.halfLifeDays then cfg.halfLifeDays = opts.halfLifeDays end
  if opts.maxEntries then cfg.maxEntries = opts.maxEntries end
  store = nil
  return M
end

local function load()
  if store then return store end
  local raw = hs.settings.get(cfg.key)
  store = {}
  if type(raw) == "table" then
    for path, e in pairs(raw) do
      -- Tolerate anything that is not the shape written here, since this outlives the code that
      -- wrote it and a malformed entry must cost one row rather than the whole store.
      if type(path) == "string" and type(e) == "table" and tonumber(e.score) and tonumber(e.at) then
        store[path] = { score = tonumber(e.score), at = tonumber(e.at) }
      end
    end
  end
  return store
end

local function save()
  if store then hs.settings.set(cfg.key, store) end
end

-- What an entry is worth right now. Halves every halfLifeDays, so nothing has to be swept.
local function decayed(e, now)
  local halfLife = (cfg.halfLifeDays or 14) * 86400
  if halfLife <= 0 then return e.score end
  local age = now - (e.at or now)
  if age <= 0 then return e.score end
  return e.score * 0.5 ^ (age / halfLife)
end

-- Forget the weakest entries once the store is over its cap, which is the only trimming there
-- is. It runs on write rather than on read, so the cost lands on an action rather than on a
-- picker opening.
local function trim(s, now)
  local n = 0
  for _ in pairs(s) do n = n + 1 end
  local maxEntries = cfg.maxEntries or 500
  if n <= maxEntries then return end
  local ranked = {}
  for path, e in pairs(s) do
    ranked[#ranked + 1] = { path = path, score = decayed(e, now) }
  end
  table.sort(ranked, function(a, b) return a.score > b.score end)
  for i = maxEntries + 1, #ranked do
    s[ranked[i].path] = nil
  end
end

--- frecency.note(path) - record that this path was just used.
--- Decay first and then add one, so a use is always worth the same at the moment it happens and
--- age is applied to what came before it rather than to it.
function M.note(path)
  if type(path) ~= "string" or path == "" then return end
  local s = load()
  local now = os.time()
  local e = s[path]
  if e then
    s[path] = { score = decayed(e, now) + 1, at = now }
  else
    s[path] = { score = 1, at = now }
  end
  trim(s, now)
  save()
end

--- frecency.score(path) -> number
--- Zero for anything never used, which is most paths, so a caller can add this unconditionally.
function M.score(path)
  if type(path) ~= "string" or path == "" then return 0 end
  local e = load()[path]
  if not e then return 0 end
  return decayed(e, os.time())
end

--- frecency.usedAt(path) -> epoch seconds of the last use, or nil for a path never used
--- The moment of the last use is already held, since the decay is measured from it, so this
--- exposes what is there rather than recording anything more. It is what lets a row say when you
--- last reached for it, the only thing a row can report that is about you rather than the file.
function M.usedAt(path)
  if type(path) ~= "string" or path == "" then return nil end
  local e = load()[path]
  return e and e.at or nil
end

--- frecency.top(n) -> list of paths, best first
--- Existence is checked only on the ones being returned, and a path that has gone is forgotten
--- as it is passed over, so this both bounds the cost and prunes itself. Anything below the cut
--- is never checked, which is the point, since the long tail is not being shown to anyone.
function M.top(n)
  n = tonumber(n) or 0
  if n <= 0 then return {} end
  local s = load()
  local now = os.time()
  local ranked = {}
  for path, e in pairs(s) do
    ranked[#ranked + 1] = { path = path, score = decayed(e, now) }
  end
  -- Path breaks a tie so the order is stable across opens rather than following pairs.
  table.sort(ranked, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.path < b.path
  end)
  local out = {}
  local forgot = false
  for _, item in ipairs(ranked) do
    if #out >= n then break end
    if hs.fs.attributes(item.path, "mode") then
      out[#out + 1] = item.path
    else
      s[item.path] = nil
      forgot = true
    end
  end
  if forgot then save() end
  return out
end

--- frecency.forget(path) - drop one path, for a caller that knows it is gone or unwanted.
function M.forget(path)
  local s = load()
  if s[path] then
    s[path] = nil
    save()
  end
end

return M
