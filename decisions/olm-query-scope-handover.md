# Olm query scope hand over, a typed word that reaches a list with a preview pane

Status. A typed alias whose tool shows its own list with a preview pane hands the launcher over
to that list, the same push choosing the tool's launcher row makes, and every other alias stays a
query scope inside the launcher.

## Now

A plugin declares its aliases and nothing more, and Olm does the rest, the rule Milos stated on
2026-11-04. For a tool whose registered presentation declares a preview pane, a `previewPaneWidth`
of true or a number above zero, `lib/registrar.lua`'s `scopeSpec` builds the scope from the tool's
aliases alone, with no `registry.scope` and no `provides` from the plugin, one pinned row naming
the tool for the moment before the hand over, and names in the console any scope such a plugin
still declares, which it ignores. The root, `root/compose.lua`, gives that scope a `handOver` and a
`run`. The query scope answers the hand over as a third value on every claim, handing it the typed rest and the
word that entered the scope with its separator, `host/queryscope/init.lua`. The launcher calls it
on the next turn of the run loop through one kept timer, `host/launcher/init.lua`
`_scheduleHandOver`, and the root's function pushes the presentation onto the stage with that word
as the level's field prefix, `Stage:push(p, { prefix })` in `host/stage/init.lua`.

The field keeps the word, so `/ report` still reads `/ report` while File Search's own list,
preview pane and every key are showing. The level's rows, its search, `query()` and `setQuery()`
only ever see what follows the word, so the tool never learns a word reached it. Deleting into the
word steps back to the launcher with whatever text is left, the same thing deleting the space does
in a query scope, so the rule that the alias stays and removing it returns to the launcher holds for
every alias. File Search and Speed Test take it today, and any tool that has an alias and a list
with a preview pane takes it with no edit, Clipboard and Processes the day either is given an
alias. Neither File Search nor Speed Test declares a scope any more. An alias of a tool with no
pane stays a query scope inside the launcher, unchanged. `test/cases/stage-prefix.lua` pins the
prefix and `test/cases/registrar-panescope.lua` the scope Olm builds.

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

Handing over by clearing the word from the field. Rejected 2026-11-04 11:47, after it shipped in
fd75a009 and was tried live. The field lost the alias the moment the list changed and Backspace on
an empty field became the way back, which broke the rule every alias keeps, that the word stays and
deleting it returns to the launcher.

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

### 2026-11-04 11:47

Tried live, the hand over worked and the pane showed, but the field lost `/ ` the moment File
Search's list took over, since the push cleared the field and only the typed rest went back in.
Milos's rule is that an alias always stays in the field and deleting it returns to the launcher,
and that a plugin declares its aliases and Olm handles the rest. The stage gained a field prefix
per pushed level, kept on the stage rather than on the presentation table the registry shares. The
swap writes the prefix into the field, `setQuery` puts it in front, `query` and the rows strip it,
the level's search ranks by what follows it, and a field that no longer starts with it pops the
level on the next turn and hands the level below the text that was left. No plugin changed.

### 2026-11-04 12:16

A plugin with a pane still had to declare a full scope only so its alias would resolve, since
`scopeSpec` built a scope only from `registry.scope`, and since the hand over every row and verb of
those scopes was unreachable. `scopeSpec` now builds the scope for such a tool from its aliases, a
member by having them whatever the set answered, and the root adds its hand over and its run. File
Search dropped `registry.scope`, `provides`, `scopeRows`, the join verb `ensureSession` in its
chooser, root and engine, and `closePreview`, and folded `peekRow`, `revealRow` and `copyPathRow`
back into the one verb each served. Speed Test dropped `registry.scope`, `provides`, `scopeRows` and
`scopeAct`. Losing `provides` moved Speed Test's row from sixteenth to twenty seventh in the
untouched launcher list, since the registry lists tools in wiring order and the set question sorts
its members first, and the launcher goldens were refreshed with every row otherwise unchanged.
