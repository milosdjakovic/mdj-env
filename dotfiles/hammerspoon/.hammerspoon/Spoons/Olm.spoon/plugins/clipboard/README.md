# Clipboard

Keeps a history of what you copy, text, urls, images, and files alike, and pastes
any of them back into whatever app is in front. The picker shows a live preview
beside the list, filtered by whatever you type.

Opens on Hyper and X, showing its own list rather than the launcher. Two extra
actions work with nothing open at all, append copy on Ctrl and Option and C
glues the current selection onto the newest entry instead of pushing a new one,
and paste next on Ctrl and Option and V walks backward through history one press
at a time. Both, and manage history, are action descriptors the plugin answers,
so Olm binds their keys and lists each as a launcher row beside Clipboard history.

Typing searches the history by each entry's first line, its whole text and the names of
copied files, the best matches first and the newer first among equally good ones. A leading
img, url, file or txt keeps only that kind, so file report lists the copied files named report. A copied file answers only to its
file name, so a word from the folder it sits in finds nothing.

While the list is open, j and k move, i pastes the highlighted entry, a appends it
to a batch, d deletes it, and x closes the list.

The same list has a second page for deleting in bulk, reached with m while the list
is open and from the launcher row named manage clipboard history. An empty field
offers the usual rungs, the last hour, the last twelve hours, the last twenty four,
two days, seven days, and everything, each row saying how many of how many items it
would take. Typing a duration instead, in weeks, days, hours, and minutes written in
any order, so 4d12h or 12h4d or 90m, offers the same thing both ways round, delete
what was copied in that span or delete everything older than it. A plain number is a
count rather than a span and offers the same pair, so 100 will either delete the newest
hundred or delete everything but them. The pane beside the list shows what would go,
newest first, before anything is chosen. Backspace on an empty field, or m again, gives
the history list back.
