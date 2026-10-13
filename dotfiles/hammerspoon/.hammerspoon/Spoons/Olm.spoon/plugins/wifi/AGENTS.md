# Wifi, decisions and findings

Measured on macOS 27 on 2026-10-10, recorded so nobody has to find them again.

## Network names, and how the grant is judged

macOS hands a network name only to an application holding Location Services, and without it
the answer is a string of spaces, not nil and not an error. The speedtest plugin met the same
thing first and its `util.lua` says so. A scan without the grant returns every network with no
name, so the list has nothing to offer, which is why the grant is declared as a gate.

`hs.location.authorizationStatus()` cannot be trusted to say whether that grant is held. In a
fresh Hammerspoon process it answers `undefined` on a machine where the grant was given, and
it only answers `authorized` once `hs.location.start()` has run in that process. The network
name read correctly the whole time. So the plugin judges the grant from the answers it gets,
a joined interface with a blank name or a scan of nameless networks, and never asks the status.
The module's `grants-probe` judges the same way for the same reason, and it cannot start
location updates to get a truer answer, because starting them is what raises the prompt.

The row that asks for the grant starts location updates, since that is the only thing that
raises the prompt, and stops them a minute later. Nothing here wants a location.

## Joining runs through networksetup, not hs.wifi

`hs.wifi.associate` joins on the main thread and holds it for the whole association, which is
seconds, so every key on the machine would wait with it. `networksetup -setairportnetwork` runs
as a task instead. Given no password it joins a saved network with the password the system
holds, which is why saved networks join with no prompt.

## The password prompt is a system dialog

A password typed into the chooser field would sit there in plain text, and the field has no
secure mode. `hs.dialog.textPrompt` with its secure field is the one way to take a password
without showing it, so an unsaved secured network asks there. It is the only place this plugin
shows anything outside the shared stage.

## Scanning

Five things about `hs.wifi.backgroundScan` were measured during the live test, and the shape of
the list follows from them.

A cold scan, the first after moving somewhere new, took about eight seconds. So while one is in
flight and nothing else is listed, the list says it is still looking, because a list showing only
the current network reads as finished and was closed as finished.

A scan started soon after another answers within milliseconds from a cache with every name
stripped, dozens of nameless networks, even with the grant held. So a scan with no names never
replaces a list that has them, and it counts as a missing grant only when the current network is
nameless too.

A scan reports only part of what is in range. A saved 5 GHz network a few metres away was missing
from one scan and present in the scans either side of it. So the list is what recent scans saw
together, a network staying listed for two minutes after it was last seen, and the network just
left counts as seen at the moment it was left, since it is in range by definition.

Two scans in flight at once answer only one of their callbacks. One scan runs at a time here,
every caller waiting on it is called back, and a scan that never answers is given up on after a
bound so the list cannot wait forever.

The launcher scope is asked for rows on every keystroke and again on every redraw, so a scope
that started a scan whenever it was asked looped, each landing asking for the next, and the
looping scans were the stripped ones above, which emptied the list a moment after it filled. The
scope starts a scan only when the last one is stale. The tool's own list scans on present, which
runs once per opening.
