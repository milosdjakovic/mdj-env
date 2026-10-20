-- The app toggle list, the one key list left outside config/keymap.lua.
--
-- Pure data, no logic. This file holds the app toggle list the AppToggler plugin reads, which
-- config/plugins.lua hands over as that plugin's own data, next to the bundle id catalog in
-- config/apps.lua. That plugin then tells the Hyper cheat sheet and the launcher's app rows what
-- it bound. Every other key choice a person makes is written in config/keymap.lua, a chord to
-- any plugin's action, a leader of their own, a role moved to another held leader, and a
-- plugin's aliases. Which held leader each role lands on lived here as appLeader and windowLeader
-- until phase 5 of the keymap plan, and is the roles section of that file now. Phase 6 moves
-- these toggles there too, each key into its keys section, and this file goes.

local M = {
  -- App toggle bindings (for Olm's AppToggler plugin)
  -- Uses app names from config/apps.lua. Reaches the plugin through the apptoggler entry in
  -- config/plugins.lua, which points at this list rather than copying it.
  -- An entry with no `modifiers` field binds into the Hyper modal, fired by holding the
  -- Hyper key (Caps Lock, remapped to F18 and held through Olm's one leader adapter,
  -- lib/leader.lua) plus the letter. A quick Caps Lock tap toggles real Caps Lock
  -- instead. Olm binds every key, so there is no fallback combo any more.
  --
  -- An entry that DOES state `modifiers` binds outside the Hyper modal. It asks
  -- for a literal global combo through hs.hotkey.bind, live all the time rather than
  -- only while Hyper is held, which is what a placement toggle like the terminal's
  -- below needs, since it is pressed mid work rather than reached through a leader.
  --
  -- `hides` turns an entry from focus-or-cycle into show-and-hide, a second press on
  -- an already frontmost app hiding it instead of walking its windows. `placement`
  -- centers and sizes the window once showing, launching, or focusing is the actual
  -- outcome of the press, never when the press only cycled to another window of an
  -- app already in front. Both are AppToggler's own fields, read in full in that
  -- plugin's own README.
  appToggles = {
    -- First character
    { app = "Books",            key = "B" },
    { app = "GoogleChrome",     key = "C" },
    { app = "Docker",           key = "D" },
    { app = "Finder",           key = "F" },
    { app = "Mail",             key = "M" },
    { app = "Obsidian",         key = "O" },
    { app = "Safari",           key = "S" },
    { app = "VisualStudioCode", key = "V" },
    { app = "Notes",            key = "N" },
    { app = "iPhoneMirroring",  key = "I" },
    { app = "Zed",              key = "Z" },
    { app = "Preview",          key = "R" },
    -- Second character
    { app = "Stickies",         key = "T" },
    { app = "Slack",            key = "L" },
    -- Third character
    { app = "Claude",           key = "A" },
    -- Default terminal: plain focus/cycle, still on the Hyper modal.
    { app = "Ghostty",          key = "`" },
    -- The terminal's own placed summon, a literal combo rather than a Hyper chord since
    -- it is pressed mid work, show-and-hide rather than cycle since a second press while
    -- it is frontmost should get it out of the way, and centered at a fixed size on
    -- whichever display it is already on. This is what TerminalHandler.spoon used to be,
    -- absorbed into AppToggler as one entry rather than a whole spoon kept outside Olm,
    -- since the behaviour it needed turned out to be a handful of fields every toggle
    -- can now ask for rather than a tool of its own.
    { app = "Ghostty", key = "`", modifiers = { "alt" }, hides = true,
      description = "Terminal placed",
      placement = { width = 2400, height = 1350, padding = { x = 40, y = 20 } } },
    -- Activity Monitor. On backslash rather than slash, because slash now opens file search,
    -- and the two read as a pair on adjacent keys, one for what the machine is doing and one
    -- for what is on it.
    { app = "ActivityMonitor",  key = "\\" },
    -- System Settings, opened straight to the General pane. The url field makes
    -- AppToggler open (and navigate) to that pane instead of a plain focus.
    { app = "SystemSettings",   key = ",", url = "x-apple.systempreferences:com.apple.systempreferences.GeneralSettings" },
    -- Disabled (uncomment to enable)
    -- { app = "ChatGPTAtlas",   key = "A" },
    -- { app = "AndroidStudio",  key = "A" },
    -- { app = "Hammerspoon",    key = "H" },
    -- { app = "TablePlus",      key = "P" },
    -- { app = "Xcode",          key = "X" },
  },
}

return M
