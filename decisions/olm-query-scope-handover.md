# Olm query scope hand over, a typed word that reaches a list with a preview pane

Status. A typed alias whose tool shows its own list with a preview pane hands the launcher over
to that list, the same push choosing the tool's launcher row makes, and every other alias stays a
query scope inside the launcher.

## Now

The root, `root/compose.lua`, gives a scope a `handOver` function when the registry's presentation
for that tool declares a preview pane, a `previewPaneWidth` of true or a number above zero. The
query scope answers it as a third value on every claim, `host/queryscope/init.lua`, the launcher
calls it on the next turn of the run loop through one kept timer, `host/launcher/init.lua`
`_scheduleHandOver`, and the root's function pushes the presentation onto the stage and puts what
was typed after the alias into its field. So `/ report` shows File Search's own list, preview pane
and every key included, exactly as Hyper and semicolon or choosing its launcher row would. Backspace
on an empty field steps back to the launcher, as it does after choosing the row. File Search and
Speed Test take it today, and any tool that has an alias and a list with a preview pane takes it
with no edit, Clipboard and Processes the day either is given an alias. An alias of a tool with no
pane, Keep Awake, VPN, volume, emoji and the rest, is unchanged, and deleting its space still hands
the launcher's list back.

## Rejected

A scope that claims and drives a preview pane of its own. Rejected 2026-11-04. The launcher would
have had to take on the tool's pane width, highlight, scroll, position and close callbacks while a
scope held the query, unwrapping the scope's row descriptors back into the tool's items for each,
which is a second copy of the presentation routed through the launcher, the arrangement the stage
exists to end. The window would also gain and lose a pane on a single keystroke.

Handing over every alias of a tool that presents on the stage, pane or not. Rejected 2026-11-04.
It would end the query scope's recorded design for tools it already serves fully, where the typed
value such as `k 2h` and deleting the space to step out are the point, to fix a gap only the pane
tools have.

Calling the hand over from inside the rows supplier. Rejected 2026-11-04. The stage is building
the launcher's list when it asks for rows, and asking what a query shows must not change what is
showing, the rule the launcher's `_replacementFor` already keeps.

## Log

### 2026-11-04 10:59

Reported that typing the File Search alias, slash, in the launcher showed the files with no preview
pane, while Hyper and semicolon, and choosing the File Search row, both showed it. The cause was two
routes to one tool. Choosing the row pushes File Search's presentation onto the stage,
`lib/rowintercept.lua`, while the typed alias stays in the launcher's presentation and only replaces
its rows through the query scope, and the launcher reserves no pane. The query scope's `AGENTS.md`
already named this as a presenter limit, and Speed Test's manifest had worked around it with a row
opening the tool proper. Built the hand over above, on the query scope's own rule that a scope is
dropped when what it must leave out is the point of the tool.
