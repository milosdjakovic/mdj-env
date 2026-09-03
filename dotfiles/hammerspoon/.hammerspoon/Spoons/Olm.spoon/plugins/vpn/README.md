# Vpn

Picks a VPN location and connects to it. One flat list merges the connect or
disconnect action with the location search, the action naming where the tunnel
is or where it would go, and every location follows below it ordered by the one
you most recently chose. Typing filters the locations, and once anything is
typed the action row drops out so the top match connects rather than the tunnel
toggling.

Two backends are supported, Mullvad and IVPN, and one of them drives at a time.
The last row of the list opens a page listing every backend, saying which one is
active, which are installed, and which this machine cannot reach. Choosing one
there switches to it and is remembered across reloads. The page can also be
reached by typing settings, config, or provider.

Opens on Hyper and P, appears in the launcher under Network, and can be searched
without leaving the launcher by typing v or vpn. The provider page is reachable
from the list itself rather than from the launcher, since the launcher's scoped
rows cannot open a level.

While the list is open, j and k move, i confirms the highlighted row, and x
closes it. On the provider page, Backspace or the Back row returns to the
locations, and choosing a backend leaves the page open.

Without the active backend's app installed, the list opens to one row explaining
that, with the provider page still beside it so the choice can be taken back.
