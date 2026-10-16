-- Keybinding definitions that belong to no plugin.
--
-- Pure data, no logic. This file holds two things only, the physical key each leader domain
-- uses, and the app toggle list the AppToggler plugin reads through init.lua. That plugin then
-- tells the Hyper cheat sheet and the launcher's app rows what it bound. Everything else about
-- a key lives with the plugin that owns it. A plugin's own key, its aliases and the Hyper
-- contexts it joins are declared in that plugin's manifest, and a person's change to any of
-- them, or to a plugin's data, goes in config/plugins.lua, keyed by plugin identity.

local M = {
  -- Which catalog key each domain uses. This single reference is the domain
  -- naming its leader, the only place the app or window to physical key link
  -- lives. Change a name to move that domain onto another key; leave a catalog
  -- key unreferenced and it stays a normal key. HYPER is the app leader and the
  -- window leader drives the window layout keys.
  appLeader    = "HYPER",
  windowLeader = "META",

  -- App toggle bindings (for Olm's AppToggler plugin)
  -- Uses app names from config/apps.lua.
  -- An entry with no `modifiers` field binds into the Hyper modal, fired by holding the
  -- Hyper key (Caps Lock, remapped to F18 and driven by HyperKey, now Olm's
  -- lib/hyperkey.lua) plus the letter. A quick Caps Lock tap toggles real Caps Lock
  -- instead. When HyperKey is not wired up in init.lua, AppToggler falls back to
  -- binding such an entry to the literal ⇧⌃⌥⌘ combo it holds internally, so losing
  -- HyperKey degrades the chord rather than the toggle.
  --
  -- An entry that DOES state `modifiers` means the opposite of that fallback. It asks
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
