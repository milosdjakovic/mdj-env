# Browser Switcher

With Olm as the default browser, every link you click opens this list, which asks where it goes,
your favourites, each a browser or one of its profiles, and Show All in the actions pane lists
every browser and profile this Mac has. Return opens the link and Command and Return copies it. It
has no launcher row, since without a link there is nothing to do with it.

It is a core plugin, built into Olm.app as its own module, docs/DESIGN-APP-PLUGINS.md. It ran as an
external plugin from 2026-11-24 and moved into the app on 2026-11-28, Milos asking that every plugin
of ours be core. `olm-plugin.json` beside it declares what its page in Olm Settings shows, its
settings, Default Browser, Order and Favourites, its two abilities and its actions, in the external
format without the sandbox's fields. Olm reads the browsers' profiles for it while Browser Profiles
is on and opens the link where it is chosen, by Olm's id for that browser. What it keeps, the last
link and its uses, is in `~/.olm/state/browserswitcher`.
