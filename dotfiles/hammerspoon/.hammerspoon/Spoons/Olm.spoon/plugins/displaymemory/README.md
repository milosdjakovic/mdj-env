# DisplayMemory

Remembers which display one particular app's window last sat on, kept separately
for each set of attached monitors, so the app returns to the same screen the next
time that same set of monitors is attached. It watches the app for a move across
displays and stores nothing beyond a display identifier, keyed to the current
set of monitors.

It runs on its own with no key and no picker. Today it watches the terminal app
on behalf of the terminal handler that opens and places it, and nothing else asks
it for anything.
