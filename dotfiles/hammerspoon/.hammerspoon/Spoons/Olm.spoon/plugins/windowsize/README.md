# WindowSize

Turns a typed pair of dimensions into one launcher row that sizes the focused window to
exactly that and centers it. Typing `1920x1080` offers the row, and choosing it resizes the
window once focus is back on the application the list was covering. A capital X and the
multiplication sign are the same separator. An asterisk is not one, since `1920*1080` is
arithmetic and already answers with a product.

There is no key and no list of its own. It is a launcher query row source, found only by
typing a size, and the launcher's empty field carries the hint that says so.

The resize itself belongs to the window manager, which already sizes a window to exact pixels
and centers it. This plugin asks that one what a request would land as before offering it, so
a size larger than the display reads as trimmed on the row rather than surprising you after
the fact, and the row hands over the size as it was typed so the trim happens against the
screen the window is really on.

A size whose shorter edge falls below `smallestEdge` offers no row at all, so a slip like
`19x1080` does nothing rather than shrinking a window into a sliver.
