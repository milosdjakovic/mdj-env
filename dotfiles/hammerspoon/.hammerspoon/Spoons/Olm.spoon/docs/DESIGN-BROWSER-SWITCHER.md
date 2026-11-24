# The browser switcher

Status. Designed on 2026-11-24, asked by Milos, and built the same day after he answered the
questions, see As built. `decisions/olm-browser-switcher.md` has what was turned down.

## What a person gets

Olm becomes the Mac's default browser and never shows a page itself. Every link clicked anywhere,
in Slack, Mail, a terminal or a PDF, goes to Olm, and Olm hands it to a real browser in a fraction
of a second, picked by rules a person sets.

1. **Rules, first match wins.** Each rule is a pattern and a browser: `*.github.com` to Safari,
   `meet.google.com` to Chrome, `localhost:*` to Firefox. A pattern matches the host, with `*` for
   any part, or a whole address prefix when it has a path. A rule may also name the app the link
   came from, so every link out of Slack goes to Chrome whatever its address.
2. **A fallback browser.** A link no rule matches opens there, or Olm asks, as the person chooses.
3. **Asking.** Olm's own list opens with the browsers installed on this Mac as its rows, the link
   as its subtitle line, the last browser chosen for that host first. Return opens it there.
   Escape opens nothing. The actions pane has **Always Use for This Host**, which writes the rule,
   and **Copy Link**.
4. **A key held at the click.** Holding Option while clicking a link makes Olm ask, whatever the
   rules say. Holding Shift opens it in the fallback browser, skipping every rule.
5. **Becoming the default, and back.** The plugin's page has **Make Olm the Default Browser**,
   which raises macOS's own dialog. Switching the plugin off offers **Give the Default Back**
   to the fallback browser, the same dialog. Nothing does either on its own.

## Where each part lives

Two parts, split by what must never fail.

- **Receiving a link is the app's, always.** Olm.app declares `http` and `https` under
  `CFBundleURLTypes` and the HTML document types, the three records that make an app a default
  browser candidate, and takes each link in its URL handler, which `olm://` already uses.
  Receiving can't live in a plugin, since a link that arrives while Hammerspoon reloads, or while
  a plugin is stopped, would be lost.
- **Choosing the browser is the plugin's.** The app asks the plugin, with the link, the source
  app's bundle id from the Apple Event's sender, and the keys held at that moment. The plugin
  answers a browser to open it in, or that it asks, and then it opens its own list. Today the
  plugin is Lua and the question goes over the bridge as one new request, `link`. Once external
  plugins load, steps 2 to 4 of `docs/DESIGN-APP-PLUGINS.md`, the same request goes to its Swift
  rewrite through the runner, like every other plugin.
- **A link is never lost.** The app waits up to 250 ms for an answer, and up to 2 s for the bridge
  to connect when it is down, a reload. Past either it opens the link in the fallback browser and
  logs why. The app keeps the fallback itself, read from the shared settings, so this works with
  the plugin off or broken.

## The loop to avoid

Once Olm is the default, anything that opens a link "in the default browser" reaches Olm again,
Olm's own `open` request included. So the app and the plugin always open a link in a named
browser, `NSWorkspace.open(_:withApplicationAt:)`, never through the default. Olm is never a
choice in the fallback menu or on a rule, and a rule that names an app no longer installed falls
through to the next one.

## Settings, on the plugin's page

- **Fallback Browser**, a choice of the installed browsers, the ones LaunchServices lists for
  `https`, without Olm.
- **When No Rule Matches**, Open in the Fallback Browser or Ask.
- **Rules**, a list of pattern, optional source app and browser. This needs a new setting kind,
  a table of rows each with a text and a choice, which plugin pages don't have yet.
- **Default Browser**, a status line saying whether Olm holds it, and the button.

## Prior art, ideas taken, nothing copied

Finicky's rules by host and source app, Velja's and Choosy's held key to ask, and Browserosaurus's
picker. Finicky writes its rules as a JavaScript file. Ours are settings, so a person never edits
code to add one.

## What it costs

- **Every link goes through Olm.** Olm.app quit means a link starts it first, about a second.
- **macOS asks every time the default changes.** Both buttons raise its dialog, and a script can't
  answer it, as `decisions/dev-defaults.md` measured for file types.
- **A browser profile isn't a browser.** Opening Chrome's work profile needs `--profile-directory`
  passed to a launch, which works only when Chrome starts or through its own command line. Profiles
  are left for later, see the questions.

## The order to build it in

1. **The app as a browser.** It declares the types and takes every link. It opens each in the
   fallback browser, with the page's button and the default given back. Nothing chooses yet, so this
   proves receiving, the dialogs and the loop guard alone.
2. **The plugin and `link`.** Rules by host and source app, the fallback when no rule matches, the
   held keys and the timeouts.
3. **Asking.** The list of browsers, its memory per host and Always Use for This Host.
4. **The rules table** on the plugin's page, the new setting kind. Until it lands, rules live in
   the plugin's settings as text, one rule per line, `pattern => Browser`.

## As built, 2026-11-24

His answers changed the draft above in four places, and where this section and the draft differ,
this section is true.

- **Asking is the default.** A link no rule matches always asks. The list shows the person's
  **Favourites**, in the order written, one per line, a browser, a browser and its profile after a
  colon, `Chrome: Work`, or `Copy Link`. **Show All** in the actions pane lists every browser and
  profile, **Show Favourites** goes back. Empty favourites show everything. Return opens the link,
  Command and Return copies it, Escape drops it.
- **Profiles** are listed for Chromium browsers from `Local State` and Firefox from
  `profiles.ini`, and opened by starting the browser's own program with the profile. Safari's
  profiles have no way in from outside. On this Mac macOS refused Chrome's `Local State` to every
  process, so the list says Chrome's profiles are hidden rather than inventing them.
- **Option** held at the click asks whatever the rules say. **Shift** was dropped, since with
  asking the default it meant the same.
- **Rules are text** on the plugin's page, `pattern => favourite`, a site with `*`, a path prefix,
  or `app:` and the source app's name or bundle id. The table setting is the planned next step.
- **No fallback setting.** A link nobody answers opens in Safari.
- **Default Browser** is the first row of the plugin's page, a menu of every app that opens https,
  read live, and choosing one raises macOS's question. It was two launcher rows for an hour, and
  Milos moved it here, the settings API's `handler` kind.
- The settings API gained `lines` on a text, its box that many rows tall under the title, one
  entry per line, and a text of one line refuses a line break.

- **Olm.app finds the browsers,** `app/Sources/OlmSettings/Browsers.swift`, at launch, before each
  link and while the plugin's page shows, and writes them to `~/.olm/run/browsers.json`, which the
  plugin reads to open a profile. **Favourites are checkboxes** over that list and Copy Link, the
  settings API's `picks` kind. None checked shows everything, any checked shows only those. Olm.app is
  kept from Chrome's profiles too until it has Full Disk Access, which the Permissions page lists.

- **Rules are gone,** 2026-11-24, asked by Milos. Every link opens the list, so Option has nothing
  left to override.

## Next

1. **Chrome's profiles,** confirmed once Olm.app has Full Disk Access.
2. **Rules, if wanted again,** a table setting of a site and a favourite.
