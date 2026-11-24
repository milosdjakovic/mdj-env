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
