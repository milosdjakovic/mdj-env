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
--   compared without case. fn is refused on a held leader, which compares only the other
--   four, and stays legal in a chord of modifiers alone or on a leader of modifiers. The plus on the
--   main row is written as its unshifted key, shift+=, and the keypad plus is pad+, hyper+pad+.
--   An action is the plugin or host identity, a dot and the action name, vpn.open,
--   windowmanager.leftHalf, clipboard.appendCopy, apptoggler.Safari for an app in
--   config/apps.lua, whose style config/toggles.lua may set,
--   systemsettings.General for a System Settings pane, and launcher.open, launcher.lock and
--   launcher.sleep for Olm's own.
--   An action named here takes exactly the chords listed for it here and loses its defaults, and
--   every action not named keeps its own. A chord a default holds is taken from that default, and
--   that one row of the default is not bound, said in one routine console line, while the action
--   keeps every other chord it has. false frees a global chord, so whatever held it is not bound
--   and nothing takes its place. The keys live while a list is open are the lists section below,
--   never this one.
--   An app's key shows wherever Olm lists the app, on the sheet of the leader it sits on and on
--   the app's own launcher row, so moving one here moves it everywhere.
--     ["meta+E"] = "vpn.open",
--     ["meta+Y"] = "clipboard.open",
--
-- leaders is the one place a leader is defined, the key or modifiers it is and how it behaves, in
-- one entry. An entry states its kind with mods, a list of shift, ctrl, alt and cmd, which makes a
-- leader of real modifiers, or with key, one key Olm makes act as a modifier. Both or neither is a
-- problem line, and the leader keeps its shipped default, a new name is ignored. A leader may
-- listen on one of each at once, written triggers = { { key = ... }, { mods = ... } }, with a
-- remapTo inside the key trigger. More than two, or two of one kind, is a problem line. Only these keys
-- may be a held leader, capsLock, rightCommand, rightOption, rightControl and f13 to f20. Anything
-- else is a problem line naming them, since a letter as a leader taxes every word typed with it
-- and the left modifiers and F1 to F12 are what ordinary shortcuts and the media keys need. f13 to
-- f20 are how extra hardware becomes a leader, since a foot pedal, a macro pad or a programmable
-- keyboard can be set in its own firmware to send one of them, and Olm hears it as it is.
-- capsLock and the right modifiers are remapped to a function key instead. remapTo, beside key,
-- pins which one, one of f13 to f20, and without it Olm uses the key's preferred one, capsLock f18,
-- rightOption f16 and rightCommand f17, and rightControl or a taken preference gets the first free
-- one. A taken preference is said in one routine console line. remapTo is a problem line beside
-- mods, beside a key that is f13 to f20 already, when it is not one of f13 to f20, and when another
-- leader uses that key. Two leaders on one key, or on one function key, are problem lines too and
-- every entry here that conflicts is dropped. A quick tap of the key alone toggles Caps Lock when
-- the key is capsLock and does nothing for any other key, so there is no field for it, and
-- tapTogglesCapsLock is retired, a problem line saying so, and ignored. Beside its trigger an entry
-- may state behaviour, ranked, drivenRepeat, sheet and sheetLayout. Olm ships hyper on capsLock
-- and on shift, ctrl, alt and cmd, meta on rightOption and on shift, ctrl and alt, and super on
-- rightCommand, with their behaviour already written, and an entry here is laid over the shipped
-- one of the same name. hyper and meta answer whichever form arrives, so a machine where kanata
-- sends the modifiers and one where Caps Lock arrives as f18 both reach them, and the cost is that
-- the modifier combinations their chords add up to are taken from every app on every machine. The
-- trigger, mods, key, remapTo or triggers, is replaced as one, so hyper = { key = "capsLock" } leaves
-- hyper on Caps Lock alone, and each behaviour field is merged over the shipped one, so naming one
-- field keeps the rest. A new name starts with every behaviour off. No name is reserved, a name is
-- refused only when it is not one word of letters and digits, is a modifier or role word, or
-- repeats another in a different case. A leader of modifiers reads like hyper in a chord and on a
-- launcher row. It has no tap, since holding real modifiers is ordinary typing, and a sheet on
-- one is opt in, revealed once exactly that set has been held for the hold delay and taken down
-- on any key or change of the set. Its chords are taken from every app, so it suits combinations
-- the apps here leave free. Its behaviour fields work, ranked as anywhere and drivenRepeat counting the
-- hotkey's own repeats. A modifier leader that hosts a list key seals over an open list, so none
-- of its chords acts beneath one. A leader no chord uses is said in one routine console line. A
-- bare list, nav = { "shift", "ctrl" }, is still read as mods with a routine console line saying
-- to write mods. A shipped name may take the other kind. hyper written with mods stops being
-- Caps Lock, which is then not remapped, and keeps the behaviour it ships, so a person whose
-- Karabiner sends Hyper as the four modifiers writes the first line below. A role and the list
-- role land on any leader, held or modifier. With the four modifiers, a chord asking for shift,
-- ctrl, alt or cmd beside hyper cannot be told from the plain one, and is said in the console. On a
-- hyper that listens on both, such a chord is answered by Caps Lock alone and the console counts
-- them in one routine line. Two chords on different leaders that come to the same modifiers and key
-- once those halves are counted, meta+cmd+K beside hyper+K, are one problem line naming both.
--     hyper = { mods = { "shift", "ctrl", "alt", "cmd" } },
--     meta = { triggers = { { key = "rightOption", remapTo = "f15" }, { mods = { "shift", "ctrl", "alt" } } } },
--     pedal = { key = "f13", sheet = true },
--     hyper = { key = "capsLock", remapTo = "f19" },
--     nav = { mods = { "shift", "ctrl" } },
--     meta = { drivenRepeat = false },
--     super = { key = "rightCommand", sheet = false },
--
-- roles moves every default on a role to another leader at once. A plugin's defaults name a
-- role, app or window, never a leader, and every default list key rides the list role. app and
-- list land on hyper and window on meta unless this says otherwise. A held leader is remapped
-- only while some chord uses it, so moving the window role to super claims Right Command and frees
-- Right Option. Moving the app role off hyper still keeps Caps Lock remapped while the list role
-- or any chord sits there, and moving both frees it.
--     window = "super",
--     list = "meta",
--
-- aliases maps a plugin identity to the words that scope the launcher to it, in place of the words
-- the plugin ships. Every plugin not named keeps its own.
--     vpn = { "v", "vpn", "tunnel" },
--
-- lists holds the keys live only while a list is open, one table per list keyed by its context
-- name, clipboard, fileSearch, emoji, launcher and the rest, and all for the keys every list
-- shares. Each maps a chord to the action it runs in that list, or to false to free it. The
-- shared verbs are primary, the list's own main action, selectNext, selectPrev, close and
-- openActionPanel, which Olm puts on hyper and i, j, k, x and o unless a list states its own, the
-- launcher closing on space, then secondary, a list's second action, which Olm puts on Command and
-- Return and Command and keypad Enter, and showKeys on Command and ? and Command and slash, all with no leader. Any
-- other action a list lists, deleteSelected in the clipboard, is named the same way. all is read first and each list's own table over it, so a list's own entry
-- decides every action and chord it names there. all moves only the keys Olm gave, so the
-- launcher's space close, which is also its open key, moves only in a launcher table, and a key a
-- list adds of its own, deleteSelected's d, moves only in that list's table. The rules are the keys section's inside one list.
-- An action named takes exactly the chords listed for it, a chord a default holds is taken from it
-- with one routine console line, and false frees the chord. A list chord names its leader the way
-- a global chord does, hyper, meta or super, so meta+j in a list is live only while that list is
-- open and moves only that key, while the list role above moves every default at once. A list
-- chord with no held leader, ctrl+j, a leader named below such as nav+k, or a bare key such as tab,
-- is answered by the list's own text field while the list is up and is never taken from another
-- app. One that would type into the field, a key that types a character pressed alone or with
-- shift, is refused, and so is one the field already reads, its editing keys, return, the up and
-- down arrows, escape and cmd with a digit, and one naming fn. alt on a printable key is kept, and
-- in that list it then acts rather than typing its character, said in one routine console line.
-- The legacy chooser answers none of them. While a
-- list is open a held leader answers only its keys for that list and swallows every other key, and
-- a list key may shadow a global chord on purpose, the way hyper+j opens emoji outside a list and
-- moves down inside one. A key a list reads for itself, Backspace leaving a hosted list, is the
-- list's own and is not set here.
--     all       = { ["hyper+n"] = "selectNext" },
--     clipboard = { ["meta+e"] = "deleteSelected", ["hyper+o"] = false },

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
    -- The terminal, popping in and out through its popup style in config/toggles.lua. The popup
    -- sat on Option and backtick as a variant of its own beside the plain toggle on this chord
    -- until 2026-10-23.
    ["hyper+`"] = "apptoggler.Ghostty",
    -- Activity Monitor. On backslash, chosen when file search sat on slash beside it. File search
    -- moved to semicolon on 2026-10-23, since macOS takes Hyper and slash before any event tap.
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
    -- nav = { mods = { "shift", "ctrl" } },
  },

  roles = {
    -- window = "super",
  },

  aliases = {
    -- vpn = { "v", "vpn", "tunnel" },
  },

  lists = {
    -- all       = { ["hyper+n"] = "selectNext" },
    -- clipboard = { ["hyper+e"] = "deleteSelected" },
  },
}
