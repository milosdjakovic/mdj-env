# Olm browser switcher

Status. Built on 2026-11-24 as a Lua plugin answering links Olm.app receives as the default browser,
asking by default from favourites the person orders, with rules as text until a table setting exists.

## Now

Olm.app declares http and https and hands each link over the bridge's `link` request to the first
plugin providing `links`, Browser Switcher. A rule opens it at once, otherwise the list asks, Option
held at the click always asks. A link nobody answers within 2 s, or 3 s of the bridge being down,
opens in Safari. Favourites and rules are multi line texts on the plugin's own page in Olm Settings,
the settings API's `lines` field. Profiles come from each Chromium browser's `Local State` and
Firefox's `profiles.ini`, and macOS refused Chrome's `Local State` to every process tried on
2026-11-24, so Chrome lists as one browser and the list says its profiles are hidden.

## Rejected

- **Receiving the link in Hammerspoon,** `hs.urlevent.httpCallback`. 2026-11-24. A link arriving
  while Hammerspoon reloads would be lost, and Hammerspoon is going away, `olm-standalone.md`.
- **Matching rules in the app.** 2026-11-24. The choice of browser is the plugin's, so the Swift
  rewrite later answers the same request, and the app keeps only receiving and the fallback.
- **Shift to skip the rules.** 2026-11-24. With asking the default, skipping the rules is the same
  as Option's always ask, and Milos did not follow what it meant.
- **A fallback browser setting.** 2026-11-24. The fallback only covers a link nobody answered, and
  reading a plugin's setting from the app would have the app name the plugin. Safari is on every Mac.

## Log

### 2026-11-24 15:21, built, asked by Milos

He answered the design's questions: profiles where possible, ask by default with Copy Link one of
the choices, favourites he orders with Show All in the actions pane, Option fine, rules as text
first with the table planned, all set through the plugin settings API. Built as above. Checked
headless through Hammerspoon, a rule copying a link and the rows listing Chrome, Safari, Switchbar
and Copy Link. The machine's https handler was Switchbar when this was built, so nothing reaches
Olm until Make Olm the Default Browser is chosen.

### 2026-11-24 16:26, every link fell to Safari, the handler called as a method

Reported by Milos, the list flashed and the link opened in a browser. The manifest declared
`links = "link"`, a string spec, which the registrar calls as a method, so `M.link` got the module
table where the link belonged and raised on every link, and the app opened each in Safari. The
headless check of 15:21 called `M.link` directly and never went through the registrar, which is how
it passed. Now `{ member = "link", call = "dot" }`, checked through `registrar.action`. Rows are
titled `Chrome (Personal)` with no second line, and the field shows the link shortened in the
middle, both asked by him.

### 2026-11-24 16:35, Olm.app finds the browsers, favourites are checkboxes, asked by Milos

The scan moved into Olm.app, `Browsers.swift`, written to `~/.olm/run/browsers.json` for the
plugin, since Olm.app draws the page the favourites are picked on and is where the plugin is going.
Favourites are the new settings kind `picks`, checkboxes over the scan and Copy Link. Olm.app was
refused Chrome's `Local State` too, so Full Disk Access joined the Permissions page, naming Browser
Switcher. His typed favourites were converted to the new list in `~/.olm/state/settings.json`, the
old file kept in the session's scratch folder.

### 2026-11-24 17:00, rules removed, asked by Milos

Every link opens the picker. The rules setting, the matching and Option's override are gone, and
rules come back as a table setting if he asks for them.

### 2026-11-24 17:16, favourites live, the list only what is found, Full Disk Access read right

Reported by Milos. Full Disk Access given showed Not allowed, since the check opened the user's TCC
database, which macOS 27 keeps closed with access given, so it now tries a few files only that access
opens. Checking a box dimmed the whole list while the save went over the bridge, so a picks list
stays live and shows the click at once. Favourites waited for a reload, so a plugin setting may name
`onChange`, a member told the new value, and then applies at once. A saved name the scan no longer
finds is not shown and leaves on the next click, his Red Burst being the profile Redburst.

### 2026-11-24 20:00, rewritten in Swift and run by Olm.app

The list, its favourites, Show All and Show Favourites, Copy Link on Command and Return, the link in
the field and the launcher row that opens the last link again are the Lua plugin's, now
`app/Plugins/External/browserswitcher`, sandboxed. The Lua plugin is switched off, not deleted,
until Milos has tried the new one. `decisions/olm-standalone.md` has the rest.
