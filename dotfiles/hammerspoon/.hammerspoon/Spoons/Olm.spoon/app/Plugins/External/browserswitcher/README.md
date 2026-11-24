# Browser Switcher

With Olm as the default browser, every link you click opens this list, which asks where it goes,
your favourites, a browser, one of its profiles or Copy Link, and Show All in the actions pane lists
every browser and profile this Mac has. Return opens the link, Command and Return copies it, and the
launcher row Browser Switcher opens the last link again to send it somewhere else.

It is an external plugin, run by Olm.app in a sandbox with no permission of its own,
docs/DESIGN-APP-PLUGINS.md. Olm reads the browsers' profiles for it while Browser Profiles is on and
opens the link where it is chosen. Its settings, Default Browser and Favourites, and its two
abilities are on its page in Olm Settings, under Plugins. `src/setup-olmapp.sh` installs it into
`~/.olm/plugins/browserswitcher`, and Olm.app builds it from `Sources` with OlmPluginKit.
