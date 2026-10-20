-- Every key choice this person makes, in one file Olm owns.
--
-- A plugin says what it can run and which keys it would like, and this file says how each thing
-- is reached. Olm reads it as cfg.keymap, handed in by init.lua beside the plugins, and no plugin
-- ever reads it. A section left empty keeps everything Olm and its plugins ship, so this file
-- empty is the shipped keys exactly. A line Olm cannot read is a problem line in the console
-- naming the entry, and the rest of the file is still read.
--
-- keys maps a chord to an action, or to false.
--   A chord is a leader or modifiers joined by a plus sign, with the key last, the way a cheat
--   sheet reads it. The leaders are hyper, meta and super, the three held keys, and any name in
--   the leaders section below. The modifiers are shift, ctrl, alt, cmd and fn. A chord may hold a
--   leader and modifiers, hyper+shift+4, or modifiers alone, ctrl+alt+C. Words and the key are
--   compared without case. fn is refused on hyper, meta and super, which compare only the other
--   four, and stays legal in a chord of modifiers alone or on a named leader. The plus on the
--   main row is written as its unshifted key, shift+=, and the keypad plus is pad+, hyper+pad+.
--   An action is the plugin or host identity, a dot and the action name, vpn.open,
--   windowmanager.leftHalf, clipboard.appendCopy, apptoggler.Safari for an app in
--   config/apps.lua, apptoggler.GhosttyPlaced for a variant of one in config/plugins.lua,
--   systemsettings.General for a System Settings pane, and launcher.open, launcher.lock and
--   launcher.sleep for Olm's own.
--   An action named here takes exactly the chords listed for it here and loses its defaults, and
--   every action not named keeps its own. A chord a default holds is taken from that default, and
--   that one row of the default is not bound, said in one routine console line, while the action
--   keeps every other chord it has. false frees a global chord, so whatever held it is not bound
--   and nothing takes its place. List keys, the ones live while a list is open, are not reached
--   by false or by any entry until phase 7 of the keymap plan brings them here.
--   An app's key shows wherever Olm lists the app, on the sheet of the leader it sits on and on
--   the app's own launcher row, so moving one here moves it everywhere.
--     ["meta+E"] = "vpn.open",
--     ["meta+Y"] = "clipboard.open",
--
-- leaders names a set of real modifiers as a leader of its own, a name to a list of shift, ctrl,
-- alt and cmd. It reads like hyper in a chord and on a launcher row, it has no cheat sheet and
-- no tap, since holding real modifiers is ordinary typing, and its chords are taken from every
-- app, so it suits combinations the apps here leave free. A leader no chord uses is said in one
-- routine console line.
--     nav = { "shift", "ctrl" },
--
-- roles moves every default on a role to another held leader at once. A plugin's defaults name a
-- role, app or window, never a leader, and app lands on hyper and window on meta unless this says
-- otherwise. A held leader is remapped only while some chord uses it, so moving the window role
-- to super claims Right Command and frees Right Option. Moving the app role off hyper still keeps
-- Caps Lock remapped, since every list's keys live on hyper.
--     window = "super",
--
-- aliases maps a plugin identity to the words that scope the launcher to it, in place of the words
-- the plugin ships. Every plugin not named keeps its own.
--     vpn = { "v", "vpn", "tunnel" },

return {
  keys = {
    -- ["meta+E"] = "vpn.open",
    -- ["meta+Y"] = "clipboard.open",

    -- App toggles, each app named as in config/apps.lua. Holding Hyper and the key focuses the
    -- app, or walks its windows when it is already in front.
    -- First character
    ["hyper+B"] = "apptoggler.Books",
    ["hyper+C"] = "apptoggler.GoogleChrome",
    ["hyper+D"] = "apptoggler.Docker",
    ["hyper+F"] = "apptoggler.Finder",
    ["hyper+M"] = "apptoggler.Mail",
    ["hyper+O"] = "apptoggler.Obsidian",
    ["hyper+S"] = "apptoggler.Safari",
    ["hyper+V"] = "apptoggler.VisualStudioCode",
    ["hyper+N"] = "apptoggler.Notes",
    ["hyper+I"] = "apptoggler.iPhoneMirroring",
    ["hyper+Z"] = "apptoggler.Zed",
    ["hyper+R"] = "apptoggler.Preview",
    -- Second character
    ["hyper+T"] = "apptoggler.Stickies",
    ["hyper+L"] = "apptoggler.Slack",
    -- Third character
    ["hyper+A"] = "apptoggler.Claude",
    -- The default terminal, plain focus or cycle.
    ["hyper+`"] = "apptoggler.Ghostty",
    -- The terminal's own placed summon, the GhosttyPlaced variant in config/plugins.lua, a plain
    -- combination rather than a Hyper chord since it is pressed mid work, live all the time
    -- rather than only while Hyper is held.
    ["alt+`"] = "apptoggler.GhosttyPlaced",
    -- Activity Monitor. On backslash rather than slash, because slash opens file search, and the
    -- two read as a pair on adjacent keys, one for what the machine is doing and one for what is
    -- on it.
    ["hyper+\\"] = "apptoggler.ActivityMonitor",
    -- System Settings, opened straight to the General pane, a hide when it is already in front.
    ["hyper+,"] = "systemsettings.General",
    -- Disabled, uncomment to enable.
    -- ["hyper+A"] = "apptoggler.ChatGPTAtlas",
    -- ["hyper+A"] = "apptoggler.AndroidStudio",
    -- ["hyper+H"] = "apptoggler.Hammerspoon",
    -- ["hyper+P"] = "apptoggler.TablePlus",
    -- ["hyper+X"] = "apptoggler.Xcode",
  },

  leaders = {
    -- nav = { "shift", "ctrl" },
  },

  roles = {
    -- window = "super",
  },

  aliases = {
    -- vpn = { "v", "vpn", "tunnel" },
  },
}
