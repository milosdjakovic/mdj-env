-- What the bridge serves, step 2.2 of docs/PLAN-STANDALONE.md, read only. `hello`, the launcher's
-- `catalog` at rest, `icons` by owner, `open` for the launcher with its query memory, `rows` for a
-- query on that level, `close` and the `metrics` notification, as docs/PROTOCOL-BRIDGE.md writes
-- them, and the `memory` notification after a pick, step 2.3, and nothing that runs anything, so no row can be chosen through it. Any other list asked
-- for answers -32013, not served yet. Pure, the launcher and the manifests are handed in as
-- functions, so test/bridgeserve.lua replays the transcripts in test/fixtures/bridge over fakes.

local M = {}

M.PROTOCOL = 1
M.ROW_LIMIT = 200
M.NAME_LIMIT = 65536

-- The icon spec's two sources, the icon engine's words, lib/icons/init.lua, held here as values,
-- since one of them is also a plugin's name.
local SF, GLYPH = "sf", "emoji"

--- serve.new(opts) -> the methods table rpc.new takes, and the service behind it
--- opts.rpc        the rpc module, for its codes and fail
--- opts.clean      frame.clean, valid UTF-8 and whether anything was replaced
--- opts.launcher   { rows = function(query) -> rows, exclusive, memoryKey = function(item) -> key,
---                   memory = function() -> { [query] = { key, ... } }, placeholder = function() }
--- opts.icons      function(owner) -> the icons its manifest declares, or nil
--- opts.version    the olm version hello names
--- opts.styled     function(value) -> plain text, for an hs.styledtext, optional
--- opts.rowLimit    the rows a list shows when it names no limit of its own, chooser.rowLimit, which
---                  hello sends as limits.rowLimit, M.ROW_LIMIT when none is handed in
function M.new(opts)
  local rpc = opts.rpc
  local service = { levels = {}, nextLevel = 0, metrics = nil, sentMemory = nil }
  local rowLimit = type(opts.rowLimit) == "number" and opts.rowLimit >= 1 and opts.rowLimit or M.ROW_LIMIT

  -- A row's identity across answers. A row with a memory key is its key, which the launcher keeps
  -- for every row worth remembering. Any other is minted per item table, weakly, so a row whose
  -- item table comes back keeps its key, the protocol's A key.
  local minted = setmetatable({}, { __mode = "k" })
  local mintCount = 0
  local function keyFor(item, memoryKey)
    if memoryKey then return memoryKey end
    if type(item) ~= "table" then
      mintCount = mintCount + 1
      return "k" .. mintCount
    end
    local key = minted[item]
    if not key then
      mintCount = mintCount + 1
      key = "k" .. mintCount
      minted[item] = key
    end
    return key
  end

  local function text(value)
    if value == nil then return nil, false end
    if type(value) ~= "string" then
      if opts.styled then value = opts.styled(value) end
      value = tostring(value)
    end
    return opts.clean(value)
  end

  -- The icon a row draws, as the app resolves it. An app row's picture is the app's own, a
  -- manifest key names its owner, and a spelled symbol or emoji crosses as written.
  local function iconOf(row)
    local item = row.item
    if type(item) == "table" and item.kind == "app" and item.bundleID then return { app = item.bundleID } end
    local icon = row.icon
    if type(icon) == "string" and row.iconOwner then return { owner = row.iconOwner, key = icon } end
    if type(icon) == "table" then
      if type(icon[SF]) == "string" then return { [SF] = icon[SF] } end
      if type(icon[GLYPH]) == "string" then return { [GLYPH] = icon[GLYPH] } end
    end
    return nil
  end

  -- One row as it crosses, with its ref, and a signature of everything but the ref that tells
  -- whether it changed since it was last sent.
  local function rowOut(row, ref, key, memoryKey)
    local out, lossy = { ref = ref, key = key }, false
    local title, cut = text(row.title or row.text or "")
    out.title, lossy = title, lossy or cut
    if row.subTitle ~= nil then
      out.subtitle, cut = text(row.subTitle)
      lossy = lossy or cut
    end
    if type(row.keywords) == "string" then
      out.keywords = { (text(row.keywords)) }
    elseif type(row.keywords) == "table" then
      out.keywords = {}
      for _, word in ipairs(row.keywords) do out.keywords[#out.keywords + 1] = (text(word)) end
    end
    if type(row.filterText) == "string" then out.filterText = (text(row.filterText)) end
    if row.pinned then out.pinned = true end
    if row.fromQuery then out.fromQuery = true end
    if type(row.tier) == "number" then out.tier = row.tier end
    if type(row.bonus) == "number" and row.bonus ~= 0 then out.bonus = row.bonus end
    if row.enabled == false then out.enabled = false end
    if memoryKey then out.memoryKey = memoryKey end
    out.icon = iconOf(row)
    if lossy then out.lossy = true end
    return out
  end

  -- A text that is the same for the same row every time, its keys sorted, since a JSON encoder
  -- need not keep an order and a row would then read as changed on every answer.
  local function canon(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
      local v = value[k]
      if v == nil then v = value[tonumber(k)] end
      parts[#parts + 1] = k .. "=" .. canon(v)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end

  local function signature(out)
    local copy = {}
    for k, v in pairs(out) do if k ~= "ref" then copy[k] = v end end
    return canon(copy)
  end

  -- Every row of an answer as it crosses, keyed and in order, two rows sharing a key keeping the
  -- first and minting the second, so a key is unique within the list.
  local function rowsOut(rows, level)
    local list, seen = {}, {}
    for _, row in ipairs(rows or {}) do
      local memoryKey = opts.launcher.memoryKey and opts.launcher.memoryKey(row.item) or nil
      local key = keyFor(row.item, memoryKey)
      if seen[key] then key = keyFor({}, nil) end
      seen[key] = true
      local ref = level.refs[key]
      if not ref then
        level.nextRef = level.nextRef + 1
        ref = level.id .. "." .. level.nextRef
        level.refs[key] = ref
      end
      level.items[ref] = row.item
      local out = rowOut(row, ref, key, memoryKey)
      list[#list + 1] = { key = key, out = out, sig = signature(out) }
    end
    return list
  end

  -- The launcher's memory as it may cross. The store keeps each spelling's prefixes cut by bytes, so
  -- a query of letters outside ASCII can be stored cut inside a letter, which is not UTF-8 and
  -- would fail the whole answer's JSON. Such a spelling is left out. The app walks a typed query's
  -- prefixes at letter boundaries only, so it never looks for one.
  local function memoryOut()
    local out = {}
    for query, order in pairs(opts.launcher.memory and opts.launcher.memory() or {}) do
      local _, lossy = opts.clean(query)
      if not lossy then out[query] = order end
    end
    return out
  end

  local methods = {}

  methods.hello = { run = function(params, session)
    if params.protocol ~= M.PROTOCOL then
      rpc.fail(rpc.VERSION, "protocol " .. tostring(params.protocol) .. " is not spoken", { protocol = M.PROTOCOL })
    end
    session.open = true
    service.levels, service.nextLevel, service.sentMemory = {}, 0, nil
    return { protocol = M.PROTOCOL, olm = opts.version or "0", features = {},
      limits = { message = 8 * 1024 * 1024, rowLimit = rowLimit, name = M.NAME_LIMIT } }
  end }

  -- The pixel room a row's text has, kept for stageTextBudget once a list asks it, step 3.
  methods.metrics = { run = function(params)
    service.metrics = params
    return true
  end }

  methods.icons = { run = function(params)
    if type(params.owner) ~= "string" then rpc.fail(rpc.PARAMS, "icons needs an owner") end
    local declared = opts.icons(params.owner) or {}
    local out = {}
    for key, spec in pairs(declared) do
      if type(key) == "string" and type(spec) == "table" then
        out[key] = { [SF] = type(spec[SF]) == "string" and spec[SF] or nil,
          [GLYPH] = type(spec[GLYPH]) == "string" and spec[GLYPH] or nil }
      end
    end
    return { icons = out }
  end }

  -- The launcher's rows at rest outside any level, for 2.3's shadow ranking. Its refs are for
  -- reading only, and choosing a row is done in a launcher level.
  local catalog = { id = "c", refs = {}, items = {}, nextRef = 0, sig = nil, revision = 0 }
  methods.catalog = { run = function(params)
    local rows = opts.launcher.rows("")
    local list = rowsOut(rows, catalog)
    local sigs = {}
    for i, r in ipairs(list) do sigs[i] = r.sig end
    local sig = table.concat(sigs, "\n")
    if sig ~= catalog.sig then
      catalog.sig = sig
      catalog.revision = catalog.revision + 1
    end
    local revision = "c" .. catalog.revision
    if params.have == revision then return { revision = revision, unchanged = true } end
    local out = {}
    for i, r in ipairs(list) do out[i] = r.out end
    return { revision = revision, rows = out }
  end }

  methods.open = { run = function(params)
    local what = type(params.what) == "table" and params.what or {}
    if what.launcher ~= true then
      rpc.fail(rpc.NOT_SERVED, "only the launcher is served yet", { what = what })
    end
    service.nextLevel = service.nextLevel + 1
    local level = { id = "v" .. service.nextLevel, kind = "launcher", refs = {}, items = {},
      nextRef = 0, sent = nil, revision = 0 }
    service.levels[level.id] = level
    local memory = memoryOut()
    service.sentMemory = {}
    for query, order in pairs(memory) do service.sentMemory[query] = table.concat(order, "\n") end
    return { level = { id = level.id,
      placeholder = opts.launcher.placeholder and opts.launcher.placeholder() or "",
      previewPane = false, ranking = "app", rowLimit = "default", memory = memory } }
  end }

  methods.close = { run = function(params)
    if not service.levels[params.level] then rpc.fail(rpc.GONE, "no level " .. tostring(params.level)) end
    service.levels[params.level] = nil
    return true
  end }

  methods.rows = {
    supersedes = function(params) return params.level end,
    run = function(params)
      local level = service.levels[params.level]
      if not level then rpc.fail(rpc.GONE, "no level " .. tostring(params.level)) end
      local query = type(params.query) == "string" and params.query or ""
      local rows, exclusive = opts.launcher.rows(query)
      local list = rowsOut(rows, level)
      local order, now, fromQuery = {}, {}, {}
      for i, r in ipairs(list) do
        order[i] = r.key
        now[r.key] = r
        if r.out.fromQuery then fromQuery[#fromQuery + 1] = r.key end
      end
      local orderSig = table.concat(order, "\n")
      -- What the app holds is what was last sent only when it says so. Anything else, a first ask
      -- or a revision it lost, is answered with every row.
      local since = (level.sent and params.have == "r" .. level.revision) and level.sent or {}
      local upsert, remove = {}, {}
      for _, r in ipairs(list) do
        local was = since[r.key]
        if not was or was.sig ~= r.sig then upsert[#upsert + 1] = r.out end
      end
      for key in pairs(since) do if not now[key] then remove[#remove + 1] = key end end
      table.sort(remove)
      local changed = #upsert > 0 or #remove > 0 or orderSig ~= level.orderSig
        or since ~= level.sent or not level.sent
      if changed then
        level.revision = level.revision + 1
        level.sent, level.orderSig = now, orderSig
      end
      local revision = "r" .. level.revision
      local answer = { q = params.q, revision = revision, fromQuery = fromQuery, exclusive = exclusive == true }
      if params.have ~= revision then
        answer.changes = { upsert = upsert, remove = remove, order = order }
      end
      return answer
    end,
  }

  service.methods = methods

  --- service.memoryChanges() -> the params of a memory notification, { memory = { [query] = order } },
  --- naming each query whose order differs from what this connection was last sent, a forgotten one
  --- as an empty order, or nil when nothing differs or no launcher level was opened to send it to
  function service.memoryChanges()
    if not service.sentMemory or not opts.launcher.memory then return nil end
    local now, changed, any = memoryOut(), {}, false
    for query, order in pairs(now) do
      local sig = table.concat(order, "\n")
      if service.sentMemory[query] ~= sig then
        changed[query], any = order, true
        service.sentMemory[query] = sig
      end
    end
    for query in pairs(service.sentMemory) do
      if now[query] == nil then
        changed[query], any = {}, true
        service.sentMemory[query] = nil
      end
    end
    return any and { memory = changed } or nil
  end

  return service
end

return M
