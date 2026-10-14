# Moving every piece of Olm text onto the five roles

Agreed 2026 10 14. The roles, the file and the rule live in the hammerspoon AGENTS.md
section on Olm typography. This plan is the order the consumers move in. It rests on a survey
of every plugin, host and shared component on that date.

## What the survey found

Most of Olm needs nothing. Every plugin and host hands the chooser plain strings for a row's
title and subtitle, and the provider styles them, so row text moves the day the provider
moves. Emoji drawn to images are icons rather than text, and `hs.alert` and `hs.dialog` are
system drawn. Text is set by hand in exactly these places.

| Unit | Effort | What it sets |
|---|---|---|
| canvas chooser, list, field and geometry | medium | row title and subtitle, field, row numbers, row height |
| native chooser | small | row title and subtitle sizes, row height |
| hint bar and toasts, lib/hints.lua | medium | badge glyph and label, toast message and report |
| cheat sheet, lib/cheatsheet.lua | medium | badge glyph, row label, section title, row geometry |
| empty pane state, lib/panel.lua | small | one line |
| clipboard preview pane | large | Menlo 11 and 13, meta strip, text body |
| file search side pane | large | Menlo 11 and 13, name, path, pairs, file head |
| processes preview pane | large | Menlo 11 and 12, headings, tree, ports |
| speedtest pane | large | Menlo 11, 12 and 20, figures, prose, headings |

## Decisions

The field takes title, changed on 2026 10 14 after the first live look, since the query is
the one thing on the surface a person is writing, and its height follows the title line.
Row titles take body, subtitles caption,
row numbers section. The canvas row grows from 38 to fit body over caption, and the native
row grows to match.

`settings.cheatSheet.fontSize` goes, since a second size knob for one surface is the drift the
roles end. The cheat sheet's row and badge geometry is derived from the roles instead.

Pane headings are section, written in capitals by the pane as they are today. A file name or
a process name at the top of a pane is title. Prose is caption. Paths, commands, file heads,
the process tree and ports are code. Speedtest's large figures are title, which moves them
from Menlo to the proportional system font, so their digits must be drawn tabular or they
slide as a figure changes. That is checked when speedtest moves.

## What the kit gains first

Three things the panes need and the kit lacks, each with more than one consumer.

1. A preformatted code block, one text per line in the code role, whitespace kept, no
   wrapping, cut to a height with a closing line saying how many more. The file head, the
   clipboard text, the process tree.
2. Visible slice drawing for a long block, so a long file lays out only the lines inside the
   scrolled window. The file head and the clipboard text.
3. A raw element node that places canvas elements a pane draws itself, a graph or a scroll
   thumb, inside the layout at a stated height, so the pane keeps its drawing while the kit
   keeps the position. Speedtest and processes.

## Order

1. The kit gains the three pieces above, with unit cases.
2. The canvas chooser and the native chooser, rows, field and geometry. Judged live.
3. The empty pane state, the hint bar, the toasts and the cheat sheet, then the retiring
   variants they used are deleted. Judged live.
4. The four panes, one plugin per step, clipboard, file search, processes, speedtest. Each
   step draws its pane through `ui.layout`, deletes its own fonts, sizes, palette closure and
   fallback colours, drops its theme exemption line, and is judged live before the next.
5. Close out. The last retiring variants and lib/chooser/textwidth.lua go, and a check joins
   the dry gate that reports any font name, text size or line height set outside lib/ui, the
   way the theme checker reports a hex value, so the rule cannot drift again.
