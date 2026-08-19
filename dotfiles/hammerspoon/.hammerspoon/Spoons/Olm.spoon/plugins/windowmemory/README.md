# WindowMemory

Remembers every standard window's position and size for the current set of
attached displays, and puts them all back automatically once the display
arrangement settles after docking, undocking, or waking. It is the same idea as
DisplayMemory widened from one app to every window, and from a remembered
display to a remembered frame.

It runs on its own with no key and no picker, watching windows and screen changes
rather than waiting to be asked. The memory lasts only for the current session,
so a restart or a Hammerspoon reload starts it fresh, though it fills back in the
moment windows move again.
