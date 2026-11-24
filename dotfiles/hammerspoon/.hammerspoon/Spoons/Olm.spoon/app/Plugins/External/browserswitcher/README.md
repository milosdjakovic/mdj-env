# Browser Switcher

With Olm as the default browser, every link you click opens this list, which asks where it goes,
your favourites, each a browser or one of its profiles, and Show All in the actions pane lists
every browser and profile this Mac has. Return opens the link and Command and Return copies it. It
has no launcher row, since without a link there is nothing to do with it.

It is an external plugin, run by Olm.app in a sandbox with no permission of its own,
docs/DESIGN-APP-PLUGINS.md. Olm reads the browsers' profiles for it while Browser Profiles is on and
opens the link where it is chosen. Its settings, Default Browser and Favourites, and its two
abilities are on its page in Olm Settings, under Plugins. `src/setup-olmapp.sh` installs it into
`~/.olm/plugins/browserswitcher`, and Olm.app builds it from `Sources` with OlmPluginKit.
