-- Wifi, what it declares about itself.
--
-- Native Lua over hs.wifi for reading and scanning, plus the system networksetup for joining,
-- since joining through hs.wifi blocks the main thread for as long as the association takes
-- and a task does not. One backend, so no engine and no contract, the whole plugin is init.lua.
return {
  -- The row icons, named by the rows and drawn by Olm.
  icons = {
    off = { emoji = "📴" },
    connected = { emoji = "📶" },
    network = { emoji = "📡" },
    saved = { emoji = "⭐" },
    locked = { emoji = "🔒" },
    loading = { emoji = "⏳" },
    warn = { emoji = "⚠️" },
  },

  needs = {
    tools = {
      { name = "networksetup", kind = "system", locator = "/usr/sbin/networksetup", policy = "optional",
        reason = "joining a network and reading which networks this Mac has saved, without which " ..
                 "the list still shows and disconnects but cannot connect",
        origin = { macos = "ships with the system" } },
    },

    -- macOS hands a network name only to an application holding Location Services, and it
    -- does not refuse, it answers blanks. So without this grant the current network has no
    -- name and every scanned network is nameless, which leaves nothing to pick. Optional,
    -- because disconnecting still works and the list says what is missing.
    gates = {
      { name = "location", kind = "grant", locator = "location", policy = "optional",
        reason = "reading the name of the current network and of every network a scan finds" },
    },

    data = {
      stagePresent = { source = "root", policy = "optional",
        breaks = "the launcher row and this plugin's own open reach nothing, since neither has any other way to ask the shared stage to show this presentation" },
      redrawPresented = { source = "root", policy = "optional",
        breaks = "a finished scan does not appear until the field is touched, since a background answer has no other way to reach the list" },
    },
  },

  -- What puts this tool in the launcher's scope set, so its alias and a space lists these rows.
  -- registry.scope below then says which members the scope actually calls.
  provides = {
    rows = "rows",
    select = "select",
  },

  defaults = {
    description = "Wi-Fi",
    glyph = "📡",
    aliases = { "wi", "wifi" },
    example = "Try wifi to see or change the network",
  },

  surface = {
    context = "wifi",
    primary = { action = "insertSelected", description = "Confirm" },
  },

  -- onPresent starts a scan each time the list is shown, since the networks in range are
  -- the one thing here that goes stale, and the last scan stays on screen until it lands.
  presentation = {
    rows = { member = "rows", call = "dot" },
    select = { member = "select", call = "dot" },
    placeholder = { member = "placeholder", call = "dot" },
    onPresent = { member = "onPresent", call = "dot" },
  },

  -- The scope has its own rows member because a scope is not this presentation, so a scan
  -- landing there needs the redraw callback the launcher hands in rather than redrawPresented.
  registry = {
    row = { category = "Network", detail = "see the current network, disconnect, or join another",
      glyph = "📡", keywords = "wifi wi-fi wireless network ssid join connect disconnect" },
    open = { member = "show", call = "dot" },
    hosted = true,
    scope = {
      rows = { member = "scopeRows", call = "dot" },
      run = { member = "select", call = "dot" },
    },
  },
}
