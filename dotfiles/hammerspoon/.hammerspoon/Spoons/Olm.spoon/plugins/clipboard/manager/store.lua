--- The store core, the reusable engine.
---
--- An ordered deduped list of entries, newest first, persisted as one json file. It
--- decides nothing about how media is stored or when entries are evicted. It gates what
--- kinds it accepts, dedupes, persists, and after each add runs its injected retention
--- policies. The media lifecycle is an injected optional layer, see media.lua, and
--- eviction is an injected list of policies, see retention.lua. A text only store is
--- this file with no media layer and a count policy, the clipboard is this file with the
--- media layer and count plus bytes.
---
--- Public API, unchanged from before the split so the monitor and the ui do not care
--- that the internals moved: configure, load, all, add, moveToFront, replaceText,
--- removeEntry, clear, and save. save is public because the media layer re-persists after
--- an async preview render resolves. replaceText is the one way an entry's content changes
--- after capture, so the key recompute that keeps dedupe honest lives in a single place.

local S = {}

local SCHEMA = 2 -- bump to reset an incompatible on-disk store rather than migrate

local cfg = nil      -- injected config, see configure
local accepts = nil  -- set of allowed kinds, the accept gate
local retention = {} -- ordered list of policies run after each add, an or
local media = nil    -- optional media layer, nil for a text only store
local history = {}   -- newest first

--------------------------------------------------------------------------------
-- Persistence
--------------------------------------------------------------------------------

local function ensureDirs()
  for _, d in ipairs({ cfg.cacheParent, cfg.dataDir }) do
    if d and not hs.fs.attributes(d) then
      hs.fs.mkdir(d)
    end
  end
end

--- S.save() - write the history to disk under a schema envelope, pretty printed and
--- replacing the existing file. Public so the media layer can re-persist after a late
--- async render mutates an entry.
function S.save()
  hs.json.write({ schema = SCHEMA, items = history }, cfg.storePath, true, true)
end

--------------------------------------------------------------------------------
-- Dedupe identity
--------------------------------------------------------------------------------

-- A stable identity for dedupe: same text, same url, or the same ordered list of file
-- paths. Images have no cheap identity, so they are never deduped. It works on both
-- entry shapes, the raw one at capture (paths in _paths) and the stored one loaded from
-- disk (paths in the files array), so a key recomputed on load matches one computed for
-- a fresh copy.
--
-- The separator is the Unit Separator (0x1F), not a NUL byte. hs.json does not
-- round-trip an embedded NUL, it rewrites it to U+2205, so a NUL-keyed entry read back
-- from disk never matched a freshly computed NUL key and dedupe silently broke for
-- everything loaded from disk. 0x1F survives the round-trip and is just as unlikely to
-- appear in copied content.
local KEY_SEP = "\31"

local function keyPaths(e)
  if e._paths then return e._paths end
  local ps = {}
  for _, el in ipairs(e.files or {}) do
    ps[#ps + 1] = el.path
  end
  return ps
end

local function rawKey(e)
  if e.kind == "text" or e.kind == "url" then
    return e.kind .. KEY_SEP .. (e.text or "")
  end
  if e.kind == "file" then
    return "file" .. KEY_SEP .. table.concat(keyPaths(e), KEY_SEP)
  end
  return nil
end

--------------------------------------------------------------------------------
-- Retention
--------------------------------------------------------------------------------

-- Run every retention policy over the live list. Each owns its own eviction, and
-- together they are an or, an entry leaves when any policy drops it.
local function reap()
  for _, p in ipairs(retention) do
    p.reap({ history = history, media = media })
  end
end

--------------------------------------------------------------------------------
-- History
--------------------------------------------------------------------------------

--- S.add(entry) -> entry or nil
--- Persist a raw entry from a reader and put it at the front. A kind this store does not
--- accept is refused at the gate and returns nil. A duplicate moves the existing entry
--- to the front instead, at no copy cost, and returns it.
function S.add(entry)
  if not accepts[entry.kind] then
    return nil
  end

  local key = rawKey(entry)
  if key then
    for i = 1, #history do
      if history[i]._key == key then
        local h = table.remove(history, i)
        h.ts = entry.ts -- refresh recency so a re-copied item sorts back to the top
        -- Keep the original sourceApp. The row icon marks where the content first came
        -- from and stays put, it does not flip to whatever app copied it again.
        table.insert(history, 1, h)
        S.save()
        return h
      end
    end
  end

  -- The media layer turns a raw image or file entry into its stored form and stamps its
  -- size. A text only store has no media layer, so text and url just go in as they are.
  if media then media.ingest(entry) end

  entry._key = key
  table.insert(history, 1, entry)
  reap()
  S.save()
  return entry
end

-- Locate the live history element for an entry that may be a foreign copy. The chooser
-- bridges its choices out through Objective C and hands its completion callback a freshly
-- rebuilt Lua table, so the entry that comes back from a paste is a value copy, not the
-- stored reference. Reference equality would miss it and the move would silently do
-- nothing, so match on a stable field first, the dedupe _key for text, url, and file, or
-- the unique full image path, and fall back to identity.
local function indexOf(entry)
  for i = 1, #history do
    local h = history[i]
    if h == entry then
      return i
    elseif h.kind == entry.kind then
      if h._key and entry._key then
        if h._key == entry._key then return i end
      elseif h.kind == "image" and h.full == entry.full then
        return i
      end
    end
  end
  return nil
end

--- S.moveToFront(entry) - float a used entry to the top and refresh its recency, the
--- same treatment a duplicate copy gets, so a just pasted item reads as the most recent.
--- Accepts a foreign copy of the entry, matched by stable field, see indexOf, so a paste
--- coming back through the chooser callback still moves.
function S.moveToFront(entry)
  local i = indexOf(entry)
  if not i then return end
  local h = table.remove(history, i)
  h.ts = os.time() -- refresh recency, mirroring the dedupe branch of add
  table.insert(history, 1, h)
  S.save()
end

--- S.replaceText(entry, fresh) -> entry or nil
--- Swap an entry's content in place, leaving its position in the list alone. This is the
--- seam the append accumulator grows an entry through, so nothing else has to know that an
--- entry's content can change after capture.
---
--- `fresh` is a freshly built text entry, see readers.textEntry, and only its content
--- fields cross over, so how text is labelled stays owned by the readers and this function
--- decides only identity and persistence. The kind crosses too, so appending onto a url
--- entry correctly demotes it to text. Everything else on the live entry is left alone, the
--- source app above all, since the row icon marks where the content first came from.
---
--- The dedupe key is recomputed from the new content rather than left stale, which matters
--- because every other path here trusts _key. Growing an entry into an exact copy of an
--- older row would otherwise leave two rows sharing one identity, so any other row that now
--- collides is dropped and the edited one kept. No media is released, because a text key can
--- only ever collide with another text row and those carry none.
function S.replaceText(entry, fresh)
  local i = indexOf(entry)
  if not i then return nil end

  local h = history[i]
  h.kind = fresh.kind
  h.text = fresh.text
  h.ts = fresh.ts
  h.title = fresh.title
  h.preview = fresh.preview
  h.size = fresh.size
  h.chars = fresh.chars
  h._key = rawKey(h)

  -- Compare by reference rather than by the index taken above, since removing a row below
  -- it shifts every later index.
  for j = #history, 1, -1 do
    if history[j] ~= h and h._key and history[j]._key == h._key then
      table.remove(history, j)
    end
  end

  S.save()
  return h
end

--- S.removeEntry(entry) - delete one entry and its media.
function S.removeEntry(entry)
  for i = #history, 1, -1 do
    if history[i] == entry then
      table.remove(history, i)
    end
  end
  if media then media.release(entry) end
  S.save()
end

--- S.clear() - wipe history and all media.
function S.clear()
  if media then
    for _, e in ipairs(history) do
      media.release(e)
    end
  end
  history = {}
  S.save()
end

--- S.all() - the live history list, newest first.
function S.all()
  return history
end

--- S.load() - read history from disk, resetting on a schema mismatch.
function S.load()
  local data = hs.json.read(cfg.storePath)
  if type(data) == "table" and data.schema == SCHEMA and type(data.items) == "table" then
    history = data.items
  else
    history = {}
  end

  -- Recompute every key from the entry's own content rather than trusting the value on
  -- disk, so dedupe is immune to any serialization quirk, see rawKey. Then collapse
  -- exact-key duplicates the earlier NUL-separator bug let accumulate, keeping the newest
  -- of each (history is newest-first, so the first seen wins) and reclaiming the dropped
  -- copies' media. Images carry no key, so they are left alone, matching the rule that
  -- images are never deduped.
  local seen, removed = {}, false
  local i = 1
  while i <= #history do
    local k = rawKey(history[i])
    history[i]._key = k
    if k and seen[k] then
      if media then media.release(history[i]) end
      table.remove(history, i)
      removed = true
    else
      if k then seen[k] = true end
      i = i + 1
    end
  end
  if removed then S.save() end

  return history
end

--- S.configure(c) - inject the accept set, the retention policy list, the optional media
--- layer, and the paths. Creates the store dir.
function S.configure(c)
  cfg = c
  accepts = c.accepts
  retention = c.retention or {}
  media = c.media
  ensureDirs()
  return S
end

return S
