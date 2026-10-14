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

The clipboard pane's copied text is the code role wrapped through `ui.text`, decided 2026 10 14
while building its step. It is not the code block, because copied prose is one long line and the
block never wraps, so it would cut that line at the pane edge and hide most of what was copied.
File heads elsewhere and the process tree keep the block, since there a line is a line and a cut
one is honest. The clipboard header is one component for every kind of entry, the source at the
left, the app icon and its name in caption, and the facts flush right in caption and subtext,
built from a table in the fixed order kind, details, time, marks and upper cased as a whole. To
let the facts keep their whole width while the name gives way, the kit's row gained `fillIndex`,
which names the child that takes the remaining width, and `raw` gained an optional `width` so an
icon the pane draws itself can sit beside a name.

The file search pane was decided on the same day, 2026 10 14, while building its step. Its file
head wraps, the same choice the clipboard made for its text files, so a file looks the same in both
panes. The kit's measurer, which now keeps whitespace as written and expands tabs by the same width the
code block draws, wraps each source line at the content width, and
the resulting drawn lines are drawn as a code block, so the head budget and slack stay counted in
drawn lines and the scrolled slice stays cheap for a long head. The folder listing is a code block
that does not wrap. The file name is title, the folder is code in the path colour and wraps, each
fact pair is caption with the label in subtext and the value flush right, and a heading is section.
Because the clipboard and file search panes both draw an image scaled to the pane width, the kit
gained an `image` primitive for the two, which keeps the aspect and can refuse to draw wider than
the picture itself. The header stays pinned and only the body scrolls, as before.

The processes pane was decided on the same day, 2026 10 14, while building its step. Every
heading, CPU, MEMORY, PORTS, DIRECTORY, COMMAND, IMAGE, CONTAINER and TREE, is section with its
optional facts flush right in subtext, and it is the kit's new `heading`, moved there from the file
search pane because speedtest needs it next. Ports, the command or image, and the container id are
the code role wrapped, so whitespace in a command now stays as written where the old wrap collapsed
it, and the directory is the same in the path colour. The tree is the kit's code block with a
closing line worded "… N more", so it is cut at the pane width by the block rather than by a column
budget and the label elision went, and the pid sits before the label so a cut never moves it. The
sparklines are raw nodes, their geometry stays named constants since it belongs to a graph and not to
type, their colours come from tokens, the baseline is the dim colour, and the live block's height is
derived from the section line height and the space steps. What the pane is made of is built as nodes
in a pure file, `pane-nodes.lua`, covered by a unit case, and the canvas, the cache and the sampler
stay in `preview.lua`, which caches the static half's laid out elements the way file search caches
its header, so a sampler tick lays out the live block alone.

The speedtest pane was decided on the same day, 2026 10 14, while building its step, and it was
the last of the four. The large figures, the download, the upload, Running, Warming up and Nothing
measured, are title, headings are the kit's heading, the live responsiveness line and the trend's
network label are body, and every explanation and every line of metadata is caption in subtext,
wrapped where it was wrapped before. The graphs are raw nodes coloured by rank, the download
primary, the upload secondary and the latency or responsiveness strip tertiary, with the baseline in
border, and the mark under the newest bar takes the colour of its series. What the pane is made of is
a pure file, `pane-nodes.lua`, covered by a unit case, and the canvas, the scroll and the choice of
view stay in `pane.lua`, whose scroll events add up and paint once a frame. Both large figures are
foreground, see decisions/olm-colour-roles.md.

The digits question the plan left open was checked and has a plain answer. The title role is the
proportional system font, whose digits have different widths, 8.7 points for a one and 12.1 for
an eight at twenty points. A canvas takes a font by name and size and nothing else, Hammerspoon's
font conversion reads those two keys and ignores the rest, so a tabular digit feature cannot be
asked for, and no font name reaches the system for a monospaced digit variant of the system font,
the names tried all came back as the system font. The monospace role is a different design and
not an option for a figure. So the figure is drawn in a slot. The kit's `text` gained a `width`
option, a slot of exactly that many points with the text aligned inside it, and the pane draws the
number right aligned in a slot as wide as the widest value the format can make, three digits before
the point and one after, measured at the title role with the widest digit the measurer finds, and
the unit after the slot, so the unit never moves. A reading wider than the slot widens it for that
reading only. The cost is that a short number stands a little in from the left edge.

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
   variants they used are deleted. Judged live. Built 2026 10 14, every text variant outside
   the five roles is gone and none had another consumer.
4. The four panes, one plugin per step, clipboard, file search, processes, speedtest. The
   clipboard step, the file search step, the processes step and the speedtest step were built
   2026 10 14, so every pane step is built. Each step draws its pane through `ui.layout`, deletes
   its own fonts, sizes, palette closure and fallback colours, drops its theme exemption line,
   and is judged live before the next.
5. Close out. The last retiring variants and lib/chooser/textwidth.lua go, and a check joins
   the dry gate that reports any font name, text size or line height set outside lib/ui, the
   way the theme checker reports a hex value, so the rule cannot drift again.
