--- === Obsidian ===
---
--- Searches the notes in every vault Obsidian knows about and opens the chosen one in
--- Obsidian. Typing filters by note name and folder a word at a time in any order, a
--- query that matches nothing still offers to create a note with those words as its
--- name, and a trailing row hands the words to Obsidian's own search for the one thing
--- a filename match cannot do, finding words inside a note.
---
--- Vaults come from Obsidian's own registry file rather than from any list here, so a
--- vault opened in Obsidian tomorrow appears on its own. Notes come from reading the
--- vault directories directly, the way the Raycast extension does it, rather than from
--- asking Obsidian, so the list is fresh on every open and works while Obsidian is not
--- running. Opening goes through the obsidian url scheme with the vault id rather than
--- the vault name, since two vaults may share a name and the id cannot.
---
--- The vault's own excluded files setting is respected by ranking, a note under an
--- excluded prefix still appears, since hiding it entirely would make it unreachable
--- from here, but it sorts after everything else so it never crowds out a real match.

local M = {}

local log = hs.logger.new("Obsidian", "info")

-- The one concretion this plugin owns. The manifest declares the same id as the tool
-- locator, so the two must agree and a rename fails visibly in both places.
local BUNDLE = "md.obsidian"

-- Obsidian's own vault registry. The path is fixed by Obsidian itself on macOS, keyed
-- off the home directory rather than written absolute.
local REGISTRY = os.getenv("HOME") .. "/Library/Application Support/obsidian/obsidian.json"

-- How long a scan stays fresh, in seconds. A rescan walks every vault directory, which
-- costs a few milliseconds per thousand notes, so once per present is affordable and
-- keeps a note created seconds ago visible, the staleness both Alfred integrations
-- accept and this one does not have to.
local RESCAN_AFTER = 30

-- Injected via configure.
local recency = nil          -- shared lift to front instance, notes opened here lead
local stagePresent = nil     -- the door from the launcher row to the shared stage
local redrawPresented = nil  -- repaint the staged list when a rescan lands
local redraw = nil           -- repaint a launcher hosted list when a rescan lands
local matcher = nil          -- the shared fuzzy scorer, query and haystack to score or nil
local glyphIcon = nil        -- the shared glyph drawer, an emoji to a row sized image

-- The row faces. One note emoji for every note, and each action row wearing its own,
-- so a note and an action never read alike at a glance.
local GLYPH_NOTE = "📝"
local GLYPH_NEW = "➕"
local GLYPH_SEARCH = "🔍"

-- Owned state.
local vaults = nil        -- { { id, path, name, ignore }, ... } from the registry read
local notes = nil         -- flat list over every vault, rebuilt when the scan goes stale
local scannedAt = 0
local lastQuery = nil     -- the previous keystroke's query, the key of the narrow below
local lastHits = nil      -- and the notes that survived it, scored again instead of all
local launchTimer = nil   -- held so a deferred url outlives the function that made it
local rescanTimer = nil   -- held for the same reason, the deferred rescan behind a present
local warmTimer = nil     -- the one scan configure schedules so the first open is warm

-- Percent encoding for the url scheme, everything but the unreserved set, which is what
-- the Obsidian docs ask for. Slashes in a note path must arrive encoded, and byte wise
-- gsub encodes each utf8 byte on its own, which is exactly what percent encoding wants.
local function enc(s)
  return (s:gsub("[^%w%-%.%_%~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

-- A row for the picker. The payload under item is plain data only, strings and nothing
-- else, since a function or userdata anywhere in a row makes LuaSkin reject the whole
-- choices table, the defect LinkRouter shipped and documented. The image is the one
-- sanctioned userdata a row carries, drawn by the shared glyph drawer and cached there,
-- so every row of a glyph shares one object rather than paying one drawing per row.
local function row(title, subTitle, item, enabled, glyph)
  local image = glyphIcon and glyph and glyphIcon.icon(glyph) or nil
  return { title = title, subTitle = subTitle, image = image, item = item, enabled = enabled }
end

-- The registry read. Obsidian only lists vaults that were opened at least once, which
-- is the honest set, a vault Obsidian cannot open is not worth listing notes from.
local function readVaults()
  local reg = hs.json.read(REGISTRY)
  local out = {}
  if type(reg) ~= "table" or type(reg.vaults) ~= "table" then return out end
  for id, v in pairs(reg.vaults) do
    if type(v) == "table" and type(v.path) == "string"
        and hs.fs.attributes(v.path, "mode") == "directory" then
      local vault = {
        id = id,
        path = v.path,
        name = v.path:match("([^/]+)$") or v.path,
        open = v.open == true,
        ignore = {},
      }
      -- The vault's own excluded files list. Regex entries, wrapped in slashes, are
      -- skipped rather than half honored, plain prefixes are the common case and the
      -- only one this ranking respects.
      local app = hs.json.read(v.path .. "/.obsidian/app.json")
      if type(app) == "table" and type(app.userIgnoreFilters) == "table" then
        for _, f in ipairs(app.userIgnoreFilters) do
          if type(f) == "string" and not f:match("^/.*/$") then
            vault.ignore[#vault.ignore + 1] = f
          end
        end
      end
      out[#out + 1] = vault
    end
  end
  -- A stable order, the vault marked open leads, the rest alphabetical, so subtitles
  -- and the default vault for a new note do not shuffle between reads.
  table.sort(out, function(a, b)
    if a.open ~= b.open then return a.open end
    return a.name < b.name
  end)
  return out
end

-- Whether a vault relative path sits under one of the vault's excluded prefixes.
local function ignored(rel, prefixes)
  for _, p in ipairs(prefixes) do
    if rel:sub(1, #p) == p then return true end
  end
  return false
end

-- One vault's notes, walked directly off disk. Dot entries are skipped, which covers
-- .obsidian and .trash both, and only markdown counts as a note. The walk reads
-- directory metadata alone, never a file's contents, so it cannot make iCloud download
-- an evicted note.
local function scanVault(vault, out)
  local function walk(dir, rel)
    local ok, iter, dirObj = pcall(hs.fs.dir, dir)
    if not ok then return end
    for entry in iter, dirObj do
      if entry ~= "." and entry ~= ".." and entry:sub(1, 1) ~= "." then
        local full = dir .. "/" .. entry
        local childRel = rel == "" and entry or (rel .. "/" .. entry)
        if hs.fs.attributes(full, "mode") == "directory" then
          walk(full, childRel)
        elseif entry:sub(-3) == ".md" then
          out[#out + 1] = {
            vault = vault,
            rel = childRel,
            name = entry:sub(1, -4),
            folder = rel,
            haystack = childRel:lower(),
            mtime = hs.fs.attributes(full, "modification") or 0,
            ignored = ignored(childRel, vault.ignore),
          }
        end
      end
    end
  end
  walk(vault.path, "")
end

-- The scan itself, always a full rebuild. Around 120 milliseconds warm for this vault,
-- measured live, which is why nothing on the open path calls it directly.
local function rescan()
  vaults = readVaults()
  notes = {}
  for _, v in ipairs(vaults) do scanVault(v, notes) end
  scannedAt = hs.timer.secondsSinceEpoch()
  -- The narrow cache holds notes from the list this scan just replaced, so it is
  -- dropped with it rather than serving rows the vault no longer has.
  lastQuery, lastHits = nil, nil
  log.f("scanned %d notes across %d vaults", #notes, #vaults)
end

-- The blocking form, only for a list that has never been built at all, the one case
-- where showing nothing would be worse than a beat of lag.
local function ensureScanned()
  if notes == nil then rescan() end
end

-- The open path's form. The list that is up, or about to be, shows the previous scan,
-- and a stale one is rebuilt a beat later with the landed result repainted onto
-- whichever surface is showing the rows, the stage or a launcher hosted scope. The
-- highlight is not reset, since the order rarely moves and the hand it would jump out
-- from under is the person's.
local function refreshSoon()
  local now = hs.timer.secondsSinceEpoch()
  if notes and (now - scannedAt) < RESCAN_AFTER then return end
  if rescanTimer then return end
  rescanTimer = hs.timer.doAfter(0.05, function()
    rescanTimer = nil
    rescan()
    if redrawPresented then redrawPresented("obsidian", false) end
    if redraw then redraw() end
  end)
end

-- The vault a query level action lands in when no note names one, the vault Obsidian
-- itself would open by default.
local function defaultVault()
  return vaults and vaults[1] or nil
end

-- The recency key for a note, the vault id and the vault relative path, so a note
-- moved between vaults reads as new rather than inheriting another file's history.
local function keyOf(n)
  return n.vault.id .. "/" .. n.rel
end

-- The fallback filter for a machine where the shared scorer was never granted. Every
-- typed word must appear somewhere in the note's own path as a plain substring.
local function matches(n, words)
  for _, w in ipairs(words) do
    if not n.haystack:find(w, 1, true) then return false end
  end
  return true
end

-- Whether a word's characters appear in order in the folded haystack, a linear scan.
-- This is the membership gate in front of the scorer, and it is what fzf itself calls
-- matching, so it is the behaviour a person's fingers already know. The scorer alone
-- also forgives a wrong letter, but paying its dynamic programming for every note on
-- every keystroke is what cost early keystrokes near two hundred milliseconds, since a
-- half typed word over a wide candidate set is exactly where its table is biggest. The
-- gate keeps dropped letters and abbreviations, colr and gdhart both pass, gives up
-- only the wrong letter case for membership, and leaves the scorer ranking the few
-- hundred that pass rather than the whole vault.
local function subseq(w, hay)
  local wi = 1
  local wc = w:byte(wi)
  for hi = 1, #hay do
    if hay:byte(hi) == wc then
      wi = wi + 1
      if wi > #w then return true end
      wc = w:byte(wi)
    end
  end
  return false
end

-- The typed query against the whole note list. With the shared fuzzy scorer this is the
-- same forgiving subsequence match every other list ranks with, scored over the vault
-- relative path so a folder word narrows exactly as filesearch's does, and the score
-- decides the order before recency lifts anything. Without it the substring filter
-- above stands and the order stays modification time.
local function filter(q)
  if q == "" then
    local all = {}
    for _, n in ipairs(notes) do all[#all + 1] = n end
    return all, nil
  end
  if matcher then
    -- Word at a time rather than the query as one subsequence, since one subsequence
    -- makes the space a character that must land between two matched runs, and a two
    -- word query with a typo then falls under the scorer's own relevance floor. Each
    -- word scores on its own against the whole path, every word must land somewhere,
    -- the scores add, and word order stops mattering, which is also what lets a folder
    -- word narrow a name word from either side.
    local words = {}
    for w in q:gmatch("%S+") do words[#words + 1] = { raw = w, low = w:lower() } end
    -- Typing is incremental, so a keystroke that only appended characters rescores the
    -- previous keystroke's survivors rather than every note, which is what holds a long
    -- query at a few milliseconds instead of growing with the whole vault. Measured at
    -- two hundred milliseconds per keystroke on a three word query without this. A
    -- deleted or edited character falls back to the full list. The subsequence gate is
    -- monotone under appending, so the narrow stays coherent with membership and a note
    -- dropped by one keystroke was genuinely dropped rather than lost to a cache.
    local candidates = notes
    if lastQuery and lastHits and #q > #lastQuery and q:sub(1, #lastQuery) == lastQuery then
      candidates = lastHits
    end

    -- Membership first, the gate alone, so the set is known before anything expensive
    -- runs against it.
    local passers = {}
    for _, n in ipairs(candidates) do
      local ok = true
      for _, w in ipairs(words) do
        if not subseq(w.low, n.haystack) then ok = false break end
      end
      if ok then passers[#passers + 1] = n end
    end
    lastQuery, lastHits = q, passers

    -- Ranking second, and which ranker depends on how many passed. A short prefix is a
    -- subsequence of nearly everything, so the scorer's dynamic programming over a
    -- thousand passers is where the half typed word cost its hundred and eighty
    -- milliseconds, and precise ranking of a set that wide is also worthless, nothing
    -- past the visible rows is read. So a wide set ranks cheaply, a substring hit beats
    -- a scattered one and an early hit beats a late one, both through one C level find
    -- per word, and the scorer takes over the moment the set is narrow enough that its
    -- order is actually being read. The handover point is a size, not a cliff a person
    -- steers by, the order simply sharpens as typing narrows.
    if #passers > 300 then
      local scores = {}
      for _, n in ipairs(passers) do
        local s = 0
        for _, w in ipairs(words) do
          local pos = n.haystack:find(w.low, 1, true)
          if pos then s = s + 100 - math.min(pos, 50) end
        end
        scores[n] = s
      end
      return passers, scores
    end

    local hits, scores = {}, {}
    for _, n in ipairs(passers) do
      local total = 0
      for _, w in ipairs(words) do
        local s = matcher(w.raw, n.rel)
        if s == nil then total = nil break end
        total = total + s
      end
      if total ~= nil then
        hits[#hits + 1] = n
        scores[n] = total
      end
    end
    return hits, scores
  end
  local words = {}
  for w in q:lower():gmatch("%S+") do words[#words + 1] = w end
  local hits = {}
  for _, n in ipairs(notes) do
    if matches(n, words) then hits[#hits + 1] = n end
  end
  return hits, nil
end

function M.rows(query)
  ensureScanned()
  refreshSoon()
  local q = (query or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local rows = {}

  if not vaults or #vaults == 0 then
    return { row("Obsidian knows no vaults yet",
      "open a vault in Obsidian once and it appears here", nil, false) }
  end

  local hits, scores = filter(q)

  -- Excluded prefixes last, then the fuzzy score where one exists, then newest
  -- modification, with the path as a stable tie breaker. Recency then lifts the notes
  -- actually opened through this tool to the front of whatever survived the filter,
  -- which reads right because the scorer's own relevance floor has already dropped
  -- anything a lift would embarrass.
  table.sort(hits, function(a, b)
    if a.ignored ~= b.ignored then return b.ignored end
    if scores then
      local sa, sb = scores[a], scores[b]
      if sa ~= sb then return sa > sb end
    end
    if a.mtime ~= b.mtime then return a.mtime > b.mtime end
    return a.rel < b.rel
  end)
  if recency then hits = recency.order(hits, keyOf) end

  local manyVaults = #vaults > 1
  for _, n in ipairs(hits) do
    local where = n.folder ~= "" and n.folder or n.vault.name
    if manyVaults and n.folder ~= "" then where = n.vault.name .. "  " .. n.folder end
    rows[#rows + 1] = row(n.name, where,
      { open = { vault = n.vault.id, rel = n.rel, key = keyOf(n) } }, nil, GLYPH_NOTE)
  end

  -- The two query level actions, only when there are words to act on. They trail the
  -- matches rather than lead them, since an existing note is the answer far more often
  -- than a new one, and they are the whole list when nothing matched.
  if q ~= "" then
    local v = defaultVault()
    rows[#rows + 1] = row(string.format("New note \"%s\"", q),
      "creates it in " .. v.name, { new = q }, nil, GLYPH_NEW)
    rows[#rows + 1] = row(string.format("Search notes for \"%s\"", q),
      "full text search inside Obsidian", { search = q }, nil, GLYPH_SEARCH)
  end

  return rows
end

-- Delivering a url to Obsidian. When the application is already running the url goes
-- straight out. When it is not, the url alone can leave Obsidian open with no vault,
-- a documented defect the Alfred integrations work around the same way, so the
-- application is launched first and the url follows once it has had time to come up.
local function fire(url)
  if hs.application.get(BUNDLE) then
    hs.urlevent.openURL(url)
    return
  end
  hs.application.launchOrFocusByBundleID(BUNDLE)
  launchTimer = hs.timer.doAfter(2, function()
    launchTimer = nil
    hs.urlevent.openURL(url)
  end)
end

function M.select(choice)
  if not choice or not choice.item then return end
  local it = choice.item
  if it.open then
    if recency then recency.touch(it.open.key) end
    -- The trailing .md is optional in the scheme and dropped here, so the url reads as
    -- the note's own name the way Obsidian's own copied links do.
    local rel = it.open.rel
    if rel:sub(-3) == ".md" then rel = rel:sub(1, -4) end
    fire("obsidian://open?vault=" .. enc(it.open.vault) .. "&file=" .. enc(rel))
  elseif it.new then
    local v = defaultVault()
    if v then fire("obsidian://new?vault=" .. enc(v.id) .. "&name=" .. enc(it.new)) end
  elseif it.search then
    local v = defaultVault()
    if v then fire("obsidian://search?vault=" .. enc(v.id) .. "&query=" .. enc(it.search)) end
  end
end

function M.placeholder()
  return "Obsidian notes"
end

function M.onPresent()
  refreshSoon()
end

function M.show()
  if stagePresent then stagePresent("obsidian") end
end

-- A colon method deliberately, and the colon is load bearing. The wiring layer's default
-- call for configure is a method call, so a plain dot function here receives the module
-- table where opts belongs and every grant lands one argument to the right and is lost,
-- silently, which is the identical argument shift the authoring guide warns presentation
-- members about. This plugin shipped that defect for a day, every grant reading false
-- while the wiring report said no problems.
function M:configure(opts)
  opts = opts or {}
  if opts.recency ~= nil then recency = opts.recency end
  if opts.stagePresent ~= nil then stagePresent = opts.stagePresent end
  if opts.redrawPresented ~= nil then redrawPresented = opts.redrawPresented end
  if opts.redraw ~= nil then redraw = opts.redraw end
  if opts.matcher ~= nil then matcher = opts.matcher end
  if opts.glyphIcon ~= nil then glyphIcon = opts.glyphIcon end
  -- One scan shortly after load, once the reload has settled, so the first human open
  -- of the session already has a list and pays nothing. Without it the first open
  -- inside the first few seconds falls back to the blocking scan, which still works.
  warmTimer = hs.timer.doAfter(3, function()
    warmTimer = nil
    ensureScanned()
  end)
  return M
end

return M
