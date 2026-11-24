-- Olm's list of abilities, what a plugin may ask Olm to do with a permission of macOS's that Olm
-- holds and the plugin never does, docs/DESIGN-APP-PLUGINS.md, "macOS's permissions, held by Olm
-- and lent by ability", decided with Milos on 2026-11-24.
--
-- A plugin declares the abilities it uses in its manifest, abilities = { { use, why, breaks } },
-- and is allowed every one it declares until the person turns one off, on its page or under the
-- permission on the Permissions page. An ability not on this list is refused, so Olm adding it here
-- is the only way in. Pure data and pure functions, no hs, so the dry gate and the tests read it.

local M = {}

--- M.PERMISSIONS, each permission an ability rides on, by the id Olm.app's Permissions page knows
--- it by, and its name. olm is true for a gate that is Olm's own rather than macOS's, which Olm
--- always holds.
M.PERMISSIONS = {
  accessibility = { title = "Accessibility" },
  inputMonitoring = { title = "Input Monitoring" },
  screenRecording = { title = "Screen Recording" },
  fullDiskAccess = { title = "Full Disk Access" },
  automation = { title = "Automation" },
  defaultBrowser = { title = "Default Browser" },
  pasteboard = { title = "Clipboard", olm = true },
}

--- M.LIST, every ability by name, what Olm does for it in words and the permission it rides on.
--- An ability with a subject, controlApp:<bundle id> and readFiles:<path>, is listed by its stem.
M.LIST = {
  browserProfiles = { title = "Browser Profiles", does = "lists the browsers and their profiles",
    permission = "fullDiskAccess" },
  moveWindows = { title = "Move Windows", does = "moves or sizes another app's window",
    permission = "accessibility" },
  hearKeys = { title = "Hear Keys", does = "passes key presses on", permission = "inputMonitoring" },
  captureScreen = { title = "Capture the Screen", does = "takes a picture of the screen",
    permission = "screenRecording" },
  controlApp = { title = "Control", does = "sends that app commands", permission = "automation",
    subject = "app" },
  readFiles = { title = "Read Files", does = "reads files under a declared path",
    permission = "fullDiskAccess", subject = "path" },
  readClipboard = { title = "Read the Clipboard", does = "reads the pasteboard", permission = "pasteboard" },
  receiveLinks = { title = "Receive Links", does = "hands it each link while Olm is the default browser",
    permission = "defaultBrowser" },
}

--- M.parse(use) -> stem, subject, or nil and why
--- An ability's name split at its first colon, controlApp:com.google.Chrome into controlApp and
--- the bundle id. A stem taking a subject needs one, and one taking none refuses it.
function M.parse(use)
  if type(use) ~= "string" or use == "" then return nil, "names no ability in use" end
  local stem, subject = use:match("^([^:]+):(.+)$")
  stem = stem or use
  local entry = M.LIST[stem]
  if entry == nil then return nil, "is not one of Olm's abilities, so it is refused until Olm adds it" end
  if entry.subject and subject == nil then
    return nil, "needs its " .. entry.subject .. " after a colon, " .. stem .. ":<" .. entry.subject .. ">"
  end
  if not entry.subject and subject ~= nil then return nil, "takes nothing after a colon" end
  return stem, subject
end

--- M.describe(use) -> { stem, subject, title, does, permission, permissionTitle }, or nil and why
--- What a page shows for an ability. Control's title names its app, Control Google Chrome reads
--- better as the bundle's last word, so the app id is shown beside it in does.
function M.describe(use)
  local stem, subject = M.parse(use)
  if stem == nil then return nil, subject end
  local entry = M.LIST[stem]
  local permission = M.PERMISSIONS[entry.permission]
  local title, does = entry.title, entry.does
  if subject then
    title = title .. " " .. subject
    does = does .. ", " .. subject
  end
  return {
    stem = stem, subject = subject, title = title, does = does,
    permission = entry.permission, permissionTitle = permission.title, olm = permission.olm == true,
  }
end

--- M.read(specs) -> abilities, problems
--- A manifest's abilities list checked. Each accepted entry is { use, why, breaks, about }, about
--- being M.describe's answer, and each refused one { use, why, breaks, refused }, kept so the
--- plugin's page names what was refused. problems are { where, why } for the root to say.
function M.read(specs)
  local out, problems, seen = {}, {}, {}
  if specs == nil then return out, problems end
  if type(specs) ~= "table" then
    return out, { { where = "abilities", why = "is not a list" } }
  end
  for i, spec in ipairs(specs) do
    local where = "abilities[" .. i .. "]"
    if type(spec) ~= "table" then
      problems[#problems + 1] = { where = where, why = "is not a table" }
    elseif type(spec.why) ~= "string" or spec.why == "" then
      problems[#problems + 1] = { where = where, why = "says no why, the reason a person reads" }
    elseif spec.breaks ~= nil and type(spec.breaks) ~= "string" then
      problems[#problems + 1] = { where = where, why = "has a breaks that is not words" }
    elseif type(spec.use) == "string" and seen[spec.use] then
      problems[#problems + 1] = { where = where, why = "repeats " .. spec.use }
    else
      local about, why = M.describe(spec.use)
      if type(spec.use) == "string" then seen[spec.use] = true end
      if about then
        out[#out + 1] = { use = spec.use, why = spec.why, breaks = spec.breaks, about = about }
      elseif type(spec.use) == "string" and spec.use ~= "" then
        out[#out + 1] = { use = spec.use, why = spec.why, breaks = spec.breaks, refused = why }
        problems[#problems + 1] = { where = where .. " " .. spec.use, why = why }
      else
        problems[#problems + 1] = { where = where, why = why }
      end
    end
  end
  return out, problems
end

--- M.declares(abilities, use) -> whether a read list holds use, accepted.
function M.declares(abilities, use)
  for _, a in ipairs(abilities or {}) do
    if a.use == use and a.refused == nil then return true end
  end
  return false
end

return M
