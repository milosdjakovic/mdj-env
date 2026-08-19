# Capture

Screen capture, recording, and OCR, run through a chain of backends so the
underlying screenshot tool can be replaced, or fallen back on, without changing a
key. OCR runs on Hyper and three, dragging a region and copying the recognised
text. A screenshot copies to the clipboard on Hyper and four, adding Shift saves
it to a file instead, and Hyper and five records the screen.

There is no single open and no picker. Each chord fires its own action directly,
and nothing here is navigated or searched.
