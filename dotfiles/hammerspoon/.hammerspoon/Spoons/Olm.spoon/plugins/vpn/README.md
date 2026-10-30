# Vpn

Picks a VPN location and connects to it. One flat list merges the connect or
disconnect action with the location search, the action naming where the tunnel
is or where it would go, and every location follows below it ordered by the one
you most recently chose. Typing filters the locations, and once anything is
typed the action row drops out so the top match connects rather than the tunnel
toggling.

Two backends are supported, Mullvad and IVPN, and one of them drives at a time.
Provider in the action panel lists every backend, marking the one that is active
and dimming any this machine cannot reach. Choosing one there switches to it and
is remembered across reloads.

Opens on Hyper and P, appears in the launcher under Network, and can be searched
without leaving the launcher by typing v or vpn. Provider is reached from the
list itself rather than from the launcher's scoped rows.

While the list is open, j and k move, i confirms the highlighted row, and x
closes it.

Without the active backend's app installed, the list opens to one row explaining
that, with Provider still in the action panel so the choice can be taken back.
