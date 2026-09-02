# LinkRouter

Sends a clicked link to a destination you pick at the moment you click it, rather than to one
browser you chose once in System Settings. Hammerspoon holds the system handler for http and
https, so every link on the machine arrives here first, and a short list opens under the cursor.
Choosing a row opens the link there. Copy link puts it on the clipboard instead. Escape cancels,
and a cancelled link is simply not opened.

A destination is finer than an application. A Chromium browser expands into one entry per
profile, plus a private window entry for each, so Chrome with three profiles gives you six
things you may choose to show. Everything else is one entry for the whole application.

Destinations are whatever LaunchServices reports on this machine, so a browser installed later
appears without anything being edited, and Hammerspoon itself is the one entry always removed,
since routing a link to the router would hand it straight back forever.

Safari and Arc are single entries with no profiles and no private window. Neither can be asked
for either from outside, so neither is offered rather than being offered and failing.

## How it opens and where it appears

The router opens by itself, whenever a link is clicked in any application. It has no key and no
typed word, because the thing that opens it lives outside Hammerspoon entirely.

The configuration page is a launcher row, Link routing, under System.

A url pasted or typed straight into the launcher shows one row, Open link in browser. Choosing
it pushes this same list one level down in the same window, with that url waiting to be routed,
so you see exactly what a clicked link shows, your ordered destinations, More, and Copy link.

## The main list, and More

The router shows your main list, then a More row, then Copy link. Everything not in the main
list lives under More, one level down, so a short main list never puts a browser out of reach.

## Choosing what is shown, and in what order

Both are the same act. On the configuration page, choosing a destination adds it to the end of
your main list and choosing it again sends it back under More, and the number beside each row is
its real position. So picking Safari, then Chrome (Milos), then Chrome (Vicert), in that order,
gives you exactly

```
1. Safari
2. Chrome (Milos)
3. Chrome (Vicert)
```

To reorder, choose Start over, which empties the main list, then pick the destinations again in
the order you want. Appending is the only way something joins the list, so there is no way to
move an item already in it without starting again. Nothing is lost by emptying the list, since
everything is still under More.

Until you choose anything, every ordinary destination is in the main list in the order macOS
reports them, so the router works before it is configured. Private windows are never in it by
default.

The row at the top claims the system handler for this list, or hands it back to your first
destination. macOS asks for confirmation itself every time that row changes anything.

## Rules

A rule sends a link straight to a destination without asking. The last row of the router offers
to make one for the site you are looking at, and choosing a destination on the page it opens
both saves the rule and opens the link.

A rule for a site covers everything under it, so a rule for github.com also catches
gist.github.com and will not catch notgithub.com. The newest rule is asked first, remaking one
replaces it, and a rule pointing at a browser you have since removed is skipped so the chooser
opens as though it were not there.

The Rules row on the configuration page lists them. Choosing a rule deletes it.

## In list keys

Only the shared navigation keys, and Return or the primary key to choose. There are no
shortcuts of this plugin's own, deliberately. Everything it can do is a row you select.

## Known cost

While Hammerspoon is reloading, or while a config error has it down, a clicked link goes
nowhere. That is accepted rather than solved, and the reason is in `CLAUDE.md`.
