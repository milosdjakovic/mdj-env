# WindowSize

Turns a typed pair of dimensions into one launcher row that sizes the focused window to
exactly that and centers it. Typing `1920x1080` offers a row titled `Resize Safari`, naming
the application the list was covering when it has a focused window, or `Resize window` when
that cannot be known, and
choosing it resizes that application's window once focus is back on it. A capital X and the
multiplication sign are the same separator. An asterisk is not one, since `1920*1080` is
arithmetic and already answers with a product.

There is no key and no list of its own. It is a launcher query row source, found only by
typing a size, and the launcher's empty field carries the hint that says so.

The resize itself belongs to the window manager, which already sizes a window to exact pixels
and centers it. This plugin asks that one what a request would land as before offering it, so
the subtitle is the size that will land, `1920 x 1080`, and a size larger than the display
reads `1728 x 1080, display limit` rather than surprising you after the fact. The row hands
over the size before that trim, so the trim happens against the screen the window is really
on.

An edge below `smallestEdge`, 200 by default, is raised to it, so `19x1080` reads
`200 x 1080, size limit` and choosing it sizes the window to that rather than into a sliver.
It used to offer no row at all, which was meant to keep a typo from quietly acting, but a row
that silently vanished never said why, and the subtitle now says so before Return. When both
limits apply the subtitle names the size limit, since it holds on every display.
