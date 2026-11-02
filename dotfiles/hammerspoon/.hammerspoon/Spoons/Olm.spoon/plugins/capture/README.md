# Capture

Screen capture, recording, and OCR, run through a chain of backends so the
underlying screenshot tool can be replaced, or fallen back on, without changing a
key. OCR runs on Hyper and two, dragging a region and copying the recognised
text. A screenshot saves to a file on Hyper and three, copies to the clipboard on Hyper and four,
and Hyper and five records the screen. Each has one key, after the colour picker on Hyper and one.

There is no single open and no picker. Each chord fires its own action directly,
and nothing here is navigated or searched. Each action is a descriptor this plugin
answers through `provides.actions`, and Olm binds the keys its `defaults.bindings`
suggest to them, so the plugin never binds a key itself. Olm also lists every action as a row
of the launcher's own catalog, typing screenshot finds them, built from the same descriptors, so
the plugin builds no row either.
